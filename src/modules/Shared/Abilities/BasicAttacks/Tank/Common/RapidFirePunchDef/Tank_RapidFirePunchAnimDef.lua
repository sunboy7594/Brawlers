--!strict
--[=[
	@class Tank_RapidFirePunchAnimDef

	탱크 연속 펀치 공격 절차적 애니메이션 정의.

	hold fire 루프 중 Punch1 / Punch2 를 교대로 재생.
	Tank_PunchAnimDef보다 짧은 duration + 높은 springiness로
	빠른 연타감을 표현.

	애니메이션 키:
	  "Punch1" → 오른팔 짧게 앞으로
	  "Punch2" → 왼팔 짧게 앞으로
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

local Tank_RapidFirePunchAnimDef: { [string]: AnimDef } = {}

-- ─── Punch1 (오른팔) ────────────────────────────────────────────────────────

Tank_RapidFirePunchAnimDef["Punch1"] = {
	type = "anim",
	layer = Layer.OVERRIDE,
	joints = {
		RightShoulder = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			return function(joint: Motor6D, dt: number)
				-- 오른팔 빠르게 앞으로 뻗기 (spring stiffness 높게)
				local target = defaultC0 * CFrame.Angles(math.rad(85), 0, math.rad(-5))
				ac:spring(joint, target, 30, 0.8, dt)
			end
		end,
		RightElbow = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			return function(joint: Motor6D, dt: number)
				local target = defaultC0 * CFrame.Angles(math.rad(25), 0, 0)
				ac:spring(joint, target, 30, 0.8, dt)
			end
		end,
		-- 오른팔 연타 시 왼팔은 가드 자세
		LeftShoulder = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			return function(joint: Motor6D, dt: number)
				local target = defaultC0 * CFrame.Angles(math.rad(40), 0, math.rad(15))
				ac:spring(joint, target, 20, 1.0, dt)
			end
		end,
	},
}

-- ─── Punch2 (왼팔) ──────────────────────────────────────────────────────────

Tank_RapidFirePunchAnimDef["Punch2"] = {
	type = "anim",
	layer = Layer.OVERRIDE,
	joints = {
		LeftShoulder = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			return function(joint: Motor6D, dt: number)
				local target = defaultC0 * CFrame.Angles(math.rad(85), 0, math.rad(5))
				ac:spring(joint, target, 30, 0.8, dt)
			end
		end,
		LeftElbow = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			return function(joint: Motor6D, dt: number)
				local target = defaultC0 * CFrame.Angles(math.rad(25), 0, 0)
				ac:spring(joint, target, 30, 0.8, dt)
			end
		end,
		-- 왼팔 연타 시 오른팔은 가드 자세
		RightShoulder = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			return function(joint: Motor6D, dt: number)
				local target = defaultC0 * CFrame.Angles(math.rad(40), 0, math.rad(-15))
				ac:spring(joint, target, 20, 1.0, dt)
			end
		end,
	},
}

return Tank_RapidFirePunchAnimDef
