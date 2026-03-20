--!strict
--[=[
	@class HitDetectionUtil

	박스 판정 유틸. (Shared)
	클라이언트 AbilityEffect, 서버 ProjectileHit 공용.
]=]

local HitDetectionUtil = {}

export type HitRelation = "enemy" | "self" | "team" | "wall"

export type HitInfo = {
	target   : Model,
	relation : HitRelation,
	position : Vector3,
}

export type GrowConfig = {
	from     : Vector3,
	to       : Vector3,
	duration : number,
	mode     : ("linear" | "spring")?,
	speed    : number,
	damper   : number?,
}

export type BoxConfig = {
	size         : Vector3,
	offset       : CFrame?,
	activateAt   : number?,
	deactivateAt : number?,
	sizeGrow     : GrowConfig?,
	relations    : { HitRelation }?,
}

export type HitDetectFunction = BoxConfig | (elapsed: number, handle: any, params: { [string]: any }?) -> BoxConfig?

local function lerpVec3(a: Vector3, b: Vector3, t: number): Vector3
	return a:Lerp(b, t)
end

local function resolveSize(config: BoxConfig, elapsed: number): Vector3
	local grow = config.sizeGrow
	if not grow then return config.size end
	local t = math.clamp(elapsed / grow.duration, 0, 1)
	if grow.mode == "spring" then
		t = 1 - math.exp(-grow.speed * elapsed)
		t = math.clamp(t, 0, 1)
	end
	return lerpVec3(grow.from, grow.to, t)
end

function HitDetectionUtil.Box(config: BoxConfig): BoxConfig
	return config
end

function HitDetectionUtil.Detect(
	hitDetect : HitDetectFunction?,
	elapsed   : number,
	handle    : any,
	params    : { [string]: any }?
): { HitInfo }
	if not hitDetect then return {} end

	local boxConfig: BoxConfig?
	if type(hitDetect) == "function" then
		boxConfig = (hitDetect :: any)(elapsed, handle, params)
	else
		boxConfig = hitDetect :: BoxConfig
	end

	if not boxConfig then return {} end

	if boxConfig.activateAt and elapsed < boxConfig.activateAt then return {} end
	if boxConfig.deactivateAt and elapsed > boxConfig.deactivateAt then return {} end

	local teamContext    = handle._teamContext
	local attackerChar   = teamContext and teamContext.attackerChar
	local attackerPlayer = teamContext and teamContext.attackerPlayer
	local isEnemyFn      = teamContext and teamContext.isEnemy

	local relationFilter: { [HitRelation]: boolean } = {}
	for _, r in (boxConfig.relations or { "enemy" }) do
		relationFilter[r] = true
	end

	local size     = resolveSize(boxConfig, elapsed)
	local baseCF   = handle.part and handle.part:GetPivot() or CFrame.identity
	local detectCF = boxConfig.offset and (baseCF * boxConfig.offset) or baseCF

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	if attackerChar and not relationFilter["self"] then
		overlapParams.FilterDescendantsInstances = { attackerChar }
	end

	local parts = workspace:GetPartBoundsInBox(detectCF, size, overlapParams)

	local seen    : { [Model]: boolean } = {}
	local results : { HitInfo }          = {}

	for _, part in parts do
		local char = part:FindFirstAncestorOfClass("Model")
		if not char or seen[char] then continue end
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		-- ✅ <= 0: Roblox에서 Health는 0이 최솟값 (음수 불가). < 0이면 시체도 통과되는 버그 발생.
		if not humanoid or humanoid.Health <= 0 then continue end
		seen[char] = true

		local relation: HitRelation = "enemy"
		if char == attackerChar then
			relation = "self"
		elseif isEnemyFn and attackerPlayer then
			local victimPlayer = game:GetService("Players"):GetPlayerFromCharacter(char)
			if victimPlayer then
				relation = if isEnemyFn(attackerPlayer, victimPlayer) then "enemy" else "team"
			end
		end

		if not relationFilter[relation] then continue end

		table.insert(results, {
			target   = char,
			relation = relation,
			position = char:GetPivot().Position,
		})
	end

	return results
end

return HitDetectionUtil
