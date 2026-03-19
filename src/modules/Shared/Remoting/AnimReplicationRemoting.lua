--!strict
--[=[
	@class AnimReplicationRemoting

	절차적 애니메이션 복제용 Remote 채널. (Shared)

	채널 목록:
	- AnimChanged     : (클라이언트 → 서버) 애니메이션 전환 알림
	  전달: animDefModuleName, animName, animType, layer, duration, defaultC0Map, params
	- AnimStopped     : (클라이언트 → 서버) 애니메이션 정지 알림
	  전달: animDefModuleName, animName
	- AnimBroadcast   : (서버 → 클라이언트) 다른 플레이어 애니메이션 전달
	  전달: userId, animDefModuleName, animName, animType, layer, duration, defaultC0Map, params
	- AnimStopBroadcast: (서버 → 클라이언트) 다른 플레이어 애니메이션 정지 전달
	  전달: userId, animDefModuleName?, animName? (nil이면 해당 플레이어 전체 정지)
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remoting = require("Remoting")

local AnimReplicationRemoting
if RunService:IsServer() then
	AnimReplicationRemoting = Remoting.Server.new(ReplicatedStorage, "AnimReplication")
	AnimReplicationRemoting.AnimChanged:DeclareEvent()
	AnimReplicationRemoting.AnimStopped:DeclareEvent()
	AnimReplicationRemoting.AnimBroadcast:DeclareEvent()
	AnimReplicationRemoting.AnimStopBroadcast:DeclareEvent()
else
	AnimReplicationRemoting = Remoting.Client.new(ReplicatedStorage, "AnimReplication")
end

return AnimReplicationRemoting
