--!strict
--[=[
	@class HitReactionCameraAnimDef

	PlayerState 시스템이 사용하는 카메라 애니메이션 정의.
	CameraAnimator에 주입됩니다.

	애니메이션 목록:
	- HitShake      : 일반 피격 흔들림
	- HitRecoil     : 강한 피격 밀림
	- MotionSickness: 멀미 (느리고 출렁이는 흔들림)

	intensity 전달:
	  PlayerStateClient가 factory 호출 시 intensity를 upvalue로 주입.
	  factory는 (cc, intensity: number) -> (cf, dt) -> CFrame 형태.
]=]

type CameraController = any

type CameraAnimDef = {
	layer: "effect" | "offset" | "override",
	duration: number,
	force: boolean?,
	factory: (cc: CameraController, intensity: number) -> any,
}

local HitReactionCameraAnimDef: { [string]: CameraAnimDef } = {}

-- ============================================================
-- HitShake: 일반 피격 흔들림 (intensity → 흔들림 크기)
-- ============================================================
HitReactionCameraAnimDef["HitShake"] = {
	layer = "effect", duration = 0.3, force = true,
	factory = function(_cc, intensity: number)
		local t = 0
		local freq  = 22
		local decay = 8
		local amp   = 0.02 + intensity * 0.05  -- 0.02~0.07
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
-- HitRecoil: 강한 피격 밀림 (intensity → 밀림 크기)
-- ============================================================
HitReactionCameraAnimDef["HitRecoil"] = {
	layer = "effect", duration = 0.4, force = true,
	factory = function(_cc, intensity: number)
		local t = 0
		local decay = 6
		local amp   = 0.04 + intensity * 0.06  -- 0.04~0.10
		return function(cf: CFrame, dt: number): CFrame
			t += dt
			local strength = math.exp(-decay * t) * amp
			local pitch = -strength
			local roll  = math.sin(t * 15) * strength * 0.3
			return cf * CFrame.Angles(pitch, 0, roll)
		end
	end,
}

-- ============================================================
-- MotionSickness: 멀미 (intensity → 임의 회전 + 주기)
-- 느리고 출렁이는 주기적 흔들림
-- ============================================================
HitReactionCameraAnimDef["MotionSickness"] = {
	layer = "effect", duration = math.huge, force = false,
	factory = function(_cc, intensity: number)
		local t = 0
		local freq  = 0.4 + intensity * 0.4   -- 0.4~0.8Hz
		local amp   = 0.01 + intensity * 0.04 -- 0.01~0.05rad
		local phase = math.random() * math.pi * 2  -- 매번 다른 위상
		return function(cf: CFrame, dt: number): CFrame
			t += dt
			local rx = math.sin(t * freq * math.pi * 2 + phase)            * amp
			local ry = math.sin(t * freq * math.pi * 2 + phase + 1.1) * amp * 0.7
			local rz = math.sin(t * freq * math.pi * 2 + phase + 2.3) * amp * 0.4
			return cf * CFrame.Angles(rx, ry, rz)
		end
	end,
}

return HitReactionCameraAnimDef
