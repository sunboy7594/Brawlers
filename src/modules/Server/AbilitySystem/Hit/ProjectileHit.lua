--!strict
--[=[
	@class ProjectileHit

	투사체 판정 유틸. 서버 전용.

	역할:
	- PendingProjectile 등록 / 만료 관리
	- 클라이언트 히트 보고 검증 3단계
	- 판정 결과를 InstantHit과 동일한 HitMapResult 형식으로 onHit에 전달

	검증 3단계:
	  1. projectileId 유효성 (등록된 투사체인지, 이미 소비/만료됐는지)
	  2. hitPosition 위치 타당성 (예상 이동 거리 + 레이턴시 허용 오차 내인지)
	  3. hitPosition 기준 실제 대상 근접 여부 (GetPartBoundsInRadius)

	만료 처리:
	  maxRange / speed + latencyBuffer 시간 후 자동 만료.
	  fireMaid에 등록하면 CancelCombatState 시 즉시 만료.

	HitMapResult 포맷:
	  { ["hit"]: VictimSet }
	  투사체는 단일 shape이므로 shapeId를 "hit"으로 고정.
	  InstantHit.applyMap과 동일한 형식으로 onHitChecked 기존 코드 재사용 가능.

	사용법 (서버 어빌리티 모듈 onFire에서):
	  ProjectileHit.register(
	      player,
	      state.projectileId,
	      {
	          origin        = state.origin,
	          direction     = state.direction,
	          speed         = 30,
	          hitRadius     = 2,
	          maxRange      = 50,
	          firedAt       = os.clock(),
	          attacker      = state.attacker,
	          teamService   = state.teamService,
	          attackerPlayer= state.attackerPlayer,
	          onHit         = state.onHit,
	      },
	      state.fireMaid
	  )
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local cancellableDelay = require("cancellableDelay")

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local DEFAULT_LATENCY_BUFFER = 0.25  -- 기본 레이턴시 허용 추가 시간 (초)

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type VictimSet = {
	enemies   : { Model },
	teammates : { Model },
	self      : Model?,
}

export type HitMapResult = { [string]: VictimSet }

export type ProjectileConfig = {
	origin         : Vector3,
	direction      : Vector3,     -- 단위벡터
	speed          : number,      -- 스터드/초
	hitRadius      : number,      -- 충돌 감지 반경
	maxRange       : number,      -- 최대 사거리
	firedAt        : number,      -- os.clock() 기준 서버 시각
	attacker       : Model,
	latencyBuffer  : number?,     -- 레이턴시 허용 시간 (기본 0.25)
	wallCheck      : boolean?,    -- 벽 차단 (기본 true)
	maxHitCount    : number?,     -- 최대 히트 수 (nil = 1회 후 만료)
	teamService    : any?,
	attackerPlayer : Player?,
	onHit          : ((HitMapResult) -> ())?,
}

type PendingProjectile = {
	config    : ProjectileConfig,
	hitCount  : number,
	expired   : boolean,
}

-- ─── 걸로벌 상태 ───────────────────────────────────────────────────────────────
-- userId → projectileId → PendingProjectile
-- ProjectileHitService가 onHitReport를 호출할 때 사용

local _pending: { [number]: { [string]: PendingProjectile } } = {}

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
	PendingProjectile를 등록합니다.
	fireMaid에 등록하면 CancelCombatState 시 자동 만료.

	@param player        Player         공격자 (등록자 검증용)
	@param projectileId  string         클라이언트가 생성한 고유 ID
	@param config        ProjectileConfig
	@param fireMaid      any?           등록 시 만료 cleanup 연동
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

	-- 자동 만료 시간 계산
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
		-- fireMaid Destroy 시에도 즉시 제거
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

	@param player       Player
	@param projectileId string
	@param hitPosition  Vector3
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

	-- ─── 단계 1: projectileId 유효성 ────────────────────────────────────────────
	-- (playerPending[projectileId] 존재하고 expired가 false이면 통과)

	-- ─── 단계 2: hitPosition 위치 타당성 ────────────────────────────────────────
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

	-- wallCheck
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

	-- 히트 회수 증가
	pending.hitCount += 1

	-- maxHitCount 도달 시 만료
	local maxHitCount = config.maxHitCount or 1
	if pending.hitCount >= maxHitCount then
		pending.expired = true
		playerPending[projectileId] = nil
	end

	-- onHit 콜백 실행 (InstantHit과 동일한 HitMapResult 형식)
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
end

return ProjectileHit
