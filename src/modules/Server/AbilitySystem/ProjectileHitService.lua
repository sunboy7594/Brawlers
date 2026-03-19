--!strict
--[=[
	@class ProjectileHitService

	투사체 판정 서비스 (서버).

	동작:
	- RegisterProjectile 수신 → 클라이언트 보고 전 검증 + ProjectileHit.register() 위임
	- ProjectileHit 수신 → ProjectileHit.onHitReport() 위임
	- 플레이어 퇴장 시 ProjectileHit.clearPlayer() 호출

	RegisterProjectile 사전 검증:
	- 레이트 리밋: 플레이어당 REGISTER_RATE_LIMIT_INTERVAL 당 1회
	- origin 거리: 캐릭터 HRP로부터 MAX_ORIGIN_DISTANCE 이상이면 거부
	- direction: 단위벡터 체크
	- speed/hitRadius/maxRange: 양수 체크

	ProjectileHit 사전 검증:
	- 레이트 리밋: 플레이어당 HIT_RATE_LIMIT_INTERVAL 당 1회
	- hitPosition: Vector3 타입 체크
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local Maid = require("Maid")
local ProjectileHit = require("ProjectileHit")
local ProjectileHitRemoting = require("ProjectileHitRemoting")
local ServiceBag = require("ServiceBag")

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local REGISTER_RATE_LIMIT_INTERVAL = 0.05
local HIT_RATE_LIMIT_INTERVAL       = 0.05
local MAX_ORIGIN_DISTANCE           = 200
local MAX_SPEED                     = 500
local MAX_HIT_RADIUS                = 50
local MAX_RANGE                     = 2000

-- ─── 타입 ────────────────────────────────────────────────────────────────────

type PlayerCache = {
	lastRegisterTime : number,
	lastHitTime      : number,
	maid             : any,
}

export type ProjectileHitService = typeof(setmetatable(
	{} :: {
		_serviceBag   : ServiceBag.ServiceBag,
		_maid         : any,
		_playerCaches : { [number]: PlayerCache },
	},
	{} :: typeof({ __index = {} })
))

-- ─── 서비스 ──────────────────────────────────────────────────────────────────

local ProjectileHitService = {}
ProjectileHitService.ServiceName = "ProjectileHitService"
ProjectileHitService.__index = ProjectileHitService

function ProjectileHitService.Init(self: ProjectileHitService, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._playerCaches = {}
end

function ProjectileHitService.Start(self: ProjectileHitService)
	for _, player in Players:GetPlayers() do
		self:_onPlayerAdded(player)
	end
	self._maid:GiveTask(Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end))
	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end))

	-- RegisterProjectile 수신
	self._maid:GiveTask(
		ProjectileHitRemoting.RegisterProjectile:Connect(function(player, projectileId, netConfig)
			self:_onRegisterProjectile(player, projectileId, netConfig)
		end)
	)

	-- ProjectileHit 수신
	self._maid:GiveTask(
		ProjectileHitRemoting.ProjectileHit:Connect(function(player, projectileId, hitPosition)
			self:_onProjectileHit(player, projectileId, hitPosition)
		end)
	)
end

-- ─── 플레이어 관리 ────────────────────────────────────────────────────────────

function ProjectileHitService:_onPlayerAdded(player: Player)
	self._playerCaches[player.UserId] = {
		lastRegisterTime = 0,
		lastHitTime      = 0,
		maid             = Maid.new(),
	}
end

function ProjectileHitService:_onPlayerRemoving(player: Player)
	local cache = self._playerCaches[player.UserId]
	if cache then
		cache.maid:Destroy()
	end
	self._playerCaches[player.UserId] = nil
	ProjectileHit.clearPlayer(player.UserId)
end

-- ─── RegisterProjectile ───────────────────────────────────────────────────────

--[=[
	투사체 등록 요청 처리.
	netConfig는 클라이언트가 보낸 최소 정보 (사전 검증할 것만 포함).
	ProjectileHit.register에는 firedAt과 attacker/teamService를
	포함한 완전한 config를 다른 쾼에서 서버가 직접 제공해야 합니다.
	
	❗ 현재는 클라이언트가 netConfig를 보내는 방식으로 동작.
	  어빌리티 서버 모듈(onFire)에서 ProjectileHit.register()를
	  직접 호출하는 방식으로 통합할 때까지는
	  클라이언트가 보낸 netConfig를 기반으로 등록합니다.
]=]
function ProjectileHitService:_onRegisterProjectile(
	player       : Player,
	projectileId : unknown,
	netConfig    : unknown
)
	-- 타입 검증
	if type(projectileId) ~= "string" or #projectileId == 0 then return end
	if type(netConfig) ~= "table" then return end

	local cfg = netConfig :: any
	if typeof(cfg.origin) ~= "Vector3" then return end
	if typeof(cfg.direction) ~= "Vector3" then return end
	if type(cfg.speed) ~= "number" or cfg.speed <= 0 or cfg.speed > MAX_SPEED then return end
	if type(cfg.hitRadius) ~= "number" or cfg.hitRadius <= 0 or cfg.hitRadius > MAX_HIT_RADIUS then return end
	if type(cfg.maxRange) ~= "number" or cfg.maxRange <= 0 or cfg.maxRange > MAX_RANGE then return end

	-- direction 단위벡터 체크
	local dirMag = cfg.direction.Magnitude
	if dirMag < 0.99 or dirMag > 1.01 then return end

	local cache = self._playerCaches[player.UserId]
	if not cache then return end

	-- 레이트 리밋
	local now = os.clock()
	if now - cache.lastRegisterTime < REGISTER_RATE_LIMIT_INTERVAL then return end
	cache.lastRegisterTime = now

	-- origin 거리 체크
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		local dist = (cfg.origin - hrp.Position).Magnitude
		if dist > MAX_ORIGIN_DISTANCE then
			warn("[ProjectileHitService] origin 너무 멀:", player.Name, dist)
			return
		end
	end

	-- attacker, firedAt은 서버가 직접 채움
	local attacker = char
	if not attacker then return end

	ProjectileHit.register(player, projectileId :: string, {
		origin         = cfg.origin :: Vector3,
		direction      = cfg.direction :: Vector3,
		speed          = cfg.speed :: number,
		hitRadius      = cfg.hitRadius :: number,
		maxRange       = cfg.maxRange :: number,
		firedAt        = now,
		attacker       = attacker :: Model,
		latencyBuffer  = nil,
		wallCheck      = nil,
		maxHitCount    = nil,
		teamService    = nil,    -- TODO: 어빌리티 모듈 통합 시 TeamService 주입
		attackerPlayer = player,
		onHit          = nil,    -- TODO: 어빌리티 모듈 통합 시 onHit 콜백 주입
	}, nil)
end

-- ─── ProjectileHit ───────────────────────────────────────────────────────────────

function ProjectileHitService:_onProjectileHit(
	player       : Player,
	projectileId : unknown,
	hitPosition  : unknown
)
	if type(projectileId) ~= "string" or #projectileId == 0 then return end
	if typeof(hitPosition) ~= "Vector3" then return end

	local cache = self._playerCaches[player.UserId]
	if not cache then return end

	-- 레이트 리밋
	local now = os.clock()
	if now - cache.lastHitTime < HIT_RATE_LIMIT_INTERVAL then return end
	cache.lastHitTime = now

	ProjectileHit.onHitReport(player, projectileId :: string, hitPosition :: Vector3)
end

function ProjectileHitService.Destroy(self: ProjectileHitService)
	self._maid:Destroy()
end

return ProjectileHitService
