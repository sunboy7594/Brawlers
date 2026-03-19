--!strict
--[=[
	@class ProjectileHitService

	투사체 판정 서비스 (서버).

	동작:
	- RegisterProjectile 수신 → 검증 + ProjectileHit.takePendingOnHit로 onHit callback 픽업 + register() 위임
	- ProjectileHit 수신 → ProjectileHit.onHitReport() 위임
	- 플레이어 퇴장 시 ProjectileHit.clearPlayer() 호출

	어빌리티 모듈 통합 패턴:
	  서버 onFire 모듈 → ProjectileHit.setPendingOnHit(userId, state.onHit)
	  클라이언트 onFire 모듈 → RegisterProjectile:FireServer(id, config)
	  여기서 둘을 연결하여 register(onHit 포함)
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local Maid = require("Maid")
local ProjectileHit = require("ProjectileHit")
local ProjectileHitRemoting = require("ProjectileHitRemoting")
local ServiceBag = require("ServiceBag")
local TeamService = require("TeamService")

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
		_teamService  : any,
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
	self._teamService = serviceBag:GetService(TeamService)
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

	self._maid:GiveTask(
		ProjectileHitRemoting.RegisterProjectile:Connect(function(player, projectileId, netConfig)
			self:_onRegisterProjectile(player, projectileId, netConfig)
		end)
	)

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

function ProjectileHitService:_onRegisterProjectile(
	player       : Player,
	projectileId : unknown,
	netConfig    : unknown
)
	if type(projectileId) ~= "string" or #projectileId == 0 then return end
	if type(netConfig) ~= "table" then return end

	local cfg = netConfig :: any
	if typeof(cfg.origin) ~= "Vector3" then return end
	if typeof(cfg.direction) ~= "Vector3" then return end
	if type(cfg.speed) ~= "number" or cfg.speed <= 0 or cfg.speed > MAX_SPEED then return end
	if type(cfg.hitRadius) ~= "number" or cfg.hitRadius <= 0 or cfg.hitRadius > MAX_HIT_RADIUS then return end
	if type(cfg.maxRange) ~= "number" or cfg.maxRange <= 0 or cfg.maxRange > MAX_RANGE then return end

	local dirMag = cfg.direction.Magnitude
	if dirMag < 0.99 or dirMag > 1.01 then return end

	local cache = self._playerCaches[player.UserId]
	if not cache then return end

	local now = os.clock()
	if now - cache.lastRegisterTime < REGISTER_RATE_LIMIT_INTERVAL then return end
	cache.lastRegisterTime = now

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		local dist = (cfg.origin - hrp.Position).Magnitude
		if dist > MAX_ORIGIN_DISTANCE then
			warn("[ProjectileHitService] origin 너무 멀:", player.Name, dist)
			return
		end
	end

	if not char then return end

	-- 서버 onFire 모듈이 저장한 onHit callback 픽업
	local onHit = ProjectileHit.takePendingOnHit(player.UserId)

	ProjectileHit.register(player, projectileId :: string, {
		origin         = cfg.origin :: Vector3,
		direction      = cfg.direction :: Vector3,
		speed          = cfg.speed :: number,
		hitRadius      = cfg.hitRadius :: number,
		maxRange       = cfg.maxRange :: number,
		firedAt        = now,
		attacker       = char :: Model,
		latencyBuffer  = nil,
		wallCheck      = nil,
		maxHitCount    = nil,
		teamService    = self._teamService,
		attackerPlayer = player,
		onHit          = onHit,
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

	local now = os.clock()
	if now - cache.lastHitTime < HIT_RATE_LIMIT_INTERVAL then return end
	cache.lastHitTime = now

	ProjectileHit.onHitReport(player, projectileId :: string, hitPosition :: Vector3)
end

function ProjectileHitService.Destroy(self: ProjectileHitService)
	self._maid:Destroy()
end

return ProjectileHitService
