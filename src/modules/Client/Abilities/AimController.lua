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
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Maid = require("Maid")
local ServiceBag = require("ServiceBag")

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

	-- 매 프레임: 인디케이터 갱신 + onAim 호출
	self._maid:GiveTask(RunService.Heartbeat:Connect(function()
		self:_onHeartbeat()
	end))
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	새 조준을 시작합니다.

	- 이미 같은 abilityType으로 조준 중이면 무시합니다.
	- 다른 abilityType이 조준 중이면 기존 onCancel()을 호출 후 교체합니다.

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

-- 마우스 위치 → 월드 Raycast → HumanoidRootPart 기준 수평 방향 계산
function AimController:_getAimDirection(): (Vector3?, Vector3?)
	local player = Players.LocalPlayer
	local char = player.Character
	if not char then
		return nil
	end

	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return nil
	end

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
		dirH = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	end

	return hrp.Position, dirH.Unit
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

	onCancel()
end

-- 매 프레임: 인디케이터 갱신 + onAim 호출
function AimController:_onHeartbeat()
	local state = self._aimState
	if not state then
		return
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
