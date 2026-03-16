--!strict
--[=[
	@class BasicAttackClient

	기본 공격 클라이언트 서비스.

	담당:
	- 좌클릭 감지 → AimControllerClient:StartAim() 호출
	- AmmoChanged 수신 → state 탄약 필드 갱신
	- HitChecked 수신 → state.victims 갱신 → onHitChecked 배열 실행
	  (HitChecked는 서버에서 공격자에게만 FireClient로 발송됨)
	- PlayerBinderClient.JointsChanged 구독 → joints 자가 갱신 → EntityAnimator 재생성
	- state 소유 및 관리
	- fireComboCount/hitComboCount 증감은 각 공격 모듈이 담당

	postDelay 예약 발사:
	- postDelay 잔여 비율 ≤ POST_DELAY_QUEUE_THRESHOLD(30%) 일 때 공격 시도 시
	  서버로 Fire를 전송하여 서버가 cancellableDelay로 예약하도록 허용
	- 클라이언트도 cancellableDelay(_pendingOnFireCancel)로 동일 타이밍에 OnFire 실행
	- postDelayUntil을 즉시 갱신하여 클라이언트가 만료 직후 즉시 발사를 시도하지 않도록 방지
	- 예약 OnFire 직전에 state.direction을 클릭 시점 direction으로 명시 고정
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
--          한쪽만 바꾸면 예약 발사 타이밍이 서버-클라이언트 간 어긋납니다.
local POST_DELAY_QUEUE_THRESHOLD = 0.30 -- 잔여 비율 30% 이하일 때 서버 전송 허용

-- ─── 레지스트리 ──────────────────────────────────────────────────────────────
-- 주의: 클라이언트에서는 절대로 id .. "Server" 를 require 하지 않습니다.
--       서버 모듈은 ServerScriptService에만 존재하므로 클라이언트에서 require 시 에러.

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
		_state: BasicAttackState?,
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
	self._state = nil
	self._pendingOnFireCancel = nil

	local playerBinder = serviceBag:GetService(PlayerBinderClient)
	self._maid:GiveTask(playerBinder.JointsChanged:Connect(function(joints)
		self._joints = joints
		if self._equippedAttackId then
			self:_rebuildAnimator()
		end
	end))

	-- Init 내부, 기존 remoting 구독들 옆에 추가
	self._maid:GiveTask(ClassRemoting.ClassChanged:Connect(function(_className: unknown)
		self:_cancelClientCombatState()
	end))

	self._maid:GiveTask(
		BasicAttackRemoting.AmmoChanged:Connect(
			function(current: unknown, max: unknown, reloadTime: unknown, postDelay: unknown)
				local state = self._state
				if not state then
					return
				end
				if type(current) == "number" then
					state.currentAmmo = current
				end
				if type(max) == "number" then
					state.maxAmmo = max
				end
				if type(reloadTime) == "number" then
					state.reloadTime = reloadTime
				end
				if type(postDelay) == "number" then
					state.postDelay = postDelay
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
		local state = self._state
		if not state then
			return
		end

		if self._aimController:IsAiming() then
			local hasAmmo = state.currentAmmo > 0
			local isPostDelay = os.clock() < state.postDelayUntil

			local canFire = state.currentAmmo > 0 and os.clock() >= state.postDelayUntil

			if canFire then
				state.effectiveAimTime = state.effectiveAimTime + dt
			else
				state.effectiveAimTime = 0
			end

			if not hasAmmo then
				state.indicator:update({ color = COLOR_NO_AMMO })
			else
				state.indicator:update({ color = COLOR_NORMAL })
			end

			if isPostDelay then
				state.indicator:update({ transparency = ALPHA_POST_DELAY })
			else
				state.indicator:update({ transparency = ALPHA_NORMAL })
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
	-- 조준 중이면 즉시 취소 (버그 1: 구 ctx dangling 방지)
	self._aimController:Cancel()
	-- postFire 회전 잠금 해제 (버그 2: AutoRotate 미복원 방지)
	self._aimController:CancelPostFire()

	-- 예약 클라이언트 OnFire 취소
	if self._pendingOnFireCancel then
		self._pendingOnFireCancel()
		self._pendingOnFireCancel = nil
	end

	self._equippedAttackId = attackId

	if self._state then
		self._state.indicator:destroy()
	end

	local entry = ATTACK_REGISTRY[attackId]
	local indicator = if entry then DynamicIndicator.new(entry.module.shapes) else DynamicIndicator.new(nil)

	self._state = {
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
	self._aimController:Cancel() -- 버그 A: 조준 상태 즉시 종료
	self._aimController:CancelPostFire() -- 버그 B: AutoRotate 잠금 해제
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
	if self._state then
		self._state.animator = nil
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

	if self._state then
		self._state.animator = animator
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

	local state = self._state
	if not state then
		return
	end

	state.idleTime = if state.lastFireTime > 0 then os.clock() - state.lastFireTime else 0

	self._aimController:StartAim(
		AimControllerClient.AbilityType.BasicAttack,
		entry.module,
		state,
		function(direction: Vector3)
			if state.currentAmmo <= 0 then
				return false
			end

			local now = os.clock()

			if now < state.postDelayUntil then
				local remaining = state.postDelayUntil - now

				if state.postDelay <= 0 or remaining / state.postDelay > POST_DELAY_QUEUE_THRESHOLD then
					return false
				end

				local scheduledAt = state.postDelayUntil
				state.postDelayUntil = scheduledAt + entry.def.postDelay

				local capturedDirection = direction
				if self._pendingOnFireCancel then
					self._pendingOnFireCancel()
					self._pendingOnFireCancel = nil
				end
				self._pendingOnFireCancel = cancellableDelay(remaining, function()
					self._pendingOnFireCancel = nil
					state.direction = capturedDirection
					state.lastFireTime = scheduledAt
					AbilityExecutor.OnFire(entry.module, state)
				end)

				BasicAttackRemoting.Fire:FireServer(direction)
				return true
			end

			if self._pendingOnFireCancel then
				self._pendingOnFireCancel()
				self._pendingOnFireCancel = nil
			end
			state.direction = direction
			state.postDelayUntil = now + entry.def.postDelay
			state.lastFireTime = now
			BasicAttackRemoting.Fire:FireServer(direction)
			AbilityExecutor.OnFire(entry.module, state)
			return true
		end,
		entry.def.postDelay
	)

	BasicAttackRemoting.AimStarted:FireServer()
end

function BasicAttackClient:_onHitChecked(victimUserIds: unknown)
	local state = self._state
	if not state then
		return
	end

	local victims: { Player } = {}
	for _, userId in ipairs(victimUserIds :: { number }) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			table.insert(victims, player)
		end
	end
	state.victims = victims

	if #victims > 0 then
		state.lastHitTime = os.clock()
	end

	local attackId = self._equippedAttackId
	if not attackId then
		return
	end

	local entry = ATTACK_REGISTRY[attackId]
	if not entry then
		return
	end

	AbilityExecutor.OnHitChecked(entry.module, state)
end

function BasicAttackClient.Destroy(self: BasicAttackClient)
	if self._pendingOnFireCancel then
		self._pendingOnFireCancel()
		self._pendingOnFireCancel = nil
	end
	self._maid:Destroy()
end

return BasicAttackClient
