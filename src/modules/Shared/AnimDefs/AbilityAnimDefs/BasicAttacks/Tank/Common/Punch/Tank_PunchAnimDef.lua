--!strict
--[=[
	@class Tank_PunchAnimDef

	탱크 주먹 공격 절차적 애니메이션 정의.
	BasicAttackClient가 SetEquippedAttack 시 이 AnimDef로 EntityAnimator를 생성.

	AnimDef.type:
	  "anim"   → layer 기반 재생
	  "modify" → modifier 등록

	애니메이션 이름:
	  "Punch1", "Punch2", "Punch3" → 콤보 순서별 모션
	  "AimPose"                    → 조준 중 자세 (modify)
]=]

local Layer = {
	BASE = 0,
	ACTION = 1,
	OVERRIDE = 2,
}

type OnUpdate = (joint: Motor6D, dt: number) -> ()
type AnimFactory = (joint: Motor6D, defaultC0: CFrame, ac: any) -> OnUpdate

type AnimDef =
	{ type: "anim", layer: number, joints: { [string]: AnimFactory } }
	| { type: "modify", joints: { [string]: (joint: Motor6D, defaultC0: CFrame, ac: any) -> (CFrame, number) -> CFrame } }

local Tank_PunchAnimDef: { [string]: AnimDef } = {}

-- ─── Punch1 ──────────────────────────────────────────────────────────────────

Tank_PunchAnimDef["Punch1"] = {
	type = "anim",
	layer = Layer.OVERRIDE,
	joints = {
		RightShoulder = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			return function(joint: Motor6D, dt: number)
				-- 오른팔 앞으로 뻗기 (간단한 예시)
				local target = defaultC0 * CFrame.Angles(math.rad(-80), 0, 0)
				ac:spring(joint, target, 20, 1.0, dt)
			end
		end,
		RightElbow = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			return function(joint: Motor6D, dt: number)
				local target = defaultC0 * CFrame.Angles(math.rad(-30), 0, 0)
				ac:spring(joint, target, 20, 1.0, dt)
			end
		end,
	},
}

-- ─── Punch2 ──────────────────────────────────────────────────────────────────

Tank_PunchAnimDef["Punch2"] = {
	type = "anim",
	layer = Layer.OVERRIDE,
	joints = {
		LeftShoulder = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			return function(joint: Motor6D, dt: number)
				local target = defaultC0 * CFrame.Angles(math.rad(-80), 0, 0)
				ac:spring(joint, target, 20, 1.0, dt)
			end
		end,
		LeftElbow = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			return function(joint: Motor6D, dt: number)
				local target = defaultC0 * CFrame.Angles(math.rad(-30), 0, 0)
				ac:spring(joint, target, 20, 1.0, dt)
			end
		end,
	},
}

-- ─── Punch3 (양손) ───────────────────────────────────────────────────────────

Tank_PunchAnimDef["Punch3"] = {
	type = "anim",
	layer = Layer.OVERRIDE,
	joints = {
		RightShoulder = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			return function(joint: Motor6D, dt: number)
				local target = defaultC0 * CFrame.Angles(math.rad(-90), 0, math.rad(-10))
				ac:spring(joint, target, 25, 1.0, dt)
			end
		end,
		LeftShoulder = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			return function(joint: Motor6D, dt: number)
				local target = defaultC0 * CFrame.Angles(math.rad(-90), 0, math.rad(10))
				ac:spring(joint, target, 25, 1.0, dt)
			end
		end,
		Waist = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			return function(joint: Motor6D, dt: number)
				local target = defaultC0 * CFrame.Angles(math.rad(-10), 0, 0)
				ac:spring(joint, target, 15, 1.0, dt)
			end
		end,
	},
}

-- ─── AimPose (modifier) ──────────────────────────────────────────────────────

Tank_PunchAnimDef["AimPose"] = {
	type = "modify",
	joints = {
		Waist = function(_joint: Motor6D, defaultC0: CFrame, _ac: any)
			return function(current: CFrame, _dt: number): CFrame
				return current * CFrame.Angles(math.rad(-5), 0, 0)
			end
		end,
	},
}

return Tank_PunchAnimDef
