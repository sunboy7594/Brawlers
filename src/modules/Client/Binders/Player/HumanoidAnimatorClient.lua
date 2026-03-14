--!strict
--[=[
	@class HumanoidAnimatorClient

	"Player" 태그가 붙은 캐릭터 Model에 자동으로 생성되는 Binder 컴포넌트.

	담당:
	- Motor6D 조인트 수집
	- EntityAnimator / CameraAnimator 생성 및 BasicMovementClient에 주입
	- BasicAttackClient에 joints 전달 (SetJoints)
	- Humanoid 참조를 BasicMovementClient에 전달
	- 매 프레임 MoveDirection을 로컬 좌표로 변환하여 AnimationControllerClient:SetMoveDir() 호출
]=]

local require = require(script.Parent.loader).load(script)

local AnimationControllerClient = require("AnimationControllerClient")
local BasicAttackClient = require("BasicAttackClient")
local BasicCameraAnimDefs = require("BasicCameraAnimDefs")
local BasicMovementAnimDefs = require("BasicMovementAnimDefs")
local BasicMovementClient = require("BasicMovementClient")
local CameraAnimator = require("CameraAnimator")
local CameraControllerClient = require("CameraControllerClient")
local EntityAnimator = require("EntityAnimator")
local Maid = require("Maid")
local RunService = game:GetService("RunService")

-- ─── R15 조인트 이름 목록 ────────────────────────────────────────────────────

local JOINT_NAMES = {
	"Root",
	"Waist",
	"Neck",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftHip",
	"LeftKnee",
	"LeftAnkle",
	"RightHip",
	"RightKnee",
	"RightAnkle",
}

local HumanoidAnimatorClient = {}
HumanoidAnimatorClient.__index = HumanoidAnimatorClient

function HumanoidAnimatorClient.new(model: Model, serviceBag: any)
	local self = setmetatable({}, HumanoidAnimatorClient)
	self._maid = Maid.new()
	self.Instance = model

	local animController = serviceBag:GetService(AnimationControllerClient)
	local movementClient = serviceBag:GetService(BasicMovementClient)
	local cameraController = serviceBag:GetService(CameraControllerClient)
	local attackClient = serviceBag:GetService(BasicAttackClient)

	-- Motor6D 수집
	local joints: { [string]: Motor6D } = {}
	for _, name in JOINT_NAMES do
		local joint = model:FindFirstChild(name, true)
		if joint and joint:IsA("Motor6D") then
			joints[name] = joint
		end
	end

	-- 이동 EntityAnimator 생성 + 주입
	local animator =
		EntityAnimator.new("BasicMovement", "BasicMovementAnimDefs", joints, BasicMovementAnimDefs, animController)
	self._maid:GiveTask(function()
		animator:Destroy()
		movementClient:SetAnimator(nil)
	end)
	movementClient:SetAnimator(animator)

	-- CameraAnimator 생성 + 주입
	local camAnimator = CameraAnimator.new("BasicMovement", BasicCameraAnimDefs, cameraController)
	self._maid:GiveTask(function()
		camAnimator:Destroy()
		movementClient:SetCameraAnimator(nil)
	end)
	movementClient:SetCameraAnimator(camAnimator)

	-- Humanoid 설정
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid?
	movementClient:SetHumanoid(humanoid)
	self._maid:GiveTask(function()
		movementClient:SetHumanoid(nil)
	end)

	-- BasicAttackClient에 joints 전달
	attackClient:SetJoints(joints)
	self._maid:GiveTask(function()
		attackClient:SetJoints(nil)
	end)

	-- RenderStepped: MoveDirection 로컬 좌표 변환
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	self._maid:GiveTask(RunService.RenderStepped:Connect(function()
		if not humanoid or not root then
			animController:SetMoveDir(Vector3.zero)
			return
		end
		local worldDir = humanoid.MoveDirection
		if worldDir.Magnitude < 0.01 then
			animController:SetMoveDir(Vector3.zero)
		else
			animController:SetMoveDir(root.CFrame:VectorToObjectSpace(worldDir))
		end
	end))

	return self
end

function HumanoidAnimatorClient:Destroy()
	self._maid:Destroy()
end

return HumanoidAnimatorClient
