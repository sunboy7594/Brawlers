--!strict
--[=[
	@class AbilityEffectReplicationClient
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local AbilityEffectPlayer = require("AbilityEffectPlayer")
local AbilityEffectReplicationRemoting = require("AbilityEffectReplicationRemoting")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local TeamClient = require("TeamClient")

local AbilityEffectReplicationClient = {}
AbilityEffectReplicationClient.ServiceName = "AbilityEffectReplicationClient"
AbilityEffectReplicationClient.__index = AbilityEffectReplicationClient

function AbilityEffectReplicationClient.Init(self: any, serviceBag: any)
	self._maid = Maid.new()
	self._teamClient = serviceBag:GetService(TeamClient)
end

function AbilityEffectReplicationClient.Start(self: any)
	self._maid:GiveTask(
		AbilityEffectReplicationRemoting.EffectBroadcast:Connect(
			function(userId: number, defModuleName: string, effectName: string, origin: CFrame, sentAt: number)
				if userId == Players.LocalPlayer.UserId then
					return
				end

				local elapsed = math.max(0, Workspace:GetServerTimeNow() - sentAt)

				local player = Players:GetPlayerByUserId(userId)
				local color: Color3? = nil
				if player and self._teamClient then
					color = self._teamClient:GetRelationColor(player)
				end

				local tc = self._teamClient
				local teamContext = {
					attackerChar = player and player.Character,
					attackerPlayer = player,
					color = color,
					isEnemy = function(a: Player, b: Player): boolean
						return tc:IsEnemy(a, b)
					end,
				}

				AbilityEffectPlayer.Play(defModuleName, effectName, {
					origin = origin,
					color = color,
					isOwner = false,
					userId = userId,
					firedAt = sentAt,
					teamContext = teamContext,
				})
			end
		)
	)
end

function AbilityEffectReplicationClient.Destroy(self: any)
	self._maid:Destroy()
end

return AbilityEffectReplicationClient
