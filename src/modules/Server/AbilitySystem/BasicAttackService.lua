--!strict
--[=[
	@class BasicAttackService

	기본 공격 서버 서비스.

	담당:
	- 플레이어별 탄약 상태 관리
	- 탄약 1칸씩 독립 재생 (Heartbeat)
	- BasicAttackRemoting.Fire 수신 → 검증 → 서버 공격 모듈 onFire 배열 실행
	- 히트 확정 후 HitConfirmed:FireAllClients() 발송
	- LoadoutRemoting.RequestEquipBasicAttack → 유효성 검증 후 장착 처리

	Anti-exploit:
	- 레이트 리밋 (FIRE_RATE_LIMIT = 0.1초)
	- direction 타입/크기 검증
	- 탄약 0이면 무시
	- postDelay 중 발사 무시

	sctx (서버 컨텍스트):
	- PlayerState 안에 보관, 발사마다 필드 업데이트
	- 클라이언트 전송값 일절 사용 안 함 (direction 검증 제외)
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
local COMBO_RESET_TIME = 4.0 -- 이 시간 내 발사 없으면 콤보 초기화

-- ─── 레지스트리 ──────────────────────────────────────────────────────────────

type ServerContext = {
	attacker: Model?,
	origin: Vector3,
	direction: Vector3,
	comboCount: number,
	aimTime: number, -- 서버 측정 (lastFireTime 기준)
	idleTime: number, -- 마지막 발사 후 경과 시간
	victims: { Model }?,
}

type AttackModule = {
	onFire: { (sctx: ServerContext) -> () }?,
	onHitConfirmed: { (sctx: ServerContext) -> () }?,
}

type AttackEntry = {
	def: typeof(BasicAttackDefs.Tank_Punch),
	module: AttackModule,
}

local ATTACK_REGISTRY: { [string]: AttackEntry } = {}
for id, def in BasicAttackDefs do
	ATTACK_REGISTRY[id] = {
		def = def,
		module = require(id .. "Server"),
	}
end

-- ─── 타입 ────────────────────────────────────────────────────────────────────

type PlayerState = {
	-- 장착 정보
	equippedAttackId: string?,

	-- 탄약
	currentAmmo: number,
	maxAmmo: number,
	reloadTime: number,
	postDelay: number,

	-- 타이밍
	lastFireTime: number, -- 마지막 발사 시각 (os.clock)
	postDelayUntil: number,
	lastRegenTime: number,
	lastHitTime: number, -- 마지막 발사 성공 시각
	aimStartTime: number, -- AimStarted 수신 시각 (aimTime 계산 기준)

	-- 콤보
	comboCount: number,

	-- 캐릭터
	humanoid: Humanoid?,
	rootPart: BasePart?,

	-- 서버 컨텍스트 (발사마다 필드 업데이트)
	sctx: ServerContext,
}

export type BasicAttackService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_playerStates: { [number]: PlayerState },
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

	-- AimStarted 수신 → aimStartTime 기록
	self._maid:GiveTask(BasicAttackRemoting.AimStarted:Connect(function(player: Player)
		self:_onAimStarted(player)
	end))

	-- direction만 수신 (aimTime 제거)
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
	self._maid:GiveTask(Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end))
	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end))
	self._maid:GiveTask(RunService.Heartbeat:Connect(function()
		self:_updateAmmoRegen()
	end))
end

-- ─── 플레이어 라이프사이클 ────────────────────────────────────────────────────

local function makeEmptySctx(): ServerContext
	return {
		attacker = nil,
		origin = Vector3.zero,
		direction = Vector3.new(0, 0, -1),
		comboCount = 0,
		aimTime = 0,
		idleTime = 0,
		victims = nil,
	}
end

function BasicAttackService:_onPlayerAdded(player: Player)
	local pMaid = Maid.new()
	self._playerMaids[player.UserId] = pMaid

	local function onCharacterAdded(char: Model)
		local humanoid = char:WaitForChild("Humanoid") :: Humanoid
		local rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart

		local existing = self._playerStates[player.UserId]
		local equippedId = if existing then existing.equippedAttackId else nil
		local now = os.clock()

		self._playerStates[player.UserId] = {
			equippedAttackId = equippedId,
			currentAmmo = 0,
			maxAmmo = 0,
			reloadTime = 0,
			postDelay = 0,
			lastFireTime = 0,
			postDelayUntil = 0,
			lastRegenTime = now,
			lastHitTime = 0,
			aimStartTime = 0,
			comboCount = 0,
			humanoid = humanoid,
			rootPart = rootPart,
			sctx = makeEmptySctx(),
		}

		if equippedId and ATTACK_REGISTRY[equippedId] then
			local def = ATTACK_REGISTRY[equippedId].def
			local state = self._playerStates[player.UserId]
			state.maxAmmo = def.maxAmmo
			state.reloadTime = def.reloadTime
			state.postDelay = def.postDelay
			state.currentAmmo = def.maxAmmo
			self:_fireAmmoChanged(player, state)
		end

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

	-- postDelay 중이면 무시 (스팸으로 aimStartTime 리셋 방지)
	if now < state.postDelayUntil then
		return
	end

	-- 탄약/장착 없으면 무시
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

	-- [7] sctx 업데이트 (lastFireTime 갱신 전에 aimTime 계산)
	local sctx = state.sctx

	state.comboCount = sctx.comboCount -- sctx를 통해 콤보를 바꿨을 수도.

	sctx.attacker = state.humanoid and state.humanoid.Parent :: Model? or nil
	sctx.origin = state.rootPart.Position
	sctx.direction = dir
	sctx.aimTime = if state.aimStartTime > 0 then now - state.aimStartTime else 0
	sctx.idleTime = if state.lastFireTime > 0 then now - state.lastFireTime else 0
	sctx.victims = nil

	-- [8] 발사 처리 (sctx 계산 후 갱신)
	state.lastFireTime = now
	state.aimStartTime = 0 -- 발사 후 초기화
	state.postDelayUntil = now + state.postDelay
	state.currentAmmo -= 1
	self:_fireAmmoChanged(player, state)

	-- [9] onFire 배열 실행 (판정 포함)
	local allVictims: { Model } = {}
	if entry.module.onFire then
		for _, fn in entry.module.onFire do
			local result = fn(sctx)
			-- onFire가 { Model } 반환 시 합산
			if type(result) == "table" then
				for _, v in result :: { Model } do
					table.insert(allVictims, v)
				end
			end
		end
	end

	-- [10] 히트 체크 이후
	if #allVictims > 0 then
		state.lastHitTime = now -- 실제 히트했을 때만 갱신
		state.comboCount += 1
	else
		state.comboCount = 0 -- 허공 펀치 → 콤보 리셋
	end

	if entry.module.onHitChecked then
		for _, fn in entry.module.onHitChecked do
			fn(sctx)
		end
	end

	-- [11] sctx 업데이트
	sctx.victims = allVictims
	sctx.comboCount = state.comboCount

	-- [12] 히트 체크 완료 (항상 전송)
	local victimUserIds: { number } = {}
	for _, victimModel in allVictims do
		local victimPlayer = Players:GetPlayerFromCharacter(victimModel)
		if victimPlayer then
			table.insert(victimUserIds, victimPlayer.UserId)
		end
	end
	BasicAttackRemoting.HitChecked:FireAllClients(player.UserId, victimUserIds, state.comboCount)
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

function BasicAttackService:_fireAmmoChanged(player: Player, state: PlayerState)
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
	state.comboCount = 0
	state.lastHitTime = 0

	self:_fireAmmoChanged(player, state)
end

function BasicAttackService.Destroy(self: BasicAttackService)
	self._maid:Destroy()
end

return BasicAttackService
