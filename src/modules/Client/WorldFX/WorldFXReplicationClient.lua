--!strict
--[=[
	@class WorldFXReplicationClient

	다른 플레이어의 WorldFX 이펙트를 로컬에서 재생하는 클라이언트 서비스.

	동작:
	- EffectBroadcast 수신
	- 자기 자신(LocalPlayer) userId는 무시 (이미 로컬에서 재생됨)
	- elapsed = GetServerTimeNow() - firedAt 계산
	- AbilityEffect:Play() 호출 (isOwner=false, userId, firedAt 전달)
	  → MoveFactory가 handle.firedAt으로 fast-forward 적용 가능

	fast-forward:
	  MoveFactory 내에서 시작 시점에
	  elapsed = workspace:GetServerTimeNow() - handle.firedAt
	  을 계산하여 이동을 미리 진행시키면 됩니다.
	  (AbilityEffectMoveUtils 유틸에서 자동 처리 예정)
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local AbilityEffect = require("AbilityEffect")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local WorldFX = require("WorldFX")
local WorldFXReplicationRemoting = require("WorldFXReplicationRemoting")

export type WorldFXReplicationClient = typeof(setmetatable(
	{} :: {
		_serviceBag    : ServiceBag.ServiceBag,
		_maid          : any,
		_abilityEffect : any,
	},
	{} :: typeof({ __index = {} })
))

local WorldFXReplicationClient = {}
WorldFXReplicationClient.ServiceName = "WorldFXReplicationClient"
WorldFXReplicationClient.__index = WorldFXReplicationClient

function WorldFXReplicationClient.Init(self: WorldFXReplicationClient, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	local worldFX = serviceBag:GetService(WorldFX)
	self._abilityEffect = AbilityEffect.new(worldFX)
end

function WorldFXReplicationClient.Start(self: WorldFXReplicationClient)
	local localUserId = Players.LocalPlayer.UserId

	self._maid:GiveTask(
		WorldFXReplicationRemoting.EffectBroadcast:Connect(function(
			userId, defModuleName, effectName, origin, direction, firedAt
		)
			-- 자기 자신 무시
			if userId == localUserId then return end

			-- 타입 검증
			if type(userId) ~= "number" then return end
			if type(defModuleName) ~= "string" then return end
			if type(effectName) ~= "string" then return end
			if typeof(origin) ~= "CFrame" then return end
			if type(firedAt) ~= "number" then return end

			local safeDirection: Vector3? = nil
			if direction ~= nil and typeof(direction) == "Vector3" then
				safeDirection = direction
			end

			self._abilityEffect:Play(defModuleName, effectName, origin, {
				isOwner   = false,
				userId    = userId,
				direction = safeDirection,
				firedAt   = firedAt,
				-- onHit/onMiss/fireMaid 없음: 타 클라이언트는 순수 비주얼
			})
		end)
	)
end

function WorldFXReplicationClient.Destroy(self: WorldFXReplicationClient)
	self._maid:Destroy()
end

return WorldFXReplicationClient
