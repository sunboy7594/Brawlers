--!strict
--[=[
	@class BasicMovementAnimDefs
]=]

local Layer = {
	BASE = 0,
	ACTION = 1,
	OVERRIDE = 2,
}

local BasicMovementAnimDefs = {}

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

-- ─── Idle ────────────────────────────────────────────────────────────────────

local function makeIdle(_intensity: number): AnimDef
	local RootPose = CFrame.new(0.0000, -0.1027, 0.0090) * CFrame.Angles(-0.0000, 0.0000, -0.0000)
	local WaistPose = CFrame.new(-0.0360, 0.0122, 0.1342) * CFrame.Angles(-0.1806, -0.2577, -0.0465)
	local NeckPose = CFrame.new(-0.0405, 0.0159, -0.0095) * CFrame.Angles(0.0842, 0.2608, 0.0233)
	local LeftShoulderPose = CFrame.new(0.0142, -0.0648, -0.1630) * CFrame.Angles(-0.2159, -0.2732, -0.3542)
	local RightShoulderPose = CFrame.new(0.0425, -0.0234, 0.0362) * CFrame.Angles(-0.1723, 0.3210, 0.3493)
	local LeftElbowPose = CFrame.new(0.0000, -0.0731, 0.0999) * CFrame.Angles(0.8727, -0.0000, 0.0000)
	local RightElbowPose = CFrame.new(0.0000, -0.0068, -0.0134) * CFrame.Angles(0.5236, -0.0000, 0.0000)
	local LeftWristPose = CFrame.new(-0.0000, -0.0000, 0.0000) * CFrame.Angles(-0.0000, -0.0000, 0.0000)
	local RightWristPose = CFrame.new(-0.0000, -0.0000, -0.0000) * CFrame.Angles(-0.0000, -0.0000, 0.0000)
	local LeftHipPose = CFrame.new(-0.1311, -0.0026, -0.1711) * CFrame.Angles(0.2492, -0.1980, -0.0698)
	local RightHipPose = CFrame.new(0.1182, 0.0141, 0.0425) * CFrame.Angles(0.0157, -0.2611, 0.0900)
	local LeftKneePose = CFrame.new(-0.0000, 0.0161, -0.0195) * CFrame.Angles(-0.5236, 0.0000, 0.0000)
	local RightKneePose = CFrame.new(-0.0000, 0.0469, 0.0661) * CFrame.Angles(-0.3491, -0.0000, 0.0000)
	local LeftAnklePose = CFrame.new(-0.0087, 0.1051, -0.2099) * CFrame.Angles(0.2776, 0.0005, 0.1163)
	local RightAnklePose = CFrame.new(0.0123, 0.0781, -0.1783) * CFrame.Angles(0.3414, 0.0876, -0.0863)

	return {
		type = "anim",
		layer = Layer.BASE,
		joints = {
			Root = function(_joint, defaultC0, ac): OnUpdate
				return function(j, dt)
					ac:spring(j, defaultC0 * RootPose, 200, 1.6, dt)
				end
			end,
			-- 숨쉬기(breathOffset) 제거 → Breathing modifier가 처리
			Waist = function(_joint, defaultC0, ac): OnUpdate
				return function(j, dt)
					ac:spring(j, defaultC0 * WaistPose, 200, 1.6, dt)
				end
			end,
			Neck = function(_joint, defaultC0, ac): OnUpdate
				return function(j, dt)
					ac:spring(j, defaultC0 * NeckPose, 200, 1.6, dt)
				end
			end,
			LeftShoulder = function(_joint, defaultC0, ac): OnUpdate
				return function(j, dt)
					ac:spring(j, defaultC0 * LeftShoulderPose, 200, 1.6, dt)
				end
			end,
			RightShoulder = function(_joint, defaultC0, ac): OnUpdate
				return function(j, dt)
					ac:spring(j, defaultC0 * RightShoulderPose, 200, 1.6, dt)
				end
			end,
			LeftElbow = function(_joint, defaultC0, ac): OnUpdate
				return function(j, dt)
					ac:spring(j, defaultC0 * LeftElbowPose, 200, 1.6, dt)
				end
			end,
			RightElbow = function(_joint, defaultC0, ac): OnUpdate
				return function(j, dt)
					ac:spring(j, defaultC0 * RightElbowPose, 200, 1.6, dt)
				end
			end,
			LeftWrist = function(_joint, defaultC0, ac): OnUpdate
				return function(j, dt)
					ac:spring(j, defaultC0 * LeftWristPose, 200, 1.6, dt)
				end
			end,
			RightWrist = function(_joint, defaultC0, ac): OnUpdate
				return function(j, dt)
					ac:spring(j, defaultC0 * RightWristPose, 200, 1.6, dt)
				end
			end,
			LeftHip = function(_joint, defaultC0, ac): OnUpdate
				return function(j, dt)
					ac:spring(j, defaultC0 * LeftHipPose, 200, 1.6, dt)
				end
			end,
			RightHip = function(_joint, defaultC0, ac): OnUpdate
				return function(j, dt)
					ac:spring(j, defaultC0 * RightHipPose, 200, 1.6, dt)
				end
			end,
			LeftKnee = function(_joint, defaultC0, ac): OnUpdate
				return function(j, dt)
					ac:spring(j, defaultC0 * LeftKneePose, 200, 1.6, dt)
				end
			end,
			RightKnee = function(_joint, defaultC0, ac): OnUpdate
				return function(j, dt)
					ac:spring(j, defaultC0 * RightKneePose, 200, 1.6, dt)
				end
			end,
			LeftAnkle = function(_joint, defaultC0, ac): OnUpdate
				return function(j, dt)
					ac:spring(j, defaultC0 * LeftAnklePose, 200, 1.6, dt)
				end
			end,
			RightAnkle = function(_joint, defaultC0, ac): OnUpdate
				return function(j, dt)
					ac:spring(j, defaultC0 * RightAnklePose, 200, 1.6, dt)
				end
			end,
		},
	}
end

-- ─── Breathing (modify) ──────────────────────────────────────────────────────

--[=[
	숨쉬기 modifier. Idle/Walk/Run 어느 상태에서도 독립적으로 동작합니다.
	@param cycle  숨쉬기 주기 (Hz). 높을수록 빠름.
	@param intensity  진폭 배율.
]=]
local function makeBreath(cycle: number, intensity: number): AnimDef
	local freq = cycle * math.pi * 2
	local period = 1 / cycle

	return {
		type = "modify",
		joints = {
			-- Waist: 위아래 + pitch
			Waist = function(_joint, _defaultC0, _ac): OnModify
				local t = 0
				return function(current: CFrame, dt: number): CFrame
					t = (t + dt) % period
					local breath = math.sin(t * freq)
					return current
						* CFrame.new(0, breath * 0.01 * intensity, 0)
						* CFrame.Angles(breath * 0.01 * intensity, 0, 0)
				end
			end,
			-- Neck: 고개 살짝 기울임
			Neck = function(_joint, _defaultC0, _ac): OnModify
				local t = 0
				return function(current: CFrame, dt: number): CFrame
					t = (t + dt) % period
					local sway = math.sin(t * freq + 0.5)
					return current * CFrame.Angles(-sway * 0.025 * intensity, 0, sway * 0.015 * intensity)
				end
			end,
		},
	}
end

-- ─── Walk ────────────────────────────────────────────────────────────────────

local function makeWalk(cycle: number, intensity: number, lean: number): AnimDef
	local freq = cycle * math.pi * 2
	local period = 1 / cycle

	return {
		type = "anim",
		layer = Layer.BASE,
		joints = {
			Root = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local bob = math.abs(math.sin(t * freq)) * 0.12 * intensity
					ac:spring(j, defaultC0 * CFrame.new(0, -bob, 0), 200, 0.8, dt)
				end
			end,
			Waist = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local sway = math.sin(t * freq) * 0.08 * intensity
					ac:spring(j, defaultC0 * CFrame.Angles(lean, 0, sway), 200, 0.8, dt)
				end
			end,
			Neck = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local counter = math.sin(t * freq) * 0.04 * intensity
					ac:spring(j, defaultC0 * CFrame.Angles(-lean * 0.5, 0, -counter), 200, 0.8, dt)
				end
			end,
			LeftHip = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local dir = ac:GetMoveDir()
					local fwdFactor = math.max(0.35, math.abs(dir.Z))
					local swing = math.sin(t * freq) * 0.7 * intensity * fwdFactor
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
					ac:spring(j, target, 200, 0.8, dt)
				end
			end,
			RightHip = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local dir = ac:GetMoveDir()
					local fwdFactor = math.max(0.35, math.abs(dir.Z))
					local swing = -math.sin(t * freq) * 0.7 * intensity * fwdFactor
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
					ac:spring(j, target, 200, 0.8, dt)
				end
			end,
			LeftKnee = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local dir = ac:GetMoveDir()
					local fwdFactor = math.max(0.35, math.abs(dir.Z))
					local bend = math.max(0, math.sin(t * freq + math.pi)) * 0.7 * intensity * fwdFactor
					ac:spring(j, defaultC0 * CFrame.Angles(-bend, 0, 0), 200, 0.8, dt)
				end
			end,
			RightKnee = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local dir = ac:GetMoveDir()
					local fwdFactor = math.max(0.35, math.abs(dir.Z))
					local bend = math.max(0, -math.sin(t * freq + math.pi)) * 0.7 * intensity * fwdFactor
					ac:spring(j, defaultC0 * CFrame.Angles(-bend, 0, 0), 200, 0.8, dt)
				end
			end,
			LeftAnkle = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local dir = ac:GetMoveDir()
					local baseFwd = 0.05
					local flex = math.sin(t * freq) * 0.25 * intensity * (if dir.Z > 0.3 then -1 else 1)
					local sideFlex = -dir.X * 0.2
					ac:spring(j, defaultC0 * CFrame.Angles(baseFwd + flex, 0, sideFlex), 200, 0.8, dt)
				end
			end,
			RightAnkle = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local dir = ac:GetMoveDir()
					local baseFwd = 0.05
					local flex = -math.sin(t * freq) * 0.25 * intensity * (if dir.Z > 0.3 then -1 else 1)
					local sideFlex = -dir.X * 0.2
					ac:spring(j, defaultC0 * CFrame.Angles(baseFwd + flex, 0, sideFlex), 200, 0.8, dt)
				end
			end,
			LeftShoulder = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local swing = -math.sin(t * freq) * 0.4 * intensity
					local splay = math.abs(math.sin(t * freq)) * 0.06 * intensity
					ac:spring(j, defaultC0 * CFrame.Angles(swing, 0, -splay), 200, 0.8, dt)
				end
			end,
			RightShoulder = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local swing = math.sin(t * freq) * 0.4 * intensity
					local splay = math.abs(math.sin(t * freq)) * 0.06 * intensity
					ac:spring(j, defaultC0 * CFrame.Angles(swing, 0, splay), 200, 0.8, dt)
				end
			end,
			LeftElbow = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local bend = math.max(0, -math.sin(t * freq)) * 0.4 * intensity
					ac:spring(j, defaultC0 * CFrame.Angles(bend, 0, 0), 200, 0.8, dt)
				end
			end,
			RightElbow = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local bend = math.max(0, math.sin(t * freq)) * 0.4 * intensity
					ac:spring(j, defaultC0 * CFrame.Angles(bend, 0, 0), 200, 0.8, dt)
				end
			end,
			LeftWrist = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local flick = math.sin(t * freq + 0.3) * 0.08 * intensity
					ac:spring(j, defaultC0 * CFrame.Angles(flick, 0, 0), 200, 0.8, dt)
				end
			end,
			RightWrist = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local flick = -math.sin(t * freq + 0.3) * 0.08 * intensity
					ac:spring(j, defaultC0 * CFrame.Angles(flick, 0, 0), 200, 0.8, dt)
				end
			end,
		},
	}
end

-- ─── Run ─────────────────────────────────────────────────────────────────────

local function makeRun(cycle: number, intensity: number): AnimDef
	local freq = cycle * math.pi * 2
	local period = 1 / cycle
	local FORWARD_LEAN = 0.28

	return {
		type = "anim",
		layer = Layer.BASE,
		joints = {
			Root = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local bob = math.abs(math.sin(t * freq)) * 0.22 * intensity
					local rockFwd = math.sin(t * freq) * 0.06 * intensity
					local crouchOffset = -0.18 * intensity
					ac:spring(j, defaultC0 * CFrame.new(0, crouchOffset - bob, rockFwd), 200, 0.8, dt)
				end
			end,
			Waist = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local dir = ac:GetMoveDir()
					local sway = math.sin(t * freq) * 0.12 * intensity
					local twist = math.sin(t * freq) * 0.1 * intensity
					local fwdLean = -FORWARD_LEAN * -dir.Z
					ac:spring(j, defaultC0 * CFrame.Angles(fwdLean, twist, sway), 200, 0.8, dt)
				end
			end,
			Neck = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local dir = ac:GetMoveDir()
					local counter = math.sin(t * freq) * 0.06 * intensity
					local fwdLean = FORWARD_LEAN * 0.5 * -dir.Z
					ac:spring(j, defaultC0 * CFrame.Angles(-fwdLean, 0, -counter), 200, 0.8, dt)
				end
			end,
			LeftHip = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local dir = ac:GetMoveDir()
					local fwdFactor = math.max(0.35, math.abs(dir.Z))
					local swing = math.sin(t * freq) * 1.5 * intensity * fwdFactor
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
					ac:spring(j, target, 200, 0.8, dt)
				end
			end,
			RightHip = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local dir = ac:GetMoveDir()
					local fwdFactor = math.max(0.35, math.abs(dir.Z))
					local swing = -math.sin(t * freq) * 1.5 * intensity * fwdFactor
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
					ac:spring(j, target, 200, 0.8, dt)
				end
			end,
			LeftKnee = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local dir = ac:GetMoveDir()
					local fwdFactor = math.max(0.35, math.abs(dir.Z))
					local baseBend = 0.4 * intensity * fwdFactor
					local bend = math.max(0, math.sin(t * freq + math.pi)) * 0.8 * intensity * fwdFactor
					ac:spring(j, defaultC0 * CFrame.Angles(-(baseBend + bend), 0, 0), 200, 0.8, dt)
				end
			end,
			RightKnee = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local dir = ac:GetMoveDir()
					local fwdFactor = math.max(0.35, math.abs(dir.Z))
					local baseBend = 0.4 * intensity * fwdFactor
					local bend = math.max(0, -math.sin(t * freq + math.pi)) * 0.8 * intensity * fwdFactor
					ac:spring(j, defaultC0 * CFrame.Angles(-(baseBend + bend), 0, 0), 200, 0.8, dt)
				end
			end,
			LeftAnkle = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local dir = ac:GetMoveDir()
					local baseFwd = 0.1
					local flex = math.sin(t * freq) * 0.5 * intensity * (if dir.Z > 0.3 then -1 else 1)
					local push = math.max(0, -math.sin(t * freq)) * 0.3 * intensity
					local sideFlex = -dir.X * 0.3
					ac:spring(j, defaultC0 * CFrame.Angles(baseFwd + flex + push, 0, sideFlex), 200, 0.8, dt)
				end
			end,
			RightAnkle = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local dir = ac:GetMoveDir()
					local baseFwd = 0.1
					local flex = -math.sin(t * freq) * 0.5 * intensity * (if dir.Z > 0.3 then -1 else 1)
					local push = math.max(0, math.sin(t * freq)) * 0.3 * intensity
					local sideFlex = -dir.X * 0.3
					ac:spring(j, defaultC0 * CFrame.Angles(baseFwd + flex + push, 0, sideFlex), 200, 0.8, dt)
				end
			end,
			LeftShoulder = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local swing = -math.sin(t * freq) * 0.9 * intensity
					local splay = math.abs(math.sin(t * freq)) * 0.05 * intensity
					ac:spring(j, defaultC0 * CFrame.Angles(swing, 0, -splay), 200, 0.8, dt)
				end
			end,
			RightShoulder = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local swing = math.sin(t * freq) * 0.9 * intensity
					local splay = math.abs(math.sin(t * freq)) * 0.06 * intensity
					ac:spring(j, defaultC0 * CFrame.Angles(swing, 0, splay), 200, 0.8, dt)
				end
			end,
			LeftElbow = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local baseBend = 1.2 * intensity
					local wave = math.sin(t * freq) * 0.3 * intensity
					ac:spring(j, defaultC0 * CFrame.Angles(baseBend + wave, 0, 0), 200, 0.8, dt)
				end
			end,
			RightElbow = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local baseBend = 1.2 * intensity
					local wave = -math.sin(t * freq) * 0.3 * intensity
					ac:spring(j, defaultC0 * CFrame.Angles(baseBend + wave, 0, 0), 200, 0.8, dt)
				end
			end,
			LeftWrist = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local flick = math.sin(t * freq + 0.3) * 0.12 * intensity
					ac:spring(j, defaultC0 * CFrame.Angles(flick, 0, 0), 200, 0.8, dt)
				end
			end,
			RightWrist = function(_joint, defaultC0, ac): OnUpdate
				local t = 0
				return function(j, dt)
					t = (t + dt) % period
					local flick = -math.sin(t * freq + 0.3) * 0.12 * intensity
					ac:spring(j, defaultC0 * CFrame.Angles(flick, 0, 0), 200, 0.8, dt)
				end
			end,
		},
	}
end

-- ─── 애니메이션 등록 ──────────────────────────────────────────────────────────

-- Default
BasicMovementAnimDefs["Idle"] = makeIdle(1.0)
BasicMovementAnimDefs["Walk"] = makeWalk(2.5, 1.0, 0.04)
BasicMovementAnimDefs["Run"] = makeRun(2.8, 1.0)
BasicMovementAnimDefs["Breathing"] = makeBreath(0.4, 1.0)

-- 탱커
BasicMovementAnimDefs["Idle_Tank"] = makeIdle(1.5)
BasicMovementAnimDefs["Walk_Tank"] = makeWalk(1.8, 1.4, 0.07)
BasicMovementAnimDefs["Run_Tank"] = makeRun(2.0, 1.3)
BasicMovementAnimDefs["Breathing_Tank"] = makeBreath(0.28, 1.5)

-- 어쌔신
BasicMovementAnimDefs["Idle_Assassin"] = makeIdle(0.75)
BasicMovementAnimDefs["Walk_Assassin"] = makeWalk(2.9, 0.95, 0.05)
BasicMovementAnimDefs["Run_Assassin"] = makeRun(3.2, 1.1)
BasicMovementAnimDefs["Breathing_Assassin"] = makeBreath(0.6, 0.75)

-- 서포터
BasicMovementAnimDefs["Idle_Support"] = makeIdle(0.85)
BasicMovementAnimDefs["Walk_Support"] = makeWalk(2.4, 0.9, 0.03)
BasicMovementAnimDefs["Run_Support"] = makeRun(2.6, 0.95)
BasicMovementAnimDefs["Breathing_Support"] = makeBreath(0.45, 0.85)

-- 컨트롤러
BasicMovementAnimDefs["Idle_Controller"] = makeIdle(1.0)
BasicMovementAnimDefs["Walk_Controller"] = makeWalk(2.3, 1.0, 0.04)
BasicMovementAnimDefs["Run_Controller"] = makeRun(2.6, 1.0)
BasicMovementAnimDefs["Breathing_Controller"] = makeBreath(0.38, 1.0)

-- 대미지딜러
BasicMovementAnimDefs["Idle_Dealer"] = makeIdle(0.9)
BasicMovementAnimDefs["Walk_Dealer"] = makeWalk(2.6, 1.05, 0.05)
BasicMovementAnimDefs["Run_Dealer"] = makeRun(2.9, 1.05)
BasicMovementAnimDefs["Breathing_Dealer"] = makeBreath(0.5, 0.9)

-- 저격수
BasicMovementAnimDefs["Idle_Marksman"] = makeIdle(0.8)
BasicMovementAnimDefs["Walk_Marksman"] = makeWalk(2.0, 0.85, 0.02)
BasicMovementAnimDefs["Run_Marksman"] = makeRun(2.8, 1.0)
BasicMovementAnimDefs["Breathing_Marksman"] = makeBreath(0.35, 0.8)

-- 투척수
BasicMovementAnimDefs["Idle_Artillery"] = makeIdle(1.6)
BasicMovementAnimDefs["Walk_Artillery"] = makeWalk(1.6, 1.5, 0.08)
BasicMovementAnimDefs["Run_Artillery"] = makeRun(1.9, 1.3)
BasicMovementAnimDefs["Breathing_Artillery"] = makeBreath(0.25, 1.6)

return BasicMovementAnimDefs
