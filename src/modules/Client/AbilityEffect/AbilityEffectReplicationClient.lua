--!strict
--[=[
	@class AbilityEffectReplicationClient

	타 클라이언트의 AbilityEffect를 수신하여 로컬 재생. (Client)

	동작:
	  EffectBroadcast 수신
	    → 자신이 주인인 이펙트면 스킵 (AbilityEffectPlayer가 이미 재생)
	    → firedAt 기준 elapsed 계산 (fast-forward)
	    → AbilityEffectPlayer.Play() 호출 (isOwner=false)

	수정:
	  - EffectBroadcast 수신 시 발사자의 teamContext를 빌드하여 전달.
	    teamContext가 없으면 hitDetect에서 attackerChar 필터가 누락되어
	    발사자가 자기 자신을 맞는 버그 수정.
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
				-- 자신이 발사한 이펙트는 AbilityEffectPlayer가 이미 재생
				if userId == Players.LocalPlayer.UserId then
					return
				end

				-- fast-forward: 네트워크 지연만큼 이미 진행된 상태로 시작
				local _elapsed = math.max(0, Workspace:GetServerTimeNow() - sentAt)

				-- 발사자 플레이어 참조
				local player = Players:GetPlayerByUserId(userId)

				-- 해당 플레이어 색상
				local tc = self._teamClient
				local color: Color3? = nil
				if player and tc then
					color = tc:GetRelationColor(player)
				end

				-- ✅ 발사자 teamContext 빌드
				-- teamContext가 없으면 AbilityEffectHitDetectionUtil.Detect()에서
				-- attackerChar 필터가 누락되어 발사자 본인에게도 hitbox가 반응함.
				local teamContext = nil
				if player and tc then
					teamContext = {
						attackerChar = player.Character,
						attackerPlayer = player,
						color = color,
						isEnemy = function(a: Player, b: Player): boolean
							return tc:IsEnemy(a, b)
						end,
					}
				end

				AbilityEffectPlayer.Play(defModuleName, effectName, {
					origin = origin,
					color = color,
					isOwner = false,
					userId = userId,
					firedAt = sentAt,
					teamContext = teamContext, -- ✅ 전달
				})
			end
		)
	)
end

function AbilityEffectReplicationClient.Destroy(self: any)
	self._maid:Destroy()
end

return AbilityEffectReplicationClient
