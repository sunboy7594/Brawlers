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

-- BrawlersService.lua

local PhysicsService = game:GetService("PhysicsService")

function BrawlersService.Init(self: BrawlersService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")

	-- CollisionGroup 초기화
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Characters")
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup("HitCheck")
	end)
	PhysicsService:CollisionGroupSetCollidable("HitCheck", "Characters", false)

	pcall(function()
		PhysicsService:RegisterCollisionGroup("MovementObstacle")
	end)
	-- MovementObstacle ↔ HitCheck 충돌 없음 → InstantHit Raycast에 안 잡힘
	PhysicsService:CollisionGroupSetCollidable("MovementObstacle", "HitCheck", false)
	-- MovementObstacle ↔ Characters 충돌 있음 (기본값 true, 별도 설정 불필요)

	-- External
	self._serviceBag:GetService(require("CmdrService"))

	-- Internal
	self._serviceBag:GetService(require("BrawlersTranslator"))

	-- Dev
	self._serviceBag:GetService(require("DevCommandService"))
end

return BrawlersService
