--!strict
--[=[
	@class AbilityEffectReplicationService

	EffectFired 수신 → 타 클라이언트에 EffectBroadcast 포워딩. (Server)

	역할:
	- EffectFired 수신 → 기본 유효성 검증
	- 발사자 제외 타 클라이언트에 EffectBroadcast 전송
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local AbilityEffectReplicationRemoting = require("AbilityEffectReplicationRemoting")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")

local MAX_ORIGIN_DISTANCE = 200
local RATE_LIMIT_INTERVAL  = 0.05

local AbilityEffectReplicationService = {}
AbilityEffectReplicationService.ServiceName = "AbilityEffectReplicationService"
AbilityEffectReplicationService.__index = AbilityEffectReplicationService

function AbilityEffectReplicationService.Init(self: any, _serviceBag: any)
	self._maid         = Maid.new()
	self._lastFireTime = {} :: { [number]: number }
end

function AbilityEffectReplicationService.Start(self: any)
	for _, player in Players:GetPlayers() do
		self._lastFireTime[player.UserId] = 0
	end
	self._maid:GiveTask(Players.PlayerAdded:Connect(function(player)
		self._lastFireTime[player.UserId] = 0
	end))
	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player)
		self._lastFireTime[player.UserId] = nil
	end))

	self._maid:GiveTask(
		AbilityEffectReplicationRemoting.EffectFired:Connect(function(
			player        : Player,
			defModuleName : unknown,
			effectName    : unknown,
			origin        : unknown,
			sentAt        : unknown
		)
			if type(defModuleName) ~= "string" or #defModuleName == 0 then return end
			if type(effectName) ~= "string"    or #effectName == 0    then return end
			if typeof(origin) ~= "CFrame"  then return end
			if type(sentAt)   ~= "number"  then return end

			local now = os.clock()
			local last = self._lastFireTime[player.UserId] or 0
			if now - last < RATE_LIMIT_INTERVAL then return end
			self._lastFireTime[player.UserId] = now

			-- origin 거리 검증
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				local dist = ((origin :: CFrame).Position - hrp.Position).Magnitude
				if dist > MAX_ORIGIN_DISTANCE then return end
			end

			-- 타 클라이언트에 전달
			for _, other in Players:GetPlayers() do
				if other == player then continue end
				AbilityEffectReplicationRemoting.EffectBroadcast:FireClient(
					other,
					player.UserId,
					defModuleName,
					effectName,
					origin,
					sentAt
				)
			end
		end)
	)
end

function AbilityEffectReplicationService.Destroy(self: any)
	self._maid:Destroy()
end

return AbilityEffectReplicationService
