--!strict
--[=[
	@class AbilityEffectHitDetectionUtil

	직육면체(Box) 기반 판정 유틸. Shared.
	Y축 고정 게임 기준, Box 하나로 Sphere/Cone/Capsule 모두 대체 가능.

	Box(config) → HitDetectFn

	HitDetectFn:
	  (elapsed: number, currentCFrame: CFrame, overlapParams: OverlapParams)
	  → { BasePart }?   -- nil이면 이번 프레임 판정 스킵

	직육면체 방향은 currentCFrame의 LookVector 기준 (조준 방향).
	offset은 모델 기준 상대 CFrame.
]=]

local AbilityEffectHitDetectionUtil = {}

-- ─── 타입 ─────────────────────────────────────────────────────────────────────

export type GrowConfig = {
	from: Vector3,
	to: Vector3,
	duration: number,
	mode: ("linear" | "spring")?,
	speed: number?,
}

export type BoxConfig = {
	size: Vector3 | GrowConfig,
	offset: CFrame?,
	activateAt: number?,
	deactivateAt: number?,
}

export type HitDetectFn =
	(elapsed: number, currentCFrame: CFrame, overlapParams: OverlapParams) -> { BasePart }?

-- ─── Box ──────────────────────────────────────────────────────────────────────

function AbilityEffectHitDetectionUtil.Box(config: BoxConfig): HitDetectFn
	return function(
		elapsed: number,
		currentCFrame: CFrame,
		overlapParams: OverlapParams
	): { BasePart }?
		-- 활성화 윈도우 체크
		if config.activateAt and elapsed < config.activateAt then
			return nil
		end
		if config.deactivateAt and elapsed > config.deactivateAt then
			return nil
		end

		-- 크기 계산
		local size: Vector3
		if typeof(config.size) == "Vector3" then
			size = config.size :: Vector3
		else
			local grow = config.size :: GrowConfig
			local t = math.clamp(elapsed / grow.duration, 0, 1)
			size = (grow.from):Lerp(grow.to, t)
		end

		-- 오프셋 적용 (모델 기준 상대 위치)
		local castCFrame = if config.offset
			then currentCFrame * config.offset
			else currentCFrame

		return workspace:GetPartBoundsInBox(castCFrame, size, overlapParams) :: { BasePart }
	end
end

return AbilityEffectHitDetectionUtil
