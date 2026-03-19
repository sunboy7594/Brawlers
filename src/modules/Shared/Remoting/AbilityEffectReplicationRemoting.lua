--!strict
--[=[
	@class AbilityEffectReplicationRemoting

	AbilityEffect 복제용 Remote 채널. (Shared)

	채널 목록:
	- Register      : (클라이언트 → 서버) 이펙트 등록
	  전달: defModuleName, effectName, origin, sentAt, params?
	  서버가 AbilityEffectSimulatorService에서 시뮬 시작.

	- EffectFired   : (클라이언트 → 서버) 비주얼 복제 알림
	  전달: defModuleName, effectName, origin, direction?, sentAt
	  서버가 EffectBroadcast로 타 클라이언트에 포워딩.

	- EffectBroadcast : (서버 → 클라이언트) 다른 플레이어 이펙트 전달
	  전달: userId, defModuleName, effectName, origin, direction?, sentAt
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remoting = require("Remoting")

local AbilityEffectReplicationRemoting
if RunService:IsServer() then
	AbilityEffectReplicationRemoting = Remoting.Server.new(ReplicatedStorage, "AbilityEffectReplication")
	AbilityEffectReplicationRemoting.Register:DeclareEvent()
	AbilityEffectReplicationRemoting.EffectFired:DeclareEvent()
	AbilityEffectReplicationRemoting.EffectBroadcast:DeclareEvent()
else
	AbilityEffectReplicationRemoting = Remoting.Client.new(ReplicatedStorage, "AbilityEffectReplication")
end

return AbilityEffectReplicationRemoting
