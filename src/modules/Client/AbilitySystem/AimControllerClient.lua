--!strict
--[=[
	@class AimControllerClient

	조준 상태를 중앙에서 관리하는 순수 상태머신 서비스.
	입력 이벤트를 직접 구독하지 않으며, 각 ability Client가 호출함.

	조준 타입:
	- BasicAttack: 기본 공격
	- Skill:       스킬
	- Ultimate:    궁극기

	동작:
	- StartAim     : 새 조준 시작 (기존 AimSession 있으면 cancel 후 교체)
	- ConfirmAim   : 현재 조준 방향 확정 후 세션 종료 → direction 반환
	- Cancel       : 조준 취소 (우클릭 등 외부에서 호출)
	- IsAiming     : 조준 중 여부

	ShiftLock 연동 (lockYawDuringAim = true 인 경우에만):
	- ShiftLock 활성: AutoRotate 끄고 카메라 방향으로 캐릭터 회전
	- 조준 종료 시 AutoRotate 복원
	- toggle은 lockYawDuringAim = false 로 전달 → 화면 고정 없음

	interval 회전 잠금 (stack 전용):
	- StartIntervalLock(direction, duration): 발사 방향으로 캐릭터 스냅 + duration 동안 AutoRotate=false
	- CancelIntervalLock: 강제 해제
	- interval 진행 중 새 StartAim → StartAim 내에서 자동으로 CancelIntervalLock 호출

	우클릭 취소:
	- MouseButton2 → Cancel() (전역 조준 취소. Start()에서 구독)

	RenderStep:
	- 조준 중: lockYawDuringAim이면 ShiftLock 캐릭터 회전 + onAim 훅 실행
	- 미조준 + interval 잠금 중: yawSpring으로 HRP 방향 유지
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AbilityExecutor = require("AbilityExecutor")
local CameraControllerClient = require("CameraControllerClient")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local Spring = require("Spring")
local cancellableDelay = require("cancellableDelay")

-- ─── 타입 ────────────────────────────────────────────────────────────────────

type AimSession = {
	abilityType: string,
	clientModule: any,
	abilityState: any, -- BasicAttackState | SkillState | UltimateState
	startTime: number,
	maid: any,
	lockYawDuringAim: boolean, -- toggle: false, stack/hold: true
}

export type AimControllerClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_aimSession: AimSession?,
		_cameraController: any,
		_yawSpring: any,
		_intervalLockCancel: (() -> ())?,
		_intervalLockYaw: number?,
	},
	{} :: typeof({ __index = {} })
))

-- ─── 조준 타입 상수 ──────────────────────────────────────────────────────────

local AimControllerClient = {}
AimControllerClient.ServiceName = "AimControllerClient"
AimControllerClient.__index = AimControllerClient

AimControllerClient.AbilityType = {
	BasicAttack = "BasicAttack",
	Skill = "Skill",
	Ultimate = "Ultimate",
}

-- ─── 유틸 ────────────────────────────────────────────────────────────────────

local function normalizeAngleDelta(from: number, to: number): number
	local delta = to - from
	if delta > math.pi then
		delta -= math.pi * 2
	elseif delta < -math.pi then
		delta += math.pi * 2
	end
	return delta
end

-- ─── 초기화 ──────────────────────────────────────────────────────────────────

function AimControllerClient.Init(self: AimControllerClient, serviceBag: ServiceBag.ServiceBag): ()
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._aimSession = nil
	self._cameraController = serviceBag:GetService(CameraControllerClient)
	self._intervalLockCancel = nil
	self._intervalLockYaw = nil

	local yawSpring = Spring.new(0)
	yawSpring.Speed = 10
	yawSpring.Damper = 0.3
	self._yawSpring = yawSpring
end

function AimControllerClient.Start(self: AimControllerClient): ()
	-- 우클릭: 전역 조준 취소
	self._maid:GiveTask(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:Cancel()
		end
	end))

	RunService:BindToRenderStep("AimControllerClientUpdate", Enum.RenderPriority.Camera.Value + 1, function()
		self:_onRenderStep()
	end)
	self._maid:GiveTask(function()
		RunService:UnbindFromRenderStep("AimControllerClientUpdate")
	end)
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	새 조준을 시작합니다.
	기존 AimSession이 있으면 cancel 후 교체.
	interval 잠금이 활성 중이면 해제.

	@param abilityType      string    AimControllerClient.AbilityType 중 하나
	@param clientModule     table     공격 클라이언트 모듈
	@param abilityState     table     능력 상태 객체
	@param lockYawDuringAim boolean?  ShiftLock 활성 시 캐릭터 방향 고정 여부 (기본 true)
	                                  toggle: false 전달
]=]
function AimControllerClient:StartAim(
	abilityType: string,
	clientModule: any,
	abilityState: any,
	lockYawDuringAim: boolean?
)
	local doLock = if lockYawDuringAim == nil then true else lockYawDuringAim

	-- ❌ self:CancelIntervalLock() 제거
	--    interval lock은 StartAim으로 해제되지 않음
	--    _onRenderStep에서 lock 중 캐릭터 회전만 막으면 됨

	-- 기존 AimSession cancel
	if self._aimSession then
		self:_cancelInternal()
	end

	-- ShiftLock 연동: interval lock이 없을 때만 yaw 초기화
	if doLock and self._cameraController:IsShiftLocked() and not self._intervalLockCancel then
		local humanoid = self:_getHumanoid()
		if humanoid then
			humanoid.AutoRotate = false
		end
		local hrp = self:_getHRP()
		if hrp then
			local look = hrp.CFrame.LookVector
			local currentYaw = math.atan2(-look.X, -look.Z)
			self._yawSpring.Position = currentYaw
			self._yawSpring.Target = currentYaw
		end
	end

	self._aimSession = {
		abilityType = abilityType,
		clientModule = clientModule,
		abilityState = abilityState,
		startTime = os.clock(),
		maid = Maid.new(),
		lockYawDuringAim = doLock,
	}

	abilityState.indicator:showAll()
	AbilityExecutor.OnAimStart(clientModule, abilityState)
end

--[=[
	현재 조준을 확정합니다. direction을 반환하고 AimSession을 종료합니다.
	방향을 구할 수 없으면 nil 반환 후 _cancelInternal 호출.

	@return Vector3? 확정된 direction (단위벡터)
]=]
function AimControllerClient:ConfirmAim(): Vector3?
	local aimSession = self._aimSession
	if not aimSession then
		return nil
	end

	local origin, direction = self:_getAimDirection()
	if not direction then
		self:_cancelInternal()
		return nil
	end

	local abilityState = aimSession.abilityState
	abilityState.aimTime = os.clock() - aimSession.startTime
	abilityState.direction = direction
	abilityState.origin = origin or Vector3.zero

	abilityState.indicator:hideAll()

	-- AutoRotate 복원 (lockYawDuringAim인 경우)
	-- interval lock이 없을 때만 복원 (StartIntervalLock이 직후에 걸지만 방어적으로)
	if aimSession.lockYawDuringAim and not self._intervalLockCancel then
		local humanoid = self:_getHumanoid()
		if humanoid then
			humanoid.AutoRotate = true
		end
	end

	aimSession.maid:Destroy()
	self._aimSession = nil

	return direction
end

--[=[
	현재 조준을 취소합니다.
]=]
function AimControllerClient:Cancel()
	if not self._aimSession then
		return
	end
	self:_cancelInternal()
end

--[=[
	stack 전용: 발사 방향으로 캐릭터를 스냅하고 duration 동안 AutoRotate=false 유지.
	duration 만료 시 자동 복원.
]=]
function AimControllerClient:StartIntervalLock(direction: Vector3, duration: number)
	-- 기존 잠금 교체
	if self._intervalLockCancel then
		self._intervalLockCancel()
		self._intervalLockCancel = nil
	end

	local humanoid = self:_getHumanoid()
	local hrp = self:_getHRP()
	if not humanoid or not hrp then
		return
	end

	humanoid.AutoRotate = false

	local rawYaw = math.atan2(-direction.X, -direction.Z)
	local currentLook = hrp.CFrame.LookVector
	local currentYaw = math.atan2(-currentLook.X, -currentLook.Z)
	local targetYaw = currentYaw + normalizeAngleDelta(currentYaw, rawYaw)

	self._yawSpring.Position = currentYaw
	self._yawSpring.Target = targetYaw
	self._intervalLockYaw = targetYaw

	if duration > 0 then
		self._intervalLockCancel = cancellableDelay(duration, function()
			self._intervalLockCancel = nil
			self._intervalLockYaw = nil
			if humanoid and humanoid.Parent then
				humanoid.AutoRotate = true
			end
		end)
	else
		self._intervalLockYaw = nil
		humanoid.AutoRotate = true
	end
end

--[=[
	interval 회전 잠금을 즉시 해제합니다.
	능력 교체, CancelCombatState 등 외부 초기화 시 호출합니다.
]=]
function AimControllerClient:CancelIntervalLock()
	if self._intervalLockCancel then
		self._intervalLockCancel()
		self._intervalLockCancel = nil
	end
	self._intervalLockYaw = nil
	local humanoid = self:_getHumanoid()
	if humanoid and humanoid.Parent then
		humanoid.AutoRotate = true
	end
end

function AimControllerClient:IsAiming(): boolean
	return self._aimSession ~= nil
end

-- ─── 내부 ────────────────────────────────────────────────────────────────────

function AimControllerClient:_getHRP(): BasePart?
	local char = Players.LocalPlayer.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart? or nil
end

function AimControllerClient:_getHumanoid(): Humanoid?
	local char = Players.LocalPlayer.Character
	return char and char:FindFirstChildOfClass("Humanoid") :: Humanoid? or nil
end

function AimControllerClient:_getAimDirection(): (Vector3?, Vector3?)
	local char = Players.LocalPlayer.Character
	if not char then
		return nil, nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return nil, nil
	end

	if not self._cameraController:IsShiftLocked() then
		local look = hrp.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.001 then
			flat = Vector3.new(0, 0, -1)
		end
		return hrp.Position, flat.Unit
	end

	local lookVector = self._cameraController:GetAimLookVector()
	local dirH = Vector3.new(lookVector.X, 0, lookVector.Z)
	if dirH.Magnitude < 0.001 then
		local look = hrp.CFrame.LookVector
		dirH = Vector3.new(look.X, 0, look.Z)
	end
	return hrp.Position, dirH.Unit
end

function AimControllerClient:_updateCharacterRotation()
	local hrp = self:_getHRP()
	if not hrp then
		return
	end

	local lookVector = self._cameraController:GetAimLookVector()
	local targetYaw = math.atan2(-lookVector.X, -lookVector.Z)

	local current = self._yawSpring.Target
	local delta = normalizeAngleDelta(current, targetYaw)
	self._yawSpring.Target = current + delta

	hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, self._yawSpring.Position, 0)
end

function AimControllerClient:_cancelInternal()
	local aimSession = self._aimSession
	if not aimSession then
		return
	end

	local abilityState = aimSession.abilityState
	abilityState.indicator:hideAll()
	abilityState.aimTime = 0
	abilityState.effectiveAimTime = 0

	-- interval lock이 활성 중이면 AutoRotate 복원하지 않음
	-- interval lock 종료 시 cancellableDelay 콜백에서 자동 복원됨
	if aimSession.lockYawDuringAim and not self._intervalLockCancel then
		local humanoid = self:_getHumanoid()
		if humanoid then
			humanoid.AutoRotate = true
		end
	end

	aimSession.maid:Destroy()
	self._aimSession = nil
end

function AimControllerClient:_onRenderStep()
	local aimSession = self._aimSession

	-- [미조준 상태] interval 잠금 유지
	if not aimSession then
		if self._intervalLockCancel and self._intervalLockYaw then
			local hrp = self:_getHRP()
			if hrp then
				hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, self._yawSpring.Position, 0)
			end
		end
		return
	end

	-- [조준 상태] ShiftLock 연동
	-- interval lock 중이면 캐릭터 방향 업데이트 스킵 (발사 방향 고정 유지)
	if
		aimSession.lockYawDuringAim
		and self._cameraController:IsShiftLocked()
		and not self._intervalLockCancel -- ← 추가
	then
		self:_updateCharacterRotation()
	end

	-- interval lock 중에도 hrp 방향은 lock yaw로 유지
	if self._intervalLockCancel and self._intervalLockYaw then
		local hrp = self:_getHRP()
		if hrp then
			hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, self._yawSpring.Position, 0)
		end
	end

	local origin, direction = self:_getAimDirection()
	if not origin or not direction then
		return
	end

	local abilityState = aimSession.abilityState
	abilityState.aimTime = os.clock() - aimSession.startTime
	abilityState.direction = direction
	abilityState.origin = origin

	AbilityExecutor.OnAim(aimSession.clientModule, abilityState)
end

function AimControllerClient.Destroy(self: AimControllerClient)
	self:CancelIntervalLock()
	if self._aimSession then
		self:_cancelInternal()
	end
	self._maid:Destroy()
end

return AimControllerClient
