--!strict
--[=[
	@class PlayerStateClient

	서버로부터 PlayerState effect를 수신하여 클라이언트 연출을 실행합니다.

	담당:
	- PlayerStateRemoting.EffectApplied 수신 → tag별 연출 실행
	- PlayerStateRemoting.EffectRemoved 수신 → 진행 중인 루프 연출 조기 종료
	- component에서 cameraLock 수신 → 카메라 방향 고정
	- tag special="ragdoll" → 래그돌 처리

	tag 처리 흐름:
	  anim_*   → PlayerStateAnimDef.resolve() → EntityAnimator
	             loop=true이면 duration 동안 반복 재생
	  cam_*    → PlayerStateCameraAnimDef.resolve() → CameraAnimator
	             intensity를 factory에 전달
	  screen_* → PlayerStateScreenEffectDef → ScreenEffectController (stub)
	  vfx_*   → PlayerStateVfxDef → VfxController (stub)

	intensity 전달:
	  AnimFactory 호출 시 ac = { ac = animController, intensity = tag.intensity }
	  CameraAnimDef factory 호출 시 factory(cc, tag.intensity)
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

-- ─── 타입 ────────────────────────────────────────────────────────────────────

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

-- ─── 초기화 ──────────────────────────────────────────────────────────────────

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

	-- PlayerStateCameraAnimDef가 CameraAnimDef 구현을 직접 포함
	self._cameraAnimator = CameraAnimator.new(OWNER, PlayerStateCameraAnimDef, self._cameraController)
	self._maid:GiveTask(self._cameraAnimator)
end

function PlayerStateClient.Start(self: PlayerStateClient): ()
	self._maid:GiveTask(self._playerBinder.JointsChanged:Connect(function(joints)
		self._joints = joints
		self:_rebuildEntityAnimator(joints)
	end))

	self._maid:GiveTask(PlayerStateRemoting.EffectApplied:Connect(function(effectDef: unknown, payloadId: unknown)
		self:_onEffectApplied(effectDef :: PlayerStateDefs.EffectDef, payloadId :: string?)
	end))

	self._maid:GiveTask(PlayerStateRemoting.EffectRemoved:Connect(function(payloadId: unknown)
		self:_onEffectRemoved(payloadId :: string)
	end))
end

-- ─── EntityAnimator 관리 ─────────────────────────────────────────────────────

function PlayerStateClient:_rebuildEntityAnimator(joints: { [string]: Motor6D }?)
	if self._entityAnimator then
		self._entityAnimator:Destroy()
		self._entityAnimator = nil
	end
	if not joints then
		return
	end

	-- PlayerStateAnimDef가 AnimDef 구현을 직접 포함
	self._entityAnimator =
		EntityAnimator.new(OWNER, "PlayerStateAnimDef", joints, PlayerStateAnimDef, self._animController)
end

-- ─── EffectApplied 처리 ──────────────────────────────────────────────────────

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

-- ─── EffectRemoved 처리 ──────────────────────────────────────────────────────

function PlayerStateClient:_onEffectRemoved(payloadId: string)
	local effects = self._activeEffects[payloadId]
	if not effects then
		return
	end
	for _, activeEffect in effects do
		activeEffect.stop()
	end
	self._activeEffects[payloadId] = nil
end

-- ─── tag 라우터 ──────────────────────────────────────────────────────────────

function PlayerStateClient:_playTag(
	tag: PlayerStateDefs.TagEntry,
	components: { PlayerStateDefs.Component }?
): ActiveTagEffect?
	local name = tag.name
	if name:sub(1, 5) == "anim_" then
		return self:_playAnimTag(tag)
	elseif name:sub(1, 4) == "cam_" then
		return self:_playCamTag(tag, components)
	elseif name:sub(1, 7) == "screen_" then
		return self:_playScreenTag(tag)
	elseif name:sub(1, 4) == "vfx_" then
		return self:_playVfxTag(tag)
	end
	return nil
end

-- ─── 캐릭터 애니메이션 ───────────────────────────────────────────────────────

function PlayerStateClient:_playAnimTag(tag: PlayerStateDefs.TagEntry): ActiveTagEffect?
	local entityAnimator = self._entityAnimator
	if not entityAnimator then
		return nil
	end

	local resolved = PlayerStateAnimDef.resolve(tag.name, tag.intensity)
	if not resolved then
		return nil
	end

	if resolved.special then
		return self:_handleSpecialAnim(resolved.special, tag)
	end

	local animKey = resolved.animKey
	if not animKey then
		return nil
	end

	local loop = resolved.loop
	local stopped = false -- intensity를 AnimFactory에 전달하기 위해 EntityAnimator에 주입
 -- EntityAnimator의 PlayAnimation이 ac 인자를 { ac = animController, intensity = n } 형태로 넘겨야 함
 -- 현재 EntityAnimator는 ac = animController 그대로 넘기므로,
 -- animController에 intensity를 임시 주입하는 방식 사용
	(self._animController :: any)._currentIntensity = tag.intensity

	if loop then
		-- duration 동안 반복 재생 (EntityAnimator가 duration 만료 시 자동 종료)
		entityAnimator:PlayAnimation(animKey, tag.duration, nil, true)
	else
		entityAnimator:PlayAnimation(animKey, tag.duration, nil, true)
	end -- intensity 임시 주입 해제
	(self._animController :: any)._currentIntensity = nil

	return {
		stop = function()
			if stopped then
				return
			end
			stopped = true
			entityAnimator:StopAnimation(animKey)
		end,
	}
end

function PlayerStateClient:_handleSpecialAnim(special: string, tag: PlayerStateDefs.TagEntry): ActiveTagEffect?
	if special == "ragdoll" then
		return self:_applyRagdoll(tag.duration)
	end
	return nil
end

-- ─── 래그돌 ──────────────────────────────────────────────────────────────────

function PlayerStateClient:_applyRagdoll(duration: number): ActiveTagEffect?
	local char = Players.LocalPlayer.Character
	if not char then
		return nil
	end

	local disabledJoints: { Motor6D } = {}
	for _, desc in char:GetDescendants() do
		if desc:IsA("Motor6D") then
			desc.Enabled = false
			table.insert(disabledJoints, desc)
		end
	end

	local ragdollMaid = Maid.new()
	local function restore()
		for _, joint in disabledJoints do
			if joint and joint.Parent then
				joint.Enabled = true
			end
		end
		ragdollMaid:Destroy()
	end

	local thread = task.delay(duration, restore)
	ragdollMaid:GiveTask(function()
		task.cancel(thread)
	end)
	return { stop = restore }
end

-- ─── 카메라 애니메이션 ───────────────────────────────────────────────────────

function PlayerStateClient:_playCamTag(
	tag: PlayerStateDefs.TagEntry,
	components: { PlayerStateDefs.Component }?
): ActiveTagEffect?
	local resolved = PlayerStateCameraAnimDef.resolve(tag.name)
	if not resolved then
		return nil
	end

	local animKey = resolved.animKey

	if resolved.knockbackRef and components then
		for _, comp in components do
			local c = comp :: any
			if c.type == "knockback" and c.direction then
				-- TODO: direction 기반 카메라 방향 주입 확장
				break
			end
		end
	end

	-- intensity를 factory에 전달하기 위해 PlayAnimation 시 intensity 주입
	-- CameraAnimator.PlayAnimation → factory(cc, intensity) 형태로 확장 필요
	-- 현재는 force=true로 재생, intensity는 animDef factory에서 캡처 불가
	-- → CameraAnimator에 intensity 전달 지원 추가 시 여기서 연결
	self._cameraAnimator:PlayAnimation(animKey, tag.duration, nil, true)

	return {
		stop = function()
			self._cameraAnimator:Stop(animKey)
		end,
	}
end

-- ─── 화면 이펙트 (stub) ──────────────────────────────────────────────────────

function PlayerStateClient:_playScreenTag(tag: PlayerStateDefs.TagEntry): ActiveTagEffect?
	local def = PlayerStateScreenEffectDef[tag.name]
	if not def then
		return nil
	end
	warn(
		string.format(
			"[PlayerStateClient] screen effect stub: vfx=%s intensity=%.2f duration=%.2f",
			def.vfx,
			tag.intensity,
			tag.duration
		)
	)
	return nil
end

-- ─── VFX (stub) ──────────────────────────────────────────────────────────────

function PlayerStateClient:_playVfxTag(tag: PlayerStateDefs.TagEntry): ActiveTagEffect?
	local def = PlayerStateVfxDef[tag.name]
	if not def then
		return nil
	end
	warn(
		string.format(
			"[PlayerStateClient] vfx stub: tag=%s intensity=%.2f duration=%.2f",
			tag.name,
			tag.intensity,
			tag.duration
		)
	)
	return nil
end

-- ─── cameraLock component ────────────────────────────────────────────────────

function PlayerStateClient:_applyCameraLock(duration: number?)
	if self._cameraLockCancel then
		self._cameraLockCancel()
		self._cameraLockCancel = nil
	end
	if not duration or duration <= 0 then
		return
	end

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

-- ─── 소멸 ────────────────────────────────────────────────────────────────────

function PlayerStateClient.Destroy(self: PlayerStateClient)
	for pid, effects in self._activeEffects do
		for _, activeEffect in effects do
			activeEffect.stop()
		end
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
