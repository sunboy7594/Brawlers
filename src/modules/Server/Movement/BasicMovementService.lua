--!strict
--[=[
	@class BasicMovementService

	서버 권한 이동 시스템.

	Anti-exploit 구조:
	- WalkSpeed는 오직 이 서비스만 설정합니다. 클라이언트는 절대 직접 변경 불가.
	- RemoteEvent 레이트 리밋: 플레이어당 최소 0.08초 간격 강제.
	- 속도 검증: 클라이언트가 보고한 상태와 실제 Velocity를 비교.
	  지속적으로 불일치하면 위반 카운트 증가 → 속도 동결.
	- 클래스 데이터는 서버에서만 관리. 클라이언트가 클래스를 주장해도 무시.

	관성 구조:
	- Heartbeat마다 currentSpeed를 targetSpeed 방향으로 지수 감쇠 Lerp.
	- acceleration / deceleration 값으로 클래스별 느낌 차별화.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ClassRemoting = require("ClassRemoting")
local Maid = require("Maid")
local MovementConfig = require("MovementConfig")
local MovementRemoting = require("MovementRemoting")
local ServiceBag = require("ServiceBag")

local BasicMovementService = {}
BasicMovementService.ServiceName = "BasicMovementService"

-- ─── 상수 ───────────────────────────────────────
local RATE_LIMIT_INTERVAL = 0.08 -- 초당 최대 ~12회
local MAX_VIOLATIONS = 10 -- 위반 누적 한도
local VIOLATION_DECAY_RATE = 0.5 -- 초당 위반 카운트 감소
local VELOCITY_TOLERANCE = 6 -- 속도 불일치 허용 오차 (studs/s)
local VIOLATION_FREEZE_DURATION = 5 -- 위반 시 동결 시간 (초)

-- ─── 타입 정의 ──────────────────────────────────

type PlayerState = {
	-- 직업 & 속도
	className: string,
	currentSpeed: number, -- 현재 관성 적용된 속도
	targetSpeed: number, -- 목표 속도

	-- 이동 상태
	isRunning: boolean,
	isMoving: boolean,
	isFrozen: boolean, -- 위반 시 동결 여부
	frozenUntil: number, -- 동결 해제 시각 (os.clock)

	-- 캐릭터 레퍼런스
	humanoid: Humanoid?,
	rootPart: BasePart?,

	-- Anti-exploit
	lastEventTime: number, -- 마지막 RemoteEvent 수신 시각
	violations: number, -- 누적 위반 카운트
	lastViolationDecay: number, -- 마지막 감쇠 시각
}

export type BasicMovementService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_playerStates: { [number]: PlayerState },
		_playerMaids: { [number]: any },
	},
	{} :: typeof({ __index = BasicMovementService })
))

-- ─── 초기화 ─────────────────────────────────────

function BasicMovementService.Init(self: BasicMovementService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._playerStates = {}
	self._playerMaids = {}

	-- IsRunning 이벤트 수신 (레이트 리밋 + 검증 포함)
	self._maid:GiveTask(MovementRemoting.IsRunning:Connect(function(player: Player, isRunning: unknown)
		self:_onMovementStateReceived(player, isRunning)
	end))

	-- 클라이언트 클래스 변경 요청 수신
	-- TODO: 나중에 골드 차감, 쿨다운, 전투 중 제한 등 검증 추가
	self._maid:GiveTask(ClassRemoting.RequestClassChange:Bind(function(player: Player, className: unknown)
		-- 타입 검증
		if type(className) ~= "string" then
			return false, "Invalid class name"
		end

		-- 유효한 클래스인지 확인
		if not MovementConfig.Classes[className] then
			return false, "Unknown class: " .. className
		end

		-- 확정 및 적용
		self:_setPlayerClass(player, className)
		return true, className
	end))
end

function BasicMovementService.Start(self: BasicMovementService): ()
	-- 플레이어 라이프사이클 관리
	for _, player in Players:GetPlayers() do
		self:_onPlayerAdded(player)
	end
	self._maid:GiveTask(Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end))
	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end))

	-- 서버 관성 루프
	self._maid:GiveTask(RunService.Heartbeat:Connect(function(dt)
		self:_updateInertia(dt)
	end))
end

-- ─── 플레이어 라이프사이클 ────────────────────────

function BasicMovementService:_onPlayerAdded(player: Player)
	local pMaid = Maid.new()
	self._playerMaids[player.UserId] = pMaid

	local function onCharacterAdded(char: Model)
		local humanoid = char:WaitForChild("Humanoid") :: Humanoid
		local rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart

		-- 기존 상태가 있으면 클래스명 유지, 없으면 Default
		local existingState = self._playerStates[player.UserId]
		local className = if existingState then existingState.className else "Default"
		local config = MovementConfig.GetConfig(className)

		self._playerStates[player.UserId] = {
			className = className,
			currentSpeed = config.walkSpeed, -- 스폰 시 걷기 속도로 시작
			targetSpeed = config.walkSpeed,
			isRunning = false,
			isMoving = false,
			isFrozen = false,
			frozenUntil = 0,
			humanoid = humanoid,
			rootPart = rootPart,
			lastEventTime = 0,
			violations = 0,
			lastViolationDecay = os.clock(),
		}

		-- 서버에서 초기 속도 설정
		humanoid.WalkSpeed = config.walkSpeed

		-- 사망 시 캐릭터 레퍼런스 정리
		pMaid:GiveTask(humanoid.Died:Connect(function()
			local state = self._playerStates[player.UserId]
			if state then
				state.humanoid = nil
				state.rootPart = nil
			end
		end))
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end
	pMaid:GiveTask(player.CharacterAdded:Connect(onCharacterAdded))
end

function BasicMovementService:_onPlayerRemoving(player: Player)
	self._playerStates[player.UserId] = nil

	local pMaid = self._playerMaids[player.UserId]
	if pMaid then
		pMaid:Destroy()
		self._playerMaids[player.UserId] = nil
	end
end

-- ─── RemoteEvent 수신 & Anti-exploit ────────────────

function BasicMovementService:_onMovementStateReceived(player: Player, isRunning: unknown)
	local state = self._playerStates[player.UserId]
	if not state or not state.humanoid then
		return
	end

	local now = os.clock()

	-- [1] 레이트 리밋: 너무 빠른 호출 차단
	if now - state.lastEventTime < RATE_LIMIT_INTERVAL then
		if type(isRunning) == "boolean" and isRunning == false then
			state.isRunning = false
			local config = MovementConfig.GetConfig(state.className)
			state.targetSpeed = config.walkSpeed
			return
		end
		self:_registerViolation(state, now, "Rate limit exceeded")
		return
	end
	state.lastEventTime = now

	-- [2] 타입 검증
	if type(isRunning) ~= "boolean" then
		self:_registerViolation(state, now, "Invalid argument type")
		return
	end

	-- [3] 속도 검증: isRunning=true일 때만 체크
	-- isRunning=false는 서버 관성으로 인해 실제 속도가 아직 빠를 수 있으므로 검증 제외
	if isRunning and state.rootPart then
		local actualSpeed = state.rootPart.AssemblyLinearVelocity.Magnitude
		local config = MovementConfig.GetConfig(state.className)
		local maxAllowed = config.runSpeed + VELOCITY_TOLERANCE

		if actualSpeed > maxAllowed then
			self:_registerViolation(
				state,
				now,
				string.format("Speed mismatch: actual=%.1f, max=%.1f", actualSpeed, maxAllowed)
			)
			return
		end
	end

	-- [4] 동결 상태 확인
	if state.isFrozen then
		if now < state.frozenUntil then
			return -- 동결 중, 무시
		else
			state.isFrozen = false -- 동결 해제
		end
	end

	-- [5] 상태 업데이트 → 목표 속도 변경 (실제 적용은 _updateInertia에서)
	local config = MovementConfig.GetConfig(state.className)
	state.isRunning = isRunning
	state.targetSpeed = if isRunning then config.runSpeed else config.walkSpeed
end

function BasicMovementService:_registerViolation(state: PlayerState, now: number, reason: string)
	-- 감쇠 적용 (시간이 지나면 위반 카운트 자연 감소)
	local elapsed = now - state.lastViolationDecay
	state.violations = math.max(0, state.violations - elapsed * VIOLATION_DECAY_RATE)
	state.lastViolationDecay = now

	state.violations += 1

	-- 위반 한도 초과 시 동결
	if state.violations >= MAX_VIOLATIONS then
		state.isFrozen = true
		state.frozenUntil = now + VIOLATION_FREEZE_DURATION
		state.violations = 0

		if state.humanoid then
			state.humanoid.WalkSpeed = 0
		end

		warn(string.format("[BasicMovementService] Player frozen: %s | Reason: %s", tostring(state), reason))
	end
end

-- ─── 관성 루프 (Heartbeat) ────────────────────────

function BasicMovementService:_updateInertia(dt: number)
	for _, state in self._playerStates do
		local humanoid = state.humanoid
		if not humanoid then
			continue
		end
		if state.isFrozen then
			continue
		end

		local config = MovementConfig.GetConfig(state.className)

		-- 목표 속도와 현재 속도 비교하여 가속/감속 계수 선택
		local lerpStrength = if state.currentSpeed < state.targetSpeed then config.acceleration else config.deceleration

		-- 지수 감쇠 Lerp: 프레임레이트 독립적
		-- alpha = 1 - e^(-strength * dt)
		local alpha = 1 - math.exp(-lerpStrength * dt)
		state.currentSpeed = state.currentSpeed + (state.targetSpeed - state.currentSpeed) * alpha

		-- 아주 가까우면 스냅 (떨림 방지)
		if math.abs(state.currentSpeed - state.targetSpeed) < 0.05 then
			state.currentSpeed = state.targetSpeed
		end

		-- 서버에서 직접 WalkSpeed 설정 (클라이언트는 건드릴 수 없음)
		humanoid.WalkSpeed = state.currentSpeed
	end
end

-- ─── 내부 ────────────────────────────────────────────

-- 클래스 변경 확정 및 클라이언트 통보
-- RequestClassChange 핸들러에서만 호출
function BasicMovementService:_setPlayerClass(player: Player, className: string)
	local state = self._playerStates[player.UserId]
	if not state then
		return
	end

	local config = MovementConfig.GetConfig(className)
	state.className = className
	state.targetSpeed = if state.isRunning then config.runSpeed else config.walkSpeed
	-- currentSpeed는 관성으로 서서히 따라감

	-- 클라이언트에 클래스 변경 알림 (애니메이션 전환용)
	ClassRemoting.ClassChanged:FireClient(player, className)
end

-- ─── 공개 API (다른 서비스에서 호출) ────────────────

--[=[
	플레이어 이동을 외부에서 강제로 잠급니다. (예: 스킬 시전 중)
	@param player Player
	@param locked boolean
]=]
function BasicMovementService:SetMovementLocked(player: Player, locked: boolean)
	local state = self._playerStates[player.UserId]
	if not state or not state.humanoid then
		return
	end

	if locked then
		state.targetSpeed = 0
	else
		local config = MovementConfig.GetConfig(state.className)
		state.targetSpeed = if state.isRunning then config.runSpeed else config.walkSpeed
	end
end

function BasicMovementService.Destroy(self: BasicMovementService)
	self._maid:Destroy()
end

return BasicMovementService
