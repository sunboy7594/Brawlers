--!strict
--[=[
	@class EntityReplicationClient

	타 클라이언트의 Entity를 수신하여 로컈 재생. (Client)
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local EntityPlayer              = require("EntityPlayer")
local EntityReplicationRemoting = require("EntityReplicationRemoting")
local Maid                      = require("Maid")
local ServiceBag                = require("ServiceBag")
local TeamClient                = require("TeamClient")

local EntityReplicationClient = {}
EntityReplicationClient.ServiceName = "EntityReplicationClient"
EntityReplicationClient.__index = EntityReplicationClient

function EntityReplicationClient.Init(self: any, serviceBag: any)
	self._maid = Maid.new()
	self._teamClient = serviceBag:GetService(TeamClient)
end

function EntityReplicationClient.Start(self: any)
	self._maid:GiveTask(
		EntityReplicationRemoting.EntityBroadcast:Connect(function(
			userId    : number,
			defModule : string,
			defName   : string,
			origin    : CFrame,
			sentAt    : number,
			params    : { [string]: any }?,
			tags      : { string }?
		)
			if userId == Players.LocalPlayer.UserId then return end

			local player = Players:GetPlayerByUserId(userId)
			local tc     = self._teamClient
			local color: Color3? = nil
			if player and tc then
				color = tc:GetRelationColor(player)
			end

			EntityPlayer.Play(defModule, defName, {
				origin           = origin,
				color            = color,
				attackerPlayerId = userId,
				firedAt          = sentAt,
				params           = params,
				tags             = tags,
				replicate        = false,
			})
		end)
	)
end

function EntityReplicationClient.Destroy(self: any)
	self._maid:Destroy()
end

return EntityReplicationClient
