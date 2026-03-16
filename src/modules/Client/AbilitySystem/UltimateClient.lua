--!strict
--[=[
	@class UltimateClient

	궁극기 클라이언트 서비스. (stub)

	TODO: 궁극기 시스템 구현 예정
]=]

local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local UltimateRemoting = require("UltimateRemoting") -- luacheck: ignore

export type UltimateClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
	},
	{} :: typeof({ __index = {} })
))

local UltimateClient = {}
UltimateClient.ServiceName = "UltimateClient"
UltimateClient.__index = UltimateClient

function UltimateClient.Init(self: UltimateClient, serviceBag: ServiceBag.ServiceBag): ()
	self._serviceBag = serviceBag
	self._maid = Maid.new()
end

function UltimateClient.Start(_self: UltimateClient): ()
	-- TODO: 궁극기 입력 감지 및 게이지 로직 구현 예정
end

function UltimateClient.Destroy(self: UltimateClient)
	self._maid:Destroy()
end

return UltimateClient
