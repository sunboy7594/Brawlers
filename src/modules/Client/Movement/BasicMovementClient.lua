--!strict
--[=[
	@class BasicMovementClient

	책임:
	- Shift 입력 감지 → 달리기/걷기 판단
	- 상태 변경 시 서버에 전송 (MovementStateEvent)
	- 서버로부터 클래스 변경 수신 → 애니메이션 전환
	- SetAnimator()로 주입받은 애니메이터 사용
	- SetCameraAnimator()로 주입받은 카메라 애니메이터 사용
	- SetHumanoid()로 주입받은 Humanoid 사용

	애니메이터 생성/파괴와 Humanoid 추적은 HumanoidAnimatorClient가 담당합니다.
]=]

local require = require(script.Parent.loader).load(script)

local AnimationControllerClient = require("AnimationControllerClient")
local CameraAnimator = require("CameraAnimator")
local EntityAnimator = require("EntityAnimator")
local KeybindConfig = require("KeybindConfig")
local Maid = require("Maid")
local MovementConfig = require("MovementConfig")
local ServiceBag = require("ServiceBag")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local BasicMovementClient = {}
BasicMovementClient.ServiceName = "BasicMovementClient"

export type BasicMovementClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_animController: AnimationControllerClient.AnimationControllerClient,
		_animator: EntityAnimator.EntityAnimator?,
		_cameraAnimator: CameraAnimator.CameraAnimator?,
		_humanoid: Humanoid?,
		_currentClass: string,
		_isRunning: boolean,
		_isMoving: boolean,
		_isShiftDown: boolean,
		_movementStateEvent: RemoteEvent,
		_classUpdateEvent: RemoteEvent,
	},
	{} :: typeof({ __index = BasicMovementClient })
))

-- ─── 초기화 ──────────────────────────────────────────────────────────────────

function BasicMovementClient.Init(self: BasicMovementClient, serviceBag: ServiceBag.ServiceBag): ()
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._animController = self._serviceBag:GetService(AnimationControllerClient)
	self._animator = nil
	self._cameraAnimator = nil
	self._humanoid = nil
	self._currentClass = "Default"
	self._isRunning = false
	self._isMoving = false
	self._isShiftDown = false
end

function BasicMovementClient.Start(self: BasicMovementClient): ()
	local assets = ReplicatedStorage:WaitForChild("Assets")
	local events = assets:WaitForChild("Events")
	self._movementStateEvent = events:WaitForChild("MovementStateEvent") :: RemoteEvent
	self._classUpdateEvent   = events:WaitForChild("ClassUpdateEvent") :: RemoteEvent

	-- 서버로부터 클래스 변경 수신
	self._maid:GiveTask(self._classUpdateEvent.OnClientEvent:Connect(function(className: unknown)
		if type(className) == "string" then
			self:_onClassChanged(className)
		end
	end))

	-- 매 프레임 이동 상태 감지
	self._maid:GiveTask(RunService.Heartbeat:Connect(function()
		self:_poll()
	end))
end

-- ─── 공개 API ─────────────────────────────────────────────────────────────────

--[=[
	HumanoidAnimatorClient가 캐릭터 스폰/리스폰 시 호출합니다.
	nil을 넘기면 애니메이터를 해제합니다.
	@param animator EntityAnimator?
]=]
function BasicMovementClient:SetAnimator(animator: EntityAnimator.EntityAnimator?)
	self._animator = animator
	if animator then
		self:_playAnim("Idle")
		self:_playBreath()
	end
end

--[=[
	HumanoidAnimatorClient가 캐릭터 스폰/리스폰 시 호출합니다.
	nil을 넘기면 카메라 애니메이터를 해제합니다.
	@param cameraAnimator CameraAnimator?
]=]
function BasicMovementClient:SetCameraAnimator(cameraAnimator: CameraAnimator.CameraAnimator?)
	self._cameraAnimator = cameraAnimator
end

--[=[
	HumanoidAnimatorClient가 캐릭터 스폰/리스폰 시 호출합니다.
	nil을 넘기면 Humanoid 참조를 해제합니다.
	@param humanoid Humanoid?
]=]
function BasicMovementClient:SetHumanoid(humanoid: Humanoid?)
	self._humanoid = humanoid
	if humanoid then
		self._isRunning = false
		self._isMoving = false
		self._isShiftDown = false
	end
end

-- ─── 내부 ────────────────────────────────────────────────────────────────────

function BasicMovementClient:_poll()
	local humanoid = self._humanoid
	if not humanoid then
		return
	end

	local isMoving    = humanoid.MoveDirection.Magnitude > 0
	local isShiftDown = UserInputService:IsKeyDown(KeybindConfig.Binds.Run)
	local isRunning   = isMoving and isShiftDown

	if self._isRunning == isRunning and self._isMoving == isMoving then
		return
	end

	local prevShiftDown = self._isShiftDown
	self._isRunning   = isRunning
	self._isMoving    = isMoving
	self._isShiftDown = isShiftDown

	if prevShiftDown ~= isShiftDown then
		self._movementStateEvent:FireServer(isShiftDown)
	end

	if not self._isMoving then
		self:_playAnim("Idle")
		self:_playCamAnim(false)
	elseif self._isRunning then
		self:_playAnim("Run")
		self:_playCamAnim(true)
	else
		self:_playAnim("Walk")
		self:_playCamAnim(false)
	end
end

function BasicMovementClient:_playAnim(animKey: string)
	if not self._animator then
		return
	end
	local config = MovementConfig.GetConfig(self._currentClass)
	local animName = (config.animations :: any)[animKey] :: string
	self._animator:PlayAnimation(animName)
end

function BasicMovementClient:_playBreath()
	if not self._animator then
		return
	end
	local config = MovementConfig.GetConfig(self._currentClass)
	self._animator:PlayAnimation(config.animations.Breathing)
end

function BasicMovementClient:_playCamAnim(isRunning: boolean)
	if not self._cameraAnimator then
		return
	end
	if isRunning then
		self._cameraAnimator:PlayAnimation("RunFOV")
	else
		self._cameraAnimator:Stop("RunFOV")
	end
end

function BasicMovementClient:_onClassChanged(className: string)
	self._currentClass = className

	-- 이동 anim 교체
	if not self._isMoving then
		self:_playAnim("Idle")
	elseif self._isRunning then
		self:_playAnim("Run")
	else
		self:_playAnim("Walk")
	end

	-- 숨쉬기 modifier 교체 (기존 제거 → 새 클래스 등록)
	if self._animator then
		self._animator:StopAnimation("modify")
		self:_playBreath()
	end
end

function BasicMovementClient.Destroy(self: BasicMovementClient)
	self._maid:Destroy()
end

return BasicMovementClient
