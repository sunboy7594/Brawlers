--!strict
--[=[
    @class CameraControllerClient

    레이어 구조:
    [0] Custom 팔로우 + ShiftLock (토글)
    [1] Offset Modifier  → 시점 위치/FOV 조정 (Nevermore Spring)
    [2] Effect Modifier  → 후처리 효과 (shake/impulse)
    [3] Override         → 완전 점령 (컷신/MoonAnimator)

    ShiftLock은 UserInputService를 직접 사용합니다.
    MouseShiftLockService는 Roblox 기본 ShiftLock 기능 비활성화에 사용됩니다.
]=]

local require = require(script.Parent.loader).load(script)

local KeybindConfig = require("KeybindConfig")
local Maid = require("Maid")
local MouseShiftLockService = require("MouseShiftLockService")
local Spring = require("Spring")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraControllerClient = {}
CameraControllerClient.ServiceName = "CameraControllerClient"

local CAMERA_MIN_ZOOM = 10
local CAMERA_MAX_ZOOM = 15
local CAMERA_INIT_ZOOM = 12

local SHIFTLOCK_OFFSET = Vector3.new(1.8, -0.2, 0)
local DEFAULT_FOV = 70
local IMPULSE_SPEED = 15 -- impulse spring 감쇠 속도
local RESTORE_STIFFNESS = 200
local RESTORE_DAMPING = 10

-- Spring 변환 상수 (AnimationControllerClient와 동일)
local SPRING_SPEED_SCALE = 1.41
local SPRING_DAMPER_SCALE = 0.625

type OffsetModifier = {
	offset: Vector3,
	fov: number?,
	stiffness: number,
	damping: number,
}

type EffectModifier = (currentCF: CFrame, dt: number) -> CFrame

-- offset modifier별 Spring 쌍
type OffsetSprings = {
	pos: any, -- Spring<Vector3>
	fov: any, -- Spring<number>
}

export type CameraControllerClient = typeof(setmetatable(
	{} :: {
		_maid: any,
		_camera: Camera,
		_player: Player,
		_mouseShiftLockService: any,

		_isShiftLocked: boolean,
		_crosshair: ImageLabel?,

		_rawLookVector: Vector3, -- Effect 적용 전 순수 카메라 LookVector

		_offsetModifiers: { [string]: OffsetModifier },
		_offsetSprings: { [string]: OffsetSprings },
		_pendingRemovals: { [string]: boolean },

		_effectModifiers: { [string]: EffectModifier },

		_impulseSpring: any, -- Spring<Vector3>

		_currentOverride: ((camera: Camera, dt: number) -> ())?,
	},
	{} :: typeof({ __index = CameraControllerClient })
))

function CameraControllerClient.Init(self: CameraControllerClient, serviceBag: any)
	self._maid = Maid.new()
	self._camera = workspace.CurrentCamera
	self._player = Players.LocalPlayer

	-- Roblox 기본 ShiftLock 비활성화 (커스텀 ShiftLock과 충돌 방지)
	self._mouseShiftLockService = serviceBag:GetService(MouseShiftLockService)
	self._mouseShiftLockService:DisableShiftLock()

	self._isShiftLocked = false

	self._offsetModifiers = {}
	self._offsetSprings = {}
	self._pendingRemovals = {}
	self._effectModifiers = {}

	-- 충격 spring (Target 고정: Vector3.zero, Impulse로 속도를 부여)
	local impulseSpring = Spring.new(Vector3.zero)
	impulseSpring.Speed = IMPULSE_SPEED
	impulseSpring.Damper = 1
	self._impulseSpring = impulseSpring

	self._currentOverride = nil

	self._player.CameraMinZoomDistance = CAMERA_INIT_ZOOM
	self._player.CameraMaxZoomDistance = CAMERA_INIT_ZOOM
	task.defer(function()
		self._player.CameraMinZoomDistance = CAMERA_MIN_ZOOM
		self._player.CameraMaxZoomDistance = CAMERA_MAX_ZOOM
	end)

	self:_setupCrosshair()
end

function CameraControllerClient.Start(self: CameraControllerClient)
	local renderStepName = "CameraControllerUpdate"

	RunService:BindToRenderStep(renderStepName, Enum.RenderPriority.Camera.Value, function(dt)
		self:_update(dt)
	end)

	self._maid:GiveTask(function()
		RunService:UnbindFromRenderStep(renderStepName)
	end)

	self._maid:GiveTask(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == KeybindConfig.Binds.ShiftLock then
			self:ToggleShiftLock(not self._isShiftLocked)
		end
	end))
end

-- ============================================================
-- [Public] ShiftLock
-- ============================================================

function CameraControllerClient:ToggleShiftLock(enable: boolean)
	self._isShiftLocked = enable

	if self._crosshair then
		self._crosshair.Visible = enable
	end

	if enable then
		UserInputService.MouseIconEnabled = false
	else
		UserInputService.MouseIconEnabled = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end

function CameraControllerClient:IsShiftLocked(): boolean
	return self._isShiftLocked
end

-- Effect·Offset이 섞이지 않은 순수 조준용 LookVector 반환
function CameraControllerClient:GetAimLookVector(): Vector3
	return self._rawLookVector or self._camera.CFrame.LookVector
end

-- ============================================================
-- [Public] Offset Modifier
-- ============================================================

function CameraControllerClient:SetOffsetModifier(name: string, modifier: OffsetModifier)
	self._offsetModifiers[name] = modifier
	self._pendingRemovals[name] = nil -- 재등록 시 pending 취소

	-- Spring이 없으면 생성, 있으면 재사용
	if not self._offsetSprings[name] then
		local posSpring = Spring.new(Vector3.zero)
		local fovSpring = Spring.new(DEFAULT_FOV)
		self._offsetSprings[name] = { pos = posSpring, fov = fovSpring }
	end

	local speed = math.sqrt(modifier.stiffness) * SPRING_SPEED_SCALE
	local damper = math.clamp(modifier.damping * SPRING_DAMPER_SCALE, 0.4, 2.0)
	local springs = self._offsetSprings[name]

	springs.pos.Speed = speed
	springs.pos.Damper = damper
	springs.pos.Target = modifier.offset

	if modifier.fov then
		springs.fov.Speed = speed
		springs.fov.Damper = damper
		springs.fov.Target = modifier.fov
	end
end

function CameraControllerClient:RemoveOffsetModifier(name: string)
	local springs = self._offsetSprings[name]
	if not springs then
		return
	end

	-- spring 타겟을 기본값으로 전환 (빠른 수렴)
	local restoreSpeed = math.sqrt(RESTORE_STIFFNESS) * SPRING_SPEED_SCALE
	local restoreDamper = math.clamp(RESTORE_DAMPING * SPRING_DAMPER_SCALE, 0.4, 2.0)

	springs.pos.Speed = restoreSpeed
	springs.pos.Damper = restoreDamper
	springs.pos.Target = Vector3.zero

	local modifier = self._offsetModifiers[name]
	if modifier and modifier.fov then
		springs.fov.Speed = restoreSpeed
		springs.fov.Damper = restoreDamper
		springs.fov.Target = DEFAULT_FOV
	end

	self._pendingRemovals[name] = true
end

-- ============================================================
-- [Public] Effect Modifier
-- ============================================================

function CameraControllerClient:SetEffectModifier(name: string, modifier: EffectModifier)
	self._effectModifiers[name] = modifier
end

function CameraControllerClient:RemoveEffectModifier(name: string)
	self._effectModifiers[name] = nil
end

function CameraControllerClient:ApplyImpulse(impulse: Vector3)
	self._impulseSpring:Impulse(impulse)
end

-- ============================================================
-- [Public] Override
-- ============================================================

function CameraControllerClient:SetOverride(onUpdate: (camera: Camera, dt: number) -> ())
	self._currentOverride = onUpdate
end

function CameraControllerClient:ClearOverride()
	self._currentOverride = nil
	self._camera.CameraType = Enum.CameraType.Custom
end

-- ============================================================
-- [Internal] Update
-- ============================================================

function CameraControllerClient:_update(dt: number)
	local char = self._player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
	local hum = char and char:FindFirstChildWhichIsA("Humanoid") :: Humanoid

	-- [레이어 3] Override
	if self._currentOverride then
		self._camera.CameraType = Enum.CameraType.Scriptable
		self._currentOverride(self._camera, dt)
		return
	end

	-- [레이어 0] Custom 팔로우 + ShiftLock
	self._camera.CameraType = Enum.CameraType.Custom

	if self._isShiftLocked and root and hum then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end

	self._rawLookVector = self._camera.CFrame.LookVector

	-- [레이어 1] Offset Modifier (Spring 기반)
	local finalOffset = Vector3.zero
	local finalFov = DEFAULT_FOV

	for name, modifier in self._offsetModifiers do
		local springs = self._offsetSprings[name]
		if not springs then
			continue
		end

		-- Nevermore Spring: lazy evaluation (읽는 순간 현재 시각 기준으로 계산)
		finalOffset += springs.pos.Position

		if modifier.fov then
			finalFov = springs.fov.Position
		end

		-- pending: spring이 수렴했으면 완전 제거
		if self._pendingRemovals[name] then
			local posSettled = springs.pos.Position.Magnitude < 0.002 and (springs.pos :: any).Velocity.Magnitude < 0.01
			local fovSettled = not modifier.fov
				or (
					math.abs(springs.fov.Position - DEFAULT_FOV) < 0.1
					and math.abs((springs.fov :: any).Velocity) < 0.05
				)
			if posSettled and fovSettled then
				self._offsetModifiers[name] = nil
				self._offsetSprings[name] = nil
				self._pendingRemovals[name] = nil
			end
		end
	end

	self._camera.FieldOfView = finalFov

	-- ShiftLock 오프셋은 CFrame 적용 직전에 합산
	local appliedOffset = finalOffset + if self._isShiftLocked then SHIFTLOCK_OFFSET else Vector3.zero
	local finalCF = self._camera.CFrame * CFrame.new(appliedOffset)

	-- [레이어 2] Effect Modifier
	for _, effect in self._effectModifiers do
		finalCF = effect(finalCF, dt)
	end

	-- impulse spring 적용 (Target=zero, 자동 감쇠)
	local iv = self._impulseSpring.Position
	if (iv :: Vector3).Magnitude > 0.001 then
		finalCF = finalCF * CFrame.Angles(iv.X, iv.Y, iv.Z)
	end

	self._camera.CFrame = finalCF
end

-- ============================================================
-- [Internal] Crosshair
-- ============================================================

function CameraControllerClient:_setupCrosshair()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CameraCrosshair"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = self._player:WaitForChild("PlayerGui")

	local crosshair = Instance.new("ImageLabel")
	crosshair.Name = "CrosshairLabel"
	crosshair.Size = UDim2.fromOffset(32, 32)
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Position = UDim2.fromScale(0.5, 0.5)
	crosshair.BackgroundTransparency = 1
	crosshair.Image = "rbxassetid://6073628964"
	crosshair.Visible = false
	crosshair.Parent = screenGui

	self._crosshair = crosshair
	self._maid:GiveTask(screenGui)
end

function CameraControllerClient.Destroy(self: CameraControllerClient)
	self._maid:Destroy()
end

return CameraControllerClient
