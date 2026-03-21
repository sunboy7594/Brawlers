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

	-- HRP 이동 처리 (JumpPunch 등 클라이언트 로컬 arc 이동)
	self._serviceBag:GetService(require("HRPMoveClient"))
end

return BrawlersServiceClient
