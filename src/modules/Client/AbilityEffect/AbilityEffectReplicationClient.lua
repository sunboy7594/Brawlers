--!strict
--[=[
	@class AbilityEffectReplicationClient

	타 클라이언트의 AbilityEffect를 수신하여 로컈 재생. (Client)

	동작:
	  EffectBroadcast 수신
	    → 자신이 주인인 이펙트면 스킵 (AbilityEffectPlayer가 이미 재생)
	    → firedAt 기준 elapsed 계산 (fast-forward)
	    → AbilityEffectPlayer.Play() 호출 (isOwner=false)
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local AbilityEffectPlayer              = require("AbilityEffectPlayer")
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
		AbilityEffectReplicationRemoting.EffectBroadcast:Connect(function(
			userId        : number,
			defModuleName : string,
			effectName    : string,
			origin        : CFrame,
			sentAt        : number
		)
			-- 자신이 발사한 이펙트는 AbilityEffectPlayer가 이미 재생
			if userId == Players.LocalPlayer.UserId then return end

			-- fast-forward: 네트워크 지연만큼 이미 진행된 상태로 시작
			local elapsed = math.max(0, Workspace:GetServerTimeNow() - sentAt)

			-- 해당 플레이어 색상
			local player = Players:GetPlayerByUserId(userId)
			local color: Color3? = nil
			if player and self._teamClient then
				color = self._teamClient:GetRelationColor(player)
			end

			-- fast-forward를 반영한 firedAt
			local adjustedOrigin = origin
			-- 이동은 Controller 내부에서 elapsed 기반으로 처리될 예정
			-- (firedAt을 넣으면 Controller가 시작 시각 기준으로 elapsed 계산)

			AbilityEffectPlayer.Play(defModuleName, effectName, {
				origin  = adjustedOrigin,
				color   = color,
				isOwner = false,
				userId  = userId,
				firedAt = sentAt,
			})
		end)
	)
end

function AbilityEffectReplicationClient.Destroy(self: any)
	self._maid:Destroy()
end

return AbilityEffectReplicationClient
