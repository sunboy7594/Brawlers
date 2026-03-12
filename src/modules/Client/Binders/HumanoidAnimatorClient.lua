--!strict
--[=[
	@class HumanoidAnimatorClient

	"Player" 태그가 붙은 캐릭터 Model에 자동으로 생성되는 Binder 컴포넌트.

	담당:
	- Motor6D 조인트 수집
	- EntityAnimator / CameraAnimator 생성 및 BasicMovementClient에 주입
	- Humanoid 참조를 BasicMovementClient에 전달
	- 매 프레임 MoveDirection을 로컬 좌표로 변환하여 AnimationControllerClient:SetMoveDir() 호출
	- 소멸 시 정리 (maid)
]=]

local require = require(script.Parent.loader).load(script)

local AnimationControllerClient = require("AnimationControllerClient")
local BasicCameraAnimDefs       = require("BasicCameraAnimDefs")
local BasicMovementAnimDefs     = require("BasicMovementAnimDefs")
local BasicMovementClient       = require("BasicMovementClient")
local CameraAnimator            = require("CameraAnimator")
local CameraControllerClient    = require("CameraControllerClient")
local EntityAnimator            = require("EntityAnimator")
local Maid                      = require("Maid")
local RunService                = game:GetService("RunService")

-- ─── R15 조인트 이름 목록 (R15Utils에 bulk getter 없으므로 직접 정의) ─────────
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

-- ─── 생성자 ──────────────────────────────────────────────────────────────────

function HumanoidAnimatorClient.new(model: Model, serviceBag: any)
	local self = setmetatable({}, HumanoidAnimatorClient)
	self._maid = Maid.new()
	self.Instance = model

	-- 서비스 획득
	local animController   = serviceBag:GetService(AnimationControllerClient)
	local movementClient   = serviceBag:GetService(BasicMovementClient)
	local cameraController = serviceBag:GetService(CameraControllerClient)

	-- Motor6D 수집 (재귀 검색)
	local joints: { [string]: Motor6D } = {}
	for _, name in JOINT_NAMES do
		local joint = model:FindFirstChild(name, true)
		if joint and joint:IsA("Motor6D") then
			joints[name] = joint
		end
	end

	-- EntityAnimator 생성 + 주입
	local animator = EntityAnimator.new("BasicMovement", joints, BasicMovementAnimDefs, animController)
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

	-- RenderStepped: MoveDirection을 HumanoidRootPart 로컬 좌표로 변환 후 전달
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

-- ─── 정리 ────────────────────────────────────────────────────────────────────

function HumanoidAnimatorClient:Destroy()
	self._maid:Destroy()
end

return HumanoidAnimatorClient
