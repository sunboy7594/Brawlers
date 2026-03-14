--!strict
--[=[
	@class AimController

	조준 상태를 중앙에서 관리하는 서비스.

	조준 타입:
	- BasicAttack: 기본 공격
	- Skill:       스킬
	- Ultimate:    궁극기

	동작:
	- 새 조준 요청 시 기존 조준 취소 후 전환
	- 우클릭(MouseButton2) → 현재 조준 취소
	- 좌클릭(MouseButton1) 해제 → confirm (발사)
	- 매 프레임 onAim 배열 실행 → IndicatorUpdateParams 병합 → indicator:update()

	ShiftLock 연동:
	- ShiftLock 비활성: HRP LookVector 수평 성분 사용
	- ShiftLock 활성: AutoRotate 끄고 카메라 방향으로 캐릭터 회전
	- 조준 종료 시 AutoRotate 복원

	postFire 회전 잠금:
	- 발사 확정 시 HRP를 조준방향으로 스냅
	- postFireDuration 동안 AutoRotate = false 유지
	- cancellableDelay로 복원 → 새 조준 시작 시 취소 가능

	클라이언트 공격 모듈 훅 (AbilityExecutor가 실행):
	- OnAimStart: { (ctx) -> () }?  조준 시작 1회
	- OnAim:      { (ctx) -> () }?  매 프레임, ctx.indicator 직접 업데이트
	- OnFire:     { (ctx) -> () }?  발사 확정 후
	취소 시: indicator hide만 (onCancel 없음)
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
	ctx: any,
	onFireServer: (direction: Vector3) -> (),
	startTime: number,
	maid: any,
	postFireDuration: number, -- 발사 후 AutoRotate 잠금 시간 (초)
}

export type AimController = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_aimState: AimState?,
		_cameraController: any,
		_yawSpring: any,
		_postFireCancel: (() -> ())?, -- cancellableDelay 취소 함수
		_postFireYaw: number?, -- postFire spring이 향할 목표 yaw
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
	self._postFireCancel = nil
	self._postFireYaw = nil

	local yawSpring = Spring.new(0)
	yawSpring.Speed = 10
	yawSpring.Damper = 0.3
	self._yawSpring = yawSpring
end

function AimController.Start(self: AimController): ()
	-- 우클릭: 조준 취소
	self._maid:GiveTask(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:Cancel()
		end
	end))

	-- 좌클릭 해제: 발사
	self._maid:GiveTask(UserInputService.InputEnded:Connect(function(input: InputObject, _processed: boolean)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:_confirm()
		end
	end))

	RunService:BindToRenderStep("AimControllerUpdate", Enum.RenderPriority.Camera.Value + 1, function()
		self:_onRenderStep()
	end)
	self._maid:GiveTask(function()
		RunService:UnbindFromRenderStep("AimControllerUpdate")
	end)
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	새 조준을 시작합니다.

	@param abilityType      string                       AimController.AbilityType 중 하나
	@param clientModule     table                        공격 클라이언트 모듈
	@param ctx              table                        BasicAttackClient가 소유하는 ClientContext
	@param onFireServer     (direction: Vector3) -> ()   서버 전송 콜백
	@param postFireDuration number?                      발사 후 AutoRotate 잠금 시간 (기본 0)
]=]
function AimController:StartAim(
	abilityType: string,
	clientModule: any,
	ctx: any,
	onFireServer: (direction: Vector3) -> (),
	postFireDuration: number?
)
	local state = self._aimState

	-- 이미 같은 타입으로 조준 중이면 무시
	if state and state.abilityType == abilityType then
		return
	end

	-- 다른 타입이 조준 중이면 취소
	if state then
		self:_cancelInternal()
	end

	-- postFire 잠금 타이머가 남아있으면 취소
	-- (새 조준이 시작됐으므로 AutoRotate 복원 필요 없음 — 아래에서 직접 관리)
	if self._postFireCancel then
		self._postFireCancel()
		self._postFireCancel = nil
	end

	-- ShiftLock 활성 시 AutoRotate 비활성 + yawSpring 초기화
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
		ctx = ctx,
		onFireServer = onFireServer,
		startTime = os.clock(),
		maid = Maid.new(),
		postFireDuration = postFireDuration or 0,
	}

	-- 인디케이터 표시
	ctx.indicator:show()

	-- onAimStart 배열 실행
	AbilityExecutor.OnAimStart(clientModule, ctx)
end

--[=[
	현재 조준을 취소합니다.
]=]
function AimController:Cancel()
	if not self._aimState then
		return
	end
	self:_cancelInternal()
end

--[=[
	현재 조준 중 여부를 반환합니다.
]=]
function AimController:IsAiming(): boolean
	return self._aimState ~= nil
end

-- ─── 내부 ────────────────────────────────────────────────────────────────────

function AimController:_getHRP(): BasePart?
	local char = Players.LocalPlayer.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart? or nil
end

function AimController:_getHumanoid(): Humanoid?
	local char = Players.LocalPlayer.Character
	return char and char:FindFirstChildOfClass("Humanoid") :: Humanoid? or nil
end

function AimController:_getAimDirection(): (Vector3?, Vector3?)
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

function AimController:_updateCharacterRotation()
	local hrp = self:_getHRP()
	if not hrp then
		return
	end

	local lookVector = self._cameraController:GetAimLookVector()
	local targetYaw = math.atan2(-lookVector.X, -lookVector.Z)

	local current = self._yawSpring.Target
	local delta = targetYaw - current
	if delta > math.pi then
		delta -= math.pi * 2
	end
	if delta < -math.pi then
		delta += math.pi * 2
	end
	self._yawSpring.Target = current + delta

	hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, self._yawSpring.Position, 0)
end

-- 좌클릭 해제 시 발사
function AimController:_confirm()
	local state = self._aimState
	if not state then
		return
	end

	local origin, direction = self:_getAimDirection()
	if not direction then
		self:_cancelInternal()
		return
	end

	-- ctx 갱신
	local ctx = state.ctx
	ctx.aimTime = os.clock() - state.startTime
	ctx.direction = direction
	ctx.origin = origin or Vector3.zero

	-- 인디케이터 숨기기
	ctx.indicator:hide()

	local clientModule = state.clientModule
	local onFireServer = state.onFireServer
	local postFireDuration = state.postFireDuration

	state.maid:Destroy()
	self._aimState = nil

	-- ── postFire 회전 고정 ────────────────────────────────────────────────────
	-- AutoRotate를 끄고 HRP를 조준방향으로 즉시 스냅한 뒤,
	-- postFireDuration 후 cancellableDelay로 복원.
	-- 새 조준이 시작되면 startAim에서 _postFireCancel()을 호출해 타이머를 취소.
	local humanoid = self:_getHumanoid()
	local hrp = self:_getHRP()

	if humanoid and hrp then
		humanoid.AutoRotate = false

		-- 발사 방향 yaw 계산
		local yaw = math.atan2(-direction.X, -direction.Z)

		-- spring 현재 위치를 HRP 실제 yaw로 초기화 (단타 시 spring이 미초기화 상태일 수 있음)
		local currentLook = hrp.CFrame.LookVector
		local currentYaw = math.atan2(-currentLook.X, -currentLook.Z)
		self._yawSpring.Position = currentYaw
		self._yawSpring.Target = yaw -- 즉시 스냅 대신 spring이 부드럽게 이동
		self._postFireYaw = yaw

		if postFireDuration > 0 then
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
	-- ─────────────────────────────────────────────────────────────────────────

	-- onFire 배열 실행 (클라이언트 측 애니메이션/이펙트)
	AbilityExecutor.OnFire(clientModule, ctx)

	-- 서버 전송
	onFireServer(direction)
end

-- 취소: indicator hide만, postFire 타이머는 건드리지 않음
function AimController:_cancelInternal()
	local state = self._aimState
	if not state then
		return
	end

	state.ctx.indicator:hide()
	state.maid:Destroy()
	self._aimState = nil

	-- ShiftLock 조준 중에 취소된 경우 AutoRotate 즉시 복원
	local humanoid = self:_getHumanoid()
	if humanoid then
		humanoid.AutoRotate = true
	end
end

-- 매 프레임
function AimController:_onRenderStep()
	local state = self._aimState
	if not state then
		-- postFire 중이면 spring이 목표 방향까지 부드럽게 회전 계속 구동
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

	-- ctx 갱신
	local ctx = state.ctx
	ctx.aimTime = os.clock() - state.startTime
	ctx.direction = direction
	ctx.origin = origin

	-- 매 프레임 기본 위치/방향 업데이트
	ctx.indicator:update({ origin = origin, direction = direction })

	-- onAim 배열 실행
	AbilityExecutor.OnAim(state.clientModule, ctx)
end

function AimController.Destroy(self: AimController)
	if self._postFireCancel then
		self._postFireCancel()
		self._postFireCancel = nil
	end
	if self._aimState then
		self:_cancelInternal()
	end
	self._maid:Destroy()
end

return AimController
