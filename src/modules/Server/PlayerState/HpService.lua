--!strict
--[=[
	@class HpService

	HP 통합 관리 서비스. 서버 전용.

	규칙:
	- HP 값은 이 서비스만 변경한다. humanoid.Health 직접 조작 금지.
	- 대미지 / 힐은 반드시 ApplyDamage / ApplyHeal을 통할 것.
	- 패시브 · 스킬이 최대 HP를 바꿀 때는 SetMaxHp() 호출.

	초기화 흐름:
	  캐릭터 스폰 → ClassService:GetClass(player)로 클래스 조회
	               → HpConfig.GetBaseMaxHp(className) → current = max (풀 회복)
	               → HpSync 클라이언트 동기화 (delta = 0)

	클래스 변경:
	  ClassService.ClassChanged 구독
	  → maxHp 갱신, current를 기존 비율 기준으로 조정
	  → HpSync 동기화 (delta = 0)

	사망:
	  current ≤ 0 → humanoid.Health = 0 (기본 Roblox 사망 처리)
	              → OnDeath:Fire(player) 발행

	InstantHit 연동:
	  InstantHit은 ServiceBag 외부 유틸 모듈이므로
	  Init에서 InstantHit.init(self)로 인스턴스를 직접 주입함.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local ClassService = require("ClassService")
local HpConfig = require("HpConfig")
local HpRemoting = require("HpRemoting")
local InstantHit = require("InstantHit")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local Signal = require("Signal")

-- ─── 타입 ────────────────────────────────────────────────────────────────────

type PlayerHp = {
	current: number,
	max: number,
	className: string,
}

export type HpService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_classService: any,
		_hpData: { [number]: PlayerHp },
		_playerMaids: { [number]: any },
		OnDeath: any, -- Signal<Player>
	},
	{} :: typeof({ __index = {} })
))

-- ─── 서비스 ──────────────────────────────────────────────────────────────────

local HpService = {}
HpService.ServiceName = "HpService"
HpService.__index = HpService

function HpService.Init(self: HpService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._classService = serviceBag:GetService(ClassService)
	self._hpData = {}
	self._playerMaids = {}
	self.OnDeath = Signal.new()

	-- InstantHit은 ServiceBag 외부 유틸이므로 인스턴스를 직접 주입
	InstantHit.init(self)
end

function HpService.Start(self: HpService): ()
	-- 클래스 변경 구독 → maxHp 갱신
	self._maid:GiveTask(self._classService.ClassChanged:Connect(function(player: Player, className: string)
		self:_onClassChanged(player, className)
	end))

	-- 플레이어 라이프사이클
	for _, player in Players:GetPlayers() do
		self:_onPlayerAdded(player)
	end
	self._maid:GiveTask(Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end))
	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end))
end

-- ─── 플레이어 라이프사이클 ────────────────────────────────────────────────────

function HpService:_onPlayerAdded(player: Player)
	local pMaid = Maid.new()
	self._playerMaids[player.UserId] = pMaid

	local function onCharacterAdded(_char: Model)
		local className = self._classService:GetClass(player)
		local baseMax = HpConfig.GetBaseMaxHp(className)

		-- 패시브 등으로 이미 maxHp가 조정된 경우 그 값을 유지
		local existing = self._hpData[player.UserId]
		local max = if existing and existing.className == className then existing.max else baseMax

		self._hpData[player.UserId] = {
			current = max,
			max = max,
			className = className,
		}
		self:_sync(player, 0)
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end
	pMaid:GiveTask(player.CharacterAdded:Connect(onCharacterAdded))
end

function HpService:_onPlayerRemoving(player: Player)
	self._hpData[player.UserId] = nil
	local pMaid = self._playerMaids[player.UserId]
	if pMaid then
		pMaid:Destroy()
		self._playerMaids[player.UserId] = nil
	end
end

function HpService:_onClassChanged(player: Player, className: string)
	local data = self._hpData[player.UserId]
	if not data then
		return
	end
	-- 기존 HP 비율 유지하면서 maxHp를 새 클래스 기준으로 갱신
	local ratio = if data.max > 0 then data.current / data.max else 1
	local newMax = HpConfig.GetBaseMaxHp(className)
	data.className = className
	data.max = newMax
	data.current = math.clamp(math.round(ratio * newMax), 0, newMax)
	self:_sync(player, 0)
end

-- ─── 내부 유틸 ───────────────────────────────────────────────────────────────

function HpService:_sync(player: Player, delta: number)
	local data = self._hpData[player.UserId]
	if not data then
		return
	end
	HpRemoting.HpSync:FireClient(player, data.current, data.max, delta)
end

function HpService:_triggerDeath(player: Player)
	local char = player.Character
	if char then
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end
	self.OnDeath:Fire(player)
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	대미지를 적용합니다.
	multiplier(receiveDamageMult, dealDamageMult) 적용이 완료된 최종 값을 전달할 것.
	ignoreDamage 보호 처리는 호출 측(PlayerStateService)이 담당.
	@param target Player
	@param amount number  최종 대미지 (양수)
]=]
function HpService:ApplyDamage(target: Player, amount: number)
	if amount <= 0 then
		return
	end
	local data = self._hpData[target.UserId]
	if not data or data.current <= 0 then
		return
	end

	local actual = math.min(amount, data.current)
	data.current = math.max(0, data.current - amount)
	self:_sync(target, -actual)

	if data.current <= 0 then
		self:_triggerDeath(target)
	end
end

--[=[
	HP를 회복합니다.
	@param target Player
	@param amount number  회복량 (양수)
]=]
function HpService:ApplyHeal(target: Player, amount: number)
	if amount <= 0 then
		return
	end
	local data = self._hpData[target.UserId]
	if not data or data.current <= 0 then
		return
	end

	local actual = math.min(amount, data.max - data.current)
	if actual <= 0 then
		return
	end
	data.current = math.min(data.max, data.current + amount)
	self:_sync(target, actual)
end

--[=[
	최대 HP를 설정합니다. 패시브 · 스킬에서 호출.
	현재 HP는 기존 비율 기준으로 자동 조정됩니다.
	@param target Player
	@param newMax number
]=]
function HpService:SetMaxHp(target: Player, newMax: number)
	local data = self._hpData[target.UserId]
	if not data then
		return
	end
	local ratio = if data.max > 0 then data.current / data.max else 1
	data.max = math.max(1, newMax)
	data.current = math.clamp(math.round(ratio * data.max), 1, data.max)
	self:_sync(target, 0)
end

--[=[
	현재 HP와 최대 HP를 반환합니다.
	@return number, number  current, max
]=]
function HpService:GetHp(target: Player): (number, number)
	local data = self._hpData[target.UserId]
	if not data then
		return 0, 0
	end
	return data.current, data.max
end

function HpService.Destroy(self: HpService)
	self.OnDeath:Destroy()
	self._maid:Destroy()
end

return HpService
