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
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BasicAttackDefs = require("BasicAttackDefs")
local BasicAttackRemoting = require("BasicAttackRemoting")
local LoadoutRemoting = require("LoadoutRemoting")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local TankPunch = require("TankPunch")

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local FIRE_RATE_LIMIT = 0.1 -- 초, 최소 발사 간격
local MAX_DIRECTION_MAGNITUDE_DELTA = 0.1 -- 정규화 벡터 허용 오차

-- ─── 전역 공격 레지스트리 ────────────────────────────────────────────────────
-- attackId → { def: 공격 정의, module: 서버 공격 모듈 }

type AttackDef = {
	rarity: string,
	class: string,
	maxAmmo: number,
	reloadTime: number,
}

type AttackModule = {
	onFire: (attacker: Model, origin: Vector3, direction: Vector3, aimTime: number) -> { Model },
}

type AttackEntry = {
	def: AttackDef,
	module: AttackModule,
}

local ATTACK_REGISTRY: { [string]: AttackEntry } = {
	Punch = {
		def = BasicAttackDefs.Punch,
		module = TankPunch,
	},
}

-- ─── 타입 정의 ───────────────────────────────────────────────────────────────

type PlayerState = {
	equippedAttackId: string?,
	currentAmmo: number,
	maxAmmo: number,
	reloadTime: number,
	lastFireTime: number, -- 마지막 발사 시각 (os.clock)
	lastRegenTime: number, -- 마지막 탄약 재생 시각 (os.clock)
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

	-- 클라이언트 → 서버: 공격 발사 수신
	self._maid:GiveTask(BasicAttackRemoting.Fire:Connect(function(player: Player, direction: unknown, aimTime: unknown)
		self:_onFire(player, direction, aimTime)
	end))

	-- 클라이언트 → 서버: 기본 공격 장착 요청
	self._maid:GiveTask(LoadoutRemoting.RequestEquipBasicAttack:Bind(function(player: Player, attackId: unknown)
		-- 타입 검증
		if type(attackId) ~= "string" then
			return false, "Invalid attackId type"
		end

		-- 유효한 공격인지 확인
		if not ATTACK_REGISTRY[attackId] then
			return false, "Unknown attackId: " .. attackId
		end

		self:_setPlayerAttack(player, attackId)
		return true, attackId
	end))
end

function BasicAttackService.Start(self: BasicAttackService): ()
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

	-- 탄약 재생 루프
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

		-- 기존 상태가 있으면 장착 유지, 없으면 초기화
		local existing = self._playerStates[player.UserId]
		local equippedId = if existing then existing.equippedAttackId else nil

		self._playerStates[player.UserId] = {
			equippedAttackId = equippedId,
			currentAmmo = 0,
			maxAmmo = 0,
			reloadTime = 0,
			lastFireTime = 0,
			lastRegenTime = os.clock(),
			humanoid = humanoid,
			rootPart = rootPart,
		}

		-- 장착된 공격이 있으면 탄약 재설정
		if equippedId and ATTACK_REGISTRY[equippedId] then
			local def = ATTACK_REGISTRY[equippedId].def
			local state = self._playerStates[player.UserId]
			state.maxAmmo = def.maxAmmo
			state.reloadTime = def.reloadTime
			state.currentAmmo = def.maxAmmo
			self:_fireAmmoChanged(player, state)
		end

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

	-- [2] direction 타입 검증
	if typeof(direction) ~= "Vector3" then
		return
	end
	local dir = direction :: Vector3

	-- [3] direction 크기 검증 (정규화 벡터여야 함)
	local mag = dir.Magnitude
	if math.abs(mag - 1) > MAX_DIRECTION_MAGNITUDE_DELTA then
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

	-- [6] 장착된 공격 확인
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
	state.currentAmmo -= 1
	self:_fireAmmoChanged(player, state)

	-- 공격 모듈 onFire 호출
	local char = state.humanoid.Parent :: Model?
	if char then
		local origin = state.rootPart.Position
		entry.module.onFire(char, origin, dir, aimTime :: number)
	end
end

-- ─── 탄약 재생 (Heartbeat) ────────────────────────────────────────────────────

function BasicAttackService:_updateAmmoRegen()
	local now = os.clock()

	for userId, state in self._playerStates do
		-- 풀 충전이면 재생 불필요
		if state.currentAmmo >= state.maxAmmo or state.maxAmmo == 0 then
			continue
		end
		if state.reloadTime <= 0 then
			continue
		end

		-- 탄약 1개 재생 조건 충족 시 충전
		if now - state.lastRegenTime >= state.reloadTime then
			state.currentAmmo = math.min(state.currentAmmo + 1, state.maxAmmo)
			state.lastRegenTime = now

			-- 해당 플레이어 찾아서 AmmoChanged 전송
			local player = Players:GetPlayerByUserId(userId)
			if player then
				self:_fireAmmoChanged(player, state)
			end
		end
	end
end

-- ─── 내부 헬퍼 ───────────────────────────────────────────────────────────────

-- AmmoChanged 이벤트를 클라이언트로 전송합니다.
function BasicAttackService:_fireAmmoChanged(player: Player, state: PlayerState)
	BasicAttackRemoting.AmmoChanged:FireClient(player, state.currentAmmo, state.maxAmmo, state.reloadTime)
end

--[=[
	장착 공격을 변경하고 탄약을 초기화합니다.
	LoadoutRemoting.RequestEquipBasicAttack:Bind() 핸들러에서만 호출합니다.
	외부에서 직접 호출하지 마세요.
]=]
function BasicAttackService:_setPlayerAttack(player: Player, attackId: string)
	local state = self._playerStates[player.UserId]
	if not state then
		return
	end

	local entry = ATTACK_REGISTRY[attackId]
	if not entry then
		return
	end

	-- 탄약 초기화
	state.equippedAttackId = attackId
	state.maxAmmo = entry.def.maxAmmo
	state.reloadTime = entry.def.reloadTime
	state.currentAmmo = entry.def.maxAmmo
	state.lastRegenTime = os.clock()

	self:_fireAmmoChanged(player, state)
end

function BasicAttackService.Destroy(self: BasicAttackService)
	self._maid:Destroy()
end

return BasicAttackService
