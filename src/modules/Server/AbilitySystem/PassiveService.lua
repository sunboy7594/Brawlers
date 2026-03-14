--!strict
--[=[
	@class PassiveService

	스킬 서버 서비스. (stub)

	TODO: 스킬 시스템 구현 예정
]=]

local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local PassiveRemoting = require("PassiveRemoting") -- luacheck: ignore
local ServiceBag = require("ServiceBag")

export type PassiveService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
	},
	{} :: typeof({ __index = {} })
))

local PassiveService = {}
PassiveService.ServiceName = "PassiveService"
PassiveService.__index = PassiveService

function PassiveService.Init(self: PassiveService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
end

function PassiveService.Start(_self: PassiveService): ()
	-- TODO: 스킬 Cast 수신 및 쿨다운 관리 구현 예정
end

function PassiveService.Destroy(self: PassiveService)
	self._maid:Destroy()
end

return PassiveService
