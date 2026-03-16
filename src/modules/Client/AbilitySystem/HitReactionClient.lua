--!strict
--[=[
	@class HitReactionClient

	피격 반응 클라이언트 서비스.

	담당:
	- BasicAttackRemoting.HitReaction 수신
	  → CameraAnimator로 카메라 흔들림
	  → EntityAnimator로 몸 피격 애니메이션
	- CameraAnimator, EntityAnimator 직접 소유/관리
	- PlayerBinderClient.JointsChanged 구독 → EntityAnimator 재생성

	사용 측 (각 공격기술 서버 onHitChecked):
	  BasicAttackRemoting.HitReaction:FireClient(victimPlayer, {
	      animName = "HitStagger",       -- HitReactionAnimDef 키
	      cameraAnimName = "HitShake",   -- HitReactionCameraAnimDef 키
	  })
	  duration은 각 Def에 정의되어 있으므로 신호에 포함하지 않습니다.
]=]

local require = require(script.Parent.loader).load(script)

local AnimationControllerClient = require("AnimationControllerClient")
local BasicAttackRemoting = require("BasicAttackRemoting")
local CameraAnimator = require("CameraAnimator")
local CameraControllerClient = require("CameraControllerClient")
local EntityAnimator = require("EntityAnimator")
local HitReactionAnimDef = require("HitReactionAnimDef")
local HitReactionCameraAnimDef = require("HitReactionCameraAnimDef")
local Maid = require("Maid")
local PlayerBinderClient = require("PlayerBinderClient")
local ServiceBag = require("ServiceBag")

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type HitReactionClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_cameraAnimator: CameraAnimator.CameraAnimator,
		_animator: EntityAnimator.EntityAnimator?,
		_animController: AnimationControllerClient.AnimationControllerClient,
	},
	{} :: typeof({ __index = {} })
))

local HitReactionClient = {}
HitReactionClient.ServiceName = "HitReactionClient"
HitReactionClient.__index = HitReactionClient

-- ─── 초기화 ──────────────────────────────────────────────────────────────────

function HitReactionClient.Init(self: HitReactionClient, serviceBag: ServiceBag.ServiceBag): ()
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._animator = nil
	self._animController = serviceBag:GetService(AnimationControllerClient)

	-- CameraAnimator 생성 (캐릭터 생명주기와 무관)
	local cameraController = serviceBag:GetService(CameraControllerClient)
	local camAnimator = CameraAnimator.new("HitReaction", HitReactionCameraAnimDef, cameraController)
	self._cameraAnimator = camAnimator
	self._maid:GiveTask(function()
		camAnimator:Destroy()
	end)

	-- PlayerBinderClient.JointsChanged → EntityAnimator 재생성
	local playerBinder = serviceBag:GetService(PlayerBinderClient)
	self._maid:GiveTask(playerBinder.JointsChanged:Connect(function(joints)
		if self._animator then
			self._animator:Destroy()
			self._animator = nil
		end

		if not joints then
			return
		end

		self._animator =
			EntityAnimator.new("HitReaction", "HitReactionAnimDef", joints, HitReactionAnimDef, self._animController)
	end))

	-- HitReaction 수신
	self._maid:GiveTask(BasicAttackRemoting.HitReaction:Connect(function(data: unknown)
		self:_onHitReaction(data)
	end))
end

function HitReactionClient.Start(_self: HitReactionClient): () end

-- ─── 내부 ────────────────────────────────────────────────────────────────────

function HitReactionClient:_onHitReaction(data: unknown)
	if type(data) ~= "table" then
		return
	end

	local payload = data :: {
		animName: string?,
		cameraAnimName: string?,
	}

	-- 카메라 애니메이션 (duration, force는 CameraAnimDef에서 읽음)
	local cameraAnimName = payload.cameraAnimName
	if cameraAnimName and type(cameraAnimName) == "string" then
		local def = (HitReactionCameraAnimDef :: any)[cameraAnimName]
		if def then
			print(cameraAnimName)
			self._cameraAnimator:PlayAnimation(cameraAnimName, def.duration, nil, def.force)
		end
	end

	-- 몸 애니메이션 (duration, force는 AnimDef에서 읽음)
	local animName = payload.animName
	if animName and type(animName) == "string" and self._animator then
		local def = (HitReactionAnimDef :: any)[animName]
		if def then
			print(animName)
			self._animator:PlayAnimation(animName, def.duration, nil, def.force)
		end
	end
end

function HitReactionClient.Destroy(self: HitReactionClient)
	self._maid:Destroy()
end

return HitReactionClient
