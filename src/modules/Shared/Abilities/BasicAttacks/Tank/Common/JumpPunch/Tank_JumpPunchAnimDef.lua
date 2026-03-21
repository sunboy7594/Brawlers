--!strict
--[=[
	@class Tank_JumpPunchAnimDef

	탱크 점프 펀치 절차적 애니메이션 정의.

	"JumpPunch":
	  양손을 위로 모아 올린 후 내려찍는 오버헤드 슬램 모션.
	  RightShoulder / LeftShoulder → 위로 뻗어 모음
	  RightElbow    / LeftElbow    → 약간 굽혀 파워 자세
	  HumanoidRootPart Neck        → 아래를 향해 집중

	"AimPose":
	  조준 중 양손을 앞으로 내민 긴장 자세. (modify 레이어)
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

local Tank_JumpPunchAnimDef: { [string]: AnimDef } = {}

-- ─── JumpPunch (양손 오버헤드 내려찍기) ──────────────────────────────────────

Tank_JumpPunchAnimDef["JumpPunch"] = {
	type = "anim",
	layer = Layer.OVERRIDE,
	joints = {
		-- 오른팔: 위로 뻗어 올리기
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

		-- 왼팔: 오른팔과 대칭으로 위로 모음
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

		-- 목: 아래를 향해 집중
		Neck = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			return function(joint: Motor6D, dt: number)
				local target = defaultC0 * CFrame.Angles(math.rad(20), 0, 0)
				ac:spring(joint, target, 14, 0.75, dt)
			end
		end,

		-- 상체: 앞으로 약간 기울어 내려찍는 자세
		UpperTorso = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			return function(joint: Motor6D, dt: number)
				local target = defaultC0 * CFrame.Angles(math.rad(15), 0, 0)
				ac:spring(joint, target, 12, 0.7, dt)
			end
		end,
	},
}

-- ─── AimPose (조준 중 긴장 자세) ─────────────────────────────────────────────

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
