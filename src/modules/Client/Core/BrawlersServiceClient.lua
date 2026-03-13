--!strict
--[=[
	@class BrawlersServiceClient
]=]

local require = require(script.Parent.loader).load(script)

local ServiceBag = require("ServiceBag")

local BrawlersServiceClient = {}
BrawlersServiceClient.ServiceName = "BrawlersServiceClient"

export type BrawlersServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
	},
	{} :: typeof({ __index = BrawlersServiceClient })
))

function BrawlersServiceClient.Init(self: BrawlersServiceClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")

	-- External
	self._serviceBag:GetService(require("CmdrServiceClient"))

	-- Internal
	self._serviceBag:GetService(require("BrawlersTranslator"))
end

return BrawlersServiceClient
