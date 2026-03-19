--!strict
--[=[
	@class AbilityEffectReplicationRemoting

	AbilityEffect 복제용 Remote 채널. (Shared)

	채널 목록:
	- EffectFired     : (클라이언트 → 서버) 이펙트 발동 알림
	  전달: defModuleName, effectName, origin(CFrame), sentAt(number), params(table?)
	  서버가 firedAt을 스탬핑하여 EffectBroadcast에 포함.
	  동시에 AbilityEffectSimulatorService에 시뮬 등록.

	- EffectBroadcast : (서버 → 클라이언트) 다른 플레이어 이펙트 전달
	  전달: userId, defModuleName, effectName, origin, firedAt, params
	  클라이언트는 수신 시 elapsed = GetServerTimeNow() - firedAt 으로 fast-forward.
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remoting = require("Remoting")

local AbilityEffectReplicationRemoting
if RunService:IsServer() then
	AbilityEffectReplicationRemoting = Remoting.Server.new(ReplicatedStorage, "AbilityEffectReplication")
	AbilityEffectReplicationRemoting.EffectFired:DeclareEvent()
	AbilityEffectReplicationRemoting.EffectBroadcast:DeclareEvent()
else
	AbilityEffectReplicationRemoting = Remoting.Client.new(ReplicatedStorage, "AbilityEffectReplication")
end

return AbilityEffectReplicationRemoting
