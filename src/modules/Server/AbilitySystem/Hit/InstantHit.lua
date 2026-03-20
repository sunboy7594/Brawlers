--!strict
--[=[
	@class InstantHit

	범위 판정 유틸리티. 서버 전용.

	verdict():
	  hitMap의 각 shape를 판정 후 VictimSet으로 분류.
	  latency 보정: effectiveDelay = math.max(0, delay - latency)

	지원 shape:
	- "cone":   부채꼴 (range, angleMin, angleMax)
	- "circle": 원/도넛 (radius, innerRadius)
	- "line":   직선 (range, width)
	- "arc":    포물선 착탈 (range, arcRadius)

	wallCheck:
	- 기본 true: attacker HRP → victim HRP 단일 Ray.
	- false 지정 시만 비활성화.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local cancellableDelay = require("cancellableDelay")

export type HitConfig = {
	shape    : "cone" | "circle" | "line" | "arc",
	range    : number?,
	angleMin : number?,
	angleMax : number?,
	width    : number?,
	radius   : number?,
	innerRadius : number?,
	arcRadius : number?,
	wallCheck : boolean?,
	delay    : number?,
}

export type VictimSet = {
	enemies   : { Model },
	teammates : { Model },
	self      : Model?,
}

export type HitMapResult = { [string]: VictimSet }
export type HitMap       = { [string]: HitConfig }

local WALL_CHECK_PARAMS = RaycastParams.new()
WALL_CHECK_PARAMS.CollisionGroup = "HitCheck"

local InstantHit = {}

local function getCharactersInSphere(origin: Vector3, searchRadius: number): { Model }
	local parts = workspace:GetPartBoundsInRadius(origin, searchRadius, OverlapParams.new())
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

local function filterCone(origin, direction, chars, range, angleMin, angleMax)
	local dirH = Vector3.new(direction.X, 0, direction.Z)
	if dirH.Magnitude < 0.001 then return chars end
	dirH = dirH.Unit
	local minRad = math.rad(angleMin)
	local maxRad = math.rad(angleMax)
	local result: { Model } = {}
	for _, char in chars do
		local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then continue end
		local toTarget   = rootPart.Position - origin
		local horizontal = Vector3.new(toTarget.X, 0, toTarget.Z)
		if horizontal.Magnitude > range then continue end
		if horizontal.Magnitude < 0.001 then table.insert(result, char) continue end
		local dot       = math.clamp(horizontal.Unit:Dot(dirH), -1, 1)
		local ang       = math.acos(dot)
		local cross     = dirH:Cross(horizontal.Unit)
		local signedAng = ang * (if cross.Y >= 0 then 1 else -1)
		if signedAng >= minRad and signedAng <= maxRad then table.insert(result, char) end
	end
	return result
end

local function filterLine(origin, direction, chars, range, width)
	local halfWidth = width / 2
	local dirH = Vector3.new(direction.X, 0, direction.Z)
	if dirH.Magnitude < 0.001 then return {} end
	dirH = dirH.Unit
	local result: { Model } = {}
	for _, char in chars do
		local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then continue end
		local toTarget  = rootPart.Position - origin
		local toTargetH = Vector3.new(toTarget.X, 0, toTarget.Z)
		local forward   = toTargetH:Dot(dirH)
		if forward < 0 or forward > range then continue end
		local side = (toTargetH - dirH * forward).Magnitude
		if side <= halfWidth then table.insert(result, char) end
	end
	return result
end

local function filterCircle(origin, chars, radius, innerRadius)
	local result: { Model } = {}
	for _, char in chars do
		local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then continue end
		local dist = Vector3.new(rootPart.Position.X - origin.X, 0, rootPart.Position.Z - origin.Z).Magnitude
		if dist <= radius and dist >= innerRadius then table.insert(result, char) end
	end
	return result
end

local function filterArc(origin, direction, chars, range, arcRadius)
	local dirH = Vector3.new(direction.X, 0, direction.Z)
	if dirH.Magnitude < 0.001 then return {} end
	dirH = dirH.Unit
	local landingH = Vector3.new(origin.X + dirH.X * range, origin.Y, origin.Z + dirH.Z * range)
	local result: { Model } = {}
	for _, char in chars do
		local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then continue end
		local dist = Vector3.new(rootPart.Position.X - landingH.X, 0, rootPart.Position.Z - landingH.Z).Magnitude
		if dist <= arcRadius then table.insert(result, char) end
	end
	return result
end

local function isObstructed(attackerHRP: BasePart, targetRootPart: BasePart): boolean
	local from = attackerHRP.Position
	local to   = targetRootPart.Position
	return workspace:Raycast(from, to - from, WALL_CHECK_PARAMS) ~= nil
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
	local attackerHRP  = if useWallCheck then attacker:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local hits: { Model }
	if config.shape == "cone" then
		local range = config.range or 8
		hits = filterCone(origin, direction, getCharactersInSphere(origin, range), range, config.angleMin or -180, config.angleMax or 180)
	elseif config.shape == "line" then
		local range = config.range or 10
		hits = filterLine(origin, direction, getCharactersInSphere(origin, range), range, config.width or 2)
	elseif config.shape == "circle" then
		local radius = config.radius or 5
		hits = filterCircle(origin, getCharactersInSphere(origin, radius), radius, config.innerRadius or 0)
	elseif config.shape == "arc" then
		local range = config.range or 20
		local arcRadius = config.arcRadius or 3
		local dirH = Vector3.new(direction.X, 0, direction.Z)
		dirH = if dirH.Magnitude < 0.001 then Vector3.new(0, 0, -1) else dirH.Unit
		local landingOrigin = Vector3.new(origin.X + dirH.X * range, origin.Y, origin.Z + dirH.Z * range)
		hits = filterArc(origin, direction, getCharactersInSphere(landingOrigin, arcRadius), range, arcRadius)
	else
		hits = {}
	end
	if useWallCheck and attackerHRP then
		hits = applyWallCheck(attackerHRP, hits)
	end
	return hits
end

local function classifyHits(hits: { Model }, attacker: Model, attackerPlayer: Player?, teamService: any?): VictimSet
	local result: VictimSet = { enemies = {}, teammates = {}, self = nil }
	for _, char in hits do
		if char == attacker then result.self = char continue end
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

function InstantHit.verdict(
	attacker       : Model,
	origin         : Vector3,
	direction      : Vector3,
	hitMap         : HitMap,
	onHit          : ((results: HitMapResult) -> ())?,
	fireMaid       : any?,
	teamService    : any?,
	attackerPlayer : Player?,
	latency        : number?
): ()
	local lat = latency or 0

	local function execute()
		local results: HitMapResult = {}
		for id, config in hitMap do
			local hits = doHit(attacker, origin, direction, config)
			results[id] = classifyHits(hits, attacker, attackerPlayer, teamService)
		end
		if onHit then onHit(results) end
	end

	local delay: number? = nil
	for _, config in hitMap do
		if config.delay and config.delay > 0 then delay = config.delay end
		break
	end

	if delay and delay > 0 then
		local effectiveDelay = math.max(0, delay - lat)
		if effectiveDelay > 0 then
			local cancel = cancellableDelay(effectiveDelay, execute)
			if fireMaid then fireMaid:GiveTask(cancel) end
		else
			execute()
		end
	else
		execute()
	end
end

return InstantHit
