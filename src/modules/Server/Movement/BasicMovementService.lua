--!strict
--[=[
	@class BasicMovementService

	서버 권한 이동 시스템.

	변경 이력:
	- RequestClassChange 처리 및 클래스 상태 소유권을 ClassService로 이관.
	- ClassService.ClassChanged 구독 → WalkSpeed 기준만 갱신.
	- _setPlayerClass 메서드 제거.
	- BasicAttackService 의존 제거 (CancelCombatState는 ClassService가 호출).
	- PlayerState → BasicMovementState 로 타입명 변경 (PlayerState 시스템과 혼동 방지).
	- isMoveLocked 필드 추가: CC 이동방지 중 클라이언트 보고가 targetSpeed 덮어쓰는 버그 수정.

	Anti-exploit 구조:
	- WalkSpeed는 오직 이 서비스만 설정합니다. 클라이언트는 절대 직접 변경 불가.
	- RemoteEvent 레이트 리밋: 플레이어당 최소 0.08초 간격 강제.
	- 속도 검증: 클라이언트가 보고한 상태와 실제 Velocity를 비교.
	  지속적으로 불일치하면 위반 카운트 증가 → 속도 동결.

	관성 구조:
	- Heartbeat마다 currentSpeed를 targetSpeed 방향으로 지수 감쇠 Lerp.
	- acceleration / deceleration 값으로 클래스별 느낌 차별화.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BasicMovementConfig = require("BasicMovementConfig")
local ClassService = require("ClassService")
local Maid = require("Maid")
local MovementRemoting = require("MovementRemoting")
local ServiceBag = require("ServiceBag")

local BasicMovementService = {}
BasicMovementService.ServiceName = "BasicMovementService"

-- ─── 상수 ───────────────────────────────────────

local RATE_LIMIT_INTERVAL = 0.08
local MAX_VIOLATIONS = 10
local VIOLATION_DECAY_RATE = 0.5
local VELOCITY_TOLERANCE = 6
local VIOLATION_FREEZE_DURATION = 5

-- ─── 타입 정의 ──────────────────────────────────

type BasicMovementState = {
	className: string,
	currentSpeed: number,
	targetSpeed: number,
	isRunning: boolean,
	isMoving: boolean,
	isFrozen: boolean,
	frozenUntil: number,
	isMoveLocked: boolean,
	humanoid: Humanoid?,
	rootPart: BasePart?,
	lastEventTime: number,
	violations: number,
	lastViolationDecay: number,
}

export type BasicMovementService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_classService: any,
		_playerStates: { [number]: BasicMovementState },
		_playerMaids: { [number]: any },
	},
	{} :: typeof({ __index = BasicMovementService })
))

-- ─── 초기화 ─────────────────────────────────────

function BasicMovementService.Init(self: BasicMovementService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._classService = serviceBag:GetService(ClassService)
	self._playerStates = {}
	self._playerMaids = {}

	self._maid:GiveTask(MovementRemoting.IsRunning:Connect(function(player: Player, isRunning: unknown)
		self:_onMovementStateReceived(player, isRunning)
	end))
end

function BasicMovementService.Start(self: BasicMovementService): ()
	for _, player in Players:GetPlayers() do
		self:_onPlayerAdded(player)
	end
	self._maid:GiveTask(Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end))
	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end))
	self._maid:GiveTask(RunService.Heartbeat:Connect(function(dt)
		self:_updateInertia(dt)
	end))

	-- 클래스 변경 시 WalkSpeed 기준 갱신
	self._maid:GiveTask(self._classService.ClassChanged:Connect(function(player: Player, className: string)
		local state = self._playerStates[player.UserId]
		if not state then
			return
		end
		local config = BasicMovementConfig.GetConfig(className)
		state.className = className
		state.targetSpeed = if state.isRunning then config.runSpeed else config.walkSpeed
		-- currentSpeed는 관성으로 서서히 따라감
	end))
end

-- ─── 플레이어 라이프사이클 ────────────────────────

function BasicMovementService:_onPlayerAdded(player: Player)
	local pMaid = Maid.new()
	self._playerMaids[player.UserId] = pMaid

	local function onCharacterAdded(char: Model)
		local humanoid = char:WaitForChild("Humanoid") :: Humanoid
		local rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart

		local className = self._classService:GetClass(player)
		local config = BasicMovementConfig.GetConfig(className)

		self._playerStates[player.UserId] = {
			className = className,
			currentSpeed = config.walkSpeed,
			targetSpeed = config.walkSpeed,
			isRunning = false,
			isMoving = false,
			isFrozen = false,
			frozenUntil = 0,
			isMoveLocked = false,
			humanoid = humanoid,
			rootPart = rootPart,
			lastEventTime = 0,
			violations = 0,
			lastViolationDecay = os.clock(),
		}

		humanoid.WalkSpeed = config.walkSpeed

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

-- ─── 이벤트 수신 ─────────────────────────────────

function BasicMovementService:_onMovementStateReceived(player: Player, isRunning: unknown)
	local state = self._playerStates[player.UserId]
	if not state then
		return
	end

	local now = os.clock()
	if now - state.lastEventTime < RATE_LIMIT_INTERVAL then
		return
	end
	state.lastEventTime = now

	-- isFrozen: 시간 만료 시 자동 해제 (isMoveLocked 체크 전에 처리)
	if state.isFrozen then
		if now >= state.frozenUntil then
			state.isFrozen = false
		else
			return
		end
	end

	if type(isRunning) ~= "boolean" then
		return
	end

	-- isRunning은 lock 중에도 기록 (lock 해제 시 올바른 속도 복원용)
	state.isRunning = isRunning

	-- isMoveLocked: CC 이동방지 중이면 targetSpeed 갱신 차단
	if state.isMoveLocked then
		return
	end

	local config = BasicMovementConfig.GetConfig(state.className)
	state.targetSpeed = if isRunning then config.runSpeed else config.walkSpeed

	if state.rootPart then
		local velocity = state.rootPart.AssemblyLinearVelocity
		local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local expectedSpeed = state.currentSpeed
		if math.abs(horizontalSpeed - expectedSpeed) > VELOCITY_TOLERANCE and expectedSpeed > 1 then
			self:_recordViolation(state, "speed mismatch")
		end
	end
end

-- ─── Violation ────────────────────────────────────

function BasicMovementService:_recordViolation(state: BasicMovementState, reason: string)
	local now = os.clock()
	local elapsed = now - state.lastViolationDecay
	state.violations = math.max(0, state.violations - elapsed * VIOLATION_DECAY_RATE)
	state.lastViolationDecay = now
	state.violations += 1

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

		local config = BasicMovementConfig.GetConfig(state.className)
		local lerpStrength = if state.currentSpeed < state.targetSpeed then config.acceleration else config.deceleration
		local alpha = 1 - math.exp(-lerpStrength * dt)
		state.currentSpeed = state.currentSpeed + (state.targetSpeed - state.currentSpeed) * alpha

		if math.abs(state.currentSpeed - state.targetSpeed) < 0.05 then
			state.currentSpeed = state.targetSpeed
		end

		humanoid.WalkSpeed = state.currentSpeed
	end
end

-- ─── 공개 API ────────────────────────────────────

--[=[
	플레이어 이동을 외부에서 강제로 잠급니다. (예: 스킬 시전 중, CC 효과)
	PlayerStateControllerService._syncMovement에서 호출됩니다.
	@param player Player
	@param locked boolean
]=]
function BasicMovementService:SetMovementLocked(player: Player, locked: boolean)
	local state = self._playerStates[player.UserId]
	if not state or not state.humanoid then
		return
	end

	state.isMoveLocked = locked

	if locked then
		state.targetSpeed = 0
	else
		local config = BasicMovementConfig.GetConfig(state.className)
		state.targetSpeed = if state.isRunning then config.runSpeed else config.walkSpeed
	end
end

function BasicMovementService.Destroy(self: BasicMovementService)
	self._maid:Destroy()
end

return BasicMovementService
