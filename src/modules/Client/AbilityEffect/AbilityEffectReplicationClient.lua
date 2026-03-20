--!strict
--[=[
	@class AbilityEffectReplicationClient

	타 클라이언트의 AbilityEffect를 수신하여 로컀 재생. (Client)

	수정:
	  EffectBroadcast 수신 시 발사자의 teamContext를 빌드하여 전달.
	  teamContext 없으면 hitDetect에서 attackerChar 필터 누락 →
	  발사자 자신에게 hitbox 반응 버그 수정.
]=]

local require = require(script.Parent.loader).load(script)

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local AbilityEffectPlayer              = require("AbilityEffectPlayer")
local AbilityEffectReplicationRemoting = require("AbilityEffectReplicationRemoting")
local Maid       = require("Maid")
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
		AbilityEffectReplicationRemoting.EffectBroadcast:Connect(function(
			userId        : number,
			defModuleName : string,
			effectName    : string,
			origin        : CFrame,
			sentAt        : number
		)
			if userId == Players.LocalPlayer.UserId then return end

			local _elapsed = math.max(0, Workspace:GetServerTimeNow() - sentAt)
			local player   = Players:GetPlayerByUserId(userId)
			local tc       = self._teamClient

			local color: Color3? = nil
			if player and tc then color = tc:GetRelationColor(player) end

			local teamContext = nil
			if player and tc then
				teamContext = {
					attackerChar   = player.Character,
					attackerPlayer = player,
					color          = color,
					isEnemy        = function(a: Player, b: Player): boolean
						return tc:IsEnemy(a, b)
					end,
				}
			end

			AbilityEffectPlayer.Play(defModuleName, effectName, {
				origin      = origin,
				color       = color,
				isOwner     = false,
				userId      = userId,
				firedAt     = sentAt,
				teamContext = teamContext,
			})
		end)
	)
end

function AbilityEffectReplicationClient.Destroy(self: any)
	self._maid:Destroy()
end

return AbilityEffectReplicationClient
