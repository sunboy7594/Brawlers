--!strict
--[=[
	@class HitDetectionUtil

	판정 유틸. (Shared)
	EntityController / ProjectileHit 공용.

	지원 형태:
	  Box    → 직육면체
	  Sphere → 구형

	relations:
	  nil                → { "enemy" } 기본값
	  { "enemy" }       → 적만
	  { "team" }        → 아군만
	  { "self" }        → 자기 자신만
	  { "obstacle" }    → Humanoid 없는 오브젝트 (HitRole attribute 있는 것만)

	obstacle HitRole 세부 구분:
	  "Floor"            → 착지 감지용 바닥
	  "WallObstacle"     → 일반 벽. relations 필터 적용. 관통 어빌리티는 통과 가능.
	  "HardObstacle"     → 경기장 외벽 등 절대 막히는 것. relations 무관하게 무조건 onHit.
	                       Penetrate도 무시. (hitInfo.hard = true)
	  "MovementObstacle" → 이동만 막는 것 (물 투명벽 등).
	                       HitDetection에서 항상 무시. (투사체 관통)

	무기 파트 제외:
	  CanQuery = false로 설정된 파트는 판정 안 잡힘
]=]

local HitDetectionUtil = {}

-- ─── 타입 ───────────────────────────────────────────────────────────────────

export type HitRelation = "enemy" | "self" | "team" | "obstacle"

export type HitInfo = {
	target: Model | BasePart,
	relation: HitRelation,
	position: Vector3,
	hard: boolean?, -- HardObstacle이면 true (Penetrate 무시, 무조건 onHit)
}

export type GrowConfig = {
	from: Vector3,
	to: Vector3,
	duration: number,
	mode: ("linear" | "spring")?,
	speed: number,
	damper: number?,
}

export type BoxConfig = {
	size: Vector3,
	offset: CFrame?,
	activateAt: number?,
	deactivateAt: number?,
	sizeGrow: GrowConfig?,
	relations: { HitRelation }?,
}

export type SphereConfig = {
	radius: number,
	offset: CFrame?,
	activateAt: number?,
	deactivateAt: number?,
	relations: { HitRelation }?,
	_isSphere: boolean?,
}

export type HitDetectConfig = BoxConfig | SphereConfig
export type HitDetectFunction =
	HitDetectConfig
	| (elapsed: number, handle: any, params: { [string]: any }?) -> HitDetectConfig?

-- ─── 내부 유틸 ──────────────────────────────────────────────────────────────

local function lerpVec3(a: Vector3, b: Vector3, t: number): Vector3
	return a:Lerp(b, t)
end

local function resolveBoxSize(config: BoxConfig, elapsed: number): Vector3
	local grow = config.sizeGrow
	if not grow then
		return config.size
	end
	local t = math.clamp(elapsed / grow.duration, 0, 1)
	if grow.mode == "spring" then
		t = math.clamp(1 - math.exp(-grow.speed * elapsed), 0, 1)
	end
	return lerpVec3(grow.from, grow.to, t)
end

local function classifyChar(
	char: Model,
	attackerChar: Model?,
	attackerPlayer: Player?,
	isEnemyFn: ((Player, Player) -> boolean)?
): HitRelation
	if char == attackerChar then
		return "self"
	end
	if isEnemyFn and attackerPlayer then
		local victimPlayer = game:GetService("Players"):GetPlayerFromCharacter(char)
		if victimPlayer then
			return if isEnemyFn(attackerPlayer, victimPlayer) then "enemy" else "team"
		end
	end
	return "enemy"
end

-- ─── Box ─────────────────────────────────────────────────────────────────────

function HitDetectionUtil.Box(config: BoxConfig): BoxConfig
	return config
end

-- ─── Sphere ──────────────────────────────────────────────────────────────────

function HitDetectionUtil.Sphere(config: SphereConfig): SphereConfig
	config._isSphere = true
	return config
end

-- ─── 판정 실행 ──────────────────────────────────────────────────────────────

function HitDetectionUtil.Detect(
	hitDetect: HitDetectFunction?,
	elapsed: number,
	handle: any,
	params: { [string]: any }?
): { HitInfo }
	if not hitDetect then
		return {}
	end

	local config: HitDetectConfig?
	if type(hitDetect) == "function" then
		config = (hitDetect :: any)(elapsed, handle, params)
	else
		config = hitDetect :: HitDetectConfig
	end

	if not config then
		return {}
	end
	local cfg = config :: any

	-- activateAt / deactivateAt
	if cfg.activateAt and elapsed < cfg.activateAt then
		return {}
	end
	if cfg.deactivateAt and elapsed > cfg.deactivateAt then
		return {}
	end

	local teamContext = handle._teamContext
	local attackerChar = teamContext and teamContext.attackerChar
	local attackerPlayer = teamContext and teamContext.attackerPlayer
	local isEnemyFn = teamContext and teamContext.isEnemy

	local relationFilter: { [string]: boolean } = {}
	for _, r in (cfg.relations or { "enemy" }) do
		relationFilter[r] = true
	end

	local baseCF = handle.part and handle.part:GetPivot() or CFrame.identity
	local detectCF = cfg.offset and (baseCF * cfg.offset) or baseCF

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	if attackerChar and not relationFilter["self"] then
		overlapParams.FilterDescendantsInstances = { attackerChar }
	end

	local parts: { BasePart }
	if cfg._isSphere then
		parts = workspace:GetPartBoundsInRadius(detectCF.Position, cfg.radius, overlapParams)
	else
		local size = resolveBoxSize(cfg :: BoxConfig, elapsed)
		parts = workspace:GetPartBoundsInBox(detectCF, size, overlapParams)
	end

	local seen: { [any]: boolean } = {}
	local results: { HitInfo } = {}

	for _, part in parts do
		-- 캐릭터 판정
		local char = part:FindFirstAncestorOfClass("Model")
		if char and not seen[char] then
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				seen[char] = true
				local relation = classifyChar(char :: Model, attackerChar, attackerPlayer, isEnemyFn)
				if relationFilter[relation] then
					table.insert(results, {
						target = char :: Model,
						relation = relation,
						position = char:GetPivot().Position,
					})
				end
				continue
			end
		end

		-- obstacle 판정 (Humanoid 없는 것)
		if not seen[part] then
			seen[part] = true

			local target: (Model | BasePart)?
			local role: string?
			local position: Vector3?

			if char and not seen[char] then
				seen[char] = true
				role = (char :: any):GetAttribute("HitRole")
				target = char :: Model
				position = (char :: Model):GetPivot().Position
			elseif not char then
				role = part:GetAttribute("HitRole")
				target = part
				position = part.Position
			end

			if not role or not target or not position then
				continue
			end

			if role == "MovementObstacle" then
				-- 이동만 막는 것 → 투사체는 항상 통과, 무시
			elseif role == "HardObstacle" then
				-- 경기장 외벽 등 → relations 무관하게 무조건 추가
				-- hard = true → EntityController에서 Penetrate 무시하고 즉시 onHit
				table.insert(results, {
					target = target,
					relation = "obstacle",
					position = position,
					hard = true,
				})
			elseif relationFilter["obstacle"] then
				-- WallObstacle, Floor 등 → 기존대로 relations 필터 적용
				table.insert(results, {
					target = target,
					relation = "obstacle",
					position = position,
				})
			end
		end
	end

	return results
end

return HitDetectionUtil
