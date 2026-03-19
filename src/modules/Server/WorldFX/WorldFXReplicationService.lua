--!strict
--[=[
	@class WorldFXReplicationService

	WorldFX 이펙트 복제 서비스 (서버).

	동작:
	- 클라이언트로부터 EffectFired 수신
	- 검증 (레이트 리밋, 타입 체크, origin 거리)
	- workspace:GetServerTimeNow() 스탬핑
	- 발신자 제외 나머지 모든 클라이언트에 EffectBroadcast 포워딩

	서버는 이펙트를 직접 생성하지 않음. 포워더 전용.
	이펙트는 순수 비주얼이므로 exploit 위험도가 낮지만
	레이트 리밋 + origin 거리 체크로 기본 방어.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local WorldFXReplicationRemoting = require("WorldFXReplicationRemoting")

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local RATE_LIMIT_INTERVAL = 0.05   -- 플레이어당 최소 간격 (초)
local MAX_ORIGIN_DISTANCE = 200    -- 캐릭터 HRP에서 origin까지 최대 허용 거리

-- ─── 타입 ────────────────────────────────────────────────────────────────────

type PlayerCache = {
	lastFireTime : number,
	maid         : any,
}

export type WorldFXReplicationService = typeof(setmetatable(
	{} :: {
		_serviceBag   : ServiceBag.ServiceBag,
		_maid         : any,
		_playerCaches : { [number]: PlayerCache },
	},
	{} :: typeof({ __index = {} })
))

-- ─── 서비스 ──────────────────────────────────────────────────────────────────

local WorldFXReplicationService = {}
WorldFXReplicationService.ServiceName = "WorldFXReplicationService"
WorldFXReplicationService.__index = WorldFXReplicationService

function WorldFXReplicationService.Init(self: WorldFXReplicationService, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._playerCaches = {}
end

function WorldFXReplicationService.Start(self: WorldFXReplicationService)
	for _, player in Players:GetPlayers() do
		self:_onPlayerAdded(player)
	end
	self._maid:GiveTask(Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end))
	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end))

	self._maid:GiveTask(
		WorldFXReplicationRemoting.EffectFired:Connect(function(player, defModuleName, effectName, origin, direction)
			self:_onEffectFired(player, defModuleName, effectName, origin, direction)
		end)
	)
end

-- ─── 플레이어 관리 ────────────────────────────────────────────────────────────

function WorldFXReplicationService:_onPlayerAdded(player: Player)
	self._playerCaches[player.UserId] = {
		lastFireTime = 0,
		maid = Maid.new(),
	}
end

function WorldFXReplicationService:_onPlayerRemoving(player: Player)
	local cache = self._playerCaches[player.UserId]
	if cache then
		cache.maid:Destroy()
	end
	self._playerCaches[player.UserId] = nil
end

-- ─── 수신 + 검증 + 포워딩 ────────────────────────────────────────────────────

function WorldFXReplicationService:_onEffectFired(
	player      : Player,
	defModuleName : unknown,
	effectName  : unknown,
	origin      : unknown,
	direction   : unknown
)
	-- 타입 검증
	if type(defModuleName) ~= "string" or #defModuleName == 0 then return end
	if type(effectName) ~= "string" or #effectName == 0 then return end
	if typeof(origin) ~= "CFrame" then return end

	-- direction 검증 (옵셔널, Vector3이어야 함)
	local safeDirection: Vector3? = nil
	if direction ~= nil then
		if typeof(direction) ~= "Vector3" then return end
		local mag = (direction :: Vector3).Magnitude
		if mag < 0.001 or mag > 1.001 then return end  -- 단위 벡터 체크
		safeDirection = direction :: Vector3
	end

	local cache = self._playerCaches[player.UserId]
	if not cache then return end

	-- 레이트 리밋
	local now = os.clock()
	if now - cache.lastFireTime < RATE_LIMIT_INTERVAL then return end
	cache.lastFireTime = now

	-- origin 거리 검증
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		local dist = ((origin :: CFrame).Position - hrp.Position).Magnitude
		if dist > MAX_ORIGIN_DISTANCE then
			warn("[WorldFXReplicationService] origin 너무 멂:", player.Name, dist)
			return
		end
	end

	-- 서버 시각 스탬핑
	local firedAt = Workspace:GetServerTimeNow()

	-- 발신자 제외 모든 클라이언트에 브로드캐스트
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= player then
			WorldFXReplicationRemoting.EffectBroadcast:FireClient(
				otherPlayer,
				player.UserId,
				defModuleName,
				effectName,
				origin,
				safeDirection,
				firedAt
			)
		end
	end
end

function WorldFXReplicationService.Destroy(self: WorldFXReplicationService)
	self._maid:Destroy()
end

return WorldFXReplicationService
