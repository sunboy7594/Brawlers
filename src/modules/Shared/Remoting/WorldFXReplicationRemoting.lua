--!strict
--[=[
	@class WorldFXReplicationRemoting

	WorldFX 이펙트 복제용 Remote 채널. (Shared)

	채널 목록:
	- EffectFired     : (클라이언트 → 서버) 이펙트 발동 알림
	  전달: defModuleName, effectName, origin, direction?
	  서버가 firedAt(서버 시각)을 스탬핑하여 EffectBroadcast에 포함.

	- EffectBroadcast : (서버 → 클라이언트) 다른 플레이어 이펙트 전달
	  전달: userId, defModuleName, effectName, origin, direction?, firedAt
	  firedAt은 workspace:GetServerTimeNow() 기준 서버 시각.
	  클라이언트는 수신 시 elapsed = GetServerTimeNow() - firedAt 으로 fast-forward.

	서버는 이펙트를 직접 생성하지 않음. 검증 + 포워딩만 담당.
	실제 렌더링은 각 클라이언트가 AbilityEffect:Play()로 로컬 실행.
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remoting = require("Remoting")

local WorldFXReplicationRemoting
if RunService:IsServer() then
	WorldFXReplicationRemoting = Remoting.Server.new(ReplicatedStorage, "WorldFXReplication")
	WorldFXReplicationRemoting.EffectFired:DeclareEvent()
	WorldFXReplicationRemoting.EffectBroadcast:DeclareEvent()
else
	WorldFXReplicationRemoting = Remoting.Client.new(ReplicatedStorage, "WorldFXReplication")
end

return WorldFXReplicationRemoting
