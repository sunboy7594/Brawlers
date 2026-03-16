--!strict
--[=[
	@class HitReactionAnimDef

	PlayerState 시스템이 사용하는 캐릭터 몸 애니메이션 정의.
	EntityAnimator에 주입됩니다.

	애니메이션 목록:
	- HitStagger  : 일반 피격 (intensity 무시)
	- HitKnockback: 강한 피격 (intensity 무시)
	- Knockback   : 넘백 (intensity → 각도/속도)
	- Stun        : 스턴 루프 (intensity → 루프 속도)
	- Airborne    : 에어본 루프 (intensity → 루프 속도)
	- Freeze      : 빙결 루프 (intensity → 고정 강도)
	- Exhausted   : 탈진 루프 (intensity → 루프 속도)

	loop 애니메이션 사용 방식:
	  EntityAnimator:PlayAnimation("Stun", duration) 형태로 호출.
	  duration이 만료되면 자동 종료.

	intensity 전달 방식:
	  AnimFactory는 ac(AnimationControllerClient)를 인자로 받음.
	  ac는 PlayerStateClient에서 intensity를 upvalue로 주입하여
	  factory 호출 시 전달합니다:
	    factory(joint, defaultC0, { ac = animController, intensity = tag.intensity })
]=]

local Layer = {
	BASE     = 0,
	ACTION   = 1,
	OVERRIDE = 2,
}

type OnUpdate = (joint: Motor6D, dt: number) -> ()
type AC = { ac: any, intensity: number }
type AnimFactory = (joint: Motor6D, defaultC0: CFrame, ac: AC) -> OnUpdate

type AnimDef =
	{ type: "anim", layer: number, duration: number, force: boolean?, joints: { [string]: AnimFactory } }
	| { type: "modify", joints: { [string]: (joint: Motor6D, defaultC0: CFrame, ac: AC) -> (CFrame, number) -> CFrame } }

local HitReactionAnimDef: { [string]: AnimDef } = {}

-- ============================================================
-- HitStagger: 일반 피격
-- ============================================================
HitReactionAnimDef["HitStagger"] = {
	type = "anim", layer = Layer.ACTION, duration = 0.3, force = true,
	joints = {
		Waist = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			return function(joint: Motor6D, dt: number)
				t += dt
				local p = math.min(t / 0.25, 1)
				local angle = math.sin(p * math.pi) * math.rad(-12)
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(angle, 0, 0), 25, 1.0, dt)
			end
		end,
		Neck = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			return function(joint: Motor6D, dt: number)
				t += dt
				local p = math.min(t / 0.25, 1)
				local angle = math.sin(p * math.pi) * math.rad(-8)
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(angle, 0, 0), 20, 1.0, dt)
			end
		end,
	},
}

-- ============================================================
-- HitKnockback: 강한 피격
-- ============================================================
HitReactionAnimDef["HitKnockback"] = {
	type = "anim", layer = Layer.ACTION, duration = 0.4, force = true,
	joints = {
		Waist = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			return function(joint: Motor6D, dt: number)
				t += dt
				local p = math.min(t / 0.4, 1)
				local angle = math.sin(p * math.pi) * math.rad(-22)
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(angle, 0, 0), 20, 1.0, dt)
			end
		end,
		Neck = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			return function(joint: Motor6D, dt: number)
				t += dt
				local p = math.min(t / 0.4, 1)
				local angle = math.sin(p * math.pi) * math.rad(-15)
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(angle, 0, 0), 18, 1.0, dt)
			end
		end,
		RightShoulder = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			return function(joint: Motor6D, dt: number)
				t += dt
				local p = math.min(t / 0.4, 1)
				local angle = math.sin(p * math.pi) * math.rad(30)
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(0, 0, angle), 18, 1.0, dt)
			end
		end,
		LeftShoulder = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			return function(joint: Motor6D, dt: number)
				t += dt
				local p = math.min(t / 0.4, 1)
				local angle = math.sin(p * math.pi) * math.rad(-30)
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(0, 0, angle), 18, 1.0, dt)
			end
		end,
	},
}

-- ============================================================
-- Knockback: 넘백 반응 (intensity → 각도/속도)
-- ============================================================
HitReactionAnimDef["Knockback"] = {
	type = "anim", layer = Layer.ACTION, duration = 0.5, force = true,
	joints = {
		Waist = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local intensity = ac.intensity
			local maxAngle = math.rad(10 + intensity * 25)  -- 10~35도
			local speed = 15 + intensity * 10               -- 15~25
			return function(joint: Motor6D, dt: number)
				t += dt
				local p = math.min(t / 0.5, 1)
				local angle = math.sin(p * math.pi) * -maxAngle
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(angle, 0, 0), speed, 1.0, dt)
			end
		end,
		Neck = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local intensity = ac.intensity
			local maxAngle = math.rad(8 + intensity * 18)   -- 8~26도
			local speed = 14 + intensity * 8
			return function(joint: Motor6D, dt: number)
				t += dt
				local p = math.min(t / 0.5, 1)
				local angle = math.sin(p * math.pi) * -maxAngle
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(angle, 0, 0), speed, 1.0, dt)
			end
		end,
		RightShoulder = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local intensity = ac.intensity
			local maxAngle = math.rad(15 + intensity * 25)  -- 15~40도
			return function(joint: Motor6D, dt: number)
				t += dt
				local p = math.min(t / 0.5, 1)
				local angle = math.sin(p * math.pi) * maxAngle
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(0, 0, angle), 16, 1.0, dt)
			end
		end,
		LeftShoulder = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local intensity = ac.intensity
			local maxAngle = math.rad(15 + intensity * 25)
			return function(joint: Motor6D, dt: number)
				t += dt
				local p = math.min(t / 0.5, 1)
				local angle = math.sin(p * math.pi) * -maxAngle
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(0, 0, angle), 16, 1.0, dt)
			end
		end,
	},
}

-- ============================================================
-- Stun: 스턴 루프 (intensity → 루프 속도)
-- 머리가 흤델리며 상체가 굳어짐
-- ============================================================
HitReactionAnimDef["Stun"] = {
	type = "anim", layer = Layer.OVERRIDE, duration = math.huge, force = true,
	joints = {
		Waist = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local intensity = ac.intensity
			local freq = 1.5 + intensity * 1.5  -- 1.5~3Hz
			local amp = math.rad(3 + intensity * 6)  -- 3~9도
			return function(joint: Motor6D, dt: number)
				t += dt
				local sway = math.sin(t * freq * math.pi * 2) * amp
				local droop = math.rad(8 + intensity * 10)  -- 앞으로 굳어짐
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(droop, sway, 0), 8, 0.9, dt)
			end
		end,
		Neck = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local intensity = ac.intensity
			local freq = 1.5 + intensity * 1.5
			local amp = math.rad(5 + intensity * 8)
			return function(joint: Motor6D, dt: number)
				t += dt
				local sway = math.sin(t * freq * math.pi * 2 + 0.5) * amp
				local droop = math.rad(12 + intensity * 12)
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(droop, sway, 0), 6, 0.85, dt)
			end
		end,
	},
}

-- ============================================================
-- Airborne: 에어본 루프 (intensity → 효과)
-- 뫸엞리며 팔이 벌어짐
-- ============================================================
HitReactionAnimDef["Airborne"] = {
	type = "anim", layer = Layer.OVERRIDE, duration = math.huge, force = true,
	joints = {
		Waist = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local intensity = ac.intensity
			local targetAngle = math.rad(-(10 + intensity * 20))  -- 앞으로 굳어짐
			return function(joint: Motor6D, dt: number)
				t += dt
				local wobble = math.sin(t * 4) * math.rad(2 + intensity * 4)
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(targetAngle + wobble, 0, 0), 10, 0.9, dt)
			end
		end,
		RightShoulder = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local intensity = ac.intensity
			local spread = math.rad(25 + intensity * 35)
			return function(joint: Motor6D, dt: number)
				t += dt
				local wobble = math.sin(t * 3 + 0.3) * math.rad(3)
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(0, 0, spread + wobble), 8, 0.85, dt)
			end
		end,
		LeftShoulder = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local intensity = ac.intensity
			local spread = math.rad(25 + intensity * 35)
			return function(joint: Motor6D, dt: number)
				t += dt
				local wobble = math.sin(t * 3 - 0.3) * math.rad(3)
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(0, 0, -(spread + wobble)), 8, 0.85, dt)
			end
		end,
	},
}

-- ============================================================
-- Freeze: 빙결 루프 (intensity → 고정 강도)
-- 전체적으로 굳어지고 미세하게 떨림
-- ============================================================
HitReactionAnimDef["Freeze"] = {
	type = "anim", layer = Layer.OVERRIDE, duration = math.huge, force = true,
	joints = {
		Waist = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local intensity = ac.intensity
			local frozenAngle = math.rad(5 + intensity * 10)
			return function(joint: Motor6D, dt: number)
				t += dt
				-- 매우 작은 떨림으로 빙결 품표현
				local tremble = math.sin(t * 18) * math.rad(0.3 + intensity * 0.7)
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(frozenAngle + tremble, 0, 0), 30, 1.0, dt)
			end
		end,
		Neck = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local intensity = ac.intensity
			local frozenAngle = math.rad(3 + intensity * 7)
			return function(joint: Motor6D, dt: number)
				t += dt
				local tremble = math.sin(t * 20 + 0.5) * math.rad(0.2 + intensity * 0.5)
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(frozenAngle + tremble, 0, 0), 28, 1.0, dt)
			end
		end,
	},
}

-- ============================================================
-- Exhausted: 탈진 루프 (intensity → 휘음/속도)
-- 숫을 헥헥 도르며 말이 굳어짐
-- ============================================================
HitReactionAnimDef["Exhausted"] = {
	type = "anim", layer = Layer.OVERRIDE, duration = math.huge, force = true,
	joints = {
		Waist = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local intensity = ac.intensity
			local freq = 0.8 + intensity * 0.8    -- 0.8~1.6Hz (숨 주기)
			local droop = math.rad(12 + intensity * 18)  -- 기본 굳어짐
			local amp = math.rad(4 + intensity * 6)      -- 휘음 효과
			return function(joint: Motor6D, dt: number)
				t += dt
				local breath = math.sin(t * freq * math.pi * 2) * amp
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(droop + breath, 0, 0), 5, 0.8, dt)
			end
		end,
		Neck = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local intensity = ac.intensity
			local freq = 0.8 + intensity * 0.8
			local droop = math.rad(15 + intensity * 20)
			local amp = math.rad(3 + intensity * 5)
			return function(joint: Motor6D, dt: number)
				t += dt
				local breath = math.sin(t * freq * math.pi * 2 + 0.3) * amp
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(droop + breath, 0, 0), 4, 0.75, dt)
			end
		end,
	},
}

return HitReactionAnimDef
