--!strict
--[=[
	@class PassiveService

	패시브 서버 서비스. (stub)

	TODO: 패시브 시스템 구현 예정
]=]

local require = require(script.Parent.loader).load(script)

local LoadoutRemoting = require("LoadoutRemoting")
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
	-- TODO: 패시브 Cast 수신 및 쿨다운 관리 구현 예정

	-- 미구현 동안 InvokeServer 영구 yield 방지용 fail-safe
	LoadoutRemoting.RequestEquipPassive:Bind(function(_player, _passiveId)
		return false, "미구현"
	end)
end

function PassiveService.Destroy(self: PassiveService)
	self._maid:Destroy()
end

return PassiveService
