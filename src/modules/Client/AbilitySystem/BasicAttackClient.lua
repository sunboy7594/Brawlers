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
	  - onCancel 훅 실행
	  - _stackReloadTimer 리셋

	interval 예약 (stack/toggle만):
	  interval 잔여 비율 ≤ INTERVAL_QUEUE_THRESHOLD(80%) 일 때 발사 시도 시
	  cancellableDelay로 잔여 시간 후 자동 발사 예약.
	  서버에도 즉시 Fire:FireServer 전송.

	fireMaid:
	  onFire 실행 시 새 Maid 생성. CancelCombatState 시 Destroy.
	  모듈이 GiveTask로 cleanup 등록 가능 (애니메이션 중단, 딜레이 히트 취소 등).

	abilityEffect:
	  AbilityEffect.new(worldFX)로 생성된 유틸 인스턴스.
	  state.abilityEffect로 각 어빌리티 모듈에서 접근 가능.
	  3D 이펙트 소환/이동/충돌 콜백 처리에 사용.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AbilityCoordinator = require("AbilityCoordinator")
local AbilityEffect = require("AbilityEffect")
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
local WorldFX = require("WorldFX")
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

	-- 발사 수명 관리 (모듈이 GiveTask로 cleanup 등록)
	fireMaid: any?,

	-- 인디케이터 / 애니메이터
	indicator: any,
	animator: any?,

	-- AbilityEffect 유틸 (WorldFX 기반 3D 이펙트 재생)
	abilityEffect: any?,
}

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type BasicAttackClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_aimController: AimControllerClient.AimControllerClient,
		_animController: AnimationControllerClient.AnimationControllerClient,
		_coordinator: any, -- AbilityCoordinator
		_equippedAttackId: string?,
		_joints: { [string]: Motor6D }?,
		_attackAnimator: any?,
		_attackState: BasicAttackState?,
		_pendingFireCancel: (() -> ())?,
		_fireLoopCancel: (() -> ())?,
		_stackReloadTimer: number,
		_abilityEffect: any?,
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
local ALPHA_INTERVAL = 0.85

-- ─── 초기화 ──────────────────────────────────────────────────────────────────

function BasicAttackClient.Init(self: BasicAttackClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._aimController = serviceBag:GetService(AimControllerClient)
	self._animController = serviceBag:GetService(AnimationControllerClient)
	self._coordinator = serviceBag:GetService(AbilityCoordinator)
	self._playerStateClient = serviceBag:GetService(PlayerStateClient)

	self._equippedAttackId = nil
	self._joints = nil
	self._attackAnimator = nil
	self._attackState = nil
	self._pendingFireCancel = nil
	self._fireLoopCancel = nil
	self._stackReloadTimer = 0

	-- AbilityEffect 유틸 생성 (WorldFX 서비스에서 모델 소환)
	local worldFX = serviceBag:GetService(WorldFX)
	self._abilityEffect = AbilityEffect.new(worldFX)
	self._maid:GiveTask(function()
		self._abilityEffect:Destroy()
	end)

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
	-- AbilityCoordinator에 자신 등록
	self._coordinator:Register(self)

	-- Heartbeat: 인디케이터 갱신 + 로컬 리소스 추적
	self._maid:GiveTask(RunService.Heartbeat:Connect(function(dt: number)
		local state = self._attackState
		if not state then
			return
		end

		-- 로컬 리소스 추적
		self:_updateLocalResource(state, dt)

		-- 인디케이터 갱신 (조준 중에만)
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

	-- 입력 처리
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

	self._attackState = {
		-- 리소스 공통
		resourceType = resourceType,
		interval = if def then def.interval else 0,
		intervalUntil = 0,
		isFiring = false,

		-- stack 초기값
		currentStack = 0,
		maxStack = 0,
		reloadTime = 0,

		-- gauge 초기값
		currentGauge = 0,
		maxGauge = 0,
		minGauge = 0,
		drainRate = 0,
		regenRate = 0,
		regenDelay = 0,

		-- 로컬 추적용
		lastFireEndTime = 0,

		-- 콤보
		lastFireTime = 0,
		lastHitTime = 0,
		fireComboCount = 0,
		hitComboCount = 0,

		-- 조준
		origin = Vector3.zero,
		direction = Vector3.new(0, 0, -1),
		aimTime = 0,
		effectiveAimTime = 0,
		idleTime = 0,

		victims = nil,
		fireMaid = nil,
		indicator = indicator,
		animator = nil,
		abilityEffect = self._abilityEffect,
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
		-- fireMaid Destroy (모듈이 등록한 cleanup 자동 실행)
		if state.fireMaid then
			state.fireMaid:Destroy()
			state.fireMaid = nil
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
		-- interval 중이면 hold 시작 불가
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
			-- 두번째 클릭: 루프 종료 (interval 허용 구간에서만)
			local now = os.clock()
			local remaining = state.intervalUntil - now
			if now >= state.intervalUntil then
				self:_stopFireLoop()
			elseif remaining / state.interval <= INTERVAL_QUEUE_THRESHOLD then
				-- 예약 종료
				if self._pendingFireCancel then
					self._pendingFireCancel()
				end
				self._pendingFireCancel = cancellableDelay(remaining, function()
					self._pendingFireCancel = nil
					self:_stopFireLoop()
				end)
			end
			-- 아직 threshold 안 됐으면 무시
		else
			-- 첫번째 클릭: StartAim (toggle은 화면 고정 없음)
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
			-- 루프 진행 중: 업 이벤트 무시 (다운이 처리)
			return
		end
		-- 첫번째 업: 발사 루프 시작
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

	-- 리소스 부족: aim 실패 처리
	if not self:_hasResourceForStart(state) then
		return
	end

	local now = os.clock()
	local def = entry.def

	if now < state.intervalUntil then
		local remaining = state.intervalUntil - now
		-- threshold 미만이면 거부
		if remaining / def.interval > INTERVAL_QUEUE_THRESHOLD then
			return
		end

		-- 예약 발사
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

			-- 예약 실행 시점에 비로소 방향 전환
			self._aimController:StartIntervalLock(capturedDir, def.interval)
		end)

		BasicAttackRemoting.Fire:FireServer(direction)
		return
	end

	-- 즉시 발사
	if self._pendingFireCancel then
		self._pendingFireCancel()
		self._pendingFireCancel = nil
	end

	state.direction = direction
	state.intervalUntil = now + def.interval
	state.lastFireTime = now
	state.effectiveAimTime = 0

	-- 로컬 리소스 차감
	state.currentStack = math.max(0, state.currentStack - 1)
	self._stackReloadTimer = 0 -- 차감 시 타이머 리셋

	self:_onFireExecuted(entry, state)

	BasicAttackRemoting.Fire:FireServer(direction)
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
	self:_onFireExecuted(entry, state) -- coordinator 알림

	local running = true
	self._fireLoopCancel = function()
		running = false
	end

	local def = entry.def

	task.spawn(function()
		while running do
			local now = os.clock()

			-- 루프 지속 조건: gauge는 currentGauge > 0, stack은 시작 조건과 동일
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

			-- interval 대기
			if now >= state.intervalUntil then
				state.intervalUntil = now + def.interval
				state.lastFireTime = now
				state.effectiveAimTime = 0

				-- toggle: HRP 방향, hold: aimController의 현재 direction
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
				-- hold: state.direction은 _onRenderStep(AimController)에서 매 프레임 갱신됨

				-- 로컬 리소스 차감
				if state.resourceType == "stack" then
					state.currentStack = math.max(0, state.currentStack - 1)
					self._stackReloadTimer = 0
				end

				-- fireMaid 갱신
				if state.fireMaid then
					state.fireMaid:Destroy()
				end
				state.fireMaid = Maid.new()

				BasicAttackRemoting.Fire:FireServer(state.direction)
				AbilityExecutor.OnFire(entry.module, state)
			end

			task.wait(0.016) -- ~60fps 간격으로 체크
		end
	end)
end

function BasicAttackClient:_stopFireLoop()
	if self._fireLoopCancel then
		self._fireLoopCancel()
		self._fireLoopCancel = nil
	end

	local state = self._attackState
	if state then
		state.isFiring = false
		state.lastFireEndTime = os.clock()
		-- hold/toggle은 화면 고정 없음 → CancelIntervalLock 호출 안 함
	end

	BasicAttackRemoting.FireEnd:FireServer()
end

-- ─── 내부: fire 공통 처리 ────────────────────────────────────────────────────

function BasicAttackClient:_onFireExecuted(entry: { def: any, module: any, animDef: any }, state: BasicAttackState)
	-- stack의 경우 fireMaid 갱신
	if not state.isFiring then
		if state.fireMaid then
			state.fireMaid:Destroy()
		end
		state.fireMaid = Maid.new()
	end

	-- coordinator에 발동 알림
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
			state.currentStack = payload.currentStack -- 서버 기준 보정
		end
		if type(payload.maxStack) == "number" then
			state.maxStack = payload.maxStack
		end
		if type(payload.reloadTime) == "number" then
			state.reloadTime = payload.reloadTime
			self._stackReloadTimer = 0 -- 보정 시 타이머 리셋 (서버 기준 재시작)
		end

		-- 소진 보정 수신 시 즉시 루프 캔슬
		if state.currentStack <= 0 then
			self:_stopFireLoop()
		end
	elseif rt == "gauge" then
		if type(payload.currentGauge) == "number" then
			state.currentGauge = payload.currentGauge -- 서버 기준 보정
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

		-- 소진 보정 수신 시 즉시 루프 캔슬
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
