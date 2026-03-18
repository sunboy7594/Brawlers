--!strict
--[=[
	@class BasicAttackService

	기본 공격 서버 서비스.

	담당:
	- 플레이어별 리소스 상태 관리
	- stack: 독립 재생 (Heartbeat) → 장전 틱마다 ResourceSync
	- gauge: 발사 중 drain, 종료 후 regenDelay → regen (Heartbeat)
	         소진 시 / max 도달 시 ResourceSync
	- BasicAttackRemoting.Fire 수신 → 검증 → onFire 실행 → ResourceSync
	- BasicAttackRemoting.FireEnd 수신 → hold/toggle 상태 관리
	- 히트 체크 후 HitChecked:FireClient(공격자) 발송
	- LoadoutRemoting.RequestEquipBasicAttack → 유효성 검증 후 장착 처리

	ResourceSync 발송 시점:
	- stack: 발사마다 + 장전 틱마다
	- gauge: 발사마다 + 소진 시 + max 도달 시
	- reloadRateMult / regenRateMult 변경 시 (PSC의 EffectiveMultipliersChanged)
	- resourceDelta 적용 시 (PSC의 ResourceDeltaApplied)

	리소스 배율:
	- reloadRateMult: PSC에서 가져와 유효 reloadTime에 반영 (높을수록 빠른 장전)
	- regenRateMult:  PSC에서 가져와 유효 regenRate에 반영  (높을수록 빠른 재생)
	- ResourceSync에는 항상 유효 값(배율 적용됨)을 전송합니다.

	Anti-exploit:
	- FIRE_RATE_LIMIT (0.1초)
	- direction 타입/크기 검증
	- IsAbilityLocked("BasicAttack") 검증
	- stack: currentStack > 0, interval 비율 검증
	- gauge 시작: currentGauge >= minGauge
	- gauge 루프 중: currentGauge > 0

	fireMaid:
	- _executeFire 시마다 새 Maid 생성. CancelCombatState 시 Destroy.
	- 서버 모듈(onFire)이 GiveTask로 딜레이 히트 취소 등록 가능.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AbilityTypes = require("AbilityTypes")
local BasicAttackDefs = require("BasicAttackDefs")
local BasicAttackRemoting = require("BasicAttackRemoting")
local ClassService = require("ClassService")
local LoadoutRemoting = require("LoadoutRemoting")
local Maid = require("Maid")
local PlayerStateControllerService = require("PlayerStateControllerService")
local ServiceBag = require("ServiceBag")
local cancellableDelay = require("cancellableDelay")

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local FIRE_RATE_LIMIT = 0.1
local MAX_DIRECTION_MAGNITUDE_DELTA = 0.1
local MIN_RELOAD_RATE_MULT = 0.01 -- 0 나누기 방지

-- ⚠️ 주의: BasicAttackClient.lua의 INTERVAL_QUEUE_THRESHOLD와 반드시 동일해야 합니다.
local INTERVAL_QUEUE_THRESHOLD = AbilityTypes.INTERVAL_QUEUE_THRESHOLD

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type BasicAttackState = {
	-- 장착 정보
	equippedAttackId: string?,
	fireType: "stack" | "hold" | "toggle",
	resourceType: "stack" | "gauge",

	-- 캐릭터
	humanoid: Humanoid?,
	rootPart: BasePart?,

	-- stack 리소스
	currentStack: number,
	maxStack: number,
	reloadTime: number,
	lastRegenTime: number,

	-- gauge 리소스
	currentGauge: number,
	maxGauge: number,
	minGauge: number,
	drainRate: number,
	regenRate: number,
	regenDelay: number,
	isFiring: boolean,
	lastFireEndTime: number,

	-- 공통 타이밍
	interval: number,
	lastFireTime: number,
	intervalUntil: number,
	lastHitTime: number,
	aimStartTime: number,

	-- 콤보
	fireComboCount: number,
	hitComboCount: number,

	-- 발사 컨텍스트
	attacker: Model?,
	origin: Vector3,
	direction: Vector3,
	aimTime: number,
	effectiveAimTime: number,
	idleTime: number,
	victims: { Model }?,

	-- 판정 콜백
	onHit: ((victims: { Model }) -> ())?,

	-- 예약 발사 취소 함수
	pendingFireCancel: (() -> ())?,

	-- 발사 수명 관리 (모듈이 GiveTask로 딜레이 히트 취소 등록)
	fireMaid: any?,

	-- snapshot 전용 주입 필드
	playerStateController: any?,
	attackerStates: { any }?,
}

type AttackModule = {
	onFire: { (state: BasicAttackState) -> () }?,
	onHitChecked: { (state: BasicAttackState) -> () }?,
}

type AttackEntry = {
	def: BasicAttackDefs.BasicAttackDef,
	module: AttackModule,
}

-- ─── 레지스트리 ──────────────────────────────────────────────────────────────

local ATTACK_REGISTRY: { [string]: AttackEntry } = {}
for id, def in BasicAttackDefs do
	ATTACK_REGISTRY[id] = {
		def = def,
		module = require(id .. "Server"),
	}
end

-- ─── 서비스 타입 ─────────────────────────────────────────────────────────────

export type BasicAttackService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_playerStateController: any,
		_classService: any,
		_playerStates: { [number]: BasicAttackState },
		_playerMaids: { [number]: any },
	},
	{} :: typeof({ __index = {} })
))

local BasicAttackService = {}
BasicAttackService.ServiceName = "BasicAttackService"
BasicAttackService.__index = BasicAttackService

-- ─── 초기화 ──────────────────────────────────────────────────────────────────

function BasicAttackService.Init(self: BasicAttackService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._playerStateController = serviceBag:GetService(PlayerStateControllerService)
	self._classService = serviceBag:GetService(ClassService)
	self._playerStates = {}
	self._playerMaids = {}
end

function BasicAttackService.Start(self: BasicAttackService): ()
	self._maid:GiveTask(Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end))
	for _, player in Players:GetPlayers() do
		self:_onPlayerAdded(player)
	end
	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end))

	self._maid:GiveTask(RunService.Heartbeat:Connect(function(dt: number)
		self:_updateResources(dt)
	end))

	self._maid:GiveTask(BasicAttackRemoting.AimStarted:Connect(function(player: Player)
		self:_onAimStarted(player)
	end))

	self._maid:GiveTask(BasicAttackRemoting.Fire:Connect(function(player: Player, direction: unknown)
		self:_onFire(player, direction)
	end))

	self._maid:GiveTask(BasicAttackRemoting.FireEnd:Connect(function(player: Player)
		self:_onFireEnd(player)
	end))

	LoadoutRemoting.RequestEquipBasicAttack:Bind(function(player: Player, attackId: unknown)
		return self:_onRequestEquip(player, attackId)
	end)

	-- PSC 시그널 구독: resourceDelta 즉시 반영
	self._maid:GiveTask(
		self._playerStateController.ResourceDeltaApplied:Connect(function(player: Player, amount: number)
			self:_applyResourceDelta(player, amount)
		end)
	)

	-- PSC 시그널 구독: reloadRateMult/regenRateMult 변경 시 ResourceSync 재발송
	self._maid:GiveTask(self._playerStateController.EffectiveMultipliersChanged:Connect(function(player: Player)
		local state = self._playerStates[player.UserId]
		if state then
			self:_fireResourceSync(player, state)
		end
	end))
end

-- ─── 플레이어 관리 ───────────────────────────────────────────────────────────

function BasicAttackService:_onPlayerAdded(player: Player)
	local playerMaid = Maid.new()
	self._playerMaids[player.UserId] = playerMaid

	local state: BasicAttackState = {
		equippedAttackId = nil,
		fireType = "stack",
		resourceType = "stack",
		humanoid = nil,
		rootPart = nil,

		currentStack = 0,
		maxStack = 0,
		reloadTime = 0,
		lastRegenTime = 0,

		currentGauge = 0,
		maxGauge = 0,
		minGauge = 0,
		drainRate = 0,
		regenRate = 0,
		regenDelay = 0,
		isFiring = false,
		lastFireEndTime = 0,

		interval = 0,
		lastFireTime = 0,
		intervalUntil = 0,
		lastHitTime = 0,
		aimStartTime = 0,

		fireComboCount = 0,
		hitComboCount = 0,

		attacker = nil,
		origin = Vector3.zero,
		direction = Vector3.new(0, 0, -1),
		aimTime = 0,
		effectiveAimTime = 0,
		idleTime = 0,
		victims = nil,

		onHit = nil,
		pendingFireCancel = nil,
		fireMaid = nil,
		playerStateController = nil,
		attackerStates = nil,
	}
	self._playerStates[player.UserId] = state

	playerMaid:GiveTask(player.CharacterAdded:Connect(function(char)
		self:_onCharacterAdded(player, char)
	end))
	if player.Character then
		self:_onCharacterAdded(player, player.Character)
	end
end

function BasicAttackService:_onCharacterAdded(player: Player, char: Model)
	local state = self._playerStates[player.UserId]
	if not state then
		return
	end

	local hum = char:WaitForChild("Humanoid") :: Humanoid
	local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart

	state.humanoid = hum
	state.rootPart = hrp
end

function BasicAttackService:_onPlayerRemoving(player: Player)
	local maid = self._playerMaids[player.UserId]
	if maid then
		maid:Destroy()
		self._playerMaids[player.UserId] = nil
	end
	self._playerStates[player.UserId] = nil
end

-- ─── 리소스 업데이트 (Heartbeat) ─────────────────────────────────────────────

function BasicAttackService:_updateResources(dt: number)
	local now = os.clock()
	for userId, state in self._playerStates do
		if state.resourceType == "stack" then
			self:_updateStackRegen(userId, state, now)
		elseif state.resourceType == "gauge" then
			self:_updateGauge(userId, state, now, dt)
		end
	end
end

function BasicAttackService:_updateStackRegen(userId: number, state: BasicAttackState, now: number)
	if state.currentStack >= state.maxStack or state.maxStack == 0 then
		return
	end
	if state.reloadTime <= 0 then
		return
	end

	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end

	local reloadRateMult = self._playerStateController:GetReloadRateMult(player)
	local effectiveReloadTime = state.reloadTime / math.max(reloadRateMult, MIN_RELOAD_RATE_MULT)

	if now - state.lastRegenTime >= effectiveReloadTime then
		state.currentStack = math.min(state.currentStack + 1, state.maxStack)
		state.lastRegenTime = now
		self:_fireResourceSync(player, state)
	end
end

function BasicAttackService:_updateGauge(userId: number, state: BasicAttackState, now: number, dt: number)
	if state.maxGauge <= 0 then
		return
	end

	if state.isFiring and state.currentGauge > 0 then
		state.currentGauge = math.max(0, state.currentGauge - state.drainRate * dt)

		if state.currentGauge <= 0 then
			state.isFiring = false
			state.lastFireEndTime = now
			local player = Players:GetPlayerByUserId(userId)
			if player then
				self:_fireResourceSync(player, state)
			end
		end
	elseif not state.isFiring and state.currentGauge < state.maxGauge then
		if now - state.lastFireEndTime >= state.regenDelay then
			local player = Players:GetPlayerByUserId(userId)
			if not player then
				return
			end

			local regenRateMult = self._playerStateController:GetRegenRateMult(player)
			local effectiveRegenRate = state.regenRate * regenRateMult

			local prev = state.currentGauge
			state.currentGauge = math.min(state.maxGauge, state.currentGauge + effectiveRegenRate * dt)

			if prev < state.maxGauge and state.currentGauge >= state.maxGauge then
				self:_fireResourceSync(player, state)
			end
		end
	end
end

-- ─── 조준 시작 처리 ──────────────────────────────────────────────────────────

function BasicAttackService:_onAimStarted(player: Player)
	local state = self._playerStates[player.UserId]
	if not state then
		return
	end

	local now = os.clock()
	if now < state.intervalUntil then
		return
	end
	if not self:_hasResourceForStart(state) then
		return
	end
	if not state.equippedAttackId then
		return
	end
	if self._playerStateController:IsAbilityLocked(player, "BasicAttack") then
		return
	end

	state.aimStartTime = now
end

-- ─── FireEnd (hold/toggle) ────────────────────────────────────────────────────

function BasicAttackService:_onFireEnd(player: Player)
	local state = self._playerStates[player.UserId]
	if not state then
		return
	end

	state.isFiring = false
	state.lastFireEndTime = os.clock()
end

-- ─── 발사 처리 ───────────────────────────────────────────────────────────────

function BasicAttackService:_onFire(player: Player, direction: unknown)
	local state = self._playerStates[player.UserId]
	if not state or not state.humanoid or not state.rootPart then
		return
	end

	-- 어빌리티 잠금 검증
	if self._playerStateController:IsAbilityLocked(player, "BasicAttack") then
		return
	end

	local now = os.clock()

	if now - state.lastFireTime < FIRE_RATE_LIMIT then
		return
	end

	if typeof(direction) ~= "Vector3" then
		return
	end
	local dir = direction :: Vector3
	if math.abs(dir.Magnitude - 1) > MAX_DIRECTION_MAGNITUDE_DELTA then
		return
	end

	local attackId = state.equippedAttackId
	if not attackId then
		return
	end
	local entry = ATTACK_REGISTRY[attackId]
	if not entry then
		return
	end

	local fireType = state.fireType

	if fireType == "hold" or fireType == "toggle" then
		if not state.isFiring then
			if not self:_hasResourceForStart(state) then
				return
			end
			state.isFiring = true
		else
			if state.resourceType == "gauge" and state.currentGauge <= 0 then
				return
			end
			if state.resourceType == "stack" and not self:_hasResourceForStart(state) then
				return
			end
		end
	else
		if not self:_hasResourceForStart(state) then
			return
		end
	end

	if fireType == "stack" then
		if now < state.intervalUntil then
			local remaining = state.intervalUntil - now
			if remaining / state.interval <= INTERVAL_QUEUE_THRESHOLD then
				if state.pendingFireCancel then
					state.pendingFireCancel()
				end
				state.pendingFireCancel = cancellableDelay(remaining, function()
					state.pendingFireCancel = nil
					self:_executeFire(player, state, dir, entry)
				end)
			end
			return
		end

		if state.pendingFireCancel then
			state.pendingFireCancel()
			state.pendingFireCancel = nil
		end
	end

	self:_executeFire(player, state, dir, entry)
end

-- ─── 실제 발사 실행 ──────────────────────────────────────────────────────────

function BasicAttackService:_executeFire(player: Player, state: BasicAttackState, dir: Vector3, entry: AttackEntry)
	if not state.humanoid or not state.rootPart then
		return
	end

	local now = os.clock()

	state.attacker = state.humanoid.Parent :: Model?
	state.origin = state.rootPart.Position
	state.direction = dir
	state.aimTime = if state.aimStartTime > 0 then now - state.aimStartTime else 0
	state.idleTime = if state.lastFireTime > 0 then now - state.lastFireTime else 0
	state.effectiveAimTime = 0
	state.victims = nil

	state.lastFireTime = now
	state.aimStartTime = 0

	if state.fireType == "stack" then
		state.currentStack -= 1
		state.intervalUntil = now + state.interval
		self:_fireResourceSync(player, state)
	end

	if state.resourceType == "gauge" then
		self:_fireResourceSync(player, state)
	end

	if state.fireMaid then
		state.fireMaid:Destroy()
	end
	state.fireMaid = Maid.new()

	local snapshot = table.clone(state)
	snapshot.victims = nil
	snapshot.onHit = nil
	snapshot.pendingFireCancel = nil
	snapshot.fireMaid = state.fireMaid
	snapshot.playerStateController = self._playerStateController
	snapshot.attackerStates = self._playerStateController:GetActiveEffects(player)

	state.onHit = function(victims: { Model })
		if #victims > 0 then
			state.lastHitTime = os.clock()
		end
		state.victims = victims
		snapshot.victims = victims
		snapshot.fireComboCount = state.fireComboCount
		snapshot.hitComboCount = state.hitComboCount

		if entry.module.onHitChecked then
			for _, fn in entry.module.onHitChecked do
				fn(snapshot)
			end
		end

		local victimUserIds: { number } = {}
		for _, victimModel in victims do
			local victimPlayer = Players:GetPlayerFromCharacter(victimModel)
			if victimPlayer then
				table.insert(victimUserIds, victimPlayer.UserId)
			end
		end
		BasicAttackRemoting.HitChecked:FireClient(player, victimUserIds)
	end

	if entry.module.onFire then
		for _, fn in entry.module.onFire do
			fn(state)
		end
	end
end

-- ─── 리소스 델타 적용 ────────────────────────────────────────────────────────

--[=[
	PSC의 ResourceDeltaApplied 시그널에서 호출됩니다.
	stack → currentStack 직접 증감
	gauge → currentGauge 직접 증감
	양수=충전/회복, 음수=소모.
]=]
function BasicAttackService:_applyResourceDelta(player: Player, amount: number)
	local state = self._playerStates[player.UserId]
	if not state then
		return
	end

	if state.resourceType == "stack" then
		state.currentStack = math.clamp(state.currentStack + math.round(amount), 0, state.maxStack)
	elseif state.resourceType == "gauge" then
		state.currentGauge = math.clamp(state.currentGauge + amount, 0, state.maxGauge)
	end

	self:_fireResourceSync(player, state)
end

-- ─── 헬퍼 ────────────────────────────────────────────────────────────────────

function BasicAttackService:_hasResourceForStart(state: BasicAttackState): boolean
	if state.resourceType == "stack" then
		return state.currentStack > 0
	elseif state.resourceType == "gauge" then
		return state.currentGauge >= state.minGauge
	end
	return false
end

--[=[
	유효 값(배율 적용)을 클라이언트에 전송합니다.
	reloadTime → base / reloadRateMult
	regenRate  → base * regenRateMult
]=]
function BasicAttackService:_fireResourceSync(player: Player, state: BasicAttackState)
	local payload: { [string]: any }

	if state.resourceType == "stack" then
		local reloadRateMult = self._playerStateController:GetReloadRateMult(player)
		local effectiveReloadTime = state.reloadTime / math.max(reloadRateMult, MIN_RELOAD_RATE_MULT)
		payload = {
			resourceType = "stack",
			currentStack = state.currentStack,
			maxStack = state.maxStack,
			reloadTime = effectiveReloadTime,
			interval = state.interval,
		}
	else
		local regenRateMult = self._playerStateController:GetRegenRateMult(player)
		local effectiveRegenRate = state.regenRate * regenRateMult
		payload = {
			resourceType = "gauge",
			currentGauge = state.currentGauge,
			maxGauge = state.maxGauge,
			minGauge = state.minGauge,
			drainRate = state.drainRate,
			regenRate = effectiveRegenRate,
			regenDelay = state.regenDelay,
			interval = state.interval,
		}
	end

	BasicAttackRemoting.ResourceSync:FireClient(player, payload)
end

function BasicAttackService:_setPlayerAttack(player: Player, attackId: string)
	local state = self._playerStates[player.UserId]
	if not state then
		return
	end
	local entry = ATTACK_REGISTRY[attackId]
	if not entry then
		return
	end

	self:CancelCombatState(player)

	local def = entry.def
	local resource = def.resource

	state.equippedAttackId = attackId
	state.fireType = def.fireType
	state.resourceType = resource.resourceType
	state.interval = def.interval
	state.intervalUntil = 0
	state.aimStartTime = 0
	state.effectiveAimTime = 0
	state.lastHitTime = 0
	state.fireComboCount = 0
	state.hitComboCount = 0
	state.onHit = nil
	state.isFiring = false
	state.lastFireEndTime = 0
	state.lastFireTime = 0

	if resource.resourceType == "stack" then
		local r = resource :: AbilityTypes.StackResource
		state.maxStack = r.maxStack
		state.reloadTime = r.reloadTime
		state.currentStack = r.maxStack
		state.lastRegenTime = os.clock()
		state.currentGauge = 0
		state.maxGauge = 0
		state.minGauge = 0
		state.drainRate = 0
		state.regenRate = 0
		state.regenDelay = 0
	elseif resource.resourceType == "gauge" then
		local r = resource :: AbilityTypes.GaugeResource
		state.maxGauge = r.maxGauge
		state.minGauge = r.minGauge
		state.drainRate = r.drainRate
		state.regenRate = r.regenRate
		state.regenDelay = r.regenDelay
		state.currentGauge = r.maxGauge
		state.currentStack = 0
		state.maxStack = 0
		state.reloadTime = 0
		state.lastRegenTime = 0
	end

	self:_fireResourceSync(player, state)
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	공격불가 등 외부 이벤트로 전투 상태를 강제 초기화합니다.
]=]
function BasicAttackService:CancelCombatState(player: Player)
	local state = self._playerStates[player.UserId]
	if not state then
		return
	end

	if state.pendingFireCancel then
		state.pendingFireCancel()
		state.pendingFireCancel = nil
	end

	if state.fireMaid then
		state.fireMaid:Destroy()
		state.fireMaid = nil
	end

	state.isFiring = false
	state.lastFireEndTime = os.clock()
	state.intervalUntil = 0
	state.aimStartTime = 0
	state.effectiveAimTime = 0
	state.onHit = nil
end

function BasicAttackService:ForceEquip(player: Player, attackId: string): (boolean, string?)
	if not ATTACK_REGISTRY[attackId] then
		return false, "unknown attackId: " .. attackId
	end
	self:_setPlayerAttack(player, attackId)
	LoadoutRemoting.EquippedBasicAttackChanged:FireClient(player, attackId)
	return true, nil
end

function BasicAttackService:_onRequestEquip(player: Player, attackId: unknown): (boolean, string?)
	if type(attackId) ~= "string" then
		return false, "invalid attackId"
	end
	if not ATTACK_REGISTRY[attackId] then
		return false, "unknown attackId"
	end

	local classData = self._classService:GetClass(player)
	local entry = ATTACK_REGISTRY[attackId]
	if classData and entry.def.class ~= classData then
		return false, "class mismatch"
	end

	self:_setPlayerAttack(player, attackId)
	return true, nil
end

function BasicAttackService.Destroy(self: BasicAttackService)
	self._maid:Destroy()
end

return BasicAttackService
