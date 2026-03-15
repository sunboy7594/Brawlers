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
	- postDelay 중 발사 무시

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
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BasicAttackDefs = require("BasicAttackDefs")
local BasicAttackRemoting = require("BasicAttackRemoting")
local LoadoutRemoting = require("LoadoutRemoting")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local FIRE_RATE_LIMIT = 0.1
local MAX_DIRECTION_MAGNITUDE_DELTA = 0.1

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
	fireComboCount: number, -- 공격할 때마다 증가
	hitComboCount: number, -- 피격시켰을 때만 증가

	-- 발사 컨텍스트 (발사마다 업데이트)
	attacker: Model?,
	origin: Vector3,
	direction: Vector3,
	aimTime: number,
	idleTime: number,
	victims: { Model }?,

	-- 판정 콜백 (BasicAttackService가 Fire마다 주입, 공격기술 모듈이 InstantHit에 전달)
	onHit: ((victims: { Model }) -> ())?,
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
		idleTime = 0,
		victims = nil,
		onHit = nil,
	}
	self._playerStates[player.UserId] = state

	local function onCharacterAdded(char: Model)
		local humanoid = char:WaitForChild("Humanoid") :: Humanoid
		local rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart
		state.humanoid = humanoid
		state.rootPart = rootPart
		state.attacker = char

		pMaid:GiveTask(humanoid.Died:Connect(function()
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

	-- [1] 레이트 리밋
	if now - state.lastFireTime < FIRE_RATE_LIMIT then
		return
	end

	-- [2] postDelay 검증
	if now < state.postDelayUntil then
		return
	end

	-- [3] direction 검증
	if typeof(direction) ~= "Vector3" then
		return
	end
	local dir = direction :: Vector3
	if math.abs(dir.Magnitude - 1) > MAX_DIRECTION_MAGNITUDE_DELTA then
		return
	end

	-- [4] 탄약 확인
	if state.currentAmmo <= 0 then
		return
	end

	-- [5] 장착 확인
	local attackId = state.equippedAttackId
	if not attackId then
		return
	end
	local entry = ATTACK_REGISTRY[attackId]
	if not entry then
		return
	end

	-- [6] 발사 컨텍스트 업데이트
	state.attacker = state.humanoid and state.humanoid.Parent :: Model? or nil
	state.origin = state.rootPart.Position
	state.direction = dir
	state.aimTime = if state.aimStartTime > 0 then now - state.aimStartTime else 0
	state.idleTime = if state.lastFireTime > 0 then now - state.lastFireTime else 0
	state.victims = nil

	-- [7] 발사 처리
	state.lastFireTime = now
	state.aimStartTime = 0
	state.postDelayUntil = now + state.postDelay
	state.currentAmmo -= 1
	self:_fireAmmoChanged(player, state)

	-- [8] 스냅샷 생성 (Fire 시점 state 복사)
	--     onHit/victims는 이 발사에서 의미 없으므로 초기화
	local snapshot = table.clone(state)
	snapshot.victims = nil
	snapshot.onHit = nil

	-- [9] onHit 콜백 주입
	--     공격기술 모듈의 onFire에서 InstantHit.apply(…, state.onHit)로 사용됨
	--     판정 완료 시점(delay 있든 없든)에 호출됨
	state.onHit = function(victims: { Model })
		-- live state 갱신
		if #victims > 0 then
			state.lastHitTime = os.clock()
		end
		state.victims = victims

		-- snapshot에 victims + 최신 콤보 카운트 반영
		-- fireComboCount는 onFire에서 변경되므로 onHit 시점에 동기화
		snapshot.victims = victims
		snapshot.fireComboCount = state.fireComboCount
		snapshot.hitComboCount = state.hitComboCount

		-- 서버 onHitChecked 훅 실행 (snapshot 기준 컨텍스트)
		if entry.module.onHitChecked then
			for _, fn in entry.module.onHitChecked do
				fn(snapshot)
			end
		end

		-- HitChecked → 공격자만
		local victimUserIds: { number } = {}
		for _, victimModel in victims do
			local victimPlayer = Players:GetPlayerFromCharacter(victimModel)
			if victimPlayer then
				table.insert(victimUserIds, victimPlayer.UserId)
			end
		end
		BasicAttackRemoting.HitChecked:FireClient(player, victimUserIds)
	end

	-- [10] onFire 배열 실행
	--      공격기술 모듈은 InstantHit.apply(…, state.onHit)를 호출함
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

	state.equippedAttackId = attackId
	state.maxAmmo = entry.def.maxAmmo
	state.reloadTime = entry.def.reloadTime
	state.postDelay = entry.def.postDelay
	state.currentAmmo = entry.def.maxAmmo
	state.postDelayUntil = 0
	state.lastRegenTime = os.clock()
	state.lastHitTime = 0
	state.fireComboCount = 0
	state.hitComboCount = 0
	state.onHit = nil

	self:_fireAmmoChanged(player, state)
end

function BasicAttackService.Destroy(self: BasicAttackService)
	self._maid:Destroy()
end

return BasicAttackService
