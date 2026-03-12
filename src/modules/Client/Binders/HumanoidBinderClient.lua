--!strict
--[=[
	@class HumanoidBinderClient

	"Player" 태그가 붙은 캐릭터 Model을 감시하는 서비스 래퍼.
	CollectionService가 "Player" 태그를 감지하면 HumanoidAnimatorClient를 자동으로 생성합니다.
	서버에서 캐릭터 스폰 시 CollectionService:AddTag(character, "Player")를 호출해야 합니다.
]=]

local require = require(script.Parent.loader).load(script)

local Binder = require("Binder")
local HumanoidAnimatorClient = require("HumanoidAnimatorClient")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")

local HumanoidBinderClient = {}
HumanoidBinderClient.ServiceName = "HumanoidBinderClient"

export type HumanoidBinderClient = typeof(setmetatable(
	{} :: {
		_maid: any,
		_serviceBag: ServiceBag.ServiceBag,
		_binder: any,
	},
	{} :: typeof({ __index = HumanoidBinderClient })
))

function HumanoidBinderClient.Init(self: HumanoidBinderClient, serviceBag: ServiceBag.ServiceBag): ()
	self._serviceBag = serviceBag
	self._maid = Maid.new()

	-- "Player" 태그가 붙은 인스턴스에 HumanoidAnimatorClient를 자동 생성
	self._binder = Binder.new("Player", HumanoidAnimatorClient, serviceBag)
	self._maid:GiveTask(self._binder)
end

function HumanoidBinderClient.Start(self: HumanoidBinderClient): ()
	self._binder:Start()
end

function HumanoidBinderClient.Destroy(self: HumanoidBinderClient)
	self._maid:Destroy()
end

return HumanoidBinderClient
