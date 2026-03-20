--!strict
--[=[
	@class AbilityEffectReplicationRemoting

	AbilityEffect 복제용 Remote 채널. (Shared)

	채널 목록:
	- EffectFired     : (클라이언트 → 서버) 비주얼 복제 알림
	  전달: defModuleName, effectName, origin, sentAt
	  서버가 EffectBroadcast로 타 클라이언트에 포워딩.

	- EffectBroadcast : (서버 → 클라이언트) 다른 플레이어 이펙트 전달
	  전달: userId, defModuleName, effectName, origin, sentAt

	변경:
	  Register 채널 제거.
	  서버 투사체 판정은 BasicAttack.Fire Remote 수신 후
	  서버 모듈(onFire)에서 ProjectileHit.fire()로 직접 처리.
	  클라이언트에서 origin/params를 서버 판정에 쓰지 않음.
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
