--!strict
--[=[
	@class PlayerStateAnimDef

	PlayerState 시스템의 캐릭터 애니메이션 정의.
	tag name → AnimDef 구현을 직접 포함합니다.

	EntityAnimator에 주입되며, PlayerStateClient가 직접 require합니다.

	resolve(tagName, intensity):
	  intensity 구간에 따라 사용할 animKey와 loop 여부를 반환.

	loop = true:
	  EntityAnimator:PlayAnimation(animKey, duration) 형태로 호출하면
	  duration 동안 반복 재생 후 자동 종료.

	intensity 전달 방식:
	  AnimFactory의 세 번째 인자 ac = { ac: AnimationControllerClient, intensity: number }
	  factory 내부에서 ac.intensity로 강도 스케일링.

	─── 애니메이션 목록 ─────────────────────────────────────────────
	  HitStagger   : 일반 피격 (intensity 무시)
	  HitKnockback : 강한 피격 (intensity 무시)
	  Knockback    : 넉백 반응 (intensity → 각도/속도)
	  Stun         : 스턴 루프 (intensity → 흔들림 속도/크기)
	  Airborne     : 에어본 루프 (intensity → 팔 벌어짐/흔들림)
	  Freeze       : 빙결 루프 (intensity → 고정 강도/떨림)
	  Exhausted    : 탈진 루프 (intensity → 숨 주기/크기)
]=]

local Layer = {
	BASE = 0,
	ACTION = 1,
	OVERRIDE = 2,
}

-- ─── 타입 ────────────────────────────────────────────────────────────────────

type AC = { ac: any, intensity: number }
type OnUpdate = (joint: Motor6D, dt: number) -> ()
type AnimFactory = (joint: Motor6D, defaultC0: CFrame, ac: AC) -> OnUpdate

type AnimDef =
	{ type: "anim", layer: number, duration: number, force: boolean?, joints: { [string]: AnimFactory } }
	| { type: "modify", joints: { [string]: (joint: Motor6D, defaultC0: CFrame, ac: AC) -> (CFrame, number) -> CFrame } }

-- ─── 내부 매핑 타입 ──────────────────────────────────────────────────────────

type AnimVariant = {
	threshold: number,
	animKey: string?,
	loop: boolean?,
	special: string?,
}

type AnimMapping = {
	variants: { AnimVariant },
}

export type ResolvedAnim = {
	animKey: string?,
	loop: boolean?,
	special: string?,
}

-- ─── AnimDef 구현 ─────────────────────────────────────────────────────────────

local Anims: { [string]: AnimDef } = {}

-- ============================================================
-- HitStagger: 일반 피격
-- ============================================================
Anims["HitStagger"] = {
	type = "anim",
	layer = Layer.ACTION,
	duration = 0.3,
	force = true,
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
Anims["HitKnockback"] = {
	type = "anim",
	layer = Layer.ACTION,
	duration = 0.4,
	force = true,
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
-- Knockback: 넉백 반응 (intensity → 각도/속도)
-- ============================================================
Anims["Knockback"] = {
	type = "anim",
	layer = Layer.ACTION,
	duration = 0.5,
	force = true,
	joints = {
		Waist = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local maxAngle = math.rad(10 + ac.intensity * 25)
			local speed = 15 + ac.intensity * 10
			return function(joint: Motor6D, dt: number)
				t += dt
				local p = math.min(t / 0.5, 1)
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(math.sin(p * math.pi) * -maxAngle, 0, 0), speed, 1.0, dt)
			end
		end,
		Neck = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local maxAngle = math.rad(8 + ac.intensity * 18)
			local speed = 14 + ac.intensity * 8
			return function(joint: Motor6D, dt: number)
				t += dt
				local p = math.min(t / 0.5, 1)
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(math.sin(p * math.pi) * -maxAngle, 0, 0), speed, 1.0, dt)
			end
		end,
		RightShoulder = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local maxAngle = math.rad(15 + ac.intensity * 25)
			return function(joint: Motor6D, dt: number)
				t += dt
				local p = math.min(t / 0.5, 1)
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(0, 0, math.sin(p * math.pi) * maxAngle), 16, 1.0, dt)
			end
		end,
		LeftShoulder = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local maxAngle = math.rad(15 + ac.intensity * 25)
			return function(joint: Motor6D, dt: number)
				t += dt
				local p = math.min(t / 0.5, 1)
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(0, 0, math.sin(p * math.pi) * -maxAngle), 16, 1.0, dt)
			end
		end,
	},
}

-- ============================================================
-- Stun: 스턴 루프 (intensity → 흔들림 속도/크기)
-- ============================================================
Anims["Stun"] = {
	type = "anim",
	layer = Layer.OVERRIDE,
	duration = math.huge,
	force = true,
	joints = {
		Waist = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local freq = 1.5 + ac.intensity * 1.5
			local amp = math.rad(3 + ac.intensity * 6)
			local droop = math.rad(8 + ac.intensity * 10)
			return function(joint: Motor6D, dt: number)
				t += dt
				local sway = math.sin(t * freq * math.pi * 2) * amp
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(droop, sway, 0), 8, 0.9, dt)
			end
		end,
		Neck = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local freq = 1.5 + ac.intensity * 1.5
			local amp = math.rad(5 + ac.intensity * 8)
			local droop = math.rad(12 + ac.intensity * 12)
			return function(joint: Motor6D, dt: number)
				t += dt
				local sway = math.sin(t * freq * math.pi * 2 + 0.5) * amp
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(droop, sway, 0), 6, 0.85, dt)
			end
		end,
	},
}

-- ============================================================
-- Airborne: 에어본 루프 (intensity → 팔 벌어짐/흔들림)
-- ============================================================
Anims["Airborne"] = {
	type = "anim",
	layer = Layer.OVERRIDE,
	duration = math.huge,
	force = true,
	joints = {
		Waist = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local targetAngle = math.rad(-(10 + ac.intensity * 20))
			return function(joint: Motor6D, dt: number)
				t += dt
				local wobble = math.sin(t * 4) * math.rad(2 + ac.intensity * 4)
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(targetAngle + wobble, 0, 0), 10, 0.9, dt)
			end
		end,
		RightShoulder = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local spread = math.rad(25 + ac.intensity * 35)
			return function(joint: Motor6D, dt: number)
				t += dt
				local wobble = math.sin(t * 3 + 0.3) * math.rad(3)
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(0, 0, spread + wobble), 8, 0.85, dt)
			end
		end,
		LeftShoulder = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local spread = math.rad(25 + ac.intensity * 35)
			return function(joint: Motor6D, dt: number)
				t += dt
				local wobble = math.sin(t * 3 - 0.3) * math.rad(3)
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(0, 0, -(spread + wobble)), 8, 0.85, dt)
			end
		end,
	},
}

-- ============================================================
-- Freeze: 빙결 루프 (intensity → 고정 강도/떨림)
-- ============================================================
Anims["Freeze"] = {
	type = "anim",
	layer = Layer.OVERRIDE,
	duration = math.huge,
	force = true,
	joints = {
		Waist = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local frozenAngle = math.rad(5 + ac.intensity * 10)
			return function(joint: Motor6D, dt: number)
				t += dt
				local tremble = math.sin(t * 18) * math.rad(0.3 + ac.intensity * 0.7)
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(frozenAngle + tremble, 0, 0), 30, 1.0, dt)
			end
		end,
		Neck = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local frozenAngle = math.rad(3 + ac.intensity * 7)
			return function(joint: Motor6D, dt: number)
				t += dt
				local tremble = math.sin(t * 20 + 0.5) * math.rad(0.2 + ac.intensity * 0.5)
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(frozenAngle + tremble, 0, 0), 28, 1.0, dt)
			end
		end,
	},
}

-- ============================================================
-- Exhausted: 탈진 루프 (intensity → 숨 주기/크기)
-- ============================================================
Anims["Exhausted"] = {
	type = "anim",
	layer = Layer.OVERRIDE,
	duration = math.huge,
	force = true,
	joints = {
		Waist = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local freq = 0.8 + ac.intensity * 0.8
			local droop = math.rad(12 + ac.intensity * 18)
			local amp = math.rad(4 + ac.intensity * 6)
			return function(joint: Motor6D, dt: number)
				t += dt
				local breath = math.sin(t * freq * math.pi * 2) * amp
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(droop + breath, 0, 0), 5, 0.8, dt)
			end
		end,
		Neck = function(_j: Motor6D, defaultC0: CFrame, ac: AC): OnUpdate
			local t = 0
			local freq = 0.8 + ac.intensity * 0.8
			local droop = math.rad(15 + ac.intensity * 20)
			local amp = math.rad(3 + ac.intensity * 5)
			return function(joint: Motor6D, dt: number)
				t += dt
				local breath = math.sin(t * freq * math.pi * 2 + 0.3) * amp
				ac.ac:spring(joint, defaultC0 * CFrame.Angles(droop + breath, 0, 0), 4, 0.75, dt)
			end
		end,
	},
}

-- ─── tag → animKey 매핑 ───────────────────────────────────────────────────────

local MAPPING: { [string]: AnimMapping } = {

	-- 0~0.5: 일반 피격, 0.5~1: 강한 피격
	["anim_hit"] = {
		variants = {
			{ threshold = 0.0, animKey = "HitStagger" },
			{ threshold = 0.5, animKey = "HitKnockback" },
		},
	},

	-- intensity → 스턴 루프 속도/크기
	["anim_stun"] = {
		variants = {
			{ threshold = 0.0, animKey = "Stun", loop = true },
		},
	},

	["anim_airborne"] = {
		variants = {
			{ threshold = 0.0, animKey = "Airborne", loop = true },
		},
	},

	["anim_ragdoll"] = {
		variants = {
			{ threshold = 0.0, special = "ragdoll" },
		},
	},

	["anim_freeze"] = {
		variants = {
			{ threshold = 0.0, animKey = "Freeze", loop = true },
		},
	},

	-- intensity → 넉백 각도/속도 스케일링
	["anim_knockback"] = {
		variants = {
			{ threshold = 0.0, animKey = "Knockback" },
		},
	},

	["anim_exhausted"] = {
		variants = {
			{ threshold = 0.0, animKey = "Exhausted", loop = true },
		},
	},
}

-- ─── 공개 API ─────────────────────────────────────────────────────────────────

local PlayerStateAnimDef = Anims

--[=[
	intensity에 따라 사용할 animKey/loop/special을 반환합니다.
]=]
function PlayerStateAnimDef.resolve(tagName: string, intensity: number): ResolvedAnim?
	local mapping = MAPPING[tagName]
	if not mapping then
		return nil
	end
	local chosen = mapping.variants[1]
	for _, variant in mapping.variants do
		if intensity >= variant.threshold then
			chosen = variant
		end
	end
	return {
		animKey = chosen.animKey,
		loop = chosen.loop,
		special = chosen.special,
	}
end

return PlayerStateAnimDef
