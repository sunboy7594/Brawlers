--!strict
--[=[
	@class BasicMovementClient

	책임:
	- Shift 입력 감지 → 달리기/걷기 판단
	- 상태 변경 시 서버에 전송 (MovementRemoting.IsRunning)
	- 서버로부터 클래스 변경 수신 → 애니메이션 전환 (ClassRemoting.ClassChanged)
	- PlayerBinderClient.JointsChanged 구독 → EntityAnimator 생성/파괴 자가 처리
	- CameraAnimator 직접 생성 및 관리

	애니메이터 생성/파괴와 MoveDir 계산은 PlayerAnimatorClient가 담당합니다.
]=]

local require = require(script.Parent.loader).load(script)

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AnimationControllerClient = require("AnimationControllerClient")
local BasicMovementAnimDef = require("BasicMovementAnimDef")
local BasicMovementCameraAnimDef = require("BasicMovementCameraAnimDef")
local BasicMovementConfig = require("BasicMovementConfig")
local CameraAnimator = require("CameraAnimator")
local CameraControllerClient = require("CameraControllerClient")
local ClassRemoting = require("ClassRemoting")
local EntityAnimator = require("EntityAnimator")
local KeybindConfig = require("KeybindConfig")
local Maid = require("Maid")
local MovementRemoting = require("MovementRemoting")
local PlayerBinderClient = require("PlayerBinderClient")
local ServiceBag = require("ServiceBag")

local BasicMovementClient = {}
BasicMovementClient.ServiceName = "BasicMovementClient"

export type BasicMovementClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_animController: AnimationControllerClient.AnimationControllerClient,
		_cameraAnimator: CameraAnimator.CameraAnimator,
		_animator: EntityAnimator.EntityAnimator?,
		_currentClass: string,
		_isRunning: boolean,
		_isMoving: boolean,
		_isShiftDown: boolean,
	},
	{} :: typeof({ __index = BasicMovementClient })
))

-- ─── 초기화 ──────────────────────────────────────────────────────────────────

function BasicMovementClient.Init(self: BasicMovementClient, serviceBag: ServiceBag.ServiceBag): ()
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._animController = self._serviceBag:GetService(AnimationControllerClient)
	self._animator = nil
	self._currentClass = "Default"
	self._isRunning = false
	self._isMoving = false
	self._isShiftDown = false

	-- CameraAnimator 직접 생성 (캐릭터 생명주기와 무관하게 항상 존재)
	local cameraController = serviceBag:GetService(CameraControllerClient)
	local camAnimator = CameraAnimator.new("BasicMovement", BasicMovementCameraAnimDef, cameraController)
	self._cameraAnimator = camAnimator
	self._maid:GiveTask(function()
		camAnimator:Destroy()
	end)

	-- PlayerBinderClient.JointsChanged 구독 → EntityAnimator 생성/파괴
	local playerBinder = serviceBag:GetService(PlayerBinderClient)
	self._maid:GiveTask(playerBinder.JointsChanged:Connect(function(joints)
		-- 기존 animator 정리
		if self._animator then
			self._animator:Destroy()
			self._animator = nil
		end

		if not joints then
			-- 캐릭터 제거됨 → 이동 상태 초기화
			self._isRunning = false
			self._isMoving = false
			self._isShiftDown = false
			return
		end

		-- 새 EntityAnimator 생성
		local animator = EntityAnimator.new(
			"BasicMovement",
			"BasicMovementAnimDef",
			joints,
			BasicMovementAnimDef,
			self._animController
		)
		self._animator = animator
		self:_playAnim("Idle", true)
		self:_playAnim("Breathing", true)
	end))

	-- 서버 → 클라이언트: 클래스 변경 수신
	self._maid:GiveTask(ClassRemoting.ClassChanged:Connect(function(className: unknown)
		if type(className) == "string" then
			self:_onClassChanged(className)
		end
	end))
end

function BasicMovementClient.Start(self: BasicMovementClient): ()
	-- 매 프레임 이동 상태 감지
	self._maid:GiveTask(RunService.Heartbeat:Connect(function()
		self:_poll()
	end))
end

-- ─── 내부 ────────────────────────────────────────────────────────────────────

function BasicMovementClient:_poll()
	if not self._animator then
		return
	end

	-- MoveDir은 AnimationControllerClient가 PlayerBinderClient로부터 매 프레임 폴링하여 캐싱
	local moveDir = self._animController:GetMoveDir()
	local isMoving = moveDir.Magnitude > 0.01
	local isShiftDown = UserInputService:IsKeyDown(KeybindConfig.Binds.Run)
	local isRunning = isMoving and isShiftDown

	if self._isRunning == isRunning and self._isMoving == isMoving then
		return
	end

	local prevShiftDown = self._isShiftDown
	self._isRunning = isRunning
	self._isMoving = isMoving
	self._isShiftDown = isShiftDown

	-- Shift 상태가 바뀔 때만 서버로 전송
	if prevShiftDown ~= isShiftDown then
		MovementRemoting.IsRunning:FireServer(isShiftDown)
	end

	-- 이동 상태에 따라 애니메이션 전환
	if not self._isMoving then
		self:_playAnim("Idle", true)
		self:_playCamAnim("RunFOV", false)
	elseif self._isRunning then
		self:_playAnim("Run", true)
		self:_playCamAnim("RunFOV", true)
	else
		self:_playAnim("Walk", true)
		self:_playCamAnim("RunFOV", false)
	end
end

function BasicMovementClient:_playAnim(animKey: string, play: boolean)
	if not self._animator then
		return
	end
	local config = BasicMovementConfig.GetConfig(self._currentClass)
	local animName = (config.animations :: any)[animKey] :: string
	if play then
		self._animator:PlayAnimation(animName)
	else
		self._animator:StopAnimation(animName)
	end
end

function BasicMovementClient:_playCamAnim(animName: string, play: boolean)
	if play then
		self._cameraAnimator:PlayAnimation(animName)
	else
		self._cameraAnimator:Stop(animName)
	end
end

function BasicMovementClient:_onClassChanged(className: string)
	-- 1. 이전 클래스 Breathing 정지
	if self._animator then
		self:_playAnim("Breathing", false)
	end

	-- 2. 클래스 교체
	self._currentClass = className

	-- 3. 새 클래스 이동 애니메이션 교체
	if not self._isMoving then
		self:_playAnim("Idle", true)
	elseif self._isRunning then
		self:_playAnim("Run", true)
	else
		self:_playAnim("Walk", true)
	end

	-- 4. 새 클래스 Breathing 시작
	if self._animator then
		self:_playAnim("Breathing", true)
	end
end

function BasicMovementClient.Destroy(self: BasicMovementClient)
	self._maid:Destroy()
end

return BasicMovementClient
