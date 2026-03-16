--!strict
--[=[
	@class HitReactionCameraAnimDef

	피격 시 카메라 애니메이션 정의.
	HitReactionClient의 CameraAnimator에 주입됩니다.

	애니메이션 목록:
	- HitShake  : 전방향 흔들림 (일반 피격)
	- HitRecoil : 맞은 방향 반대로 밀리는 느낌 (강한 피격)
]=]

type CameraController = any

type CameraAnimDef = {
	layer: "effect" | "offset" | "override",
	duration: number,
	force: boolean?,
	factory: (cc: CameraController) -> any,
}

local HitReactionCameraAnimDef: { [string]: CameraAnimDef } = {}

-- ============================================================
-- [effect] 일반 피격 흔들림
-- HitReactionClient:Play("HitShake", 0.3) 형태로 사용
-- ============================================================
HitReactionCameraAnimDef["HitShake"] = {
	layer = "effect",
	duration = 0.3,
	force = true,
	factory = function(_cc)
		local t = 0
		local freq = 22
		local decay = 8
		local amp = 0.04

		return function(cf: CFrame, dt: number): CFrame
			t += dt
			local strength = math.exp(-decay * t) * amp
			local rx = math.sin(t * freq * 1.3) * strength
			local ry = math.cos(t * freq * 0.9) * strength * 0.5
			return cf * CFrame.Angles(rx, ry, 0)
		end
	end,
}

-- ============================================================
-- [effect] 강한 피격 밀림 (넉백 피격 등에 사용)
-- HitReactionClient:Play("HitRecoil", 0.4) 형태로 사용
-- ============================================================
HitReactionCameraAnimDef["HitRecoil"] = {
	layer = "effect",
	duration = 0.4,
	force = true,
	factory = function(_cc)
		local t = 0
		local decay = 6
		local amp = 0.07

		return function(cf: CFrame, dt: number): CFrame
			t += dt
			local strength = math.exp(-decay * t) * amp
			-- 뒤로 살짝 젖혀지는 느낌
			local pitch = -strength
			local roll = math.sin(t * 15) * strength * 0.3
			return cf * CFrame.Angles(pitch, 0, roll)
		end
	end,
}

return HitReactionCameraAnimDef
