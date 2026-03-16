--!strict
--[=[
	@class PassiveClient

	패시브 클라이언트 서비스. (stub)

	TODO: 스킬 시스템 구현 예정
]=]

local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local PassiveRemoting = require("PassiveRemoting") -- luacheck: ignore
local ServiceBag = require("ServiceBag")

export type PassiveClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
	},
	{} :: typeof({ __index = {} })
))

local PassiveClient = {}
PassiveClient.ServiceName = "PassiveClient"
PassiveClient.__index = PassiveClient

function PassiveClient.Init(self: PassiveClient, serviceBag: ServiceBag.ServiceBag): ()
	self._serviceBag = serviceBag
	self._maid = Maid.new()
end

function PassiveClient.Start(_self: PassiveClient): ()
	-- TODO: 스킬 입력 감지 및 조준 로직 구현 예정
end

function PassiveClient.Destroy(self: PassiveClient)
	self._maid:Destroy()
end

return PassiveClient
