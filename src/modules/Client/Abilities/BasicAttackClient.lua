--!strict
--[=[
	@class BasicAttackClient

	기본 공격 클라이언트 서비스.

	담당:
	- 좌클릭 홀드 감지 → AimController:startAim() 호출
	- onFire: BasicAttackRemoting.Fire:FireServer(direction, aimTime)
	- AmmoChanged 수신 → 탄약 상태 보관
	- 탄약 0이면 조준 시작 불가
	- SetEquippedAttack(): 외부(TestLoadoutClient 등)에서 장착 공격 ID 갱신 시 호출
]=]

local require = require(script.Parent.loader).load(script)

local UserInputService = game:GetService("UserInputService")

local AimController = require("AimController")
local BasicAttackRemoting = require("BasicAttackRemoting")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local TankPunchClient = require("TankPunchClient")

-- ─── 공격 모듈 레지스트리 ────────────────────────────────────────────────────
-- attackId → 클라이언트 공격 모듈 (indicator, onAim, onHitConfirmed)
local ATTACK_REGISTRY = {
	Punch = TankPunchClient,
}

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

	-- 서버 → 클라이언트: 탄약 변경 수신
	self._maid:GiveTask(BasicAttackRemoting.AmmoChanged:Connect(function(
		current: unknown,
		max: unknown,
		reloadTime: unknown
	)
		if type(current) == "number" then
			self._currentAmmo = current
		end
		if type(max) == "number" then
			self._maxAmmo = max
		end
		if type(reloadTime) == "number" then
			self._reloadTime = reloadTime
		end
	end))
end

function BasicAttackClient.Start(self: BasicAttackClient): ()
	-- 좌클릭 홀드 감지 → 조준 시작
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
	장착 공격 ID를 갱신합니다.
	TestLoadoutClient 또는 슬롯 UI에서 성공 응답 수신 후 호출합니다.
	@param attackId string
]=]
function BasicAttackClient:SetEquippedAttack(attackId: string)
	self._equippedAttackId = attackId
end

-- ─── 내부 ────────────────────────────────────────────────────────────────────

function BasicAttackClient:_tryStartAim()
	-- 탄약 없으면 조준 불가
	if self._currentAmmo <= 0 then
		return
	end

	local attackId = self._equippedAttackId
	if not attackId then
		return
	end

	local attackModule = ATTACK_REGISTRY[attackId]
	if not attackModule then
		return
	end

	self._aimController:startAim(
		AimController.AbilityType.BasicAttack,
		attackModule.indicator,
		-- onFire: 좌클릭 해제 시 서버로 발사 신호 전송
		function(direction: Vector3, aimTime: number)
			BasicAttackRemoting.Fire:FireServer(direction, aimTime)
		end,
		-- onCancel: AimController가 인디케이터를 숨기므로 추가 처리 불필요
		function() end,
		-- onAim: 공격 모듈의 프레임별 콜백 (옵션)
		attackModule.onAim
	)
end

function BasicAttackClient.Destroy(self: BasicAttackClient)
	self._maid:Destroy()
end

return BasicAttackClient
