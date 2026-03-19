--!strict
--[=[
	@class AnimReplicationService

	절차적 애니메이션 복제 서비스 (서버).

	동작:
	- 클라이언트로부터 AnimChanged 수신 → 검증 → 캐시 → AnimBroadcast로 전체 클라이언트에 포워딩
	- 클라이언트로부터 AnimStopped 수신 → 캐시 제거 → AnimStopBroadcast 포워딩
	- CharacterAdded 시 해당 플레이어에게 현재 진행 중인 다른 플레이어 상태 전송 (레이트 조인)
	- 플레이어 퇴장 시 AnimStopBroadcast(userId, nil, nil) 전송 → 클라이언트가 전체 정지

	서버는 factory를 실행하지 않음. Motor6D.C0 변경은 클라이언트(AnimReplicationClient)가 담당.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local AnimReplicationRemoting = require("AnimReplicationRemoting")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")

-- ─── 타입 ────────────────────────────────────────────────────────────────────

type AnimParams = {
	intensity: number?,
	direction: Vector3?,
}

type CachedAnim = {
	animDefModuleName: string,
	animName: string,
	animType: string,
	layer: number?,
	duration: number,
	defaultC0Map: { [string]: CFrame },
	params: AnimParams?,
	startTime: number,
}

type PlayerCache = {
	anims: { [string]: CachedAnim },
	maid: any,
}

export type AnimReplicationService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_playerCaches: { [number]: PlayerCache },
	},
	{} :: typeof({ __index = {} })
))

local AnimReplicationService = {}
AnimReplicationService.ServiceName = "AnimReplicationService"
AnimReplicationService.__index = AnimReplicationService

-- ─── 초기화 ──────────────────────────────────────────────────────────────────

function AnimReplicationService.Init(self: AnimReplicationService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._playerCaches = {}
end

function AnimReplicationService.Start(self: AnimReplicationService): ()
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
		AnimReplicationRemoting.AnimChanged:Connect(
			function(player, animDefModuleName, animName, animType, layer, duration, defaultC0Map, rawParams)
				self:_onAnimChanged(
					player,
					animDefModuleName,
					animName,
					animType,
					layer,
					duration,
					defaultC0Map,
					rawParams
				)
			end
		)
	)
	self._maid:GiveTask(
		AnimReplicationRemoting.AnimStopped:Connect(function(player, animDefModuleName, animName)
			self:_onAnimStopped(player, animDefModuleName, animName)
		end)
	)
end

-- ─── 플레이어 관리 ────────────────────────────────────────────────────────────

function AnimReplicationService:_onPlayerAdded(player: Player)
	local pMaid = Maid.new()
	self._maid:GiveTask(pMaid)

	local cache: PlayerCache = {
		anims = {},
		maid = pMaid,
	}
	self._playerCaches[player.UserId] = cache

	-- 레이트 조인: 캐릭터 로드 시 현재 진행 중인 다른 플레이어 상태 전송
	pMaid:GiveTask(player.CharacterAdded:Connect(function()
		task.defer(function()
			self:_sendExistingStateTo(player)
		end)
	end))
end

function AnimReplicationService:_onPlayerRemoving(player: Player)
	local cache = self._playerCaches[player.UserId]
	if cache then
		cache.maid:Destroy()
	end
	self._playerCaches[player.UserId] = nil

	-- 다른 클라이언트에 해당 플레이어 애니메이션 전부 정지 알림 (nil = 전체)
	AnimReplicationRemoting.AnimStopBroadcast:FireAllClients(player.UserId, nil, nil)
end

-- 레이트 조인: 접속한 플레이어에게 다른 플레이어들의 현재 상태 전송
function AnimReplicationService:_sendExistingStateTo(player: Player)
	local now = os.clock()
	for userId, cache in self._playerCaches do
		if userId == player.UserId then
			continue
		end
		for _, cached in cache.anims do
			local remaining = cached.duration - (now - cached.startTime)
			if remaining <= 0 then
				continue
			end
			AnimReplicationRemoting.AnimBroadcast:FireClient(
				player,
				userId,
				cached.animDefModuleName,
				cached.animName,
				cached.animType,
				cached.layer,
				remaining,
				cached.defaultC0Map,
				cached.params
			)
		end
	end
end

-- ─── 수신 → 브로드캐스트 ─────────────────────────────────────────────────────

function AnimReplicationService:_onAnimChanged(
	player: Player,
	animDefModuleName: unknown,
	animName: unknown,
	animType: unknown,
	layer: unknown,
	duration: unknown,
	defaultC0Map: unknown,
	rawParams: unknown
)
	if type(animDefModuleName) ~= "string" then
		return
	end
	if type(animName) ~= "string" then
		return
	end
	if type(animType) ~= "string" then
		return
	end
	if type(defaultC0Map) ~= "table" then
		return
	end

	local cache = self._playerCaches[player.UserId]
	if not cache then
		return
	end

	-- params 파싱 (보안: 타입 검증)
	local animParams: AnimParams? = nil
	if type(rawParams) == "table" then
		local p = rawParams :: any
		local parsed: AnimParams = {}
		if type(p.intensity) == "number" then
			parsed.intensity = math.clamp(p.intensity, 0, 1)
		end
		if typeof(p.direction) == "Vector3" then
			parsed.direction = p.direction
		end
		animParams = parsed
	end

	local animDuration = type(duration) == "number" and duration or math.huge
	local animKey = animDefModuleName .. "_" .. animName

	-- anim 타입: 같은 layer 기존 캐시 제거
	if animType == "anim" and type(layer) == "number" then
		for key, cached in cache.anims do
			if cached.animType == "anim" and cached.layer == layer then
				cache.anims[key] = nil
				break
			end
		end
	end

	cache.anims[animKey] = {
		animDefModuleName = animDefModuleName :: string,
		animName = animName :: string,
		animType = animType :: string,
		layer = type(layer) == "number" and layer or nil,
		duration = animDuration,
		defaultC0Map = defaultC0Map :: { [string]: CFrame },
		params = animParams,
		startTime = os.clock(),
	}

	-- 모든 클라이언트에 포워딩 (로컬 플레이어 포함 — 클라이언트에서 자기 자신 걸러냄)
	AnimReplicationRemoting.AnimBroadcast:FireAllClients(
		player.UserId,
		animDefModuleName,
		animName,
		animType,
		layer,
		animDuration,
		defaultC0Map,
		animParams
	)
end

function AnimReplicationService:_onAnimStopped(player: Player, animDefModuleName: unknown, animName: unknown)
	if type(animDefModuleName) ~= "string" then
		return
	end
	if type(animName) ~= "string" then
		return
	end

	local cache = self._playerCaches[player.UserId]
	if not cache then
		return
	end

	cache.anims[animDefModuleName .. "_" .. animName] = nil

	AnimReplicationRemoting.AnimStopBroadcast:FireAllClients(player.UserId, animDefModuleName, animName)
end

function AnimReplicationService.Destroy(self: AnimReplicationService)
	self._maid:Destroy()
end

return AnimReplicationService
