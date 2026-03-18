--!strict
--[=[
	@class BasicMovementAnimDef
]=]

local Layer = {
	BASE = 0,
	ACTION = 1,
	OVERRIDE = 2,
}

local TWO_PI = math.pi * 2

local BasicMovementAnimDef = {}

type OnUpdate = (joint: Motor6D, dt: number) -> ()
type OnModify = (current: CFrame, dt: number) -> CFrame

type AnimFactory = (joint: Motor6D, defaultC0: CFrame, animController: any) -> OnUpdate
type ModifyFactory = (joint: Motor6D, defaultC0: CFrame, animController: any) -> OnModify

type AnimDef =
	{
		type: "anim",
		layer: number,
		joints: { [string]: AnimFactory },
	}
	| {
		type: "modify",
		joints: { [string]: ModifyFactory },
	}

export type CycleRef = { base: number, value: number }

-- ─── Idle ────────────────────────────────────────────────────────────────────

-- [변경] 포즈 상수를 모듈 레벨로 호이스팅
local IDLE_ROOT_POSE = CFrame.new(0.0000, -0.1027, 0.0090) * CFrame.Angles(-0.0000, 0.0000, -0.0000)
local IDLE_WAIST_POSE = CFrame.new(-0.0360, 0.0122, 0.1342) * CFrame.Angles(-0.1806, -0.2577, -0.0465)
local IDLE_NECK_POSE = CFrame.new(-0.0405, 0.0159, -0.0095) * CFrame.Angles(0.0842, 0.2608, 0.0233)
local IDLE_LEFT_SHOULDER_POSE = CFrame.new(0.0142, -0.0648, -0.1630) * CFrame.Angles(-0.2159, -0.2732, -0.3542)
local IDLE_RIGHT_SHOULDER_POSE = CFrame.new(0.0425, -0.0234, 0.0362) * CFrame.Angles(-0.1723, 0.3210, 0.3493)
local IDLE_LEFT_ELBOW_POSE = CFrame.new(0.0000, -0.0731, 0.0999) * CFrame.Angles(0.8727, -0.0000, 0.0000)
local IDLE_RIGHT_ELBOW_POSE = CFrame.new(0.0000, -0.0068, -0.0134) * CFrame.Angles(0.5236, -0.0000, 0.0000)
local IDLE_LEFT_WRIST_POSE = CFrame.new(-0.0000, -0.0000, 0.0000) * CFrame.Angles(-0.0000, -0.0000, 0.0000)
local IDLE_RIGHT_WRIST_POSE = CFrame.new(-0.0000, -0.0000, -0.0000) * CFrame.Angles(-0.0000, -0.0000, 0.0000)
local IDLE_LEFT_HIP_POSE = CFrame.new(-0.1311, -0.0026, -0.1711) * CFrame.Angles(0.2492, -0.1980, -0.0698)
local IDLE_RIGHT_HIP_POSE = CFrame.new(0.1182, 0.0141, 0.0425) * CFrame.Angles(0.0157, -0.2611, 0.0900)
local IDLE_LEFT_KNEE_POSE = CFrame.new(-0.0000, 0.0161, -0.0195) * CFrame.Angles(-0.5236, 0.0000, 0.0000)
local IDLE_RIGHT_KNEE_POSE = CFrame.new(-0.0000, 0.0469, 0.0661) * CFrame.Angles(-0.3491, -0.0000, 0.0000)
local IDLE_LEFT_ANKLE_POSE = CFrame.new(-0.0087, 0.1051, -0.2099) * CFrame.Angles(0.2776, 0.0005, 0.1163)
local IDLE_RIGHT_ANKLE_POSE = CFrame.new(0.0123, 0.0781, -0.1783) * CFrame.Angles(0.3414, 0.0876, -0.0863)

-- [추가] 외부에서 참조할 수 있도록 export
BasicMovementAnimDef.IdleJoints = {
	Root = function(_j, defaultC0, ac): OnUpdate
		return function(j, dt)
			ac:spring(j, defaultC0 * IDLE_ROOT_POSE, 10, 0.3, dt)
		end
	end,
	Waist = function(_j, defaultC0, ac): OnUpdate
		return function(j, dt)
			ac:spring(j, defaultC0 * IDLE_WAIST_POSE, 10, 0.3, dt)
		end
	end,
	Neck = function(_j, defaultC0, ac): OnUpdate
		return function(j, dt)
			ac:spring(j, defaultC0 * IDLE_NECK_POSE, 10, 0.3, dt)
		end
	end,
	LeftShoulder = function(_j, defaultC0, ac): OnUpdate
		return function(j, dt)
			ac:spring(j, defaultC0 * IDLE_LEFT_SHOULDER_POSE, 10, 0.3, dt)
		end
	end,
	RightShoulder = function(_j, defaultC0, ac): OnUpdate
		return function(j, dt)
			ac:spring(j, defaultC0 * IDLE_RIGHT_SHOULDER_POSE, 10, 0.3, dt)
		end
	end,
	LeftElbow = function(_j, defaultC0, ac): OnUpdate
		return function(j, dt)
			ac:spring(j, defaultC0 * IDLE_LEFT_ELBOW_POSE, 10, 0.3, dt)
		end
	end,
	RightElbow = function(_j, defaultC0, ac): OnUpdate
		return function(j, dt)
			ac:spring(j, defaultC0 * IDLE_RIGHT_ELBOW_POSE, 10, 0.3, dt)
		end
	end,
	LeftWrist = function(_j, defaultC0, ac): OnUpdate
		return function(j, dt)
			ac:spring(j, defaultC0 * IDLE_LEFT_WRIST_POSE, 10, 0.3, dt)
		end
	end,
	RightWrist = function(_j, defaultC0, ac): OnUpdate
		return function(j, dt)
			ac:spring(j, defaultC0 * IDLE_RIGHT_WRIST_POSE, 10, 0.3, dt)
		end
	end,
	LeftHip = function(_j, defaultC0, ac): OnUpdate
		return function(j, dt)
			ac:spring(j, defaultC0 * IDLE_LEFT_HIP_POSE, 10, 1, dt)
		end
	end,
	RightHip = function(_j, defaultC0, ac): OnUpdate
		return function(j, dt)
			ac:spring(j, defaultC0 * IDLE_RIGHT_HIP_POSE, 10, 1, dt)
		end
	end,
	LeftKnee = function(_j, defaultC0, ac): OnUpdate
		return function(j, dt)
			ac:spring(j, defaultC0 * IDLE_LEFT_KNEE_POSE, 10, 1, dt)
		end
	end,
	RightKnee = function(_j, defaultC0, ac): OnUpdate
		return function(j, dt)
			ac:spring(j, defaultC0 * IDLE_RIGHT_KNEE_POSE, 10, 1, dt)
		end
	end,
	LeftAnkle = function(_j, defaultC0, ac): OnUpdate
		return function(j, dt)
			ac:spring(j, defaultC0 * IDLE_LEFT_ANKLE_POSE, 10, 1, dt)
		end
	end,
	RightAnkle = function(_j, defaultC0, ac): OnUpdate
		return function(j, dt)
			ac:spring(j, defaultC0 * IDLE_RIGHT_ANKLE_POSE, 10, 1, dt)
		end
	end,
}

-- [변경] makeIdle은 IdleJoints를 그대로 재사용
local function makeIdle(_intensity: number): AnimDef
	return {
		type = "anim",
		layer = Layer.BASE,
		joints = BasicMovementAnimDef.IdleJoints,
	}
end

-- ─── Breathing (modify) ──────────────────────────────────────────────────────

--[=[
	숨쉬기 modifier. Idle/Walk/Run 어느 상태에서도 독립적으로 동작합니다.
	@param cycleRef  { base: number, value: number } — value가 Hz. 외부에서 실시간 변경 가능.
	@param intensity  진폭 배율.
]=]
local function makeBreath(cycleRef: CycleRef, intensity: number): AnimDef
	return {
		type = "modify",
		joints = {
			-- Waist: 위아래 + pitch
			Waist = function(_joint, _defaultC0, _ac): OnModify
				local t = 0
				return function(current: CFrame, dt: number): CFrame
					t = (t + dt * cycleRef.value) % 1
					local breath = math.sin(t * TWO_PI)
					return current
						* CFrame.new(0, breath * 0.01 * intensity, 0)
						* CFrame.Angles(breath * 0.01 * intensity, 0, 0)
				end
			end,
			-- Neck: 고개 살짝 기울임
			Neck = function(_joint, _defaultC0, _ac): OnModify
				local t = 0
				return function(current: CFrame, dt: number): CFrame
					t = (t + dt * cycleRef.value) % 1
					local sway = math.sin(t * TWO_PI + 0.5)
					return current * CFrame.Angles(-sway * 0.025 * intensity, 0, sway * 0.015 * intensity)
				end
			end,
		},
	}
end

-- ─── Walk ────────────────────────────────────────────────────────────────────

--[=[
	@param cycleRef  { base: number, value: number } — value가 Hz. 외부에서 실시간 변경 가능.
	@param intensity  진폭 배율.
	@param lean  전방 기울기.
]=]
local function makeWalk(cycleRef: CycleRef, intensity: number, lean: number): AnimDef
	return {
		type = "anim",
		layer = Layer.BASE,
		joints = {
			Root = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local bob = math.abs(math.sin(t * TWO_PI)) * 0.12 * intensity
					ac:spring(j, defaultC0 * CFrame.new(0, -bob, 0), 10, 0.3, dt)
				end
			end,
			Waist = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local sway = math.sin(t * TWO_PI) * 0.08 * intensity
					ac:spring(j, defaultC0 * CFrame.Angles(lean, 0, sway), 10, 0.3, dt)
				end
			end,
			Neck = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local counter = math.sin(t * TWO_PI) * 0.04 * intensity
					ac:spring(j, defaultC0 * CFrame.Angles(-lean * 0.5, 0, -counter), 10, 0.3, dt)
				end
			end,
			LeftHip = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local fwdFactor = math.max(0.35, math.abs(dir.Z))
					local swing = math.sin(t * TWO_PI) * 0.7 * intensity * fwdFactor
					local backBias = math.max(0, dir.Z) * -0.25
					local swingAxis = Vector3.new(-dir.Z, 0, dir.X)
					local axisLen = swingAxis.Magnitude
					local yaw = -dir.X * 0.2 * math.abs(dir.X)
					local target = if axisLen > 0.001
						then defaultC0 * CFrame.Angles(0, yaw, 0) * CFrame.fromAxisAngle(
							swingAxis / axisLen,
							swing + backBias
						)
						else defaultC0
					ac:spring(j, target, 10, 0.3, dt)
				end
			end,
			RightHip = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local fwdFactor = math.max(0.35, math.abs(dir.Z))
					local swing = -math.sin(t * TWO_PI) * 0.7 * intensity * fwdFactor
					local backBias = math.max(0, dir.Z) * -0.25
					local swingAxis = Vector3.new(-dir.Z, 0, dir.X)
					local axisLen = swingAxis.Magnitude
					local yaw = dir.X * 0.2 * math.abs(dir.X)
					local target = if axisLen > 0.001
						then defaultC0 * CFrame.Angles(0, yaw, 0) * CFrame.fromAxisAngle(
							swingAxis / axisLen,
							swing + backBias
						)
						else defaultC0
					ac:spring(j, target, 10, 0.3, dt)
				end
			end,
			LeftKnee = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local fwdFactor = math.max(0.35, math.abs(dir.Z))
					local bend = math.max(0, math.sin(t * TWO_PI + math.pi)) * 0.7 * intensity * fwdFactor
					ac:spring(j, defaultC0 * CFrame.Angles(-bend, 0, 0), 10, 0.3, dt)
				end
			end,
			RightKnee = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local fwdFactor = math.max(0.35, math.abs(dir.Z))
					local bend = math.max(0, -math.sin(t * TWO_PI + math.pi)) * 0.7 * intensity * fwdFactor
					ac:spring(j, defaultC0 * CFrame.Angles(-bend, 0, 0), 10, 0.3, dt)
				end
			end,
			LeftAnkle = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local baseFwd = 0.05
					local flex = math.sin(t * TWO_PI) * 0.25 * intensity * (if dir.Z > 0.3 then -1 else 1)
					local sideFlex = -dir.X * 0.2
					ac:spring(j, defaultC0 * CFrame.Angles(baseFwd + flex, 0, sideFlex), 10, 0.3, dt)
				end
			end,
			RightAnkle = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local baseFwd = 0.05
					local flex = -math.sin(t * TWO_PI) * 0.25 * intensity * (if dir.Z > 0.3 then -1 else 1)
					local sideFlex = -dir.X * 0.2
					ac:spring(j, defaultC0 * CFrame.Angles(baseFwd + flex, 0, sideFlex), 10, 0.3, dt)
				end
			end,
			LeftShoulder = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local absZ = math.abs(dir.Z)
					local fwdFactor = if absZ > 0.3 then absZ else 0.3
					local swing = -math.sin(t * TWO_PI) * 0.4 * intensity * fwdFactor
					local splay = math.abs(math.sin(t * TWO_PI)) * 0.06 * intensity * fwdFactor
					ac:spring(j, defaultC0 * CFrame.Angles(swing, 0, -splay), 10, 0.3, dt)
				end
			end,
			RightShoulder = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local absZ = math.abs(dir.Z)
					local fwdFactor = if absZ > 0.3 then absZ else 0.3
					local swing = math.sin(t * TWO_PI) * 0.4 * intensity * fwdFactor
					local splay = math.abs(math.sin(t * TWO_PI)) * 0.06 * intensity * fwdFactor
					ac:spring(j, defaultC0 * CFrame.Angles(swing, 0, splay), 10, 0.3, dt)
				end
			end,
			LeftElbow = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local absZ = math.abs(dir.Z)
					local fwdFactor = if absZ > 0.3 then absZ else 0.3
					local bend = math.max(0, -math.sin(t * TWO_PI)) * 0.4 * intensity * fwdFactor
					ac:spring(j, defaultC0 * CFrame.Angles(bend, 0, 0), 10, 0.3, dt)
				end
			end,
			RightElbow = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local absZ = math.abs(dir.Z)
					local fwdFactor = if absZ > 0.3 then absZ else 0.3
					local bend = math.max(0, math.sin(t * TWO_PI)) * 0.4 * intensity * fwdFactor
					ac:spring(j, defaultC0 * CFrame.Angles(bend, 0, 0), 10, 0.3, dt)
				end
			end,
			LeftWrist = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local absZ = math.abs(dir.Z)
					local fwdFactor = if absZ > 0.3 then absZ else 0.3
					local flick = math.sin(t * TWO_PI + 0.3) * 0.08 * intensity * fwdFactor
					ac:spring(j, defaultC0 * CFrame.Angles(flick, 0, 0), 10, 0.3, dt)
				end
			end,
			RightWrist = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local absZ = math.abs(dir.Z)
					local fwdFactor = if absZ > 0.3 then absZ else 0.3
					local flick = -math.sin(t * TWO_PI + 0.3) * 0.08 * intensity * fwdFactor
					ac:spring(j, defaultC0 * CFrame.Angles(flick, 0, 0), 10, 0.3, dt)
				end
			end,
		},
	}
end

-- ─── Run ─────────────────────────────────────────────────────────────────────

--[=[
	@param cycleRef  { base: number, value: number } — value가 Hz. 외부에서 실시간 변경 가능.
	@param intensity  진폭 배율.
]=]
local function makeRun(cycleRef: CycleRef, intensity: number): AnimDef
	local FORWARD_LEAN = 0.28

	return {
		type = "anim",
		layer = Layer.BASE,
		joints = {
			Root = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local bob = math.abs(math.sin(t * TWO_PI)) * 0.22 * intensity
					local rockFwd = math.sin(t * TWO_PI) * 0.06 * intensity
					local crouchOffset = -0.18 * intensity
					ac:spring(j, defaultC0 * CFrame.new(0, crouchOffset - bob, rockFwd), 10, 0.3, dt)
				end
			end,
			Waist = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local sway = math.sin(t * TWO_PI) * 0.12 * intensity
					local twist = math.sin(t * TWO_PI) * 0.1 * intensity
					local fwdLean = -FORWARD_LEAN * -dir.Z
					ac:spring(j, defaultC0 * CFrame.Angles(fwdLean, twist, sway), 10, 0.3, dt)
				end
			end,
			Neck = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local counter = math.sin(t * TWO_PI) * 0.06 * intensity
					local fwdLean = FORWARD_LEAN * 0.5 * -dir.Z
					ac:spring(j, defaultC0 * CFrame.Angles(-fwdLean, 0, -counter), 10, 0.3, dt)
				end
			end,
			LeftHip = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local fwdFactor = math.max(0.35, math.abs(dir.Z))
					local swing = math.sin(t * TWO_PI) * 1.5 * intensity * fwdFactor
					local backBias = math.max(0, dir.Z) * -0.4
					local swingAxis = Vector3.new(-dir.Z, 0, dir.X)
					local axisLen = swingAxis.Magnitude
					local yaw = -dir.X * 0.2 * math.abs(dir.X)
					local target = if axisLen > 0.001
						then defaultC0 * CFrame.Angles(0, yaw, 0) * CFrame.fromAxisAngle(
							swingAxis / axisLen,
							swing + backBias
						)
						else defaultC0
					ac:spring(j, target, 10, 0.3, dt)
				end
			end,
			RightHip = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local fwdFactor = math.max(0.35, math.abs(dir.Z))
					local swing = -math.sin(t * TWO_PI) * 1.5 * intensity * fwdFactor
					local backBias = math.max(0, dir.Z) * -0.4
					local swingAxis = Vector3.new(-dir.Z, 0, dir.X)
					local axisLen = swingAxis.Magnitude
					local yaw = -dir.X * 0.2 * math.abs(dir.X)
					local target = if axisLen > 0.001
						then defaultC0 * CFrame.Angles(0, yaw, 0) * CFrame.fromAxisAngle(
							swingAxis / axisLen,
							swing + backBias
						)
						else defaultC0
					ac:spring(j, target, 10, 0.3, dt)
				end
			end,
			LeftKnee = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local fwdFactor = math.max(0.35, math.abs(dir.Z))
					local baseBend = 0.4 * intensity * fwdFactor
					local bend = math.max(0, math.sin(t * TWO_PI + math.pi)) * 0.8 * intensity * fwdFactor
					ac:spring(j, defaultC0 * CFrame.Angles(-(baseBend + bend), 0, 0), 10, 0.3, dt)
				end
			end,
			RightKnee = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local fwdFactor = math.max(0.35, math.abs(dir.Z))
					local baseBend = 0.4 * intensity * fwdFactor
					local bend = math.max(0, -math.sin(t * TWO_PI + math.pi)) * 0.8 * intensity * fwdFactor
					ac:spring(j, defaultC0 * CFrame.Angles(-(baseBend + bend), 0, 0), 10, 0.3, dt)
				end
			end,
			LeftAnkle = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local baseFwd = 0.1
					local flex = math.sin(t * TWO_PI) * 0.5 * intensity * (if dir.Z > 0.3 then -1 else 1)
					local push = math.max(0, -math.sin(t * TWO_PI)) * 0.3 * intensity
					local sideFlex = -dir.X * 0.3
					ac:spring(j, defaultC0 * CFrame.Angles(baseFwd + flex + push, 0, sideFlex), 10, 0.3, dt)
				end
			end,
			RightAnkle = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local baseFwd = 0.1
					local flex = -math.sin(t * TWO_PI) * 0.5 * intensity * (if dir.Z > 0.3 then -1 else 1)
					local push = math.max(0, math.sin(t * TWO_PI)) * 0.3 * intensity
					local sideFlex = -dir.X * 0.3
					ac:spring(j, defaultC0 * CFrame.Angles(baseFwd + flex + push, 0, sideFlex), 10, 0.3, dt)
				end
			end,
			LeftShoulder = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local absZ = math.abs(dir.Z)
					local fwdFactor = if absZ > 0.3 then absZ else 0.3
					local swing = math.sin(t * TWO_PI) * 1.0 * intensity * fwdFactor
					local splay = math.abs(math.sin(t * TWO_PI)) * 0.1 * intensity * fwdFactor
					ac:spring(j, defaultC0 * CFrame.Angles(swing, 0, -splay), 10, 0.3, dt)
				end
			end,
			RightShoulder = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local absZ = math.abs(dir.Z)
					local fwdFactor = if absZ > 0.3 then absZ else 0.3
					local swing = -math.sin(t * TWO_PI) * 1.0 * intensity * fwdFactor
					local splay = math.abs(math.sin(t * TWO_PI)) * 0.1 * intensity * fwdFactor
					ac:spring(j, defaultC0 * CFrame.Angles(swing, 0, splay), 10, 0.3, dt)
				end
			end,
			LeftElbow = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local absZ = math.abs(dir.Z)
					local fwdFactor = if absZ > 0.3 then absZ else 0.3
					local bend = math.max(0, math.sin(t * TWO_PI)) * 0.8 * intensity * fwdFactor
					ac:spring(j, defaultC0 * CFrame.Angles(bend, 0, 0), 10, 0.3, dt)
				end
			end,
			RightElbow = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local absZ = math.abs(dir.Z)
					local fwdFactor = if absZ > 0.3 then absZ else 0.3
					local bend = math.max(0, -math.sin(t * TWO_PI)) * 0.8 * intensity * fwdFactor
					ac:spring(j, defaultC0 * CFrame.Angles(bend, 0, 0), 10, 0.3, dt)
				end
			end,
			LeftWrist = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local absZ = math.abs(dir.Z)
					local fwdFactor = if absZ > 0.3 then absZ else 0.3
					local flick = -math.sin(t * TWO_PI + 0.3) * 0.12 * intensity * fwdFactor
					ac:spring(j, defaultC0 * CFrame.Angles(flick, 0, 0), 10, 0.3, dt)
				end
			end,
			RightWrist = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt * cycleRef.value) % 1
					local dir = ac:GetMoveDir()
					local absZ = math.abs(dir.Z)
					local fwdFactor = if absZ > 0.3 then absZ else 0.3
					local flick = math.sin(t * TWO_PI + 0.3) * 0.12 * intensity * fwdFactor
					ac:spring(j, defaultC0 * CFrame.Angles(flick, 0, 0), 10, 0.3, dt)
				end
			end,
		},
	}
end

-- ─── CycleRef 테이블 ──────────────────────────────────────────────────────────
--[=[
	외부(BasicMovementClient)에서 .value를 바꾸면 실시간으로 애니메이션 cycle 속도가 변합니다.
	.base는 클래스 기본값 — 절대 직접 수정하지 마세요.
	Walk/Run 상태 전환 시 BasicMovementClient가 현재 WalkSpeed / 기준속도 비율을 적용합니다.
]=]
local R: { [string]: CycleRef } = {
	-- Default
	Walk = { base = 1.8, value = 1.8 },
	Run = { base = 2.0, value = 2.0 },
	Breathing = { base = 0.28, value = 0.28 },
	-- 탱커
	Walk_Tank = { base = 1.8, value = 1.8 },
	Run_Tank = { base = 2.0, value = 2.0 },
	Breathing_Tank = { base = 0.28, value = 0.28 },
	-- 어쌔신
	Walk_Assassin = { base = 1.8, value = 1.8 },
	Run_Assassin = { base = 2.0, value = 2.0 },
	Breathing_Assassin = { base = 0.28, value = 0.28 },
	-- 서포터
	Walk_Support = { base = 1.8, value = 1.8 },
	Run_Support = { base = 2.0, value = 2.0 },
	Breathing_Support = { base = 0.28, value = 0.28 },
	-- 컨트롤러
	Walk_Controller = { base = 1.8, value = 1.8 },
	Run_Controller = { base = 2.0, value = 2.0 },
	Breathing_Controller = { base = 0.28, value = 0.28 },
	-- 대미지딜러
	Walk_Dealer = { base = 1.8, value = 1.8 },
	Run_Dealer = { base = 2.0, value = 2.0 },
	Breathing_Dealer = { base = 0.28, value = 0.28 },
	-- 저격수
	Walk_Marksman = { base = 1.8, value = 1.8 },
	Run_Marksman = { base = 2.0, value = 2.0 },
	Breathing_Marksman = { base = 0.28, value = 0.28 },
	-- 투척수
	Walk_Artillery = { base = 1.8, value = 1.8 },
	Run_Artillery = { base = 2.0, value = 2.0 },
	Breathing_Artillery = { base = 0.28, value = 0.28 },
}

BasicMovementAnimDef.CycleRefs = R

-- ─── 애니메이션 등록 ──────────────────────────────────────────────────────────

-- Default
BasicMovementAnimDef["Idle"] = makeIdle(0.9)
BasicMovementAnimDef["Walk"] = makeWalk(R.Walk, 1.05, 0.05)
BasicMovementAnimDef["Run"] = makeRun(R.Run, 1.05)
BasicMovementAnimDef["Breathing"] = makeBreath(R.Breathing, 0.9)

-- 탱커
BasicMovementAnimDef["Idle_Tank"] = makeIdle(0.9)
BasicMovementAnimDef["Walk_Tank"] = makeWalk(R.Walk_Tank, 1.05, 0.05)
BasicMovementAnimDef["Run_Tank"] = makeRun(R.Run_Tank, 1.05)
BasicMovementAnimDef["Breathing_Tank"] = makeBreath(R.Breathing_Tank, 0.9)

-- 어쌔신
BasicMovementAnimDef["Idle_Assassin"] = makeIdle(0.9)
BasicMovementAnimDef["Walk_Assassin"] = makeWalk(R.Walk_Assassin, 1.05, 0.05)
BasicMovementAnimDef["Run_Assassin"] = makeRun(R.Run_Assassin, 1.05)
BasicMovementAnimDef["Breathing_Assassin"] = makeBreath(R.Breathing_Assassin, 0.9)

-- 서포터
BasicMovementAnimDef["Idle_Support"] = makeIdle(0.9)
BasicMovementAnimDef["Walk_Support"] = makeWalk(R.Walk_Support, 1.05, 0.05)
BasicMovementAnimDef["Run_Support"] = makeRun(R.Run_Support, 1.05)
BasicMovementAnimDef["Breathing_Support"] = makeBreath(R.Breathing_Support, 0.9)

-- 컨트롤러
BasicMovementAnimDef["Idle_Controller"] = makeIdle(0.9)
BasicMovementAnimDef["Walk_Controller"] = makeWalk(R.Walk_Controller, 1.05, 0.05)
BasicMovementAnimDef["Run_Controller"] = makeRun(R.Run_Controller, 1.05)
BasicMovementAnimDef["Breathing_Controller"] = makeBreath(R.Breathing_Controller, 0.9)

-- 대미지딜러
BasicMovementAnimDef["Idle_Dealer"] = makeIdle(0.9)
BasicMovementAnimDef["Walk_Dealer"] = makeWalk(R.Walk_Dealer, 1.05, 0.05)
BasicMovementAnimDef["Run_Dealer"] = makeRun(R.Run_Dealer, 1.05)
BasicMovementAnimDef["Breathing_Dealer"] = makeBreath(R.Breathing_Dealer, 0.9)

-- 저격수
BasicMovementAnimDef["Idle_Marksman"] = makeIdle(0.9)
BasicMovementAnimDef["Walk_Marksman"] = makeWalk(R.Walk_Marksman, 1.05, 0.05)
BasicMovementAnimDef["Run_Marksman"] = makeRun(R.Run_Marksman, 1.05)
BasicMovementAnimDef["Breathing_Marksman"] = makeBreath(R.Breathing_Marksman, 0.9)

-- 투척수
BasicMovementAnimDef["Idle_Artillery"] = makeIdle(0.9)
BasicMovementAnimDef["Walk_Artillery"] = makeWalk(R.Walk_Artillery, 1.05, 0.05)
BasicMovementAnimDef["Run_Artillery"] = makeRun(R.Run_Artillery, 1.05)
BasicMovementAnimDef["Breathing_Artillery"] = makeBreath(R.Breathing_Artillery, 0.9)

return BasicMovementAnimDef
