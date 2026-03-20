--!strict
--[=[
	@class EntityReplicationService

	Entity 복제 서비스. (Server)
	EntityFired 수신 → 발사자 제외 전원에게 EntityBroadcast 포워딩.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local EntityReplicationRemoting = require("EntityReplicationRemoting")
local Maid                      = require("Maid")
local ServiceBag                = require("ServiceBag")

local EntityReplicationService = {}
EntityReplicationService.ServiceName = "EntityReplicationService"
EntityReplicationService.__index = EntityReplicationService

function EntityReplicationService.Init(self: any, _serviceBag: any)
	self._maid = Maid.new()
end

function EntityReplicationService.Start(self: any)
	self._maid:GiveTask(
		EntityReplicationRemoting.EntityFired:Connect(function(
			player    : Player,
			defModule : string,
			defName   : string,
			origin    : CFrame,
			sentAt    : number,
			params    : { [string]: any }?,
			tags      : { string }?
		)
			for _, other in Players:GetPlayers() do
				if other == player then continue end
				EntityReplicationRemoting.EntityBroadcast:FireClient(
					other,
					player.UserId,
					defModule,
					defName,
					origin,
					sentAt,
					params,
					tags
				)
			end
		end)
	)
end

function EntityReplicationService.Destroy(self: any)
	self._maid:Destroy()
end

return EntityReplicationService
