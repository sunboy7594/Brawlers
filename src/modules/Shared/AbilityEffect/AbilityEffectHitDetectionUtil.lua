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
	      sizeGrow     = { from = Vector3.new(1,3,1), to = Vector3.new(6,3,6), duration = 0.3, mode = "linear", speed = 1 },
	  })

	  hitDetect = function(elapsed, handle, params)
	      -- 완전 커스텀
	      return AbilityEffectHitDetectionUtil.Box({ size = Vector3.new(elapsed * 2, 3, elapsed * 2) })
	  end

	HitDetectFunction:
	  고정값: BoxConfig
	  동적:   (elapsed, handle, params) -> BoxConfig?   nil이면 이번 프레임 판정 스킵

	반환 HitInfo 배열:
	  { target: Model, relation: HitRelation, position: Vector3 }
]=]

local AbilityEffectHitDetectionUtil = {}

-- ─── 타입 ────────────────────────────────────────────────────────────────────

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
}

export type HitDetectFunction =
	BoxConfig
	| (elapsed: number, handle: any, params: { [string]: any }?) -> BoxConfig?

-- ─── 내부 유틸 ───────────────────────────────────────────────────────────────

local function lerpVec3(a: Vector3, b: Vector3, t: number): Vector3
	return a:Lerp(b, t)
end

local function resolveSize(config: BoxConfig, elapsed: number): Vector3
	local grow = config.sizeGrow
	if not grow then return config.size end
	local t = math.clamp(elapsed / grow.duration, 0, 1)
	if grow.mode == "spring" then
		-- 단순 지수 근사
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
	elapsed, handle, params를 받아 현재 프레임의 판정을 실행합니다.
	hitDetect가 nil이면 빈 배열 반환.

	@param hitDetect   HitDetectFunction?
	@param elapsed     number
	@param handle      any
	@param params      { [string]: any }?
	@param attackerChar Model   충돌 제외 대상
	@param teamService  any?    팀 판별용
	@param attackerPlayer Player?
	@return { HitInfo }
]=]
function AbilityEffectHitDetectionUtil.Detect(
	hitDetect      : HitDetectFunction?,
	elapsed        : number,
	handle         : any,
	params         : { [string]: any }?,
	attackerChar   : Model?,
	teamService    : any?,
	attackerPlayer : any?
): { HitInfo }
	if not hitDetect then return {} end

	-- BoxConfig 해석
	local boxConfig: BoxConfig?
	if type(hitDetect) == "function" then
		boxConfig = (hitDetect :: any)(elapsed, handle, params)
	else
		boxConfig = hitDetect :: BoxConfig
	end

	if not boxConfig then return {} end

	-- activateAt / deactivateAt 체크
	if boxConfig.activateAt and elapsed < boxConfig.activateAt then return {} end
	if boxConfig.deactivateAt and elapsed > boxConfig.deactivateAt then return {} end

	-- 현재 크기 계산
	local size = resolveSize(boxConfig, elapsed)

	-- 판정 기준 CFrame
	local baseCF = handle.part and handle.part:GetPivot() or CFrame.identity
	local detectCF = boxConfig.offset and (baseCF * boxConfig.offset) or baseCF

	-- OverlapParams: 자신 캐릭터 제외
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	if attackerChar then
		overlapParams.FilterDescendantsInstances = { attackerChar }
	end

	local parts = workspace:GetPartBoundsInBox(detectCF, size, overlapParams)

	-- 캐릭터 중복 제거 + HitInfo 생성
	local seen: { [Model]: boolean } = {}
	local results: { HitInfo } = {}

	for _, part in parts do
		local char = part:FindFirstAncestorOfClass("Model")
		if not char or seen[char] then continue end
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then continue end
		seen[char] = true

		local relation: HitRelation = "enemy"
		if char == attackerChar then
			relation = "self"
		elseif teamService and attackerPlayer then
			local victimPlayer = game:GetService("Players"):GetPlayerFromCharacter(char)
			if victimPlayer then
				if teamService:IsEnemy(attackerPlayer, victimPlayer) then
					relation = "enemy"
				else
					relation = "team"
				end
			end
		end

		table.insert(results, {
			target   = char,
			relation = relation,
			position = char:GetPivot().Position,
		})
	end

	return results
end

return AbilityEffectHitDetectionUtil
