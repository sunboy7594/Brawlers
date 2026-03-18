--!strict
--[=[
	@class PlayerStateClient

	서버로부터 PlayerState effect를 수신하여 클라이언트 연출을 실행합니다.

	담당:
	- PlayerStateRemoting.EffectApplied 수신 → tag별 연출 실행
	- PlayerStateRemoting.EffectRemoved 수신 → 진행 중인 루프 연출 조기 종료
	- component에서 cameraLock 수신 → 카메라 방향 고정
	- tag special="ragdoll" → 래그돌 처리

	tag 중첩 방지 (loop성 태그):
	  _tagSlots[tagName][id] 슬롯 구조로 intensity 스택 관리.
	  intensity가 가장 높은 슬롯만 실제 연출 재생.
	  같은 intensity면 duration이 긴 쪽 우선.
	  현재 재생 중인 슬롯이 제거되면 next best로 교체 (남은 시간 기준).

	단발(ONESHOT) 태그:
	  슬롯 관리 없이 즉시 재생.

	params 전달:
	  anim_* → PlayAnimation(..., { intensity })
	  cam_*  → PlayAnimation(..., { intensity, direction })
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local AbilityCoordinator = require("AbilityCoordinator")
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
local ONESHOT_TAGS = PlayerStateDefs.ONESHOT_TAGS

-- ─── 타입 ────────────────────────────────────────────────────────────────────

type ActiveTagEffect = {
	stop: () -> (),
}

type ActiveTagSlot = {
	id: string,
	intensity: number,
	expiresAt: number,
	stop: () -> (),
	components: { PlayerStateDefs.Component }?,
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
		-- 루프성 태그 슬롯 관리: [tagName][id] = ActiveTagSlot
		_tagSlots: { [string]: { [string]: ActiveTagSlot } },
		-- 역방향 맵: id → { tagName }
		_idToTags: { [string]: { string } },
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
	self._abilityCoordinator = serviceBag:GetService(AbilityCoordinator)
	self._animController = serviceBag:GetService(AnimationControllerClient)
	self._cameraController = serviceBag:GetService(CameraControllerClient)
	self._playerBinder = serviceBag:GetService(PlayerBinderClient)
	self._joints = nil
	self._entityAnimator = nil
	self._tagSlots = {}
	self._idToTags = {}
	self._cameraLockCancel = nil

	self._lockedAbilityTypes = {} :: { [string]: number }
	self._idToAbilityLockTypes = {} :: { [string]: { string } }

	self._cameraAnimator = CameraAnimator.new(OWNER, PlayerStateCameraAnimDef, self._cameraController)
	self._maid:GiveTask(self._cameraAnimator)
end

function PlayerStateClient.Start(self: PlayerStateClient): ()
	self._maid:GiveTask(self._playerBinder.JointsChanged:Connect(function(joints)
		self._joints = joints
		self:_rebuildEntityAnimator(joints)
	end))

	self._maid:GiveTask(PlayerStateRemoting.EffectApplied:Connect(function(effectDef: unknown, id: unknown)
		self:_onEffectApplied(effectDef :: PlayerStateDefs.EffectDef, id :: string)
	end))

	self._maid:GiveTask(PlayerStateRemoting.EffectRemoved:Connect(function(id: unknown)
		self:_onEffectRemoved(id :: string)
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

	self._entityAnimator =
		EntityAnimator.new(OWNER, "PlayerStateAnimDef", joints, PlayerStateAnimDef, self._animController)
end

-- ─── EffectApplied 처리 ──────────────────────────────────────────────────────

function PlayerStateClient:_onEffectApplied(effectDef: PlayerStateDefs.EffectDef, id: string)
	local tags = effectDef.tags
	local components = effectDef.components
	local now = os.clock()

	self._idToTags[id] = {}

	-- abilityLock component 감지 → 공격불가 상태 → ability 캔슬
	if components then
		for _, comp in components do
			local c = comp :: any
			if c.type == "abilityLock" then
				local keys: { string } = if c.abilityTypes == nil then { "*" } else c.abilityTypes
				self._idToAbilityLockTypes[id] = keys
				for _, key in keys do
					self._lockedAbilityTypes[key] = (self._lockedAbilityTypes[key] or 0) + 1
					self._abilityCoordinator:CancelByType(key)
				end
			end
		end
	end

	-- 연출
	if tags then
		for _, tag in tags do
			local tagName = tag.name
			table.insert(self._idToTags[id], tagName)

			if ONESHOT_TAGS[tagName] then
				-- 단발: 슬롯 없이 즉시 재생
				self:_playTagDirect(tag, components)
				continue
			end

			-- 루프성: 슬롯 관리
			if not self._tagSlots[tagName] then
				self._tagSlots[tagName] = {}
			end

			local expiresAt = now + tag.duration
			local prevBest = self:_getBestSlot(tagName)

			local slot: ActiveTagSlot = {
				id = id,
				intensity = tag.intensity,
				expiresAt = expiresAt,
				stop = function() end,
				components = components,
			}
			self._tagSlots[tagName][id] = slot

			local newBest = self:_getBestSlot(tagName)

			if not prevBest then
				-- 첫 번째 슬롯: 즉시 재생
				local activeEffect = self:_playTagDirect(tag, components)
				if activeEffect then
					slot.stop = activeEffect.stop
				end
			elseif newBest and newBest.id == id then
				-- 새 슬롯이 best → 이전 best 중단 후 새로 재생
				prevBest.stop()
				if self._tagSlots[tagName][prevBest.id] then
					self._tagSlots[tagName][prevBest.id].stop = function() end
				end
				local activeEffect = self:_playTagDirect(tag, components)
				if activeEffect then
					slot.stop = activeEffect.stop
				end
			end
			-- else: best가 아님 → 슬롯에만 저장, 재생 안 함
		end
	end

	-- cameraLock 처리
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

function PlayerStateClient:_onEffectRemoved(id: string)
	local tagNames = self._idToTags[id]
	if not tagNames then
		return
	end

	for _, tagName in tagNames do
		local slots = self._tagSlots[tagName]
		if not slots then
			continue
		end

		local removedSlot = slots[id]
		if not removedSlot then
			continue
		end

		local wasBest = self:_isBestSlot(tagName, id)

		-- 재생 중단
		removedSlot.stop()
		slots[id] = nil

		if wasBest then
			-- next best로 교체
			local nextBest = self:_getBestSlot(tagName)
			if nextBest then
				local remaining = math.max(0, nextBest.expiresAt - os.clock())
				local nextTag: PlayerStateDefs.TagEntry = {
					name = tagName,
					intensity = nextBest.intensity,
					duration = remaining,
				}
				local activeEffect = self:_playTagDirect(nextTag, nextBest.components)
				if activeEffect then
					nextBest.stop = activeEffect.stop
				end
			end
		end

		-- 빈 슬롯 테이블 정리
		if not next(slots) then
			self._tagSlots[tagName] = nil
		end
	end

	self._idToTags[id] = nil

	local lockKeys = self._idToAbilityLockTypes[id]
	if lockKeys then
		for _, key in lockKeys do
			local count = (self._lockedAbilityTypes[key] or 1) - 1
			self._lockedAbilityTypes[key] = if count <= 0 then nil else count
		end
		self._idToAbilityLockTypes[id] = nil
	end
end

-- ─── 슬롯 헬퍼 ──────────────────────────────────────────────────────────────

--[=[
	tagName 슬롯에서 intensity가 가장 높은 (동점이면 duration이 긴) 슬롯 반환.
]=]
function PlayerStateClient:_getBestSlot(tagName: string): ActiveTagSlot?
	local slots = self._tagSlots[tagName]
	if not slots then
		return nil
	end

	local best: ActiveTagSlot? = nil
	for _, slot in slots do
		if not best then
			best = slot
		elseif slot.intensity > best.intensity then
			best = slot
		elseif slot.intensity == best.intensity and slot.expiresAt > best.expiresAt then
			best = slot
		end
	end
	return best
end

function PlayerStateClient:_isBestSlot(tagName: string, id: string): boolean
	local best = self:_getBestSlot(tagName)
	return best ~= nil and best.id == id
end

-- ─── tag 라우터 (직접 재생) ──────────────────────────────────────────────────

function PlayerStateClient:_playTagDirect(
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

	local stopped = false
	entityAnimator:PlayAnimation(animKey, tag.duration, nil, true, { intensity = tag.intensity })

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

	-- direction 추출 (cam_knockback)
	local direction: Vector3? = nil
	if resolved.knockbackRef and components then
		for _, comp in components do
			local c = comp :: any
			if c.type == "knockback" and c.direction then
				direction = c.direction
				break
			end
		end
	end

	self._cameraAnimator:PlayAnimation(animKey, tag.duration, nil, true, {
		intensity = tag.intensity,
		direction = direction,
	})

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

-- ─── 공개 API ────────────────────────────────────────────────────────────────────

function PlayerStateClient:IsAbilityLocked(abilityType: string): boolean
	return (self._lockedAbilityTypes["*"] or 0) > 0 or (self._lockedAbilityTypes[abilityType] or 0) > 0
end

function PlayerStateClient.Destroy(self: PlayerStateClient)
	-- 모든 슬롯 정리
	for tagName, slots in self._tagSlots do
		for _, slot in slots do
			slot.stop()
		end
	end
	self._tagSlots = {}
	self._idToTags = {}

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
