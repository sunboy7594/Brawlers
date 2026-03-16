--!strict
--[=[
	@class BasicCameraAnimDef

	CameraAnimator에 주입하는 카메라 애니메이션 정의 모음.

	레이어 구분:
	  "effect"   → CFrame 후처리. 흔들림·롤·줌 등 매 프레임 연산.
	  "offset"   → 위치/FOV 오프셋. Controller 내부 spring이 보간.
	  "override" → 카메라 완전 점령. 컷신·스킬 연출 등.

	추가 방법:
	  BasicCameraAnimDef["MyAnim"] = {
	      layer = "effect",
	      factory = function(cc)
	          local t = 0
	          return function(cf, dt)
	              t += dt
	              return cf * CFrame.Angles(math.sin(t * 10) * 0.01, 0, 0)
	          end
	      end,
	  }
]=]

-- ─── 타입 (로컬 참조용) ──────────────────────────────────────────────────────

type CameraController = any -- CameraControllerClient

type CameraAnimDef = {
	layer: "effect" | "offset" | "override",
	factory: (cc: CameraController) -> any,
}

-- ─── 정의 테이블 ──────────────────────────────────────────────────────────────

local BasicCameraAnimDef: { [string]: CameraAnimDef } = {}

-- ============================================================
-- [offset] 달리기 FOV 확장
-- 달릴 때 FOV를 75로 늘려 속도감을 줍니다.
-- ============================================================
BasicCameraAnimDef["RunFOV"] = {
	layer = "offset",
	factory = function(_cc)
		return {
			offset = Vector3.new(0, 0, 0),
			fov = 75,
			stiffness = 200,
			damping = 10,
		}
	end,
}

-- ============================================================
-- [offset] 에임(ShiftLock) FOV 축소
-- 에임 시 FOV를 60으로 줄여 집중감을 줍니다.
-- ============================================================
BasicCameraAnimDef["AimFOV"] = {
	layer = "offset",
	factory = function(_cc)
		return {
			offset = Vector3.new(0, 0, 0),
			fov = 60,
			stiffness = 200,
			damping = 10,
		}
	end,
}

-- ============================================================
-- [effect] 피격 카메라 흔들림 (duration과 함께 사용)
-- Play("HitShake", 0.35) 형태로 사용합니다.
-- ============================================================
BasicCameraAnimDef["HitShake"] = {
	layer = "effect",
	factory = function(_cc)
		local t = 0
		local freq = 22
		local decay = 8 -- 진폭이 exp 감쇠
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

return BasicCameraAnimDef
