--!strict
--[=[
    @class BasicAttackClient

    기본 공격 클라이언트 서비스.

    담당:
    - 좌클릭 홀드 감지 → AimController:startAim() 호출
    - AmmoChanged 수신 → 탄약/postDelay 상태 보관
    - 탄약 0 또는 postDelay 중이면 조준 시작 불가
]=]

local require = require(script.Parent.loader).load(script)

local UserInputService = game:GetService("UserInputService")

local AimController = require("AimController")
local BasicAttackDefs = require("BasicAttackDefs")
local BasicAttackRemoting = require("BasicAttackRemoting")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")

-- ─── 레지스트리 자동 구성 ─────────────────────────────────────────────────────

local ATTACK_REGISTRY = {}
for id, def in BasicAttackDefs do
	ATTACK_REGISTRY[id] = {
		def = def,
		module = require(id .. "Client"),
		animDef = require(id .. "AnimDef"),
	}
end

-- ─── 타입 정의 ───────────────────────────────────────────────────────────────

export type BasicAttackClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_aimController: AimController.AimController,
		_equippedAttackId: string?,
		_currentAmmo: number,
		_maxAmmo: number,
		_reloadTime: number,
		_postDelay: number,
		_postDelayUntil: number, -- os.clock() 기준 postDelay 해제 시각
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
	self._equippedAttackId = nil
	self._currentAmmo = 0
	self._maxAmmo = 0
	self._reloadTime = 0
	self._postDelay = 0
	self._postDelayUntil = 0

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

function BasicAttackClient:SetEquippedAttack(attackId: string)
	self._equippedAttackId = attackId
	self._postDelayUntil = 0 -- 장착 변경 시 postDelay 초기화
end

-- ─── 내부 ────────────────────────────────────────────────────────────────────

function BasicAttackClient:_tryStartAim()
	-- 탄약 없으면 조준 불가
	if self._currentAmmo <= 0 then
		return
	end

	-- postDelay 중이면 조준 불가
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

	local clientModule = entry.module

	self._aimController:startAim(
		AimController.AbilityType.BasicAttack,
		clientModule.indicator,
		function(direction: Vector3, aimTime: number)
			-- postDelay 시작 (클라이언트 측 즉시 잠금)
			self._postDelayUntil = os.clock() + entry.def.postDelay
			BasicAttackRemoting.Fire:FireServer(direction, aimTime)
		end,
		function() end,
		clientModule.onAim
	)
end

function BasicAttackClient.Destroy(self: BasicAttackClient)
	self._maid:Destroy()
end

return BasicAttackClient
