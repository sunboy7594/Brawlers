--!strict
--[=[
	@class ProjectileHit

	투사체 판정 유틸. 서버 전용.

	역할:
	- PendingProjectile 등록 / 만료 관리
	- 클라이언트 히트 보고 검증 3단계
	- 판정 결과를 InstantHit과 동일한 HitMapResult 형식으로 onHit에 전달

	어빌리티 모듈 통합 패턴:
	  1. 서버 onFire 모듈에서 setPendingOnHit(userId, state.onHit) 호출
	  2. 클라이언트 onFire 모듈에서 RegisterProjectile:FireServer 호출
	  3. ProjectileHitService._onRegisterProjectile에서 takePendingOnHit으로 callback 픽업
	  4. 클라이언트 충돌 감지 → ProjectileHit:FireServer → 서버 검증 → onHit(hitMap)
	  5. onHit → onHitChecked 후크 실행
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local cancellableDelay = require("cancellableDelay")

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local DEFAULT_LATENCY_BUFFER = 0.25

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type VictimSet = {
	enemies   : { Model },
	teammates : { Model },
	self      : Model?,
}

export type HitMapResult = { [string]: VictimSet }

export type ProjectileConfig = {
	origin         : Vector3,
	direction      : Vector3,
	speed          : number,
	hitRadius      : number,
	maxRange       : number,
	firedAt        : number,
	attacker       : Model,
	latencyBuffer  : number?,
	wallCheck      : boolean?,
	maxHitCount    : number?,
	teamService    : any?,
	attackerPlayer : Player?,
	onHit          : ((HitMapResult) -> ())?,
}

type PendingProjectile = {
	config   : ProjectileConfig,
	hitCount : number,
	expired  : boolean,
}

-- ─── 걸로벌 상태 ───────────────────────────────────────────────────────────────

-- userId → projectileId → PendingProjectile
local _pending: { [number]: { [string]: PendingProjectile } } = {}

-- userId → onHit callback
-- 서버 onFire 모듈이 등록, ProjectileHitService가 RegisterProjectile 수신 시 픽업
local _pendingOnHit: { [number]: (HitMapResult) -> () } = {}

-- ─── 내부 유틸 ───────────────────────────────────────────────────────────────

local WALL_CHECK_PARAMS = RaycastParams.new()
WALL_CHECK_PARAMS.CollisionGroup = "HitCheck"

local function getCharactersInSphere(origin: Vector3, radius: number): { Model }
	local parts = workspace:GetPartBoundsInRadius(origin, radius, OverlapParams.new())
	local seen: { [Model]: boolean } = {}
	local result: { Model } = {}
	for _, part in parts do
		local char = part:FindFirstAncestorOfClass("Model")
		if not char or seen[char] then continue end
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			seen[char] = true
			table.insert(result, char)
		end
	end
	return result
end

local function isObstructed(from: Vector3, to: Vector3): boolean
	local result = workspace:Raycast(from, to - from, WALL_CHECK_PARAMS)
	return result ~= nil
end

local function classifyHits(
	hits: { Model },
	attacker: Model,
	attackerPlayer: Player?,
	teamService: any?
): VictimSet
	local result: VictimSet = { enemies = {}, teammates = {}, self = nil }
	for _, char in hits do
		if char == attacker then
			result.self = char
			continue
		end
		local player = Players:GetPlayerFromCharacter(char)
		if not player then continue end
		if teamService and attackerPlayer then
			if teamService:IsEnemy(attackerPlayer, player) then
				table.insert(result.enemies, char)
			else
				table.insert(result.teammates, char)
			end
		else
			table.insert(result.enemies, char)
		end
	end
	return result
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

local ProjectileHit = {}

--[=[
	서버 어빌리티 모듈(onFire)에서 호출.
	RegisterProjectile 도착 시 ProjectileHitService가 takePendingOnHit으로 픽업합니다.

	타이밍:
	  onFire(state) → setPendingOnHit 호출
	  클라이언트 onFire 모듈 → RegisterProjectile:FireServer 호출
	  서버 RegisterProjectile 수신 → takePendingOnHit 피업 → register()

	@param userId   number
	@param onHit    (HitMapResult) -> ()
]=]
function ProjectileHit.setPendingOnHit(userId: number, onHit: ((HitMapResult) -> ())?)
	if onHit then
		_pendingOnHit[userId] = onHit
	end
end

--[=[
	등록된 onHit callback을 가져와서 제거합니다.
	ProjectileHitService._onRegisterProjectile에서 호출.

	@param userId   number
	@return (HitMapResult -> ())?
]=]
function ProjectileHit.takePendingOnHit(userId: number): ((HitMapResult) -> ())?
	local cb = _pendingOnHit[userId]
	_pendingOnHit[userId] = nil
	return cb
end

--[=[
	PendingProjectile를 등록합니다.
	fireMaid에 등록하면 CancelCombatState 시 자동 만료.
]=]
function ProjectileHit.register(
	player       : Player,
	projectileId : string,
	config       : ProjectileConfig,
	fireMaid     : any?
)
	local userId = player.UserId
	if not _pending[userId] then
		_pending[userId] = {}
	end

	local pending: PendingProjectile = {
		config   = config,
		hitCount = 0,
		expired  = false,
	}
	_pending[userId][projectileId] = pending

	local latencyBuffer = config.latencyBuffer or DEFAULT_LATENCY_BUFFER
	local lifetime = config.maxRange / config.speed + latencyBuffer

	local function expire()
		if _pending[userId] then
			_pending[userId][projectileId] = nil
		end
	end

	local cancel = cancellableDelay(lifetime, expire)
	if fireMaid then
		fireMaid:GiveTask(cancel)
		fireMaid:GiveTask(function()
			if _pending[userId] then
				_pending[userId][projectileId] = nil
			end
		end)
	end
end

--[=[
	ProjectileHitService가 클라이언트 히트 보고를 받았을 때 호출합니다.
	3단계 검증 후 통과 시 onHit 콜백 실행.
]=]
function ProjectileHit.onHitReport(
	player       : Player,
	projectileId : string,
	hitPosition  : Vector3
)
	local userId = player.UserId
	local playerPending = _pending[userId]
	if not playerPending then return end

	local pending = playerPending[projectileId]
	if not pending or pending.expired then return end

	local config = pending.config

	-- ─── 단계 2: hitPosition 위치 타당성 ────────────────────────────────────────────
	local latencyBuffer = config.latencyBuffer or DEFAULT_LATENCY_BUFFER
	local elapsed = os.clock() - config.firedAt
	local expectedDist = config.speed * elapsed
	local allowance = config.speed * latencyBuffer + config.hitRadius
	local actualDist = (hitPosition - config.origin).Magnitude

	if actualDist > expectedDist + allowance then
		warn(string.format(
			"[ProjectileHit] 위치 검증 실패: player=%s id=%s actual=%.1f expected=%.1f+%.1f",
			player.Name, projectileId, actualDist, expectedDist, allowance
		))
		return
	end

	-- ─── 단계 3: hitPosition 기준 실제 대상 근접 확인 ───────────────────────────
	local searchRadius = config.hitRadius * 2 + latencyBuffer * config.speed
	local candidates = getCharactersInSphere(hitPosition, searchRadius)

	if config.wallCheck ~= false then
		local filtered: { Model } = {}
		for _, char in candidates do
			local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if rootPart and not isObstructed(hitPosition, rootPart.Position) then
				table.insert(filtered, char)
			end
		end
		candidates = filtered
	end

	if #candidates == 0 then return end

	local victimSet = classifyHits(candidates, config.attacker, config.attackerPlayer, config.teamService)

	pending.hitCount += 1
	local maxHitCount = config.maxHitCount or 1
	if pending.hitCount >= maxHitCount then
		pending.expired = true
		playerPending[projectileId] = nil
	end

	if config.onHit then
		config.onHit({ hit = victimSet })
	end
end

--[=[
	PlayerId에 하단 모든 PendingProjectile을 제거합니다.
	플레이어 퇴장 시 호출.
]=]
function ProjectileHit.clearPlayer(userId: number)
	_pending[userId] = nil
	_pendingOnHit[userId] = nil
end

return ProjectileHit
