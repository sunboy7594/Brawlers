--!strict
--[=[
	@class Tank_JumpPunchAnimDef

	탱크 점프 펀치 절차적 애니메이션 정의.

	"JumpPunch": 양손 오버헤드 내려찍기
	"AimPose":   조준 중 긴장 자세
]=]

local Layer = {
	BASE     = 0,
	ACTION   = 1,
	OVERRIDE = 2,
}

type OnUpdate    = (joint: Motor6D, dt: number) -> ()
type AnimFactory = (joint: Motor6D, defaultC0: CFrame, ac: any) -> OnUpdate

type AnimDef =
	{ type: "anim",   layer: number, joints: { [string]: AnimFactory } }
	| { type: "modify", joints: { [string]: (joint: Motor6D, defaultC0: CFrame, ac: any) -> (CFrame, number) -> CFrame } }

local Tank_JumpPunchAnimDef: { [string]: AnimDef } = {}

-- ─── JumpPunch (양손 오버헤드 내려찍기) ──────────────────────────────────────

Tank_JumpPunchAnimDef["JumpPunch"] = {
	type  = "anim",
	layer = Layer.OVERRIDE,
	joints = {
		RightShoulder = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			return function(joint: Motor6D, dt: number)
				local target = defaultC0 * CFrame.Angles(math.rad(165), 0, math.rad(-25))
				ac:spring(joint, target, 22, 0.85, dt)
			end
		end,
		RightElbow = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			return function(joint: Motor6D, dt: number)
				local target = defaultC0 * CFrame.Angles(math.rad(-45), 0, 0)
				ac:spring(joint, target, 22, 0.85, dt)
			end
		end,
		LeftShoulder = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			return function(joint: Motor6D, dt: number)
				local target = defaultC0 * CFrame.Angles(math.rad(165), 0, math.rad(25))
				ac:spring(joint, target, 22, 0.85, dt)
			end
		end,
		LeftElbow = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			return function(joint: Motor6D, dt: number)
				local target = defaultC0 * CFrame.Angles(math.rad(-45), 0, 0)
				ac:spring(joint, target, 22, 0.85, dt)
			end
		end,
		Neck = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			return function(joint: Motor6D, dt: number)
				local target = defaultC0 * CFrame.Angles(math.rad(20), 0, 0)
				ac:spring(joint, target, 14, 0.75, dt)
			end
		end,
		UpperTorso = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			return function(joint: Motor6D, dt: number)
				local target = defaultC0 * CFrame.Angles(math.rad(15), 0, 0)
				ac:spring(joint, target, 12, 0.7, dt)
			end
		end,
	},
}

-- ─── AimPose ─────────────────────────────────────────────────────────────────

Tank_JumpPunchAnimDef["AimPose"] = {
	type = "modify",
	joints = {
		RightShoulder = function(_joint: Motor6D, defaultC0: CFrame, _ac: any)
			return function(cf: CFrame, _weight: number): CFrame
				return cf:Lerp(defaultC0 * CFrame.Angles(math.rad(30), 0, 0), 0.4)
			end
		end,
		LeftShoulder = function(_joint: Motor6D, defaultC0: CFrame, _ac: any)
			return function(cf: CFrame, _weight: number): CFrame
				return cf:Lerp(defaultC0 * CFrame.Angles(math.rad(30), 0, 0), 0.4)
			end
		end,
	},
}

return Tank_JumpPunchAnimDef
