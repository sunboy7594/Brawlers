--!strict
--[=[
	@class BrawlersService
]=]

local require = require(script.Parent.loader).load(script)

local ServiceBag = require("ServiceBag")

local BrawlersService = {}
BrawlersService.ServiceName = "BrawlersService"

export type BrawlersService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
	},
	{} :: typeof({ __index = BrawlersService })
))

function BrawlersService.Init(self: BrawlersService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")

	-- External
	self._serviceBag:GetService(require("CmdrService"))

	-- Internal
	self._serviceBag:GetService(require("BrawlersTranslator"))
end

return BrawlersService
