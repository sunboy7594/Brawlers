--!strict
--[=[
	@class AbilityEffectHitDetectionUtil

	판정 유틸. (Shared) Box 판정만 사용.
	Y축 고정 게임이므로 직육면체 하나로 모든 판정 커버.

	사용법:
	  hitDetect = AbilityEffectHitDetectionUtil.Box({
	      size         = Vector3.new(3, 3, 3),
	      offset       = CFrame.new(0, 0, -1.5),
	      activateAt   = 0.1,
	      deactivateAt = 0.5,
	      relations    = { "enemy" },  -- nil이면 {"enemy"} 기본값
	      sizeGrow     = { from = Vector3.new(1,3,1), to = Vector3.new(6,3,6), duration = 0.3, mode = "linear", speed = 1 },
	  })

	  hitDetect = function(elapsed, handle, params)
	      return AbilityEffectHitDetectionUtil.Box({ size = Vector3.new(elapsed * 2, 3, elapsed * 2) })
	  end

	HitDetectFunction:
	  고정값: BoxConfig
	  동적:   (elapsed, handle, params) -> BoxConfig?   nil이면 이번 프레임 판정 스킵

	relations:
	  nil            → { "enemy" } 기본값
	  { "enemy" }    → 적만
	  { "team" }     → 아군만 (힐 스킬 등)
	  { "self" }     → 자기 자신만
	  { "enemy", "team", "self" } → 전체

	반환 HitInfo 배열:
	  { target: Model, relation: HitRelation, position: Vector3 }
]=]

local AbilityEffectHitDetectionUtil = {}

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type HitRelation = "enemy" | "self" | "team" | "wall"

export type HitInfo = {
	target: Model,
	relation: HitRelation,
	position: Vector3,
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

export type HitDetectFunction = BoxConfig | (elapsed: number, handle: any, params: { [string]: any }?) -> BoxConfig?

-- ─── 내부 유틸 ───────────────────────────────────────────────────────────────

local function lerpVec3(a: Vector3, b: Vector3, t: number): Vector3
	return a:Lerp(b, t)
end

local function resolveSize(config: BoxConfig, elapsed: number): Vector3
	local grow = config.sizeGrow
	if not grow then
		return config.size
	end
	local t = math.clamp(elapsed / grow.duration, 0, 1)
	if grow.mode == "spring" then
		t = 1 - math.exp(-grow.speed * elapsed)
		t = math.clamp(t, 0, 1)
	end
	return lerpVec3(grow.from, grow.to, t)
end

-- ─── Box ─────────────────────────────────────────────────────────────────────

function AbilityEffectHitDetectionUtil.Box(config: BoxConfig): BoxConfig
	return config
end

-- ─── 판정 실행 ────────────────────────────────────────────────────────────────

--[=[
	handle._teamContext에서 attackerChar, attackerPlayer, isEnemy를 꺼내 판정합니다.
	boxConfig.relations로 반환할 relation을 필터링합니다.

	@param hitDetect   HitDetectFunction?
	@param elapsed     number
	@param handle      any   handle._teamContext 참조
	@param params      { [string]: any }?
	@return { HitInfo }
]=]
function AbilityEffectHitDetectionUtil.Detect(
	hitDetect: HitDetectFunction?,
	elapsed: number,
	handle: any,
	params: { [string]: any }?
): { HitInfo }
	if not hitDetect then
		return {}
	end

	local boxConfig: BoxConfig?
	if type(hitDetect) == "function" then
		boxConfig = (hitDetect :: any)(elapsed, handle, params)
	else
		boxConfig = hitDetect :: BoxConfig
	end

	if not boxConfig then
		return {}
	end

	if boxConfig.activateAt and elapsed < boxConfig.activateAt then
		return {}
	end
	if boxConfig.deactivateAt and elapsed > boxConfig.deactivateAt then
		return {}
	end

	-- teamContext 추출
	local teamContext = handle._teamContext
	local attackerChar = teamContext and teamContext.attackerChar
	local attackerPlayer = teamContext and teamContext.attackerPlayer
	local isEnemyFn = teamContext and teamContext.isEnemy

	-- relations 필터 빌드
	local relationFilter: { [HitRelation]: boolean } = {}
	for _, r in (boxConfig.relations or { "enemy" }) do
		relationFilter[r] = true
	end

	local size = resolveSize(boxConfig, elapsed)
	local baseCF = handle.part and handle.part:GetPivot() or CFrame.identity
	local detectCF = boxConfig.offset and (baseCF * boxConfig.offset) or baseCF

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	if attackerChar and not relationFilter["self"] then
		-- self를 감지하지 않을 때만 필터에서 제외
		overlapParams.FilterDescendantsInstances = { attackerChar }
	end

	local parts = workspace:GetPartBoundsInBox(detectCF, size, overlapParams)

	local seen: { [Model]: boolean } = {}
	local results: { HitInfo } = {}

	for _, part in parts do
		local char = part:FindFirstAncestorOfClass("Model")
		if not char or seen[char] then
			continue
		end
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			continue
		end
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

		if not relationFilter[relation] then
			continue
		end

		table.insert(results, {
			target = char,
			relation = relation,
			position = char:GetPivot().Position,
		})
	end

	return results
end

return AbilityEffectHitDetectionUtil
