--!strict
--[=[
	@class AimControllerClient

	조준 상태를 중앙에서 관리하는 서비스.

	조준 타입:
	- BasicAttack: 기본 공격
	- Skill:       스킬
	- Ultimate:    궁극기

	동작:
	- 새 조준 요청 시 기존 조준 취소 후 전환
	- 우클릭(MouseButton2) → 현재 조준 취소
	- 좌클릭(MouseButton1) 해제 → confirm (발사)
	- 매 프레임 onAim 배열 실행 (origin/direction은 abilityState에 세팅 후 모듈이 직접 indicator 업데이트)

	ShiftLock 연동:
	- ShiftLock 비활성: HRP LookVector 수평 성분 사용
	- ShiftLock 활성: AutoRotate 끄고 카메라 방향으로 캐릭터 회전
	- 조준 종료 시 AutoRotate 복원

	postFire 회전 잠금:
	- 발사 확정 시 HRP를 조준방향으로 스냅
	- postFireDuration 동안 AutoRotate = false 유지
	- cancellableDelay로 복원 → 새 조준 시작 시 취소 가능
	- 새 postFire 설정 전 기존 타이머를 반드시 취소
	  (미취소 시: 구 타이머가 나중에 터지면서 새 잠금의 _postFireYaw를 nil로 덮어 방향 잠금 해제됨)

	클라이언트 공격 모듈 훅 (AbilityExecutor가 실행):
	- OnAimStart: { (abilityState) -> () }?  조준 시작 1회
	- OnAim:      { (abilityState) -> () }?  매 프레임, abilityState.indicator 직접 업데이트
	- OnFire:     { (abilityState) -> () }?  발사 확정 후 — onFireServer 콜백 내부에서 호출됨
	취소 시: indicator hideAll만 (onCancel 없음)
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

type AimState = {
	abilityType: string,
	clientModule: any,
	abilityState: any,
	onFireServer: (direction: Vector3) -> (),
	startTime: number,
	maid: any,
	postFireDuration: number,
}

export type AimControllerClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_aimState: AimState?,
		_cameraController: any,
		_yawSpring: any,
		_postFireCancel: (() -> ())?,
		_postFireYaw: number?,
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
	self._aimState = nil
	self._cameraController = serviceBag:GetService(CameraControllerClient)
	self._postFireCancel = nil
	self._postFireYaw = nil

	local yawSpring = Spring.new(0)
	yawSpring.Speed = 10
	yawSpring.Damper = 0.3
	self._yawSpring = yawSpring
end

function AimControllerClient.Start(self: AimControllerClient): ()
	self._maid:GiveTask(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:Cancel()
		end
	end))

	self._maid:GiveTask(UserInputService.InputEnded:Connect(function(input: InputObject, _processed: boolean)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:_confirm()
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

	@param abilityType      string                       AimControllerClient.AbilityType 중 하나
	@param clientModule     table                        공격 클라이언트 모듈
	@param abilityState     table                        능력 상태 객체 (BasicAttackState 등)
	@param onFireServer     (direction: Vector3) -> ()   서버 전송 콜백
	@param postFireDuration number?                      발사 후 AutoRotate 잠금 시간 (기본 0)
]=]
function AimControllerClient:StartAim(
	abilityType: string,
	clientModule: any,
	abilityState: any,
	onFireServer: (direction: Vector3) -> (),
	postFireDuration: number?
)
	local state = self._aimState

	if state and state.abilityType == abilityType then
		return
	end

	if state then
		self:_cancelInternal()
	end

	if self._cameraController:IsShiftLocked() then
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

	self._aimState = {
		abilityType = abilityType,
		clientModule = clientModule,
		abilityState = abilityState,
		onFireServer = onFireServer,
		startTime = os.clock(),
		maid = Maid.new(),
		postFireDuration = postFireDuration or 0,
	}

	abilityState.indicator:showAll()
	AbilityExecutor.OnAimStart(clientModule, abilityState)
end

--[=[
	현재 조준을 취소합니다.
]=]
function AimControllerClient:Cancel()
	if not self._aimState then
		return
	end
	self:_cancelInternal()
end

--[=[
	postFire 회전 잠금을 즉시 해제합니다.
	무기 교체 등 외부에서 전투 상태를 초기화할 때 호출합니다.
]=]
function AimControllerClient:CancelPostFire()
	if self._postFireCancel then
		self._postFireCancel()
		self._postFireCancel = nil
	end
	self._postFireYaw = nil
	local humanoid = self:_getHumanoid()
	if humanoid and humanoid.Parent then
		humanoid.AutoRotate = true
	end
end

function AimControllerClient:IsAiming(): boolean
	return self._aimState ~= nil
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

function AimControllerClient:_confirm()
	local state = self._aimState
	if not state then
		return
	end

	local origin, direction = self:_getAimDirection()
	if not direction then
		self:_cancelInternal()
		return
	end

	local abilityState = state.abilityState
	abilityState.aimTime = os.clock() - state.startTime
	abilityState.direction = direction
	abilityState.origin = origin or Vector3.zero

	abilityState.indicator:hideAll()

	local onFireServer = state.onFireServer
	local postFireDuration = state.postFireDuration

	state.maid:Destroy()
	self._aimState = nil

	local isFired = onFireServer(direction)

	local humanoid = self:_getHumanoid()
	local hrp = self:_getHRP()

	if isFired and humanoid and hrp then
		humanoid.AutoRotate = false

		local rawYaw = math.atan2(-direction.X, -direction.Z)
		local currentLook = hrp.CFrame.LookVector
		local currentYaw = math.atan2(-currentLook.X, -currentLook.Z)
		local targetYaw = currentYaw + normalizeAngleDelta(currentYaw, rawYaw)

		self._yawSpring.Position = currentYaw
		self._yawSpring.Target = targetYaw
		self._postFireYaw = targetYaw

		if postFireDuration > 0 then
			if self._postFireCancel then
				self._postFireCancel()
				self._postFireCancel = nil
			end
			self._postFireCancel = cancellableDelay(postFireDuration, function()
				self._postFireCancel = nil
				self._postFireYaw = nil
				if humanoid and humanoid.Parent then
					humanoid.AutoRotate = true
				end
			end)
		else
			self._postFireYaw = nil
			humanoid.AutoRotate = true
		end
	end
end

function AimControllerClient:_cancelInternal()
	local state = self._aimState
	if not state then
		return
	end

	state.abilityState.indicator:hideAll()
	state.maid:Destroy()
	self._aimState = nil

	local humanoid = self:_getHumanoid()
	if humanoid then
		humanoid.AutoRotate = true
	end
end

function AimControllerClient:_onRenderStep()
	local state = self._aimState
	if not state then
		if self._postFireCancel and self._postFireYaw then
			local hrp = self:_getHRP()
			if hrp then
				hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, self._yawSpring.Position, 0)
			end
		end
		return
	end

	if self._cameraController:IsShiftLocked() then
		self:_updateCharacterRotation()
	end

	local origin, direction = self:_getAimDirection()
	if not origin or not direction then
		return
	end

	local abilityState = state.abilityState
	abilityState.aimTime = os.clock() - state.startTime
	abilityState.direction = direction
	abilityState.origin = origin

	-- origin/direction은 abilityState에만 세팅.
	-- indicator 업데이트는 각 모듈의 onAim에서 담당.
	AbilityExecutor.OnAim(state.clientModule, abilityState)
end

function AimControllerClient.Destroy(self: AimControllerClient)
	if self._postFireCancel then
		self._postFireCancel()
		self._postFireCancel = nil
	end
	if self._aimState then
		self:_cancelInternal()
	end
	self._maid:Destroy()
end

return AimControllerClient
