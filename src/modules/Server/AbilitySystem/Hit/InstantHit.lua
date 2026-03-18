--!strict
--[=[
	@class InstantHit

	범위 판정 유틸리티. 서버 전용.

	변경 이력:
	- damage / knockback 제거: 데미지는 onHitChecked에서 직접 처리.
	- delay 제거: 공격 모듈에서 task.delay + fireMaid로 처리.
	- HpService 주입 제거: applyEffects 삭제로 불필요.
	- angle → angleMin / angleMax: DynamicIndicator 동일 기준 (부호 있는 각도).
	- circle: radius / innerRadius 추가 (도넛 판정 지원).
	- arc 추가: 착탄 지점(origin + direction * range) 기준 원판 판정.
	- wallCheck 기본 true: false 지정 시에만 벽 차단 비활성화.
	  CollisionGroup "HitCheck" 사용 → "Characters" 그룹 파츠 자동 통과.
	- attacker 자신 포함: getCharactersInSphere에서 attacker 제외 필터 제거.
	  onHitChecked에서 victimModel == state.attacker로 자기자신 구별.

	지원 shape:
	- "cone":   부채꼴 (range, angleMin, angleMax)
	- "circle": 원/도넛 (radius, innerRadius)
	- "line":   직선 (range, width)
	- "arc":    포물선 착탄 (range, arcRadius)

	wallCheck:
	- 기본 true: attacker HRP → victim HRP 단일 Ray, 벽에 막히면 판정 제외.
	- false 지정 시만 비활성화.
	- CollisionGroup "HitCheck"는 "Characters"와 비충돌로 설정 필요.
	  (PhysicsService 초기화는 BrawlersService 또는 별도 스크립트에서 수행)

	apply():
	- 즉시 판정, 반환값 없음.
	- delay가 필요하면 호출부에서 task.delay + fireMaid 처리.
	- onHit에는 항상 state.onHit 전달.
]=]

local require = require(script.Parent.loader).load(script)

local cancellableDelay = require("cancellableDelay")

-- ─── 타입 정의 ───────────────────────────────────────────────────────────────

export type HitConfig = {
	shape: "cone" | "circle" | "line" | "arc",

	-- cone / line / arc 공통
	range: number?,

	-- cone 전용 (도 단위, 전방 기준, 부호 있는 각도)
	-- 예) 중앙 90도  → angleMin=-45, angleMax=45
	-- 예) 오른쪽만   → angleMin=0,   angleMax=90
	-- 예) 전방향     → angleMin=-180, angleMax=180 (기본값)
	angleMin: number?,
	angleMax: number?,

	-- line 전용
	width: number?,

	-- circle 전용
	radius: number?, -- 원 반지름 (기본 5)
	innerRadius: number?, -- 도넛 내경 (기본 0, 0이면 꽉 찬 원)

	-- arc 전용: 착탄 지점 = origin + dirH * range 기준 원판
	arcRadius: number?, -- 착탄 반경 (기본 3)

	-- 벽 차단 (false 지정 시만 비활성화, 기본 true)
	wallCheck: boolean?,

	delay: number?, -- nil / 0이면 즉발
}

-- ─── RaycastParams (모듈 로드 시 1회 생성) ───────────────────────────────────

-- "HitCheck" CollisionGroup은 "Characters" 그룹과 비충돌로 설정되어야 함.
-- 캐릭터 파츠를 자동 통과, 환경(벽 등)만 감지.
local WALL_CHECK_PARAMS = RaycastParams.new()
WALL_CHECK_PARAMS.CollisionGroup = "HitCheck"

-- ─── 내부 유틸 ───────────────────────────────────────────────────────────────

local InstantHit = {}

--[=[
	구 범위 내 생존 캐릭터 수집.
	attacker 자신도 포함합니다.
	onHitChecked에서 victimModel == state.attacker로 자기자신을 구별하세요.
]=]
local function getCharactersInSphere(origin: Vector3, searchRadius: number, _attacker: Model): { Model }
	local params = OverlapParams.new()
	-- attacker 제외 없음 → 자기자신 포함

	local parts = workspace:GetPartBoundsInRadius(origin, searchRadius, params)
	local seen: { [Model]: boolean } = {}
	local result: { Model } = {}

	for _, part in parts do
		local char = part:FindFirstAncestorOfClass("Model")
		if not char or seen[char] then
			continue
		end
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			seen[char] = true
			table.insert(result, char)
		end
	end

	return result
end

-- 부채꼴 필터
-- angleMin~angleMax: 전방 기준 부호 있는 각도 (도). DynamicIndicator 동일 기준.
local function filterCone(
	origin: Vector3,
	direction: Vector3,
	chars: { Model },
	range: number,
	angleMin: number,
	angleMax: number
): { Model }
	local dirH = Vector3.new(direction.X, 0, direction.Z)
	if dirH.Magnitude < 0.001 then
		return chars
	end
	dirH = dirH.Unit

	local minRad = math.rad(angleMin)
	local maxRad = math.rad(angleMax)

	local result: { Model } = {}
	for _, char in chars do
		local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then
			continue
		end

		local toTarget = rootPart.Position - origin
		local horizontal = Vector3.new(toTarget.X, 0, toTarget.Z)

		if horizontal.Magnitude > range then
			continue
		end

		if horizontal.Magnitude < 0.001 then
			-- origin과 거의 겹침 → 무조건 히트 (자기자신 포함)
			table.insert(result, char)
			continue
		end

		local dot = math.clamp(horizontal.Unit:Dot(dirH), -1, 1)
		local ang = math.acos(dot)
		local cross = dirH:Cross(horizontal.Unit)
		local signedAng = ang * (if cross.Y >= 0 then 1 else -1)

		if signedAng >= minRad and signedAng <= maxRad then
			table.insert(result, char)
		end
	end

	return result
end

-- 직선 필터
local function filterLine(
	origin: Vector3,
	direction: Vector3,
	chars: { Model },
	range: number,
	width: number
): { Model }
	local halfWidth = width / 2
	local dirH = Vector3.new(direction.X, 0, direction.Z)
	if dirH.Magnitude < 0.001 then
		return {}
	end
	dirH = dirH.Unit

	local result: { Model } = {}
	for _, char in chars do
		local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then
			continue
		end

		local toTarget = rootPart.Position - origin
		local toTargetH = Vector3.new(toTarget.X, 0, toTarget.Z)

		local forward = toTargetH:Dot(dirH)
		if forward < 0 or forward > range then
			continue
		end

		local side = (toTargetH - dirH * forward).Magnitude
		if side <= halfWidth then
			table.insert(result, char)
		end
	end

	return result
end

-- 원/도넛 필터
-- innerRadius > 0 → 도넛 (내경 안쪽 제외)
local function filterCircle(origin: Vector3, chars: { Model }, radius: number, innerRadius: number): { Model }
	local result: { Model } = {}
	for _, char in chars do
		local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then
			continue
		end

		local toTarget = rootPart.Position - origin
		local dist = Vector3.new(toTarget.X, 0, toTarget.Z).Magnitude

		if dist <= radius and dist >= innerRadius then
			table.insert(result, char)
		end
	end

	return result
end

-- arc 착탄 필터
-- 착탄 지점 = origin + dirH * range, 그 지점 기준 arcRadius 원판 판정.
-- DynamicIndicator posUpdateArc의 t=1 착탄 지점과 동일 기준.
local function filterArc(
	origin: Vector3,
	direction: Vector3,
	chars: { Model },
	range: number,
	arcRadius: number
): { Model }
	local dirH = Vector3.new(direction.X, 0, direction.Z)
	if dirH.Magnitude < 0.001 then
		return {}
	end
	dirH = dirH.Unit

	local landingH = Vector3.new(origin.X + dirH.X * range, origin.Y, origin.Z + dirH.Z * range)

	local result: { Model } = {}
	for _, char in chars do
		local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then
			continue
		end

		local toTarget = rootPart.Position - landingH
		local dist = Vector3.new(toTarget.X, 0, toTarget.Z).Magnitude

		if dist <= arcRadius then
			table.insert(result, char)
		end
	end

	return result
end

-- attacker HRP → target HRP 단일 Ray.
-- CollisionGroup "HitCheck": Characters 파츠 통과, 환경(벽 등)만 감지.
local function isObstructed(attackerHRP: BasePart, targetRootPart: BasePart): boolean
	local from = attackerHRP.Position
	local to = targetRootPart.Position
	local result = workspace:Raycast(from, to - from, WALL_CHECK_PARAMS)
	return result ~= nil
end

-- 벽 차단 필터. useWallCheck == true일 때만 호출.
local function applyWallCheck(attackerHRP: BasePart, hits: { Model }): { Model }
	local result: { Model } = {}
	for _, char in hits do
		local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart and not isObstructed(attackerHRP, rootPart) then
			table.insert(result, char)
		end
	end
	return result
end

-- shape에 따라 판정 후 적중 목록 반환
local function doHit(attacker: Model, origin: Vector3, direction: Vector3, config: HitConfig): { Model }
	local useWallCheck = config.wallCheck ~= false
	local attackerHRP = if useWallCheck then attacker:FindFirstChild("HumanoidRootPart") :: BasePart? else nil

	local hits: { Model }

	if config.shape == "cone" then
		local range = config.range or 8
		local candidates = getCharactersInSphere(origin, range, attacker)
		hits = filterCone(origin, direction, candidates, range, config.angleMin or -180, config.angleMax or 180)
	elseif config.shape == "line" then
		local range = config.range or 10
		local candidates = getCharactersInSphere(origin, range, attacker)
		hits = filterLine(origin, direction, candidates, range, config.width or 2)
	elseif config.shape == "circle" then
		local radius = config.radius or 5
		local candidates = getCharactersInSphere(origin, radius, attacker)
		hits = filterCircle(origin, candidates, radius, config.innerRadius or 0)
	elseif config.shape == "arc" then
		local range = config.range or 20
		local arcRadius = config.arcRadius or 3
		local dirH = Vector3.new(direction.X, 0, direction.Z)
		dirH = if dirH.Magnitude < 0.001 then Vector3.new(0, 0, -1) else dirH.Unit
		local landingOrigin = Vector3.new(origin.X + dirH.X * range, origin.Y, origin.Z + dirH.Z * range)
		local candidates = getCharactersInSphere(landingOrigin, arcRadius, attacker)
		hits = filterArc(origin, direction, candidates, range, arcRadius)
	else
		hits = {}
	end

	if useWallCheck and attackerHRP then
		hits = applyWallCheck(attackerHRP, hits)
	end

	return hits
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	범위 판정을 즉시 실행합니다.
	attacker 자신도 victims에 포함됩니다.
	onHitChecked에서 victimModel == state.attacker 비교로 자기자신을 구별하세요.

	delay가 필요한 경우:
	  호출부에서 task.delay + fireMaid로 처리.
	  예)
	    local cancelled = false
	    state.fireMaid:GiveTask(function() cancelled = true end)
	    task.delay(0.3, function()
	      if cancelled then return end
	      InstantHit.apply(state.attacker, state.origin, state.direction, config, state.onHit)
	    end)

	onHit:
	  항상 state.onHit 전달. nil이면 판정만 수행.
]=]
function InstantHit.apply(
	attacker: Model,
	origin: Vector3,
	direction: Vector3,
	config: HitConfig,
	onHit: ((victims: { Model }) -> ())?,
	fireMaid: any?
): ()
	if config.delay and config.delay > 0 then
		local cancel = cancellableDelay(config.delay, function()
			local hits = doHit(attacker, origin, direction, config)
			if onHit then
				onHit(hits)
			end
		end)
		if fireMaid then
			fireMaid:GiveTask(cancel)
		end
	else
		local hits = doHit(attacker, origin, direction, config)
		if onHit then
			onHit(hits)
		end
	end
end

return InstantHit
