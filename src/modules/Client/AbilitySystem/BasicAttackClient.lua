--!strict
--[=[
	@class BasicAttackClient

	기본 공격 클라이언트 서비스.

	담당:
	- 입력 감지 (MB1 다운/업) → fireType별 분기 처리
	- ResourceSync 수신 → 로컬 추적값 서버 기준으로 보정
	- HitChecked 수신 → onHitChecked 배열 실행
	- PlayerBinderClient.JointsChanged 구독 → EntityAnimator 재생성
	- BasicAttackState 소유 및 관리
	- 리소스 로컬 병렬 추적 (Heartbeat)

	fireType별 입력 처리:
	  stack:
	    [다운] → StartAim(lockYaw=true)
	    [업]   → ConfirmAim() → _executeStack(direction)
	            interval 20% 경과 후면 예약, 아니면 즉시 or 실패

	  hold:
	    [다운] → StartAim(lockYaw=true) + _startFireLoop()
	    [업]   → _stopFireLoop() + aimController:Cancel()

	  toggle:
	    [다운] → isFiring이면 _stopFireLoop, 아니면 StartAim(lockYaw=false)
	    [업]   → isFiring이면 무시, 아니면 ConfirmAim() → _startFireLoop(direction)

	리소스 로컬 추적:
	  gauge: Heartbeat에서 drainRate/regenRate 직접 계산
	  stack: 발사 시 -1, 로컬 reloadTime 타이머로 +1
	  ResourceSync 수신 시 서버 값으로 보정
	  currentGauge=0 or currentStack=0 수신 시 즉시 _stopFireLoop()

	발사 시작 vs 루프 지속 리소스 체크:
	  시작: _hasResourceForStart() → gauge는 minGauge 기준
	  루프: currentGauge > 0 직접 비교 (gauge) / _hasResourceForStart (stack)

	CancelCombatState():
	  외부에서 공격불가/교체 등 어떤 이유로든 캔슬할 때 이 함수만 호출.
	  - aimController:Cancel() + CancelIntervalLock()
	  - _stopFireLoop()
	  - _pendingFireCancel 취소
	  - fireMaid Destroy
	  - abilityEffectMaid Destroy (대기 중 이펙트 발사 취소)
	  - onCancel 훅 실행
	  - _stackReloadTimer 리셋

	interval 예약 (stack/toggle만):
	  interval 잔여 비율 ≤ INTERVAL_QUEUE_THRESHOLD(80%) 일 때 발사 시도 시
	  cancellableDelay로 잔여 시간 후 자동 발사 예약.
	  서버에도 즉시 Fire:FireServer 전송.

	fireMaid:
	  onFire 실행 시 새 Maid 생성. CancelCombatState 시 Destroy.
	  모듈이 GiveTask로 cleanup 등록 가능 (애니메이션 중단 등).

	abilityEffectMaid:
	  장착 시 생성. CancelCombatState 시 Destroy.
	  AbilityEffectPlayer.Play()에 delay가 있을 때 넘기면
	  캔슬 시 대기 중인 이펙트 발사가 취소됨.
	  이미 발사된 이펙트는 독립 수명으로 계속 진행.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AbilityCoordinator = require("AbilityCoordinator")
local AbilityExecutor = require("AbilityExecutor")
local AbilityTypes = require("AbilityTypes")
local AimControllerClient = require("AimControllerClient")
local AnimationControllerClient = require("AnimationControllerClient")
local BasicAttackDefs = require("BasicAttackDefs")
local BasicAttackRemoting = require("BasicAttackRemoting")
local ClassRemoting = require("ClassRemoting")
local DynamicIndicator = require("DynamicIndicator")
local EntityAnimator = require("EntityAnimator")
local LoadoutRemoting = require("LoadoutRemoting")
local Maid = require("Maid")
local PlayerBinderClient = require("PlayerBinderClient")
local PlayerStateClient = require("PlayerStateClient")
local ServiceBag = require("ServiceBag")
local TeamClient = require("TeamClient")
local cancellableDelay = require("cancellableDelay")

-- ─── 상수 ────────────────────────────────────────────────────────────────────

-- ⚠️ 주의: BasicAttackService.lua의 INTERVAL_QUEUE_THRESHOLD와 반드시 동일해야 합니다.
--          AbilityTypes에서 공통 참조합니다.
local INTERVAL_QUEUE_THRESHOLD = AbilityTypes.INTERVAL_QUEUE_THRESHOLD

-- ─── 레지스트리 ──────────────────────────────────────────────────────────────

local ATTACK_REGISTRY: { [string]: { def: BasicAttackDefs.BasicAttackDef, module: any, animDef: any } } = {}
for id, def in BasicAttackDefs do
	ATTACK_REGISTRY[id] = {
		def = def,
		module = require(id .. "Client"),
		animDef = require(id .. "AnimDef"),
	}
end

-- ─── BasicAttackState 타입 ───────────────────────────────────────────────────

export type BasicAttackState = {
	-- 리소스 공통
	resourceType: "stack" | "gauge",
	interval: number,
	intervalUntil: number,
	isFiring: boolean,

	-- stack 리소스
	currentStack: number,
	maxStack: number,
	reloadTime: number,

	-- gauge 리소스
	currentGauge: number,
	maxGauge: number,
	minGauge: number,
	drainRate: number,
	regenRate: number,
	regenDelay: number,

	-- 로컬 추적용
	lastFireEndTime: number,

	-- 콤보 / 타이밍
	lastFireTime: number,
	lastHitTime: number,
	fireComboCount: number,
	hitComboCount: number,

	-- 조준 컨텍스트
	origin: Vector3,
	direction: Vector3,
	aimTime: number,
	effectiveAimTime: number,
	idleTime: number,

	-- 피격 결과
	victims: { Player }?,

	-- 발사 수명 관리 (애니메이션, 사운드 등 1회 발사 단위 cleanup)
	fireMaid: any?,

	-- 대기 중인 이펙트 발사 취소 (delay가 있는 AbilityEffectPlayer.Play용)
	-- 이미 발사된 이펙트는 독립 수명으로 영향 없음
	abilityEffectMaid: any?,

	-- 인디케이터 / 애니메이터
	indicator: any,
	animator: any?,

	-- 팀 컨텍스트 (AbilityEffectPlayer에 teamContext로 전달)
	-- BasicAttackState 타입 내부
	teamContext: {
		attackerChar: Model?,
		attackerPlayer: Player?,
		color: Color3?,
		isEnemy: (a: Player, b: Player) -> boolean,
	}?,
}

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type BasicAttackClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_aimController: AimControllerClient.AimControllerClient,
		_animController: AnimationControllerClient.AnimationControllerClient,
		_coordinator: any,
		_teamClient: any,
		_equippedAttackId: string?,
		_joints: { [string]: Motor6D }?,
		_attackAnimator: any?,
		_attackState: BasicAttackState?,
		_pendingFireCancel: (() -> ())?,
		_fireLoopCancel: (() -> ())?,
		_stackReloadTimer: number,
	},
	{} :: typeof({ __index = {} })
))

local BasicAttackClient = {}
BasicAttackClient.ServiceName = "BasicAttackClient"
BasicAttackClient.__index = BasicAttackClient
BasicAttackClient.AbilityType = "BasicAttack"

-- ─── 인디케이터 색상 상수 ─────────────────────────────────────────────────────

local COLOR_NORMAL = Color3.fromRGB(184, 184, 184)
local COLOR_NO_RESOURCE = Color3.fromRGB(220, 50, 50)
local ALPHA_NORMAL = 0
local ALPHA_INTERVAL = 0.7

-- ─── 초기화 ──────────────────────────────────────────────────────────────────

function BasicAttackClient.Init(self: BasicAttackClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._aimController = serviceBag:GetService(AimControllerClient)
	self._animController = serviceBag:GetService(AnimationControllerClient)
	self._coordinator = serviceBag:GetService(AbilityCoordinator)
	self._playerStateClient = serviceBag:GetService(PlayerStateClient)
	self._teamClient = serviceBag:GetService(TeamClient)

	self._equippedAttackId = nil
	self._joints = nil
	self._attackAnimator = nil
	self._attackState = nil
	self._pendingFireCancel = nil
	self._fireLoopCancel = nil
	self._stackReloadTimer = 0

	local playerBinder = serviceBag:GetService(PlayerBinderClient)
	self._maid:GiveTask(playerBinder.JointsChanged:Connect(function(joints)
		self._joints = joints
		if self._equippedAttackId then
			self:_rebuildAnimator()
		end
	end))

	self._maid:GiveTask(ClassRemoting.ClassChanged:Connect(function(_className: unknown)
		self:CancelCombatState()
	end))

	self._maid:GiveTask(BasicAttackRemoting.ResourceSync:Connect(function(payload: unknown)
		self:_onResourceSync(payload :: { [string]: any })
	end))

	self._maid:GiveTask(BasicAttackRemoting.HitChecked:Connect(function(victimUserIds: unknown)
		self:_onHitChecked(victimUserIds)
	end))

	self._maid:GiveTask(LoadoutRemoting.EquippedBasicAttackChanged:Connect(function(attackId: string)
		self:SetEquippedAttack(attackId)
	end))
end

function BasicAttackClient.Start(self: BasicAttackClient): ()
	self._coordinator:Register(self)

	self._maid:GiveTask(RunService.Heartbeat:Connect(function(dt: number)
		local state = self._attackState
		if not state then
			return
		end

		self:_updateLocalResource(state, dt)

		if not self._aimController:IsAiming() then
			state.effectiveAimTime = 0
			return
		end

		local hasResource = self:_hasResourceForStart(state)
		local isInterval = os.clock() < state.intervalUntil

		if hasResource and not isInterval then
			state.effectiveAimTime += dt
		else
			state.effectiveAimTime = 0
		end

		if not hasResource then
			state.indicator:updateAll({ color = COLOR_NO_RESOURCE })
		else
			state.indicator:updateAll({ color = COLOR_NORMAL })
		end

		if isInterval then
			state.indicator:updateAll({ transparency = ALPHA_INTERVAL })
		else
			state.indicator:updateAll({ transparency = ALPHA_NORMAL })
		end
	end))

	self._maid:GiveTask(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		self:_onMouseDown()
	end))

	self._maid:GiveTask(UserInputService.InputEnded:Connect(function(input: InputObject, _processed: boolean)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		self:_onMouseUp()
	end))
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

function BasicAttackClient:SetEquippedAttack(attackId: string)
	self:CancelCombatState()

	self._equippedAttackId = attackId
	self._stackReloadTimer = 0

	if self._attackState then
		self._attackState.indicator:destroy()
	end

	local entry = ATTACK_REGISTRY[attackId]
	local indicator = if entry then DynamicIndicator.new(entry.module.shapes) else DynamicIndicator.new({})
	local def = entry and entry.def

	local resourceType = if def then def.resource.resourceType else "stack"

	-- 팀 컨텍스트 (AbilityEffectPlayer teamContext용)
	local localPlayer = Players.LocalPlayer
	local teamClient = self._teamClient

	local teamContext = {
		attackerChar = localPlayer.Character,
		attackerPlayer = localPlayer,
		color = teamClient:GetMyColor(),
		isEnemy = function(a: Player, b: Player): boolean
			return teamClient:IsEnemy(a, b)
		end,
	}

	self._attackState = {
		resourceType = resourceType,
		interval = if def then def.interval else 0,
		intervalUntil = 0,
		isFiring = false,

		currentStack = 0,
		maxStack = 0,
		reloadTime = 0,

		currentGauge = 0,
		maxGauge = 0,
		minGauge = 0,
		drainRate = 0,
		regenRate = 0,
		regenDelay = 0,

		lastFireEndTime = 0,

		lastFireTime = 0,
		lastHitTime = 0,
		fireComboCount = 0,
		hitComboCount = 0,

		origin = Vector3.zero,
		direction = Vector3.new(0, 0, -1),
		aimTime = 0,
		effectiveAimTime = 0,
		idleTime = 0,

		victims = nil,
		fireMaid = nil,
		abilityEffectMaid = Maid.new(),
		indicator = indicator,
		animator = nil,
		teamContext = teamContext,
	}

	self:_rebuildAnimator()
end

--[=[
	공격불가, ability 교체, 스킬 우선 발동 등
	어떤 이유로든 전투 상태를 초기화할 때 이 함수만 호출합니다.
]=]
function BasicAttackClient:CancelCombatState()
	self._stackReloadTimer = 0
	self._aimController:Cancel()
	self._aimController:CancelIntervalLock()

	self:_stopFireLoop()

	if self._pendingFireCancel then
		self._pendingFireCancel()
		self._pendingFireCancel = nil
	end

	local state = self._attackState
	if state then
		state.isFiring = false
		state.lastFireEndTime = os.clock()
		if state.fireMaid then
			state.fireMaid:Destroy()
			state.fireMaid = nil
		end
		-- abilityEffectMaid: 대기 중인 이펙트 발사 취소
		-- 이미 발사된 이펙트는 독립 수명으로 영향 없음
		if state.abilityEffectMaid then
			state.abilityEffectMaid:Destroy()
			state.abilityEffectMaid = Maid.new()
		end
	end

	local attackId = self._equippedAttackId
	if state and attackId then
		local entry = ATTACK_REGISTRY[attackId]
		if entry then
			AbilityExecutor.OnCancel(entry.module, state)
		end
	end
end

--[=[
	AbilityCoordinator용: fire 루프 진행 중 여부
]=]
function BasicAttackClient:IsFiring(): boolean
	return self._fireLoopCancel ~= nil
end

--[=[
	AbilityCoordinator용: 다른 ability의 조준을 막는 상태인지 여부.
	stack  → postDelay(intervalUntil) 중
	hold/toggle → fire loop 중
]=]
function BasicAttackClient:IsBlockingAim(): boolean
	local attackId = self._equippedAttackId
	if not attackId then
		return false
	end
	local entry = ATTACK_REGISTRY[attackId]
	if not entry then
		return false
	end
	local state = self._attackState
	if not state then
		return false
	end

	if entry.def.fireType == "stack" then
		return os.clock() < state.intervalUntil
	else
		return self._fireLoopCancel ~= nil
	end
end

--[=[
	AbilityCoordinator용: blockAimTypes 반환.
]=]
function BasicAttackClient:GetBlockAimTypes(): { string }?
	local attackId = self._equippedAttackId
	if not attackId then
		return nil
	end
	local entry = ATTACK_REGISTRY[attackId]
	if not entry then
		return nil
	end
	return entry.def.blockAimTypes
end

--[=[
	AbilityCoordinator용: toggle fire 진행 중 여부 (예외 조건)
]=]
function BasicAttackClient:IsToggleFiring(): boolean
	local attackId = self._equippedAttackId
	if not attackId then
		return false
	end
	local entry = ATTACK_REGISTRY[attackId]
	if not entry then
		return false
	end
	return entry.def.fireType == "toggle" and self._fireLoopCancel ~= nil
end

-- ─── 내부: 로컬 리소스 추적 ─────────────────────────────────────────────────

function BasicAttackClient:_updateLocalResource(state: BasicAttackState, dt: number)
	if state.resourceType == "gauge" then
		if state.isFiring and state.currentGauge > 0 then
			state.currentGauge = math.max(0, state.currentGauge - state.drainRate * dt)
		elseif not state.isFiring and state.currentGauge < state.maxGauge then
			if os.clock() - state.lastFireEndTime >= state.regenDelay then
				state.currentGauge = math.min(state.maxGauge, state.currentGauge + state.regenRate * dt)
			end
		end
	elseif state.resourceType == "stack" then
		if state.currentStack < state.maxStack and state.reloadTime > 0 then
			self._stackReloadTimer += dt
			if self._stackReloadTimer >= state.reloadTime then
				self._stackReloadTimer -= state.reloadTime
				state.currentStack = math.min(state.currentStack + 1, state.maxStack)
			end
		end
	end
end

-- ─── 내부: 입력 처리 ────────────────────────────────────────────────────────

function BasicAttackClient:_onMouseDown()
	if self._playerStateClient:IsAbilityLocked("BasicAttack") then
		return
	end

	local attackId = self._equippedAttackId
	if not attackId then
		return
	end
	local entry = ATTACK_REGISTRY[attackId]
	if not entry then
		return
	end

	local fireType = entry.def.fireType

	if fireType == "stack" then
		self:_tryStartAim(entry, true)
	elseif fireType == "hold" then
		local state = self._attackState
		if not state then
			return
		end
		if os.clock() < state.intervalUntil then
			return
		end
		if not self:_hasResourceForStart(state) then
			return
		end
		self:_tryStartAim(entry, true)
		self:_startFireLoop(entry)
	elseif fireType == "toggle" then
		local state = self._attackState
		if not state then
			return
		end
		if self._fireLoopCancel then
			local now = os.clock()
			local remaining = state.intervalUntil - now
			if now >= state.intervalUntil then
				self:_stopFireLoop()
			elseif remaining / state.interval <= INTERVAL_QUEUE_THRESHOLD then
				if self._pendingFireCancel then
					self._pendingFireCancel()
				end
				self._pendingFireCancel = cancellableDelay(remaining, function()
					self._pendingFireCancel = nil
					self:_stopFireLoop()
				end)
			end
		else
			if os.clock() < state.intervalUntil then
				return
			end
			self:_tryStartAim(entry, false)
		end
	end
end

function BasicAttackClient:_onMouseUp()
	local attackId = self._equippedAttackId
	if not attackId then
		return
	end
	local entry = ATTACK_REGISTRY[attackId]
	if not entry then
		return
	end

	local fireType = entry.def.fireType

	if fireType == "stack" then
		local direction = self._aimController:ConfirmAim()
		if direction then
			self:_executeStack(entry, direction)
		end
	elseif fireType == "hold" then
		self:_stopFireLoop()
		self._aimController:Cancel()
	elseif fireType == "toggle" then
		if self._fireLoopCancel then
			return
		end
		local direction = self._aimController:ConfirmAim()
		if direction then
			local state = self._attackState
			if state and self:_hasResourceForStart(state) then
				self:_startFireLoop(entry)
			end
		end
	end
end

-- ─── 내부: 조준 시작 ────────────────────────────────────────────────────────

function BasicAttackClient:_tryStartAim(entry: { def: any, module: any, animDef: any }, lockYaw: boolean)
	if not self._coordinator:CanStartAim("BasicAttack") then
		return
	end

	local state = self._attackState
	if not state then
		return
	end

	state.idleTime = if state.lastFireTime > 0 then os.clock() - state.lastFireTime else 0

	self._aimController:StartAim(AimControllerClient.AbilityType.BasicAttack, entry.module, state, lockYaw)

	BasicAttackRemoting.AimStarted:FireServer()
end

-- ─── 내부: stack fire 실행 ──────────────────────────────────────────────────

function BasicAttackClient:_executeStack(entry: { def: any, module: any, animDef: any }, direction: Vector3)
	local state = self._attackState
	if not state then
		return
	end

	if not self:_hasResourceForStart(state) then
		return
	end

	local now = os.clock()
	local def = entry.def

	if now < state.intervalUntil then
		local remaining = state.intervalUntil - now
		if remaining / def.interval > INTERVAL_QUEUE_THRESHOLD then
			return
		end

		local scheduledAt = state.intervalUntil
		state.intervalUntil = scheduledAt + def.interval
		local capturedDir = direction

		if self._pendingFireCancel then
			self._pendingFireCancel()
		end
		self._pendingFireCancel = cancellableDelay(remaining, function()
			self._pendingFireCancel = nil
			state.direction = capturedDir
			state.lastFireTime = scheduledAt
			state.effectiveAimTime = 0
			state.currentStack = math.max(0, state.currentStack - 1)
			self:_onFireExecuted(entry, state)
			AbilityExecutor.OnFire(entry.module, state)
			self._aimController:StartIntervalLock(capturedDir, def.interval)
		end)

		-- sentAt: 서버 latency 보정용
		BasicAttackRemoting.Fire:FireServer(direction, Workspace:GetServerTimeNow())
		return
	end

	if self._pendingFireCancel then
		self._pendingFireCancel()
		self._pendingFireCancel = nil
	end

	state.direction = direction
	state.intervalUntil = now + def.interval
	state.lastFireTime = now
	state.effectiveAimTime = 0

	state.currentStack = math.max(0, state.currentStack - 1)
	self._stackReloadTimer = 0

	self:_onFireExecuted(entry, state)

	BasicAttackRemoting.Fire:FireServer(direction, Workspace:GetServerTimeNow())
	AbilityExecutor.OnFire(entry.module, state)
	self._aimController:StartIntervalLock(direction, def.interval)
end

-- ─── 내부: hold/toggle fire 루프 ────────────────────────────────────────────

function BasicAttackClient:_startFireLoop(entry: { def: any, module: any, animDef: any })
	if self._fireLoopCancel then
		return
	end

	local state = self._attackState
	if not state then
		return
	end

	state.isFiring = true
	local loopStartTime = os.clock() -- ← 추가
	self:_onFireExecuted(entry, state)

	local running = true
	self._fireLoopCancel = function()
		running = false
	end

	local def = entry.def

	task.spawn(function()
		while running do
			local now = os.clock()
			state.effectiveAimTime = now - loopStartTime

			if state.resourceType == "gauge" then
				if state.currentGauge <= 0 then
					self:_stopFireLoop()
					break
				end
			else
				if not self:_hasResourceForStart(state) then
					self:_stopFireLoop()
					break
				end
			end

			if now >= state.intervalUntil then
				state.intervalUntil = now + def.interval
				state.lastFireTime = now
				state.effectiveAimTime = 0

				if def.fireType == "toggle" then
					local char = Players.LocalPlayer.Character
					local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
					if hrp then
						local look = hrp.CFrame.LookVector
						local flat = Vector3.new(look.X, 0, look.Z)
						if flat.Magnitude > 0.001 then
							state.direction = flat.Unit
						end
					end
				end

				if state.resourceType == "stack" then
					state.currentStack = math.max(0, state.currentStack - 1)
					self._stackReloadTimer = 0
				end

				if state.fireMaid then
					state.fireMaid:Destroy()
				end
				state.fireMaid = Maid.new()

				BasicAttackRemoting.Fire:FireServer(state.direction, Workspace:GetServerTimeNow())
				AbilityExecutor.OnFire(entry.module, state)
			end

			task.wait(0.016)
		end
	end)
end

function BasicAttackClient:_stopFireLoop()
	if not self._fireLoopCancel then
		return -- 루프가 없으면 아무것도 하지 않음
	end

	self._fireLoopCancel()
	self._fireLoopCancel = nil

	local state = self._attackState
	if state then
		state.isFiring = false
		state.lastFireEndTime = os.clock()
	end

	BasicAttackRemoting.FireEnd:FireServer()
end

-- ─── 내부: fire 공통 처리 ────────────────────────────────────────────────────

function BasicAttackClient:_onFireExecuted(entry: { def: any, module: any, animDef: any }, state: BasicAttackState)
	if not state.isFiring then
		if state.fireMaid then
			state.fireMaid:Destroy()
		end
		state.fireMaid = Maid.new()
	end

	-- teamContext의 attackerChar를 현재 캐릭터로 갱신
	if state.teamContext then
		state.teamContext.attackerChar = Players.LocalPlayer.Character
	end

	self._coordinator:OnFireExecuted(self)
end

-- ─── 내부: 리소스 유틸 ──────────────────────────────────────────────────────

--[=[
	발사 시작 조건 체크. gauge는 minGauge 기준.
	루프 지속 중 체크에는 사용하지 않음.
]=]
function BasicAttackClient:_hasResourceForStart(state: BasicAttackState): boolean
	if state.resourceType == "stack" then
		return state.currentStack > 0
	elseif state.resourceType == "gauge" then
		return state.currentGauge >= state.minGauge
	end
	return false
end

-- ─── 내부: 서버 이벤트 처리 ─────────────────────────────────────────────────

function BasicAttackClient:_onResourceSync(payload: { [string]: any })
	local state = self._attackState
	if not state then
		return
	end

	local rt = payload.resourceType
	if rt then
		state.resourceType = rt
	end
	if payload.interval then
		state.interval = payload.interval
	end

	if rt == "stack" then
		if type(payload.currentStack) == "number" then
			state.currentStack = payload.currentStack
		end
		if type(payload.maxStack) == "number" then
			state.maxStack = payload.maxStack
		end
		if type(payload.reloadTime) == "number" then
			state.reloadTime = payload.reloadTime
			self._stackReloadTimer = 0
		end
		if state.currentStack <= 0 then
			self:_stopFireLoop()
		end
	elseif rt == "gauge" then
		if type(payload.currentGauge) == "number" then
			state.currentGauge = payload.currentGauge
		end
		if type(payload.maxGauge) == "number" then
			state.maxGauge = payload.maxGauge
		end
		if type(payload.minGauge) == "number" then
			state.minGauge = payload.minGauge
		end
		if type(payload.drainRate) == "number" then
			state.drainRate = payload.drainRate
		end
		if type(payload.regenRate) == "number" then
			state.regenRate = payload.regenRate
		end
		if type(payload.regenDelay) == "number" then
			state.regenDelay = payload.regenDelay
		end
		if state.currentGauge <= 0 then
			self:_stopFireLoop()
		end
	end
end

function BasicAttackClient:_onHitChecked(victimUserIds: unknown)
	local state = self._attackState
	if not state then
		return
	end

	local victims: { Player } = {}
	for _, userId in ipairs(victimUserIds :: { number }) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			table.insert(victims, player)
		end
	end
	state.victims = victims

	if #victims > 0 then
		state.lastHitTime = os.clock()
	end

	local attackId = self._equippedAttackId
	if not attackId then
		return
	end
	local entry = ATTACK_REGISTRY[attackId]
	if not entry then
		return
	end

	AbilityExecutor.OnHitChecked(entry.module, state)
end

-- ─── 내부: 애니메이터 ────────────────────────────────────────────────────────

function BasicAttackClient:_rebuildAnimator()
	if self._attackAnimator then
		self._attackAnimator:Destroy()
		self._attackAnimator = nil
	end
	if self._attackState then
		self._attackState.animator = nil
	end

	local attackId = self._equippedAttackId
	local joints = self._joints
	if not attackId or not joints then
		return
	end

	local entry = ATTACK_REGISTRY[attackId]
	if not entry then
		return
	end

	local animator = EntityAnimator.new(
		"BasicAttack_" .. attackId,
		attackId .. "AnimDef",
		joints,
		entry.animDef,
		self._animController
	)
	self._attackAnimator = animator

	if self._attackState then
		self._attackState.animator = animator
	end
end

function BasicAttackClient.Destroy(self: BasicAttackClient)
	self:CancelCombatState()
	self._maid:Destroy()
end

return BasicAttackClient
