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
-- [effect] 걷기 카메라 보빙
-- 좌우로 약하게 흔들립니다.
-- ============================================================
BasicCameraAnimDef["WalkBob"] = {
	layer = "effect",
	factory = function(_cc)
		local t = 0
		local freq = 4.0 -- 진동 주파수 (걸음 속도 맞춤)
		local ampX = 0.008 -- 수평 흔들림
		local ampY = 0.006 -- 수직 흔들림

		return function(cf: CFrame, dt: number): CFrame
			t = (t + dt) % (math.pi * 2 / freq * 2)
			local roll = math.sin(t * freq) * ampX
			local pitch = math.abs(math.sin(t * freq)) * ampY - ampY * 0.5
			return cf * CFrame.Angles(pitch, 0, roll)
		end
	end,
}

-- ============================================================
-- [effect] 달리기 카메라 보빙
-- WalkBob보다 진폭이 크고 빠릅니다.
-- ============================================================
BasicCameraAnimDef["RunBob"] = {
	layer = "effect",
	factory = function(_cc)
		local t = 0
		local freq = 6.5
		local ampX = 0.018
		local ampY = 0.012

		return function(cf: CFrame, dt: number): CFrame
			t = (t + dt) % (math.pi * 2 / freq * 2)
			local roll = math.sin(t * freq) * ampX
			local pitch = math.abs(math.sin(t * freq)) * ampY - ampY * 0.5
			return cf * CFrame.Angles(pitch, 0, roll)
		end
	end,
}

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
-- [offset] 전투 시 카메라 약간 당기기
-- 전투 진입 시 오프셋으로 시야를 약간 올립니다.
-- ============================================================
BasicCameraAnimDef["CombatOffset"] = {
	layer = "offset",
	factory = function(_cc)
		return {
			offset = Vector3.new(0, 0.5, 0),
			fov = nil, -- FOV는 건드리지 않음
			stiffness = 5,
			damping = 0.75,
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

-- ============================================================
-- [effect] 스킬 시전 카메라 롤 (duration과 함께 사용)
-- Play("SkillRoll", 0.5) 형태로 사용합니다.
-- ============================================================
BasicCameraAnimDef["SkillRoll"] = {
	layer = "effect",
	factory = function(_cc)
		local t = 0
		local duration = 0.5

		return function(cf: CFrame, dt: number): CFrame
			t += dt
			local progress = math.min(t / duration, 1)
			-- 0→1→0 형태의 롤
			local roll = math.sin(progress * math.pi) * 0.07
			return cf * CFrame.Angles(0, 0, roll)
		end
	end,
}

-- ============================================================
-- [effect] 궁극기 슬로우모션 연출용 줌인 (override 아님 — 연속 effect)
-- Play("UltZoom", 1.5) 형태로 사용합니다.
-- ============================================================
BasicCameraAnimDef["UltZoom"] = {
	layer = "effect",
	factory = function(_cc)
		local t = 0
		return function(cf: CFrame, dt: number): CFrame
			t += dt
			-- 0.2초에 걸쳐 살짝 앞으로 이동
			local zoom = math.min(t / 0.2, 1) * 0.6
			return cf * CFrame.new(0, 0, -zoom)
		end
	end,
}

-- ============================================================
-- [override] 간단한 고정 컷신 예시
-- Play("CutsceneFixed") → 특정 CFrame에서 카메라 고정.
-- Stop() 하면 일반 카메라로 복귀.
-- ============================================================
BasicCameraAnimDef["CutsceneFixed"] = {
	layer = "override",
	factory = function(_cc)
		local targetCF = CFrame.new(0, 10, 20) * CFrame.Angles(math.rad(-15), 0, 0)

		return function(camera: Camera, _dt: number)
			camera.CFrame = targetCF
		end
	end,
}

return BasicCameraAnimDef
