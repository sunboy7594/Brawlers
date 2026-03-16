--!strict
--[=[
	@class BasicAttackClient

	기본 공격 클라이언트 서비스.

	담당:
	- 좌클릭 감지 → AimControllerClient:StartAim() 호출
	- AmmoChanged 수신 → abilityState 탄약 필드 갱신
	- HitChecked 수신 → abilityState.victims 갱신 → onHitChecked 배열 실행
	  (HitChecked는 서버에서 공격자에게만 FireClient로 발송됨)
	- PlayerBinderClient.JointsChanged 구독 → joints 자가 갱신 → EntityAnimator 재생성
	- abilityState 소유 및 관리
	- fireComboCount/hitComboCount 증감은 각 공격 모듈이 담당

	postDelay 예약 발사:
	- postDelay 잔여 비율 ≤ POST_DELAY_QUEUE_THRESHOLD(30%) 일 때 공격 시도 시
	  서버로 Fire를 전송하여 서버가 cancellableDelay로 예약하도록 허용
	- 클라이언트도 cancellableDelay(_pendingOnFireCancel)로 동일 타이밍에 OnFire 실행
	- postDelayUntil을 즉시 갱신하여 클라이언트가 만료 직후 즉시 발사를 시도하지 않도록 방지
	- 예약 OnFire 직전에 abilityState.direction을 클릭 시점 direction으로 명시 고정
	  (미고정 시: _onRenderStep이 마지막으로 쓴 값과 달라 방향 불일치 발생)
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AbilityExecutor = require("AbilityExecutor")
local AimControllerClient = require("AimControllerClient")
local AnimationControllerClient = require("AnimationControllerClient")
local BasicAttackDefs = require("BasicAttackDefs")
local BasicAttackRemoting = require("BasicAttackRemoting")
local ClassRemoting = require("ClassRemoting")
local DynamicIndicator = require("DynamicIndicator")
local EntityAnimator = require("EntityAnimator")
local Maid = require("Maid")
local PlayerBinderClient = require("PlayerBinderClient")
local ServiceBag = require("ServiceBag")
local cancellableDelay = require("cancellableDelay")

-- ─── 상수 ────────────────────────────────────────────────────────────────────
-- ⚠️ 주의: BasicAttackService.lua의 POST_DELAY_QUEUE_THRESHOLD와
--          반드시 동일한 값을 유지해야 합니다.
local POST_DELAY_QUEUE_THRESHOLD = 0.80

-- ─── 레지스트리 ──────────────────────────────────────────────────────────────
local ATTACK_REGISTRY: { [string]: { def: any, module: any, animDef: any } } = {}
for id, def in BasicAttackDefs do
	ATTACK_REGISTRY[id] = {
		def = def,
		module = require(id .. "Client"),
		animDef = require(id .. "AnimDef"),
	}
end

-- ─── BasicAttackState 타입 ───────────────────────────────────────────────────

export type BasicAttackState = {
	indicator: any,
	animator: any?,
	currentAmmo: number,
	maxAmmo: number,
	reloadTime: number,
	postDelay: number,
	lastFireTime: number,
	postDelayUntil: number,
	lastHitTime: number,
	fireComboCount: number,
	hitComboCount: number,
	origin: Vector3,
	direction: Vector3,
	aimTime: number,
	effectiveAimTime: number,
	idleTime: number,
	victims: { Player }?,
}

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type BasicAttackClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_aimController: AimControllerClient.AimControllerClient,
		_animController: AnimationControllerClient.AnimationControllerClient,
		_equippedAttackId: string?,
		_joints: { [string]: Motor6D }?,
		_attackAnimator: any?,
		_abilityState: BasicAttackState?,
		_pendingOnFireCancel: (() -> ())?,
	},
	{} :: typeof({ __index = {} })
))

local BasicAttackClient = {}
BasicAttackClient.ServiceName = "BasicAttackClient"
BasicAttackClient.__index = BasicAttackClient

-- ─── 인디케이터 색상 상수 ─────────────────────────────────────────────────────

local COLOR_NORMAL = Color3.fromRGB(160, 160, 160)
local COLOR_NO_AMMO = Color3.fromRGB(220, 50, 50)
local ALPHA_NORMAL = 0
local ALPHA_POST_DELAY = 0.8

-- ─── 초기화 ──────────────────────────────────────────────────────────────────

function BasicAttackClient.Init(self: BasicAttackClient, serviceBag: ServiceBag.ServiceBag): ()
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._aimController = serviceBag:GetService(AimControllerClient)
	self._animController = serviceBag:GetService(AnimationControllerClient)

	self._equippedAttackId = nil
	self._joints = nil
	self._attackAnimator = nil
	self._abilityState = nil
	self._pendingOnFireCancel = nil

	local playerBinder = serviceBag:GetService(PlayerBinderClient)
	self._maid:GiveTask(playerBinder.JointsChanged:Connect(function(joints)
		self._joints = joints
		if self._equippedAttackId then
			self:_rebuildAnimator()
		end
	end))

	self._maid:GiveTask(ClassRemoting.ClassChanged:Connect(function(_className: unknown)
		self:_cancelClientCombatState()
	end))

	self._maid:GiveTask(
		BasicAttackRemoting.AmmoChanged:Connect(
			function(current: unknown, max: unknown, reloadTime: unknown, postDelay: unknown)
				local abilityState = self._abilityState
				if not abilityState then
					return
				end
				if type(current) == "number" then
					abilityState.currentAmmo = current
				end
				if type(max) == "number" then
					abilityState.maxAmmo = max
				end
				if type(reloadTime) == "number" then
					abilityState.reloadTime = reloadTime
				end
				if type(postDelay) == "number" then
					abilityState.postDelay = postDelay
				end
			end
		)
	)

	self._maid:GiveTask(BasicAttackRemoting.HitChecked:Connect(function(victimUserIds: unknown)
		self:_onHitChecked(victimUserIds)
	end))
end

function BasicAttackClient.Start(self: BasicAttackClient): ()
	self._maid:GiveTask(RunService.Heartbeat:Connect(function(dt)
		local abilityState = self._abilityState
		if not abilityState then
			return
		end

		if self._aimController:IsAiming() then
			local hasAmmo = abilityState.currentAmmo > 0
			local isPostDelay = os.clock() < abilityState.postDelayUntil
			local canFire = hasAmmo and not isPostDelay

			if canFire then
				abilityState.effectiveAimTime += dt
			else
				abilityState.effectiveAimTime = 0
			end

			-- 모든 shape에 색상/투명도 일괄 적용
			if not hasAmmo then
				abilityState.indicator:updateAll({ color = COLOR_NO_AMMO })
			else
				abilityState.indicator:updateAll({ color = COLOR_NORMAL })
			end

			if isPostDelay then
				abilityState.indicator:updateAll({ transparency = ALPHA_POST_DELAY })
			else
				abilityState.indicator:updateAll({ transparency = ALPHA_NORMAL })
			end
		end
	end))

	self._maid:GiveTask(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		self:_tryStartAim()
	end))
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

function BasicAttackClient:SetEquippedAttack(attackId: string)
	self._aimController:Cancel()
	self._aimController:CancelPostFire()

	if self._pendingOnFireCancel then
		self._pendingOnFireCancel()
		self._pendingOnFireCancel = nil
	end

	self._equippedAttackId = attackId

	if self._abilityState then
		self._abilityState.indicator:destroy()
	end

	local entry = ATTACK_REGISTRY[attackId]
	-- shapes = { cone = "cone", ... } 형태로 전달
	local indicator = if entry then DynamicIndicator.new(entry.module.shapes) else DynamicIndicator.new({})

	self._abilityState = {
		indicator = indicator,
		animator = nil,
		currentAmmo = 0,
		maxAmmo = 0,
		reloadTime = 0,
		postDelay = 0,
		lastFireTime = 0,
		postDelayUntil = 0,
		lastHitTime = 0,
		fireComboCount = 0,
		hitComboCount = 0,
		origin = Vector3.zero,
		direction = Vector3.new(0, 0, -1),
		aimTime = 0,
		effectiveAimTime = 0,
		idleTime = 0,
		victims = nil,
	}

	self:_rebuildAnimator()
end

-- ─── 내부 ────────────────────────────────────────────────────────────────────

function BasicAttackClient:_cancelClientCombatState()
	self._aimController:Cancel()
	self._aimController:CancelPostFire()
	if self._pendingOnFireCancel then
		self._pendingOnFireCancel()
		self._pendingOnFireCancel = nil
	end
end

function BasicAttackClient:_rebuildAnimator()
	if self._attackAnimator then
		self._attackAnimator:Destroy()
		self._attackAnimator = nil
	end
	if self._abilityState then
		self._abilityState.animator = nil
	end

	local attackId = self._equippedAttackId
	local joints = self._joints
	if not attackId or not joints then
		return
	end

	local entry = ATTACK_REGISTRY[attackId]
	if not entry then
		return
	end

	local animator = EntityAnimator.new(
		"BasicAttack_" .. attackId,
		attackId .. "AnimDef",
		joints,
		entry.animDef,
		self._animController
	)
	self._attackAnimator = animator

	if self._abilityState then
		self._abilityState.animator = animator
	end
end

function BasicAttackClient:_tryStartAim()
	local attackId = self._equippedAttackId
	if not attackId then
		return
	end

	local entry = ATTACK_REGISTRY[attackId]
	if not entry then
		return
	end

	local abilityState = self._abilityState
	if not abilityState then
		return
	end

	abilityState.idleTime = if abilityState.lastFireTime > 0 then os.clock() - abilityState.lastFireTime else 0

	self._aimController:StartAim(
		AimControllerClient.AbilityType.BasicAttack,
		entry.module,
		abilityState,
		function(direction: Vector3)
			if abilityState.currentAmmo <= 0 then
				return false
			end

			local now = os.clock()

			if now < abilityState.postDelayUntil then
				local remaining = abilityState.postDelayUntil - now

				if abilityState.postDelay <= 0 or remaining / abilityState.postDelay > POST_DELAY_QUEUE_THRESHOLD then
					return false
				end

				local scheduledAt = abilityState.postDelayUntil
				abilityState.postDelayUntil = scheduledAt + entry.def.postDelay

				local capturedDirection = direction
				if self._pendingOnFireCancel then
					self._pendingOnFireCancel()
					self._pendingOnFireCancel = nil
				end
				self._pendingOnFireCancel = cancellableDelay(remaining, function()
					self._pendingOnFireCancel = nil
					abilityState.direction = capturedDirection
					abilityState.lastFireTime = scheduledAt
					abilityState.effectiveAimTime = 0
					AbilityExecutor.OnFire(entry.module, abilityState)
				end)

				BasicAttackRemoting.Fire:FireServer(direction)
				return true
			end

			if self._pendingOnFireCancel then
				self._pendingOnFireCancel()
				self._pendingOnFireCancel = nil
			end
			abilityState.direction = direction
			abilityState.postDelayUntil = now + entry.def.postDelay
			abilityState.lastFireTime = now
			abilityState.effectiveAimTime = 0
			BasicAttackRemoting.Fire:FireServer(direction)
			AbilityExecutor.OnFire(entry.module, abilityState)
			return true
		end,
		entry.def.postDelay
	)

	BasicAttackRemoting.AimStarted:FireServer()
end

function BasicAttackClient:_onHitChecked(victimUserIds: unknown)
	local abilityState = self._abilityState
	if not abilityState then
		return
	end

	local victims: { Player } = {}
	for _, userId in ipairs(victimUserIds :: { number }) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			table.insert(victims, player)
		end
	end
	abilityState.victims = victims

	if #victims > 0 then
		abilityState.lastHitTime = os.clock()
	end

	local attackId = self._equippedAttackId
	if not attackId then
		return
	end

	local entry = ATTACK_REGISTRY[attackId]
	if not entry then
		return
	end

	AbilityExecutor.OnHitChecked(entry.module, abilityState)
end

function BasicAttackClient.Destroy(self: BasicAttackClient)
	if self._pendingOnFireCancel then
		self._pendingOnFireCancel()
		self._pendingOnFireCancel = nil
	end
	self._maid:Destroy()
end

return BasicAttackClient
