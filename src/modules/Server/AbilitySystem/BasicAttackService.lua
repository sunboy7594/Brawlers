--!strict
--[=[
    @class BasicAttackService

    기본 공격 서버 서비스.

    담당:
    - 플레이어별 탄약 상태 관리
    - 탄약 1칸씩 독립 재생 (Heartbeat, lastRegenTime 기반)
    - BasicAttackRemoting.Fire 수신 → 검증 → 공격 모듈 onFire 호출
    - LoadoutRemoting.RequestEquipBasicAttack:Bind() → 유효성 검증 후 장착 처리

    Anti-exploit:
    - 레이트 리밋 (FIRE_RATE_LIMIT = 0.1초)
    - direction 타입/크기 검증
    - 탄약 0이면 무시
    - postDelay 중 발사 무시
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

-- ─── 레지스트리 자동 구성 ─────────────────────────────────────────────────────
-- BasicAttackDefs의 모든 항목에서 id .. "Server" 모듈을 자동 require

type AttackModule = {
	onFire: (attacker: Model, origin: Vector3, direction: Vector3, aimTime: number) -> { Model },
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

-- ─── 타입 정의 ───────────────────────────────────────────────────────────────

type PlayerState = {
	equippedAttackId: string?,
	currentAmmo: number,
	maxAmmo: number,
	reloadTime: number,
	postDelay: number,
	lastFireTime: number, -- 마지막 발사 시각 (os.clock)
	postDelayUntil: number, -- postDelay 해제 시각 (os.clock)
	lastRegenTime: number,
	humanoid: Humanoid?,
	rootPart: BasePart?,
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

	self._maid:GiveTask(BasicAttackRemoting.Fire:Connect(function(player: Player, direction: unknown, aimTime: unknown)
		self:_onFire(player, direction, aimTime)
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

function BasicAttackService:_onPlayerAdded(player: Player)
	local pMaid = Maid.new()
	self._playerMaids[player.UserId] = pMaid

	local function onCharacterAdded(char: Model)
		local humanoid = char:WaitForChild("Humanoid") :: Humanoid
		local rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart

		local existing = self._playerStates[player.UserId]
		local equippedId = if existing then existing.equippedAttackId else nil

		self._playerStates[player.UserId] = {
			equippedAttackId = equippedId,
			currentAmmo = 0,
			maxAmmo = 0,
			reloadTime = 0,
			postDelay = 0,
			lastFireTime = 0,
			postDelayUntil = 0,
			lastRegenTime = os.clock(),
			humanoid = humanoid,
			rootPart = rootPart,
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

-- ─── 발사 처리 & Anti-exploit ────────────────────────────────────────────────

function BasicAttackService:_onFire(player: Player, direction: unknown, aimTime: unknown)
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

	-- [3] direction 타입/크기 검증
	if typeof(direction) ~= "Vector3" then
		return
	end
	local dir = direction :: Vector3
	if math.abs(dir.Magnitude - 1) > MAX_DIRECTION_MAGNITUDE_DELTA then
		return
	end

	-- [4] aimTime 타입 검증
	if type(aimTime) ~= "number" then
		return
	end

	-- [5] 탄약 확인
	if state.currentAmmo <= 0 then
		return
	end

	-- [6] 장착 확인
	local attackId = state.equippedAttackId
	if not attackId then
		return
	end
	local entry = ATTACK_REGISTRY[attackId]
	if not entry then
		return
	end

	-- [7] 발사 처리
	state.lastFireTime = now
	state.postDelayUntil = now + state.postDelay
	state.currentAmmo -= 1
	self:_fireAmmoChanged(player, state)

	local char = state.humanoid.Parent :: Model?
	if char then
		entry.module.onFire(char, state.rootPart.Position, dir, aimTime :: number)
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

-- ─── 내부 헬퍼 ───────────────────────────────────────────────────────────────

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

	self:_fireAmmoChanged(player, state)
end

function BasicAttackService.Destroy(self: BasicAttackService)
	self._maid:Destroy()
end

return BasicAttackService
