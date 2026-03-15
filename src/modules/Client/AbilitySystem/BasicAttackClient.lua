--!strict
--[=[
	@class BasicAttackClient

	기본 공격 클라이언트 서비스.

	담당:
	- 좌클릭 감지 → AimControllerClient:StartAim() 호출
	- AmmoChanged 수신 → state 탄약 필드 갱신
	- HitChecked 수신 → state.victims 갱신 → onHitChecked 배열 실행
	- PlayerBinderClient.JointsChanged 구독 → joints 자가 갱신 → EntityAnimator 재생성
	- state 소유 및 관리
	- fireComboCount/hitComboCount 증감은 각 공격 모듈이 담당
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
local DynamicIndicator = require("DynamicIndicator")
local EntityAnimator = require("EntityAnimator")
local Maid = require("Maid")
local PlayerBinderClient = require("PlayerBinderClient")
local ServiceBag = require("ServiceBag")

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
	-- 연출
	indicator: any,
	animator: any?,

	-- 탄약
	currentAmmo: number,
	maxAmmo: number,
	reloadTime: number,
	postDelay: number,

	-- 타이밍
	lastFireTime: number,
	postDelayUntil: number,
	lastHitTime: number,

	-- 콤보 (증감은 각 공격 모듈이 담당)
	fireComboCount: number, -- 공격할 때마다 증가
	hitComboCount: number, -- 피격시켰을 때만 증가

	-- 계산
	origin: Vector3,
	direction: Vector3,
	aimTime: number,
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

	-- PlayerBinderClient.JointsChanged 구독 → joints 갱신 → animator 재생성
	local playerBinder = serviceBag:GetService(PlayerBinderClient)
	self._maid:GiveTask(playerBinder.JointsChanged:Connect(function(joints)
		self._joints = joints
		if self._equippedAttackId then
			self:_rebuildAnimator()
		end
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

	self._maid:GiveTask(BasicAttackRemoting.HitChecked:Connect(function(attackerUserId: unknown, victimUserIds: unknown)
		self:_onHitChecked(attackerUserId, victimUserIds)
	end))
end

function BasicAttackClient.Start(self: BasicAttackClient): ()
	-- 매 프레임: indicator 기본 색상 관리
	self._maid:GiveTask(RunService.Heartbeat:Connect(function()
		local state = self._state
		if not state then
			return
		end

		if self._aimController:IsAiming() then
			local hasAmmo = state.currentAmmo > 0
			local isPostDelay = os.clock() < state.postDelayUntil

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

	-- 좌클릭 → 조준 시작
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
		idleTime = 0,
		victims = nil,
	}

	self:_rebuildAnimator()
end

-- ─── 내부 ────────────────────────────────────────────────────────────────────

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
				return
			end
			if os.clock() < state.postDelayUntil then
				return
			end

			state.postDelayUntil = os.clock() + entry.def.postDelay
			state.lastFireTime = os.clock()
			BasicAttackRemoting.Fire:FireServer(direction)
			AbilityExecutor.OnFire(entry.module, state)
		end,
		entry.def.postDelay
	)

	BasicAttackRemoting.AimStarted:FireServer()
end

function BasicAttackClient:_onHitChecked(_attackerUserId: unknown, victimUserIds: unknown)
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
	self._maid:Destroy()
end

return BasicAttackClient
