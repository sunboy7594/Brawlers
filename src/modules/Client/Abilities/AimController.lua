--!strict
--[=[
	@class AimController

	조준 상태를 중앙에서 관리하는 서비스.

	조준 타입:
	- BasicAttack: 기본 공격
	- Skill:       스킬
	- Ultimate:    궁극기

	동작:
	- 새 조준 요청 시 기존 조준 취소 후 전환 (나중에 누른 것이 우선)
	- 우클릭(MouseButton2) → 현재 조준 취소
	- 좌클릭(MouseButton1) 해제 → confirm (발사)
	- 매 프레임 indicator:update 및 onAim 호출

	ShiftLock 연동:
	- ShiftLock 비활성: HRP LookVector를 조준 방향으로 사용 (마우스 레이캐스트 없음)
	- ShiftLock 활성:   AutoRotate를 끄고 카메라 방향으로 캐릭터를 매 프레임 회전,
	                    마우스 레이캐스트로 수평 조준 방향 계산
	- 조준 종료(발사/취소) 시 AutoRotate 복원
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraControllerClient = require("CameraControllerClient")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local Spring = require("Spring")

-- ─── 타입 정의 ───────────────────────────────────────────────────────────────

-- 인디케이터 공통 인터페이스 (duck typing)
type Indicator = {
	update: (self: any, origin: Vector3, direction: Vector3) -> (),
	show: (self: any) -> (),
	hide: (self: any) -> (),
	destroy: (self: any) -> (),
}

type OnFireCallback = (direction: Vector3, aimTime: number) -> ()
type OnCancelCallback = () -> ()
type OnAimCallback = (aimTime: number) -> ()

type AimState = {
	abilityType: string,
	indicator: Indicator,
	onFire: OnFireCallback,
	onCancel: OnCancelCallback,
	onAim: OnAimCallback?,
	startTime: number,
	maid: any, -- Maid
}

export type AimController = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_aimState: AimState?,
		_cameraController: any, -- CameraControllerClient
		_yawSpring: any, -- Spring<number> : 캐릭터 Y축 회전 보간
	},
	{} :: typeof({ __index = {} })
))

-- ─── 조준 타입 상수 ──────────────────────────────────────────────────────────

local AimController = {}
AimController.ServiceName = "AimController"
AimController.__index = AimController

AimController.AbilityType = {
	BasicAttack = "BasicAttack",
	Skill = "Skill",
	Ultimate = "Ultimate",
}

-- ─── 초기화 ──────────────────────────────────────────────────────────────────

function AimController.Init(self: AimController, serviceBag: ServiceBag.ServiceBag): ()
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._aimState = nil
	self._cameraController = serviceBag:GetService(CameraControllerClient)

	-- 캐릭터 Y축 회전 보간 스프링 (단위: 라디안)
	local yawSpring = Spring.new(0)
	yawSpring.Speed = 10 -- 높을수록 빠르게 추적
	yawSpring.Damper = 0.3 -- 임계 감쇠 (오버슈트 없음)
	self._yawSpring = yawSpring
end

function AimController.Start(self: AimController): ()
	-- 우클릭: 조준 취소
	self._maid:GiveTask(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:cancel()
		end
	end))

	-- 좌클릭 해제: confirm (발사)
	self._maid:GiveTask(UserInputService.InputEnded:Connect(function(input: InputObject, _processed: boolean)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:_confirm()
		end
	end))

	-- 매 프레임: 인디케이터 갱신 + onAim 호출 + (ShiftLock 시) 캐릭터 회전
	self._maid:GiveTask(RunService.Heartbeat:Connect(function()
		self:_onHeartbeat()
	end))
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	새 조준을 시작합니다.

	- 이미 같은 abilityType으로 조준 중이면 무시합니다.
	- 다른 abilityType이 조준 중이면 기존 onCancel()을 호출 후 교체합니다.
	- ShiftLock 활성 시 Humanoid.AutoRotate를 비활성화하고 yawSpring을 초기화합니다.

	@param abilityType string   AimController.AbilityType 중 하나
	@param indicator Indicator  인디케이터 객체
	@param onFire function      발사 콜백 (direction: Vector3, aimTime: number)
	@param onCancel function    취소 콜백
	@param onAim function?      매 프레임 콜백 (aimTime: number)
]=]
function AimController:startAim(
	abilityType: string,
	indicator: Indicator,
	onFire: OnFireCallback,
	onCancel: OnCancelCallback,
	onAim: OnAimCallback?
)
	local state = self._aimState

	-- 이미 같은 타입으로 조준 중이면 무시
	if state and state.abilityType == abilityType then
		return
	end

	-- 다른 타입이 조준 중이면 기존 취소
	if state then
		self:_cancelInternal()
	end

	-- ShiftLock 활성 시 AutoRotate 비활성화 + yawSpring 현재 HRP 방향으로 초기화
	if self._cameraController:IsShiftLocked() then
		local humanoid = self:_getHumanoid()
		if humanoid then
			humanoid.AutoRotate = false
		end

		-- 조준 시작 순간 HRP yaw로 스프링을 초기화해 순간이동 방지
		local hrp = self:_getHRP()
		if hrp then
			local look = hrp.CFrame.LookVector
			local currentYaw = math.atan2(-look.X, -look.Z)
			self._yawSpring.Position = currentYaw
			self._yawSpring.Target = currentYaw
		end
	end

	-- 새 조준 상태 설정
	local aimMaid = Maid.new()
	self._aimState = {
		abilityType = abilityType,
		indicator = indicator,
		onFire = onFire,
		onCancel = onCancel,
		onAim = onAim,
		startTime = os.clock(),
		maid = aimMaid,
	}

	indicator:show()
end

--[=[
	현재 조준을 취소합니다. onCancel 콜백을 호출합니다.
]=]
function AimController:cancel()
	if not self._aimState then
		return
	end
	self:_cancelInternal()
end

--[=[
	현재 조준 중 여부를 반환합니다.
]=]
function AimController:isAiming(): boolean
	return self._aimState ~= nil
end

-- ─── 내부 ────────────────────────────────────────────────────────────────────

-- 로컬 플레이어의 HumanoidRootPart를 반환
function AimController:_getHRP(): BasePart?
	local char = Players.LocalPlayer.Character
	if not char then
		return nil
	end
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- 로컬 플레이어의 Humanoid를 반환
function AimController:_getHumanoid(): Humanoid?
	local char = Players.LocalPlayer.Character
	if not char then
		return nil
	end
	return char:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

--[=[
	조준 방향을 계산합니다.

	- ShiftLock 비활성: HRP LookVector 수평 성분을 그대로 사용합니다.
	- ShiftLock 활성:   마우스 레이캐스트로 월드 타겟을 구한 뒤 HRP 기준 수평 방향으로 변환합니다.

	@return (origin: Vector3?, direction: Vector3?)
]=]
function AimController:_getAimDirection(): (Vector3?, Vector3?)
	local player = Players.LocalPlayer
	local char = player.Character
	if not char then
		return nil, nil
	end

	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return nil, nil
	end

	-- ShiftLock 비활성: 마우스 레이캐스트 없이 HRP LookVector 사용
	if not self._cameraController:IsShiftLocked() then
		local look = hrp.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		if flatLook.Magnitude < 0.001 then
			flatLook = Vector3.new(0, 0, -1)
		end
		return hrp.Position, flatLook.Unit
	end

	-- ShiftLock 활성: 마우스 레이캐스트로 수평 방향 계산
	local camera = workspace.CurrentCamera
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { char }

	local rayResult = workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
	local targetPos: Vector3 = if rayResult then rayResult.Position else (ray.Origin + ray.Direction * 100)

	-- 수평 방향 정규화
	local dirH = Vector3.new(targetPos.X - hrp.Position.X, 0, targetPos.Z - hrp.Position.Z)
	if dirH.Magnitude < 0.001 then
		-- 마우스가 캐릭터 바로 위인 경우 HRP LookVector 폴백
		local look = hrp.CFrame.LookVector
		dirH = Vector3.new(look.X, 0, look.Z)
	end

	return hrp.Position, dirH.Unit
end

--[=[
	ShiftLock 활성 시 카메라 수평 방향으로 캐릭터를 부드럽게 회전합니다.
	yawSpring을 통해 보간하여 순간이동 없이 자연스럽게 회전합니다.
]=]
function AimController:_updateCharacterRotation()
	local hrp = self:_getHRP()
	if not hrp then
		return
	end

	-- 카메라 수평 방향 → 목표 yaw 계산
	local lookVector = workspace.CurrentCamera.CFrame.LookVector
	local targetYaw = math.atan2(-lookVector.X, -lookVector.Z)

	-- 각도 불연속 방지: 현재 Target 기준으로 최단 경로 delta 계산 (-π ~ π wrap)
	local current = self._yawSpring.Target
	local delta = targetYaw - current
	if delta > math.pi then
		delta -= math.pi * 2
	end
	if delta < -math.pi then
		delta += math.pi * 2
	end
	self._yawSpring.Target = current + delta

	-- Spring.Position: lazy evaluation으로 현재 시각 기준 보간값 반환
	hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, self._yawSpring.Position, 0)
end

-- 좌클릭 해제 시 발사 처리
function AimController:_confirm()
	local state = self._aimState
	if not state then
		return
	end

	local aimTime = os.clock() - state.startTime
	local _, direction = self:_getAimDirection()
	if not direction then
		-- 방향 계산 실패 시 취소로 처리
		self:_cancelInternal()
		return
	end

	-- 인디케이터 숨기기 후 발사
	state.indicator:hide()
	local onFire = state.onFire
	state.maid:Destroy()
	self._aimState = nil

	-- AutoRotate 복원
	local humanoid = self:_getHumanoid()
	if humanoid then
		humanoid.AutoRotate = true
	end

	onFire(direction, aimTime)
end

-- 내부 취소: onCancel 호출 + 상태 정리
function AimController:_cancelInternal()
	local state = self._aimState
	if not state then
		return
	end

	state.indicator:hide()
	local onCancel = state.onCancel
	state.maid:Destroy()
	self._aimState = nil

	-- AutoRotate 복원
	local humanoid = self:_getHumanoid()
	if humanoid then
		humanoid.AutoRotate = true
	end

	onCancel()
end

-- 매 프레임: (ShiftLock 시) 캐릭터 회전 + 인디케이터 갱신 + onAim 호출
function AimController:_onHeartbeat()
	local state = self._aimState
	if not state then
		return
	end

	-- ShiftLock 활성 시 카메라 방향으로 캐릭터 부드럽게 회전
	if self._cameraController:IsShiftLocked() then
		self:_updateCharacterRotation()
	end

	local origin, direction = self:_getAimDirection()
	if not origin or not direction then
		return
	end

	state.indicator:update(origin, direction)

	local aimTime = os.clock() - state.startTime
	if state.onAim then
		state.onAim(aimTime)
	end
end

function AimController.Destroy(self: AimController)
	if self._aimState then
		self:_cancelInternal()
	end
	self._maid:Destroy()
end

return AimController
