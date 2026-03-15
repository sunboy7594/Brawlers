--!strict
--[=[
	@class PlayerBinderClient

	"Player" 태그가 붙은 캐릭터 Model을 감시하는 서비스 래퍼.
	CollectionService가 "Player" 태그를 감지하면 PlayerAnimatorClient를 자동으로 생성합니다.
	서버에서 캐릭터 스폰 시 CollectionService:AddTag(character, "Player")를 호출해야 합니다.

	로컬 플레이어의 PlayerAnimatorClient로부터:
	- JointsChanged Signal을 프록시하여 구독자에게 전달
	- GetMoveDir()을 위임하여 노출
]=]

local require = require(script.Parent.loader).load(script)

local Binder = require("Binder")
local Maid = require("Maid")
local PlayerAnimatorClient = require("PlayerAnimatorClient")
local ServiceBag = require("ServiceBag")
local Signal = require("Signal")

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type PlayerBinderClient = typeof(setmetatable(
	{} :: {
		_maid: any,
		_serviceBag: ServiceBag.ServiceBag,
		_binder: any,
		_localComponent: PlayerAnimatorClient.PlayerAnimatorClient?,
		_componentMaid: any,
		JointsChanged: any, -- Signal<{ [string]: Motor6D }?>
	},
	{} :: typeof({ __index = {} })
))

-- ─── 서비스 ──────────────────────────────────────────────────────────────────

local PlayerBinderClient = {}
PlayerBinderClient.ServiceName = "PlayerBinderClient"
PlayerBinderClient.__index = PlayerBinderClient

function PlayerBinderClient.Init(self: PlayerBinderClient, serviceBag: ServiceBag.ServiceBag): ()
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._localComponent = nil
	self._componentMaid = Maid.new()
	self.JointsChanged = Signal.new()

	self._binder = Binder.new("Player", PlayerAnimatorClient, serviceBag)
	self._maid:GiveTask(self._binder)
	self._maid:GiveTask(self._componentMaid)
end

function PlayerBinderClient.Start(self: PlayerBinderClient): ()
	-- Start()를 먼저 호출해야 GetClassAddedSignal/GetClassRemovedSignal 내부 Signal이 초기화됨
	self._binder:Start()

	self._maid:GiveTask(self._binder:GetClassAddedSignal():Connect(function(component)
		if not component.IsLocalPlayer then
			return
		end
		self._localComponent = component

		-- JointsChanged 프록시
		self._componentMaid:GiveTask(component.JointsChanged:Connect(function(joints)
			self.JointsChanged:Fire(joints)
		end))
	end))

	self._maid:GiveTask(self._binder:GetClassRemovedSignal():Connect(function(component)
		if self._localComponent ~= component then
			return
		end
		self._localComponent = nil
		self._componentMaid:DoCleaning()
	end))
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	현재 활성화된 로컬 플레이어의 PlayerAnimatorClient 컴포넌트를 반환합니다.
	캐릭터가 없으면 nil입니다.
]=]
function PlayerBinderClient:GetPlayerAnimator(): PlayerAnimatorClient.PlayerAnimatorClient?
	return self._localComponent
end

--[=[
	로컬 플레이어의 현재 이동 방향(로컬 좌표)을 반환합니다.
	캐릭터가 없으면 Vector3.zero를 반환합니다.
]=]
function PlayerBinderClient:GetMoveDir(): Vector3
	if self._localComponent then
		return self._localComponent:GetMoveDir()
	end
	return Vector3.zero
end

function PlayerBinderClient.Destroy(self: PlayerBinderClient)
	self._maid:Destroy()
	self.JointsChanged:Destroy()
end

return PlayerBinderClient
