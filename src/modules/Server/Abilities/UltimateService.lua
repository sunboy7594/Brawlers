--!strict
--[=[
	@class UltimateService

	궁극기 서버 서비스. (stub)

	TODO: 궁극기 시스템 구현 예정
]=]

local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local UltimateRemoting = require("UltimateRemoting") -- luacheck: ignore

export type UltimateService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
	},
	{} :: typeof({ __index = {} })
))

local UltimateService = {}
UltimateService.ServiceName = "UltimateService"
UltimateService.__index = UltimateService

function UltimateService.Init(self: UltimateService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
end

function UltimateService.Start(_self: UltimateService): ()
	-- TODO: 궁극기 Cast 수신, 쿨다운, 게이지 관리 구현 예정
end

function UltimateService.Destroy(self: UltimateService)
	self._maid:Destroy()
end

return UltimateService
