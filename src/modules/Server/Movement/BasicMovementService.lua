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

local BasicAttackService = require("BasicAttackService")
local BasicMovementConfig = require("BasicMovementConfig")
local ClassRemoting = require("ClassRemoting")
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

type PlayerState = {
	className: string,
	currentSpeed: number,
	targetSpeed: number,
	isRunning: boolean,
	isMoving: boolean,
	isFrozen: boolean,
	frozenUntil: number,
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

	self._maid:GiveTask(MovementRemoting.IsRunning:Connect(function(player: Player, isRunning: unknown)
		self:_onMovementStateReceived(player, isRunning)
	end))

	self._maid:GiveTask(ClassRemoting.RequestClassChange:Bind(function(player: Player, className: unknown)
		if type(className) ~= "string" then
			return false, "Invalid class name"
		end
		if not BasicMovementConfig.Classes[className] then
			return false, "Unknown class: " .. className
		end
		self:_setPlayerClass(player, className)
		return true, className
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
end

-- ─── 플레이어 라이프사이클 ────────────────────────

function BasicMovementService:_onPlayerAdded(player: Player)
	local pMaid = Maid.new()
	self._playerMaids[player.UserId] = pMaid

	local function onCharacterAdded(char: Model)
		local humanoid = char:WaitForChild("Humanoid") :: Humanoid
		local rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart

		local existingState = self._playerStates[player.UserId]
		local className = if existingState then existingState.className else "Default"
		local config = BasicMovementConfig.GetConfig(className)

		self._playerStates[player.UserId] = {
			className = className,
			currentSpeed = config.walkSpeed,
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

	state.isRunning = isRunning
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

function BasicMovementService:_recordViolation(state: PlayerState, reason: string)
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

-- ─── 내부 ────────────────────────────────────────────

-- 클래스 변경 확정 및 클라이언트 통보
-- RequestClassChange 핸들러에서만 호출
function BasicMovementService:_setPlayerClass(player: Player, className: string)
	local state = self._playerStates[player.UserId]
	if not state then
		return
	end

	-- 클래스 교체 전 전투 상태 강제 초기화 (예약 발사, onHit 클로저 등 캔슬)
	self._serviceBag:GetService(BasicAttackService):CancelCombatState(player)

	local config = BasicMovementConfig.GetConfig(className)
	state.className = className
	state.targetSpeed = if state.isRunning then config.runSpeed else config.walkSpeed
	-- currentSpeed는 관성으로 서서히 따라감

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
		local config = BasicMovementConfig.GetConfig(state.className)
		state.targetSpeed = if state.isRunning then config.runSpeed else config.walkSpeed
	end
end

function BasicMovementService.Destroy(self: BasicMovementService)
	self._maid:Destroy()
end

return BasicMovementService
