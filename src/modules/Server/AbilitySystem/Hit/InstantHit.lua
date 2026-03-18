--!strict
--[=[
	@class InstantHit

	범위 판정 유틸리티. 서버 전용.

	변경 이력:
	- apply() 제거: applyMap()으로 통합.
	- VictimSet 도입: enemies / teammates / self 로 분류.
	  classifyHits에서 TeamService:IsEnemy 기준으로 자동 분류.
	- HitMapResult: { [shapeId]: VictimSet }
	  DynamicIndicator의 shapeMap과 동일한 id 구조.

	지원 shape:
	- "cone":   부채꼴 (range, angleMin, angleMax)
	- "circle": 원/도넛 (radius, innerRadius)
	- "line":   직선 (range, width)
	- "arc":    포물선 착탄 (range, arcRadius)

	wallCheck:
	- 기본 true: attacker HRP → victim HRP 단일 Ray, 벽에 막히면 판정 제외.
	- false 지정 시만 비활성화.
	- CollisionGroup "HitCheck"는 "Characters"와 비충돌로 설정 필요.

	applyMap():
	- hitMap의 각 shape를 판정 후 VictimSet으로 분류.
	- onHit: { [shapeId]: VictimSet }
	- delay가 필요하면 HitConfig.delay 사용.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local cancellableDelay = require("cancellableDelay")

-- ─── 타입 정의 ───────────────────────────────────────────────────────────────

export type HitConfig = {
	shape: "cone" | "circle" | "line" | "arc",

	-- cone / line / arc 공통
	range: number?,

	-- cone 전용 (도 단위, 전방 기준, 부호 있는 각도)
	angleMin: number?,
	angleMax: number?,

	-- line 전용
	width: number?,

	-- circle 전용
	radius: number?,
	innerRadius: number?,

	-- arc 전용
	arcRadius: number?,

	-- 벽 차단 (false 지정 시만 비활성화, 기본 true)
	wallCheck: boolean?,

	delay: number?,
}

--[=[
	판정 결과를 관계별로 분류한 구조체.
	enemies   : attacker 기준 적군 (TeamService:IsEnemy == true)
	teammates : 같은 팀 (자신 제외)
	self      : attacker 본인 캐릭터 (판정 범위에 포함된 경우)
]=]
export type VictimSet = {
	enemies: { Model },
	teammates: { Model },
	self: Model?,
}

--[=[
	shape id → VictimSet 맵.
	DynamicIndicator의 shapeMap과 동일한 id 구조.
	예) { inner = VictimSet, outer = VictimSet }
]=]
export type HitMapResult = { [string]: VictimSet }

export type HitMap = { [string]: HitConfig }

-- ─── RaycastParams ───────────────────────────────────────────────────────────

local WALL_CHECK_PARAMS = RaycastParams.new()
WALL_CHECK_PARAMS.CollisionGroup = "HitCheck"

-- ─── 내부 유틸 ───────────────────────────────────────────────────────────────

local InstantHit = {}

local function getCharactersInSphere(origin: Vector3, searchRadius: number): { Model }
	local parts = workspace:GetPartBoundsInRadius(origin, searchRadius, OverlapParams.new())
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

local function isObstructed(attackerHRP: BasePart, targetRootPart: BasePart): boolean
	local from = attackerHRP.Position
	local to = targetRootPart.Position
	local result = workspace:Raycast(from, to - from, WALL_CHECK_PARAMS)
	return result ~= nil
end

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

local function doHit(attacker: Model, origin: Vector3, direction: Vector3, config: HitConfig): { Model }
	local useWallCheck = config.wallCheck ~= false
	local attackerHRP = if useWallCheck then attacker:FindFirstChild("HumanoidRootPart") :: BasePart? else nil

	local hits: { Model }

	if config.shape == "cone" then
		local range = config.range or 8
		local candidates = getCharactersInSphere(origin, range)
		hits = filterCone(origin, direction, candidates, range, config.angleMin or -180, config.angleMax or 180)
	elseif config.shape == "line" then
		local range = config.range or 10
		local candidates = getCharactersInSphere(origin, range)
		hits = filterLine(origin, direction, candidates, range, config.width or 2)
	elseif config.shape == "circle" then
		local radius = config.radius or 5
		local candidates = getCharactersInSphere(origin, radius)
		hits = filterCircle(origin, candidates, radius, config.innerRadius or 0)
	elseif config.shape == "arc" then
		local range = config.range or 20
		local arcRadius = config.arcRadius or 3
		local dirH = Vector3.new(direction.X, 0, direction.Z)
		dirH = if dirH.Magnitude < 0.001 then Vector3.new(0, 0, -1) else dirH.Unit
		local landingOrigin = Vector3.new(origin.X + dirH.X * range, origin.Y, origin.Z + dirH.Z * range)
		local candidates = getCharactersInSphere(landingOrigin, arcRadius)
		hits = filterArc(origin, direction, candidates, range, arcRadius)
	else
		hits = {}
	end

	if useWallCheck and attackerHRP then
		hits = applyWallCheck(attackerHRP, hits)
	end

	return hits
end

--[=[
	geometry 판정 결과를 enemies / teammates / self 로 분류합니다.

	attacker 본인은 self에 저장.
	나머지는 TeamService:IsEnemy 기준으로 enemies / teammates 분류.
	teamService 또는 attackerPlayer가 nil이면 attacker 제외 전체를 enemies로 취급.
]=]
local function classifyHits(hits: { Model }, attacker: Model, attackerPlayer: Player?, teamService: any?): VictimSet
	local result: VictimSet = { enemies = {}, teammates = {}, self = nil }

	for _, char in hits do
		-- 본인 분류
		if char == attacker then
			result.self = char
			continue
		end

		local player = Players:GetPlayerFromCharacter(char)
		if not player then
			continue
		end

		if teamService and attackerPlayer then
			if teamService:IsEnemy(attackerPlayer, player) then
				table.insert(result.enemies, char)
			else
				table.insert(result.teammates, char)
			end
		else
			-- teamService 없으면 전부 enemy 취급
			table.insert(result.enemies, char)
		end
	end

	return result
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	이름(id) 기반 멀티 shape 판정을 실행합니다.
	DynamicIndicator.new(shapeMap)과 동일한 맵 구조를 받습니다.

	onHit 콜백: { [shapeId]: VictimSet }
	  → enemies / teammates / self 로 분류된 결과.
	  → 같은 캐릭터가 여러 zone에 중복 포함될 수 있음.

	delay:
	  HitConfig.delay > 0이면 cancellableDelay 사용.
	  hitMap 내 첫 번째 config의 delay 기준 (공통 delay 가정).
	  개별 delay가 필요하면 applyMap 호출을 분리하세요.

	@param attacker      Model
	@param origin        Vector3
	@param direction     Vector3
	@param hitMap        HitMap
	@param onHit         ((HitMapResult) -> ())?
	@param fireMaid      any?
	@param teamService   any?   TeamService 인스턴스
	@param attackerPlayer Player?
]=]
function InstantHit.applyMap(
	attacker: Model,
	origin: Vector3,
	direction: Vector3,
	hitMap: HitMap,
	onHit: ((results: HitMapResult) -> ())?,
	fireMaid: any?,
	teamService: any?,
	attackerPlayer: Player?
): ()
	local function execute()
		local results: HitMapResult = {}
		for id, config in hitMap do
			local hits = doHit(attacker, origin, direction, config)
			results[id] = classifyHits(hits, attacker, attackerPlayer, teamService)
		end
		if onHit then
			onHit(results)
		end
	end

	local delay: number? = nil
	for _, config in hitMap do
		if config.delay and config.delay > 0 then
			delay = config.delay
		end
		break
	end

	if delay and delay > 0 then
		local cancel = cancellableDelay(delay, execute)
		if fireMaid then
			fireMaid:GiveTask(cancel)
		end
	else
		execute()
	end
end

return InstantHit
