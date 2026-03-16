--!strict
--[=[
	@class PlayerStateClient

	서버로부터 PlayerState effect를 수신하여 클라이언트 연출을 실행합니다.

	담당:
	- PlayerStateRemoting.EffectApplied 수신 → tag별 연출 실행
	- PlayerStateRemoting.EffectRemoved 수신 → 진행 중인 루프 연출 조기 종료
	- component에서 cameraLock 수신 → 카메라 방향 고정
	- component에서 ragdoll(special) 수신 → 래그돌 처리

	tag 처리 흐름:
	  anim_*   → PlayerStateAnimDef   → EntityAnimator (진입+루프 자동 전환)
	  cam_*    → PlayerStateCameraAnimDef → CameraAnimator
	  screen_* → PlayerStateScreenEffectDef → ScreenEffectController (stub)
	  vfx_*   → PlayerStateVfxDef    → VfxController (stub)

	조기 종료 (EffectRemoved):
	  서버가 effect를 조기 제거하면 payloadId로 매핑된
	  루프 연출을 즉시 종료합니다.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local AnimationControllerClient = require("AnimationControllerClient")
local CameraAnimator = require("CameraAnimator")
local CameraControllerClient = require("CameraControllerClient")
local EntityAnimator = require("EntityAnimator")
local Maid = require("Maid")
local PlayerBinderClient = require("PlayerBinderClient")
local PlayerStateAnimDef = require("PlayerStateAnimDef")
local PlayerStateCameraAnimDef = require("PlayerStateCameraAnimDef")
local PlayerStateDefs = require("PlayerStateDefs")
local PlayerStateRemoting = require("PlayerStateRemoting")
local PlayerStateScreenEffectDef = require("PlayerStateScreenEffectDef")
local PlayerStateVfxDef = require("PlayerStateVfxDef")
local ServiceBag = require("ServiceBag")

local OWNER = "PlayerState"

type ActiveTagEffect = {
	stop: () -> (),
}

export type PlayerStateClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_animController: AnimationControllerClient.AnimationControllerClient,
		_cameraController: any,
		_playerBinder: any,
		_joints: { [string]: Motor6D }?,
		_entityAnimator: any?,
		_cameraAnimator: any,
		_activeEffects: { [string]: { [string]: ActiveTagEffect } },
		_cameraLockCancel: (() -> ())?,
	},
	{} :: typeof({ __index = {} })
))

local PlayerStateClient = {}
PlayerStateClient.ServiceName = "PlayerStateClient"
PlayerStateClient.__index = PlayerStateClient

function PlayerStateClient.Init(self: PlayerStateClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._animController = serviceBag:GetService(AnimationControllerClient)
	self._cameraController = serviceBag:GetService(CameraControllerClient)
	self._playerBinder = serviceBag:GetService(PlayerBinderClient)
	self._joints = nil
	self._entityAnimator = nil
	self._activeEffects = {}
	self._cameraLockCancel = nil
	local HitReactionCameraAnimDef = require("HitReactionCameraAnimDef")
	self._cameraAnimator = CameraAnimator.new(OWNER, HitReactionCameraAnimDef, self._cameraController)
	self._maid:GiveTask(self._cameraAnimator)
end

function PlayerStateClient.Start(self: PlayerStateClient): ()
	self._maid:GiveTask(self._playerBinder.JointsChanged:Connect(function(joints)
		self._joints = joints
		self:_rebuildEntityAnimator(joints)
	end))
	self._maid:GiveTask(PlayerStateRemoting.EffectApplied:Connect(
		function(effectDef: unknown, payloadId: unknown)
			self:_onEffectApplied(effectDef :: PlayerStateDefs.EffectDef, payloadId :: string?)
		end
	))
	self._maid:GiveTask(PlayerStateRemoting.EffectRemoved:Connect(
		function(payloadId: unknown)
			self:_onEffectRemoved(payloadId :: string)
		end
	))
end

function PlayerStateClient:_rebuildEntityAnimator(joints: { [string]: Motor6D }?)
	if self._entityAnimator then
		self._entityAnimator:Destroy()
		self._entityAnimator = nil
	end
	if not joints then return end
	local HitReactionAnimDef = require("HitReactionAnimDef")
	self._entityAnimator = EntityAnimator.new(OWNER, "HitReactionAnimDef", joints, HitReactionAnimDef, self._animController)
end

function PlayerStateClient:_onEffectApplied(effectDef: PlayerStateDefs.EffectDef, payloadId: string?)
	local tags = effectDef.tags
	local components = effectDef.components
	local pid = payloadId or ("auto_" .. tostring(os.clock()))
	self._activeEffects[pid] = {}
	if tags then
		for _, tag in tags do
			local activeEffect = self:_playTag(tag, components)
			if activeEffect then
				self._activeEffects[pid][tag.name] = activeEffect
			end
		end
	end
	if components then
		for _, comp in components do
			local c = comp :: any
			if c.type == "cameraLock" then
				self:_applyCameraLock(c.duration)
			end
		end
	end
end

function PlayerStateClient:_onEffectRemoved(payloadId: string)
	local effects = self._activeEffects[payloadId]
	if not effects then return end
	for _, activeEffect in effects do
		activeEffect.stop()
	end
	self._activeEffects[payloadId] = nil
end

function PlayerStateClient:_playTag(tag: PlayerStateDefs.TagEntry, components: { PlayerStateDefs.Component }?): ActiveTagEffect?
	local name = tag.name
	if name:sub(1, 5) == "anim_" then
		return self:_playAnimTag(tag, components)
	elseif name:sub(1, 4) == "cam_" then
		return self:_playCamTag(tag, components)
	elseif name:sub(1, 7) == "screen_" then
		return self:_playScreenTag(tag)
	elseif name:sub(1, 4) == "vfx_" then
		return self:_playVfxTag(tag)
	end
	return nil
end

function PlayerStateClient:_playAnimTag(tag: PlayerStateDefs.TagEntry, _components: { PlayerStateDefs.Component }?): ActiveTagEffect?
	local entityAnimator = self._entityAnimator
	if not entityAnimator then return nil end
	local resolved = PlayerStateAnimDef.resolve(tag.name, tag.intensity)
	if not resolved then return nil end
	if resolved.special then
		return self:_handleSpecialAnim(resolved.special, tag)
	end
	local animKey = resolved.animKey
	if not animKey then return nil end
	local loopAnimKey = resolved.loopAnimKey
	local startTime = os.clock()
	local stopped = false
	if loopAnimKey then
		entityAnimator:PlayAnimation(animKey, nil, function()
			if stopped then return end
			local remaining = tag.duration - (os.clock() - startTime)
			if remaining > 0.05 then
				entityAnimator:PlayAnimation(loopAnimKey, remaining, nil, true)
			end
		end, true)
	else
		entityAnimator:PlayAnimation(animKey, tag.duration, nil, true)
	end
	return {
		stop = function()
			if stopped then return end
			stopped = true
			entityAnimator:StopAnimation(animKey)
			if loopAnimKey then entityAnimator:StopAnimation(loopAnimKey) end
		end,
	}
end

function PlayerStateClient:_handleSpecialAnim(special: string, tag: PlayerStateDefs.TagEntry): ActiveTagEffect?
	if special == "ragdoll" then
		return self:_applyRagdoll(tag.duration, tag.intensity)
	end
	return nil
end

function PlayerStateClient:_applyRagdoll(duration: number, _intensity: number): ActiveTagEffect?
	local char = Players.LocalPlayer.Character
	if not char then return nil end
	local disabledJoints: { Motor6D } = {}
	for _, desc in char:GetDescendants() do
		if desc:IsA("Motor6D") then
			desc.Enabled = false
			table.insert(disabledJoints, desc)
		end
	end
	local ragdollMaid = Maid.new()
	local function restoreRagdoll()
		for _, joint in disabledJoints do
			if joint and joint.Parent then joint.Enabled = true end
		end
		ragdollMaid:Destroy()
	end
	local thread = task.delay(duration, restoreRagdoll)
	ragdollMaid:GiveTask(function() task.cancel(thread) end)
	return { stop = restoreRagdoll }
end

function PlayerStateClient:_playCamTag(tag: PlayerStateDefs.TagEntry, components: { PlayerStateDefs.Component }?): ActiveTagEffect?
	local mapping = PlayerStateCameraAnimDef[tag.name]
	if not mapping then return nil end
	local cameraAnimKey = mapping.cameraAnimKey
	if not cameraAnimKey then return nil end
	if mapping.knockbackRef and components then
		for _, comp in components do
			local c = comp :: any
			if c.type == "knockback" and c.direction then
				-- TODO: direction 주입 확장
				break
			end
		end
	end
	self._cameraAnimator:PlayAnimation(cameraAnimKey, tag.duration, nil, true)
	return { stop = function() self._cameraAnimator:Stop(cameraAnimKey) end }
end

function PlayerStateClient:_playScreenTag(tag: PlayerStateDefs.TagEntry): ActiveTagEffect?
	local def = PlayerStateScreenEffectDef[tag.name]
	if not def then return nil end
	warn(string.format("[PlayerStateClient] screen effect stub: vfx=%s intensity=%.2f duration=%.2f", def.vfx, tag.intensity, tag.duration))
	return nil
end

function PlayerStateClient:_playVfxTag(tag: PlayerStateDefs.TagEntry): ActiveTagEffect?
	local def = PlayerStateVfxDef[tag.name]
	if not def then return nil end
	warn(string.format("[PlayerStateClient] vfx stub: tag=%s intensity=%.2f duration=%.2f", tag.name, tag.intensity, tag.duration))
	return nil
end

function PlayerStateClient:_applyCameraLock(duration: number?)
	if self._cameraLockCancel then
		self._cameraLockCancel()
		self._cameraLockCancel = nil
	end
	if not duration or duration <= 0 then return end
	local lockedCFrame = workspace.CurrentCamera.CFrame
	self._cameraController:SetOverride(function(cam: Camera, _dt: number)
		cam.CFrame = lockedCFrame
	end)
	local thread = task.delay(duration, function()
		self._cameraLockCancel = nil
		self._cameraController:ClearOverride()
	end)
	self._cameraLockCancel = function()
		task.cancel(thread)
		self._cameraController:ClearOverride()
	end
end

function PlayerStateClient.Destroy(self: PlayerStateClient)
	for pid, effects in self._activeEffects do
		for _, activeEffect in effects do activeEffect.stop() end
		self._activeEffects[pid] = nil
	end
	if self._cameraLockCancel then
		self._cameraLockCancel()
		self._cameraLockCancel = nil
	end
	if self._entityAnimator then
		self._entityAnimator:Destroy()
		self._entityAnimator = nil
	end
	self._maid:Destroy()
end

return PlayerStateClient
