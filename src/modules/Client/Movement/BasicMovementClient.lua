--!strict
--[=[
	@class BasicMovementClient

	책임:
	- Shift 입력 감지 → 달리기/걷기 판단
	- 상태 변경 시 서버에 전송 (MovementRemoting.IsRunning)
	- 서버로부터 클래스 변경 수신 → 애니메이션 전환 (ClassRemoting.ClassChanged)
	- PlayerBinderClient.JointsChanged 구독 → EntityAnimator 생성/파괴 자가 처리
	- CameraAnimator 직접 생성 및 관리
	- Humanoid.WalkSpeed 감시 → BasicMovementAnimDef.CycleRefs 실시간 업데이트

	애니메이터 생성/파괴와 MoveDir 계산은 PlayerAnimatorClient가 담당합니다.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
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
		_speedMaid: any, -- WalkSpeed 감시용 별도 Maid (캐릭터 교체 시 재생성)
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
	self._speedMaid = Maid.new()
	self._maid:GiveTask(self._speedMaid)
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

		-- 기존 WalkSpeed 감시 해제
		self._speedMaid:DoCleaning()

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

		-- 새 캐릭터의 WalkSpeed 감시 시작
		self:_watchWalkSpeed()
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

-- ─── 내부 ─────────────────────────────────────────────────────────────────────

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
	local prevIsRunning = self._isRunning
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

	-- Walk ↔ Run 전환 시 CycleRef 기준 속도도 재계산
	-- (walk 기준 ratio로 계산하던 걸 run 기준으로 바꿔야 하기 때문)
	if prevIsRunning ~= isRunning then
		self:_refreshCycleRefs()
	end
end

-- ─── WalkSpeed 감시 ───────────────────────────────────────────────────────────

--[=[
	캐릭터가 생성될 때마다 호출.
	Humanoid.WalkSpeed 변경을 감지해 CycleRef를 업데이트합니다.
	_speedMaid에 등록되어 캐릭터 교체 시 자동 정리됩니다.
]=]
function BasicMovementClient:_watchWalkSpeed()
	local character = Players.LocalPlayer.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- 즉시 초기 동기화
	self:_refreshCycleRefs()

	-- 이후 변경될 때마다 업데이트
	self._speedMaid:GiveTask(humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		self:_refreshCycleRefs()
	end))
end

--[=[
	현재 WalkSpeed와 클래스 기준 속도를 비교해 CycleRefs.value를 업데이트합니다.

	- Walk 상태: WalkSpeed / config.walkSpeed 비율로 Walk + Breathing ref 스케일
	- Run  상태: WalkSpeed / config.runSpeed  비율로 Run  + Breathing ref 스케일
	- Idle 상태: ref를 base로 리셋 (Breathing만 Walk 기준으로 유지)

]=]
function BasicMovementClient:_refreshCycleRefs()
	local character = Players.LocalPlayer.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local currentSpeed = humanoid.WalkSpeed
	local config = BasicMovementConfig.GetConfig(self._currentClass)
	local suffix = if self._currentClass == "Default" then "" else ("_" .. self._currentClass)
	local R = BasicMovementAnimDef.CycleRefs

	local function applyRatio(key: string, baseSpeed: number)
		local ref = R[key]
		if not ref then
			return
		end
		local ratio = currentSpeed / baseSpeed -- 정직하게 배율로 올라가는데, 완하하고 싶으면 math.sqrt로 감쌀 것
		ref.value = ref.base * ratio
	end

	local function resetToBase(key: string)
		local ref = R[key]
		if not ref then
			return
		end
		ref.value = ref.base
	end

	if self._isRunning then
		-- Run 상태: Run + Breathing을 runSpeed 기준으로 스케일
		applyRatio("Run" .. suffix, config.runSpeed)
		applyRatio("Breathing" .. suffix, config.runSpeed)
		resetToBase("Walk" .. suffix)
	elseif self._isMoving then
		-- Walk 상태: Walk + Breathing을 walkSpeed 기준으로 스케일
		applyRatio("Walk" .. suffix, config.walkSpeed)
		applyRatio("Breathing" .. suffix, config.walkSpeed)
		resetToBase("Run" .. suffix)
	else
		-- Idle 상태: Walk/Run 모두 base로 리셋, Breathing은 walkSpeed 기준 유지
		resetToBase("Walk" .. suffix)
		resetToBase("Run" .. suffix)
		applyRatio("Breathing" .. suffix, config.walkSpeed)
	end
end

-- ─── 애니메이션 재생 헬퍼 ────────────────────────────────────────────────────

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

	-- 5. 새 클래스 기준으로 CycleRef 재계산
	self:_refreshCycleRefs()
end

function BasicMovementClient.Destroy(self: BasicMovementClient)
	self._maid:Destroy()
end

return BasicMovementClient
