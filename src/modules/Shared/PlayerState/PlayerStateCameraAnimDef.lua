--!strict
--[=[
	@class PlayerStateCameraAnimDef

	PlayerState 시스템의 카메라 애니메이션 정의.
	tag name → CameraAnimDef 구현을 직접 포함합니다.

	CameraAnimator에 주입되며, PlayerStateClient가 직접 require합니다.

	intensity 전달 방식:
	  factory = function(cc, intensity: number) → (cf, dt) → CFrame
	  PlayerStateClient가 tag.intensity를 factory 호출 시 전달.

	─── 애니메이션 목록 ─────────────────────────────────────────────
	  HitShake      : 일반 피격 흔들림 (intensity → 흔들림 크기)
	  HitRecoil     : 강한 피격 밀림 (intensity → 밀림 크기)
	  MotionSickness: 멀미 (intensity → 주기/크기)
]=]

-- ─── 타입 ────────────────────────────────────────────────────────────────────

type CameraController = any

type CameraAnimDef = {
	layer: "effect" | "offset" | "override",
	duration: number,
	force: boolean?,
	-- intensity를 함께 받는 factory 시그니처
	factory: (cc: CameraController, intensity: number) -> (CFrame, number) -> CFrame,
}

-- ─── 내부 매핑 타입 ──────────────────────────────────────────────────────────

type CameraMapping = {
	animKey: string, -- CameraAnimDef 키
	knockbackRef: boolean?, -- knockback component direction 참조 여부
}

-- ─── CameraAnimDef 구현 ───────────────────────────────────────────────────────

local Anims: { [string]: CameraAnimDef } = {}

-- ============================================================
-- HitShake: 일반 피격 흔들림 (intensity → 흔들림 크기)
-- ============================================================
Anims["HitShake"] = {
	layer = "effect",
	duration = 0.3,
	force = true,
	factory = function(_cc, intensity: number)
		local t = 0
		local freq = 22
		local decay = 8
		local amp = 0.02 + intensity * 0.05 -- 0.02~0.07
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
Anims["HitRecoil"] = {
	layer = "effect",
	duration = 0.4,
	force = true,
	factory = function(_cc, intensity: number)
		local t = 0
		local decay = 6
		local amp = 0.04 + intensity * 0.06 -- 0.04~0.10
		return function(cf: CFrame, dt: number): CFrame
			t += dt
			local strength = math.exp(-decay * t) * amp
			local pitch = -strength
			local roll = math.sin(t * 15) * strength * 0.3
			return cf * CFrame.Angles(pitch, 0, roll)
		end
	end,
}

-- ============================================================
-- MotionSickness: 멀미 (intensity → 주기/크기)
-- ============================================================
Anims["MotionSickness"] = {
	layer = "effect",
	duration = math.huge,
	force = false,
	factory = function(_cc, intensity: number)
		local t = 0
		local freq = 0.4 + intensity * 0.4
		local amp = 0.01 + intensity * 0.04
		local phase = math.random() * math.pi * 2
		return function(cf: CFrame, dt: number): CFrame
			t += dt
			local rx = math.sin(t * freq * math.pi * 2 + phase) * amp
			local ry = math.sin(t * freq * math.pi * 2 + phase + 1.1) * amp * 0.7
			local rz = math.sin(t * freq * math.pi * 2 + phase + 2.3) * amp * 0.4
			return cf * CFrame.Angles(rx, ry, rz)
		end
	end,
}

-- ─── tag → CameraAnimDef 매핑 ────────────────────────────────────────────────

local MAPPING: { [string]: CameraMapping } = {
	["cam_shake"] = { animKey = "HitShake" },
	["cam_recoil"] = { animKey = "HitRecoil" },
	["cam_knockback"] = { animKey = "HitRecoil", knockbackRef = true },
	["cam_motion_sickness"] = { animKey = "MotionSickness" },
}

-- ─── 공개 API ─────────────────────────────────────────────────────────────────

local PlayerStateCameraAnimDef = Anims

export type ResolvedCameraAnim = {
	animKey: string,
	knockbackRef: boolean?,
}

--[=[
	tag name에 대응하는 animKey와 knockbackRef를 반환합니다.
]=]
function PlayerStateCameraAnimDef.resolve(tagName: string): ResolvedCameraAnim?
	local mapping = MAPPING[tagName]
	if not mapping then
		return nil
	end
	return {
		animKey = mapping.animKey,
		knockbackRef = mapping.knockbackRef,
	}
end

return PlayerStateCameraAnimDef
