--!strict
--[=[
	@class PlayerAnimatorClient

	"Player" 태그가 붙은 캐릭터 Model에 자동으로 생성되는 Binder 컴포넌트.

	담당:
	- 로컬 플레이어 캐릭터 여부 확인
	- Humanoid 존재 여부에 따라 경로 분기
	  - Humanoid 있음 → HumanoidAnimator 경로 (Motor6D 수집, JointsChanged 발행)
	  - Humanoid 없음 → CustomBodyAnimator stub (추후 구현)
	- 매 프레임 MoveDirection을 로컬 좌표로 계산 → GetMoveDir()로 노출
	- JointsChanged Signal → PlayerBinderClient를 통해 구독자에게 전달
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Maid = require("Maid")
local Signal = require("Signal")

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

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type PlayerAnimatorClient = typeof(setmetatable(
	{} :: {
		Instance: Model,
		IsLocalPlayer: boolean,
		JointsChanged: any, -- Signal<{ [string]: Motor6D }?>
		_maid: any,
		_moveDir: Vector3,
	},
	{} :: typeof({ __index = {} })
))

-- ─── 클래스 ──────────────────────────────────────────────────────────────────

local PlayerAnimatorClient = {}
PlayerAnimatorClient.__index = PlayerAnimatorClient

function PlayerAnimatorClient.new(model: Model, serviceBag: any)
	local self = setmetatable({}, PlayerAnimatorClient)
	self._maid = Maid.new()
	self.Instance = model
	self.IsLocalPlayer = false
	self.JointsChanged = Signal.new()
	self._moveDir = Vector3.zero

	-- 로컬 플레이어 캐릭터가 아니면 아무것도 하지 않음
	-- 다른 플레이어 joint.C0는 서버에서 변경 → Roblox 자동 복제로 표시됨
	if model ~= Players.LocalPlayer.Character then
		return self
	end

	self.IsLocalPlayer = true

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		self:_initHumanoid(model, humanoid, serviceBag)
	else
		-- TODO: CustomBodyAnimator (AnimationController 기반) 구현 예정
	end

	return self
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	매 프레임 계산된 로컬 좌표 이동 방향을 반환합니다.
	AnimationControllerClient 등 구독자가 폴링합니다.
	@return Vector3
]=]
function PlayerAnimatorClient:GetMoveDir(): Vector3
	return self._moveDir
end

function PlayerAnimatorClient:Destroy()
	-- joints nil 발행 → 구독자가 EntityAnimator 등을 정리할 수 있도록
	if self.IsLocalPlayer then
		self.JointsChanged:Fire(nil)
	end
	self._maid:Destroy()
	self.JointsChanged:Destroy()
end

-- ─── 내부 ────────────────────────────────────────────────────────────────────

function PlayerAnimatorClient:_initHumanoid(model: Model, humanoid: Humanoid, _serviceBag: any)
	-- Motor6D 수집
	local joints: { [string]: Motor6D } = {}
	for _, name in JOINT_NAMES do
		local joint = model:FindFirstChild(name, true)
		if joint and joint:IsA("Motor6D") then
			joints[name] = joint
		end
	end

	-- 조인트 준비 완료 → 구독자에게 발행
	self.JointsChanged:Fire(joints)

	-- 매 프레임 MoveDirection 로컬 좌표 계산
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	self._maid:GiveTask(RunService.RenderStepped:Connect(function()
		if not humanoid or not root then
			self._moveDir = Vector3.zero
			return
		end
		local worldDir = humanoid.MoveDirection
		if worldDir.Magnitude < 0.01 then
			self._moveDir = Vector3.zero
		else
			self._moveDir = root.CFrame:VectorToObjectSpace(worldDir)
		end
	end))
end

return PlayerAnimatorClient
