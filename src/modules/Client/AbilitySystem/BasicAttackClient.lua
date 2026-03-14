--!strict
--[=[
	@class BasicAttackClient

	기본 공격 클라이언트 서비스.

	담당:
	- 좌클릭 감지 → AimController:startAim() 호출
	- AmmoChanged 수신 → 탄약/postDelay 상태 보관
	- HitConfirmed 수신 → ctx.comboCount 갱신 → onHitConfirmed 배열 실행
	- SetJoints(joints) 수신 → SetEquippedAttack 시 EntityAnimator 생성
	- ctx 소유 및 관리
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local AimController = require("AimController")
local AnimationControllerClient = require("AnimationControllerClient")
local BasicAttackDefs = require("BasicAttackDefs")
local BasicAttackRemoting = require("BasicAttackRemoting")
local DynamicIndicator = require("DynamicIndicator")
local EntityAnimator = require("EntityAnimator")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")

-- ─── 레지스트리 ──────────────────────────────────────────────────────────────
-- animDef는 각 공격 모듈 파일 옆에 위치 (id .. "AnimDef")

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
	aimTime: number, -- 클라이언트 측정, 비주얼 전용
	idleTime: number, -- 마지막 발사 후 경과 시간
	comboCount: number, -- HitConfirmed 수신 후 serverComboCount로 갱신
	direction: Vector3,
	origin: Vector3,
	indicator: any, -- DynamicIndicator
	animator: any?, -- EntityAnimator?
	victims: { Player }?, -- onHitConfirmed에서만 채워짐
}

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type BasicAttackClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_aimController: AimController.AimController,
		_animController: AnimationControllerClient.AnimationControllerClient,

		-- 탄약 상태 (서버에서 수신)
		_equippedAttackId: string?,
		_currentAmmo: number,
		_maxAmmo: number,
		_reloadTime: number,
		_postDelay: number,
		_postDelayUntil: number,
		_lastFireTime: number,

		-- joints / animator
		_joints: { [string]: Motor6D }?,
		_attackAnimator: any?, -- EntityAnimator?

		-- ctx (공격 모듈 훅에 넘기는 공유 컨텍스트)
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

	-- AmmoChanged 수신
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

	-- HitConfirmed 수신
	self._maid:GiveTask(
		BasicAttackRemoting.HitConfirmed:Connect(
			function(attackerUserId: unknown, victimUserIds: unknown, serverComboCount: unknown)
				self:_onHitConfirmed(attackerUserId, victimUserIds, serverComboCount)
			end
		)
	)
end

function BasicAttackClient.Start(self: BasicAttackClient): ()
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

--[=[
	HumanoidAnimatorClient가 캐릭터 스폰 시 호출.
	joints만 전달, EntityAnimator 생성은 SetEquippedAttack이 담당.
]=]
function BasicAttackClient:SetJoints(joints: { [string]: Motor6D }?)
	self._joints = joints
	-- joints가 갱신됐으므로 현재 장착 중이면 animator 재생성
	if self._equippedAttackId then
		self:_rebuildAnimator()
	end
end

--[=[
	TestLoadoutClient 등에서 장착 완료 시 호출.
]=]
function BasicAttackClient:SetEquippedAttack(attackId: string)
	self._equippedAttackId = attackId
	self._postDelayUntil = 0
	self._lastFireTime = 0

	-- ctx 초기화 (장착 변경마다 인디케이터 새로 생성)
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

	local animator = EntityAnimator.new("BasicAttack_" .. attackId, joints, entry.animDef, self._animController)
	self._attackAnimator = animator

	if self._ctx then
		self._ctx.animator = animator
	end
end

function BasicAttackClient:_tryStartAim()
	if self._currentAmmo <= 0 then
		return
	end
	if os.clock() < self._postDelayUntil then
		return
	end

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

	-- idleTime 갱신
	ctx.idleTime = if self._lastFireTime > 0 then os.clock() - self._lastFireTime else 0

	self._aimController:startAim(AimController.AbilityType.BasicAttack, entry.module, ctx, function(direction: Vector3)
		-- 클라이언트 측 발사 후처리
		self._postDelayUntil = os.clock() + entry.def.postDelay
		self._lastFireTime = os.clock()
		-- 서버 전송 (direction만)
		BasicAttackRemoting.Fire:FireServer(direction)
	end)

	-- 조준 시작을 서버에 알림 (서버의 aimStartTime 기록용)
	BasicAttackRemoting.AimStarted:FireServer()
end

function BasicAttackClient:_onHitConfirmed(attackerUserId: unknown, victimUserIds: unknown, serverComboCount: unknown)
	-- 본인 발사가 아니면 무시 (본인 발사 연출만 담당)
	local localPlayer = Players.LocalPlayer
	if attackerUserId ~= localPlayer.UserId then
		return
	end

	local ctx = self._ctx
	if not ctx then
		return
	end

	-- serverComboCount로 덮어쓰기
	if type(serverComboCount) == "number" then
		ctx.comboCount = serverComboCount
	end

	-- victims 채우기 (Player 객체로 변환)
	local victims: { Player } = {}
	if type(victimUserIds) == "table" then
		for _, uid in victimUserIds :: { unknown } do
			if type(uid) == "number" then
				local p = Players:GetPlayerByUserId(uid)
				if p then
					table.insert(victims, p)
				end
			end
		end
	end
	ctx.victims = victims

	-- 장착된 공격 모듈의 onHitConfirmed 배열 실행
	local attackId = self._equippedAttackId
	if not attackId then
		return
	end
	local entry = ATTACK_REGISTRY[attackId]
	if not entry then
		return
	end

	if entry.module.onHitConfirmed then
		for _, fn in entry.module.onHitConfirmed do
			fn(ctx)
		end
	end

	-- victims 초기화
	ctx.victims = nil
end

function BasicAttackClient.Destroy(self: BasicAttackClient)
	if self._ctx then
		self._ctx.indicator:destroy()
	end
	if self._attackAnimator then
		self._attackAnimator:Destroy()
	end
	self._maid:Destroy()
end

return BasicAttackClient
