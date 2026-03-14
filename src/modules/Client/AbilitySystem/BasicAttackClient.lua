--!strict
--[=[
	@class BasicAttackClient

	기본 공격 클라이언트 서비스.

	담당:
	- 좌클릭 감지 → AimController:StartAim() 호출
	- AmmoChanged 수신 → 탄약/postDelay 상태 보관
	- HitChecked 수신 → ctx.comboCount 갱신 → onHitChecked 배열 실행
	- SetJoints(joints) 수신 → SetEquippedAttack 시 EntityAnimator 생성
	- ctx 소유 및 관리
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService") -- ← 추가
local UserInputService = game:GetService("UserInputService")

local AbilityExecutor = require("AbilityExecutor")
local AimController = require("AimController")
local AnimationControllerClient = require("AnimationControllerClient")
local BasicAttackDefs = require("BasicAttackDefs")
local BasicAttackRemoting = require("BasicAttackRemoting")
local DynamicIndicator = require("DynamicIndicator")
local EntityAnimator = require("EntityAnimator")
local Maid = require("Maid")
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

-- ─── ClientContext 타입 ───────────────────────────────────────────────────────

type ClientContext = {
	aimTime: number,
	idleTime: number,
	comboCount: number,
	direction: Vector3,
	origin: Vector3,
	indicator: any,
	animator: any?,
	victims: { Player }?,
	isPostDelay: boolean, -- ← 추가
	hasAmmo: boolean, -- ← 추가
}

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type BasicAttackClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_aimController: AimController.AimController,
		_animController: AnimationControllerClient.AnimationControllerClient,

		_equippedAttackId: string?,
		_currentAmmo: number,
		_maxAmmo: number,
		_reloadTime: number,
		_postDelay: number,
		_postDelayUntil: number,
		_lastFireTime: number,

		_joints: { [string]: Motor6D }?,
		_attackAnimator: any?,
		_ctx: ClientContext?,
	},
	{} :: typeof({ __index = {} })
))

local BasicAttackClient = {}
BasicAttackClient.ServiceName = "BasicAttackClient"
BasicAttackClient.__index = BasicAttackClient

-- ─── 초기화 ──────────────────────────────────────────────────────────────────

function BasicAttackClient.Init(self: BasicAttackClient, serviceBag: ServiceBag.ServiceBag): ()
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._aimController = serviceBag:GetService(AimController)
	self._animController = serviceBag:GetService(AnimationControllerClient)

	self._equippedAttackId = nil
	self._currentAmmo = 0
	self._maxAmmo = 0
	self._reloadTime = 0
	self._postDelay = 0
	self._postDelayUntil = 0
	self._lastFireTime = 0

	self._joints = nil
	self._attackAnimator = nil
	self._ctx = nil

	-- Nevermore Remoting 클라이언트는 :Connect() 직접 사용 (OnClientEvent 없음)
	self._maid:GiveTask(
		BasicAttackRemoting.AmmoChanged:Connect(
			function(current: unknown, max: unknown, reloadTime: unknown, postDelay: unknown)
				if type(current) == "number" then
					self._currentAmmo = current
				end
				if type(max) == "number" then
					self._maxAmmo = max
				end
				if type(reloadTime) == "number" then
					self._reloadTime = reloadTime
				end
				if type(postDelay) == "number" then
					self._postDelay = postDelay
				end
			end
		)
	)

	self._maid:GiveTask(
		BasicAttackRemoting.HitChecked:Connect(
			function(attackerUserId: unknown, victimUserIds: unknown, serverComboCount: unknown)
				self:_onHitChecked(attackerUserId, victimUserIds, serverComboCount)
			end
		)
	)
end

-- indicator 상태별 색상 상수
local COLOR_NORMAL = Color3.fromRGB(160, 160, 160)
local COLOR_NO_AMMO = Color3.fromRGB(220, 50, 50)
local ALPHA_NORMAL = 0
local ALPHA_POST_DELAY = 0.8

function BasicAttackClient.Start(self: BasicAttackClient): ()
	-- 매 프레임: ctx 상태 갱신 + indicator 기본 색상 관리
	self._maid:GiveTask(RunService.Heartbeat:Connect(function()
		local ctx = self._ctx
		if not ctx then
			return
		end

		local isPostDelay = os.clock() < self._postDelayUntil
		local hasAmmo = self._currentAmmo > 0

		ctx.isPostDelay = isPostDelay
		ctx.hasAmmo = hasAmmo

		-- 조준 중일 때만 indicator에 반영
		-- (onAim 훅이 없거나, 커스텀하지 않을 경우의 기본 시각 상태)
		if self._aimController:IsAiming() then
			if not hasAmmo then
				ctx.indicator:update({ color = COLOR_NO_AMMO })
			else
				ctx.indicator:update({ color = COLOR_NORMAL })
			end

			if isPostDelay then
				ctx.indicator:update({ transparency = ALPHA_POST_DELAY })
			else
				ctx.indicator:update({ transparency = ALPHA_NORMAL })
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

function BasicAttackClient:SetJoints(joints: { [string]: Motor6D }?)
	self._joints = joints
	if self._equippedAttackId then
		self:_rebuildAnimator()
	end
end

function BasicAttackClient:SetEquippedAttack(attackId: string)
	self._equippedAttackId = attackId
	self._postDelayUntil = 0
	self._lastFireTime = 0

	if self._ctx then
		self._ctx.indicator:destroy()
	end

	local entry = ATTACK_REGISTRY[attackId]
	local indicator = if entry then DynamicIndicator.new(entry.module.shapes) else DynamicIndicator.new(nil)

	self._ctx = {
		aimTime = 0,
		idleTime = 0,
		comboCount = 0,
		direction = Vector3.new(0, 0, -1),
		origin = Vector3.zero,
		indicator = indicator,
		animator = nil,
		victims = nil,
		isPostDelay = false, -- ← 추가
		hasAmmo = true, -- ← 추가
	}

	self:_rebuildAnimator()
end

-- ─── 내부 ────────────────────────────────────────────────────────────────────

function BasicAttackClient:_rebuildAnimator()
	if self._attackAnimator then
		self._attackAnimator:Destroy()
		self._attackAnimator = nil
	end
	if self._ctx then
		self._ctx.animator = nil
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

	if self._ctx then
		self._ctx.animator = animator
	end
end

function BasicAttackClient:_tryStartAim()
	-- ammo/postDelay 조건 제거 → 조준은 항상 가능
	local attackId = self._equippedAttackId
	if not attackId then
		return
	end

	local entry = ATTACK_REGISTRY[attackId]
	if not entry then
		return
	end

	local ctx = self._ctx
	if not ctx then
		return
	end

	ctx.idleTime = if self._lastFireTime > 0 then os.clock() - self._lastFireTime else 0

	self._aimController:StartAim(AimController.AbilityType.BasicAttack, entry.module, ctx, function(direction: Vector3)
		-- 실제 발사 시점에만 조건 검증
		if self._currentAmmo <= 0 then
			return
		end
		if os.clock() < self._postDelayUntil then
			return
		end

		self._postDelayUntil = os.clock() + entry.def.postDelay
		self._lastFireTime = os.clock()
		BasicAttackRemoting.Fire:FireServer(direction)
		AbilityExecutor.OnFire(entry.module, ctx)
	end, entry.def.postDelay)

	BasicAttackRemoting.AimStarted:FireServer()
end

function BasicAttackClient:_onHitChecked(_attackerUserId: unknown, victimUserIds: unknown, serverComboCount: unknown)
	local ctx = self._ctx
	if not ctx then
		return
	end

	ctx.comboCount = serverComboCount :: number

	local victims: { Player } = {}
	for _, userId in ipairs(victimUserIds :: { number }) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			table.insert(victims, player)
		end
	end
	ctx.victims = victims

	local attackId = self._equippedAttackId
	if not attackId then
		return
	end

	local entry = ATTACK_REGISTRY[attackId]
	if not entry then
		return
	end

	AbilityExecutor.OnHitChecked(entry.module, ctx)
end

function BasicAttackClient.Destroy(self: BasicAttackClient)
	self._maid:Destroy()
end

return BasicAttackClient
