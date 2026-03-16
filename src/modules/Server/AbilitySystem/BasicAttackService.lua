--!strict
--[=[
	@class BasicAttackService

	기본 공격 서버 서비스.

	담당:
	- 플레이어별 탄약 상태 관리
	- 탄약 1칸씩 독립 재생 (Heartbeat)
	- BasicAttackRemoting.Fire 수신 → 검증 → 서버 공격 모듈 onFire 배열 실행
	- 히트 체크 후 HitChecked:FireClient(공격자) 발송
	- LoadoutRemoting.RequestEquipBasicAttack → 유효성 검증 후 장착 처리

	Anti-exploit:
	- 레이트 리밋 (FIRE_RATE_LIMIT = 0.1초)
	- direction 타입/크기 검증
	- 탄약 0이면 무시
	- postDelay 잔여 비율 > POST_DELAY_QUEUE_THRESHOLD 이면 무시
	- postDelay 잔여 비율 ≤ POST_DELAY_QUEUE_THRESHOLD 이면 예약 발사

	BasicAttackState:
	- 플레이어 관리 필드 + 발사 컨텍스트를 단일 테이블로 관리
	- 클라이언트 전송값 일절 사용 안 함 (direction 검증 제외)
	- hitComboCount/fireComboCount 증감은 각 공격 모듈이 담당

	onHit 콜백:
	- Fire 시점에 BasicAttackService가 state.onHit에 주입
	- 공격기술 모듈은 InstantHit.apply()에 state.onHit을 넘겨 판정 완료 시 호출되도록 함
	- 판정 완료 시점에 HitChecked(공격자), onHitChecked 훅 실행

	스냅샷:
	- Fire 시점에 table.clone(state)으로 생성
	- onHit 콜백 및 onHitChecked 훅에 전달
	- delay가 있는 공격에서 state가 다음 Fire로 덮어씌워져도 이 발사의 컨텍스트 보존

	예약 발사 (pendingFireCancel):
	- postDelay 잔여 비율 ≤ POST_DELAY_QUEUE_THRESHOLD(30%) 일 때 공격 시도 시
	  cancellableDelay로 잔여 시간 후 자동 발사 예약
	- 예약 중 새 공격 시도 → 기존 예약 교체 (방향 갱신)
	- 즉시 발사 시 / 무기 교체 시 / 클래스 변경 시 → 예약 자동 취소
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BasicAttackDefs = require("BasicAttackDefs")
local BasicAttackRemoting = require("BasicAttackRemoting")
local LoadoutRemoting = require("LoadoutRemoting")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local cancellableDelay = require("cancellableDelay")

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local FIRE_RATE_LIMIT = 0.1
local MAX_DIRECTION_MAGNITUDE_DELTA = 0.1

-- ⚠️ 주의: BasicAttackClient.lua의 POST_DELAY_QUEUE_THRESHOLD와
--          반드시 동일한 값을 유지해야 합니다.
--          한쪽만 바꾸면 예약 발사 타이밍이 서버-클라이언트 간 어긋납니다.
local POST_DELAY_QUEUE_THRESHOLD = 0.8 -- 잔여 비율 80% 이하일 때 예약 발사

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type BasicAttackState = {
	-- 장착 정보
	equippedAttackId: string?,

	-- 캐릭터
	humanoid: Humanoid?,
	rootPart: BasePart?,

	-- 탄약
	currentAmmo: number,
	maxAmmo: number,
	reloadTime: number,
	postDelay: number,

	-- 타이밍
	lastFireTime: number,
	postDelayUntil: number,
	lastRegenTime: number,
	lastHitTime: number,
	aimStartTime: number,

	-- 콤보 (증감은 각 공격 모듈이 담당)
	fireComboCount: number,
	hitComboCount: number,

	-- 발사 컨텍스트 (발사마다 업데이트)
	attacker: Model?,
	origin: Vector3,
	direction: Vector3,
	aimTime: number,
	effectiveAimTime: number, -- 추가
	idleTime: number,
	victims: { Model }?,

	-- 판정 콜백
	onHit: ((victims: { Model }) -> ())?,

	-- 예약 발사 취소 함수
	pendingFireCancel: (() -> ())?,
}

type AttackModule = {
	onFire: { (state: BasicAttackState) -> () }?,
	onHitChecked: { (state: BasicAttackState) -> () }?,
}

type AttackEntry = {
	def: typeof(BasicAttackDefs.Tank_Punch),
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
	self._playerStates = {}
	self._playerMaids = {}

	self._maid:GiveTask(BasicAttackRemoting.AimStarted:Connect(function(player: Player)
		self:_onAimStarted(player)
	end))

	self._maid:GiveTask(BasicAttackRemoting.Fire:Connect(function(player: Player, direction: unknown)
		self:_onFire(player, direction)
	end))

	self._maid:GiveTask(LoadoutRemoting.RequestEquipBasicAttack:Bind(function(player: Player, attackId: unknown)
		if type(attackId) ~= "string" then
			return false, "Invalid attackId type"
		end
		if not ATTACK_REGISTRY[attackId] then
			return false, "Unknown attackId: " .. attackId
		end
		self:_setPlayerAttack(player, attackId)
		return true, attackId
	end))
end

function BasicAttackService.Start(self: BasicAttackService): ()
	for _, player in Players:GetPlayers() do
		self:_onPlayerAdded(player)
	end

	self._maid:GiveTask(Players.PlayerAdded:Connect(function(player: Player)
		self:_onPlayerAdded(player)
	end))

	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player: Player)
		self:_onPlayerRemoving(player)
	end))

	self._maid:GiveTask(RunService.Heartbeat:Connect(function()
		self:_updateAmmoRegen()
	end))
end

-- ─── 플레이어 관리 ───────────────────────────────────────────────────────────

function BasicAttackService:_onPlayerAdded(player: Player)
	local pMaid = Maid.new()
	self._playerMaids[player.UserId] = pMaid

	local state: BasicAttackState = {
		equippedAttackId = nil,
		humanoid = nil,
		rootPart = nil,
		currentAmmo = 0,
		maxAmmo = 0,
		reloadTime = 0,
		postDelay = 0,
		lastFireTime = 0,
		postDelayUntil = 0,
		lastRegenTime = 0,
		lastHitTime = 0,
		aimStartTime = 0,
		fireComboCount = 0,
		hitComboCount = 0,
		attacker = nil,
		origin = Vector3.zero,
		direction = Vector3.new(0, 0, -1),
		aimTime = 0,
		effectiveAimTime = 0, -- 추가
		idleTime = 0,
		victims = nil,
		onHit = nil,
		pendingFireCancel = nil,
	}
	self._playerStates[player.UserId] = state

	local function onCharacterAdded(char: Model)
		local humanoid = char:WaitForChild("Humanoid") :: Humanoid
		local rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart
		state.humanoid = humanoid
		state.rootPart = rootPart
		state.attacker = char

		pMaid:GiveTask(humanoid.Died:Connect(function()
			if state.pendingFireCancel then
				state.pendingFireCancel()
				state.pendingFireCancel = nil
			end
			state.humanoid = nil
			state.rootPart = nil
			state.attacker = nil
		end))
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end
	pMaid:GiveTask(player.CharacterAdded:Connect(onCharacterAdded))
end

function BasicAttackService:_onPlayerRemoving(player: Player)
	local state = self._playerStates[player.UserId]
	if state and state.pendingFireCancel then
		state.pendingFireCancel()
		state.pendingFireCancel = nil
	end
	self._playerStates[player.UserId] = nil

	local pMaid = self._playerMaids[player.UserId]
	if pMaid then
		pMaid:Destroy()
		self._playerMaids[player.UserId] = nil
	end
end

-- ─── 조준 시작 처리 ──────────────────────────────────────────────────────────

function BasicAttackService:_onAimStarted(player: Player)
	local state = self._playerStates[player.UserId]
	if not state then
		return
	end

	local now = os.clock()
	if now < state.postDelayUntil then
		return
	end
	if state.currentAmmo <= 0 then
		return
	end
	if not state.equippedAttackId then
		return
	end

	state.aimStartTime = now
end

-- ─── 발사 처리 ───────────────────────────────────────────────────────────────

function BasicAttackService:_onFire(player: Player, direction: unknown)
	local state = self._playerStates[player.UserId]
	if not state or not state.humanoid or not state.rootPart then
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

	if state.currentAmmo <= 0 then
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

	if now < state.postDelayUntil then
		local remaining = state.postDelayUntil - now
		if remaining / state.postDelay <= POST_DELAY_QUEUE_THRESHOLD then
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
	self:_executeFire(player, state, dir, entry)
end

-- ─── 실제 발사 실행 (즉시 / 예약 공통) ──────────────────────────────────────

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
	state.effectiveAimTime = 0 -- 추가
	state.victims = nil

	state.lastFireTime = now
	state.aimStartTime = 0
	state.postDelayUntil = now + state.postDelay
	state.currentAmmo -= 1
	self:_fireAmmoChanged(player, state)

	local snapshot = table.clone(state)
	snapshot.victims = nil
	snapshot.onHit = nil
	snapshot.pendingFireCancel = nil

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

-- ─── 탄약 재생 ───────────────────────────────────────────────────────────────

function BasicAttackService:_updateAmmoRegen()
	local now = os.clock()
	for userId, state in self._playerStates do
		if state.currentAmmo >= state.maxAmmo or state.maxAmmo == 0 then
			continue
		end
		if state.reloadTime <= 0 then
			continue
		end
		if now - state.lastRegenTime >= state.reloadTime then
			state.currentAmmo = math.min(state.currentAmmo + 1, state.maxAmmo)
			state.lastRegenTime = now
			local player = Players:GetPlayerByUserId(userId)
			if player then
				self:_fireAmmoChanged(player, state)
			end
		end
	end
end

-- ─── 헬퍼 ────────────────────────────────────────────────────────────────────

function BasicAttackService:_fireAmmoChanged(player: Player, state: BasicAttackState)
	BasicAttackRemoting.AmmoChanged:FireClient(
		player,
		state.currentAmmo,
		state.maxAmmo,
		state.reloadTime,
		state.postDelay
	)
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

	if state.pendingFireCancel then
		state.pendingFireCancel()
		state.pendingFireCancel = nil
	end

	state.equippedAttackId = attackId
	state.maxAmmo = entry.def.maxAmmo
	state.reloadTime = entry.def.reloadTime
	state.postDelay = entry.def.postDelay
	state.currentAmmo = entry.def.maxAmmo
	state.postDelayUntil = 0
	state.aimStartTime = 0
	state.effectiveAimTime = 0 -- 추가
	state.lastRegenTime = os.clock()
	state.lastHitTime = 0
	state.fireComboCount = 0
	state.hitComboCount = 0
	state.onHit = nil

	self:_fireAmmoChanged(player, state)
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	클래스 변경 등 외부 이벤트로 전투 상태를 강제 초기화합니다.
	pendingFireCancel 취소, onHit 클로저 무효화, postDelayUntil/aimStartTime 리셋.
	@param player Player
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

	state.postDelayUntil = 0
	state.aimStartTime = 0
	state.effectiveAimTime = 0 -- 추가
	state.onHit = nil
end

function BasicAttackService.Destroy(self: BasicAttackService)
	self._maid:Destroy()
end

return BasicAttackService
