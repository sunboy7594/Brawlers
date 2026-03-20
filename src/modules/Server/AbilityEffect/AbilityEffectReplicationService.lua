--!strict
--[=[
	@class AbilityEffectReplicationService
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local AbilityEffectReplicationRemoting = require("AbilityEffectReplicationRemoting")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")

local AbilityEffectReplicationService = {}
AbilityEffectReplicationService.ServiceName = "AbilityEffectReplicationService"
AbilityEffectReplicationService.__index = AbilityEffectReplicationService

function AbilityEffectReplicationService.Init(self: any, serviceBag: any)
	self._maid = Maid.new()
end

function AbilityEffectReplicationService.Start(self: any)
	self._maid:GiveTask(
		AbilityEffectReplicationRemoting.EffectFired:Connect(
			function(player: Player, defModuleName: string, effectName: string, origin: CFrame, sentAt: number)
				-- 발사자 제외 모든 클라이언트에 포워딩
				for _, other in Players:GetPlayers() do
					if other == player then
						continue
					end
					AbilityEffectReplicationRemoting.EffectBroadcast:FireClient(
						other,
						player.UserId,
						defModuleName,
						effectName,
						origin,
						sentAt
					)
				end
			end
		)
	)
end

function AbilityEffectReplicationService.Destroy(self: any)
	self._maid:Destroy()
end

return AbilityEffectReplicationService
