--!strict
--[=[
	@class EntityReplicationRemoting

	Entity 복제용 Remote 채널. (Shared)

	채널:
	  EntityFired     : (클라이언트 → 서버) 비주얼 복제 알림
	    전달: defModule, defName, origin, sentAt, params, tags
	  EntityBroadcast : (서버 → 클라이언트) 다른 플레이어 엔티티 전달
	    전달: userId, defModule, defName, origin, sentAt, params, tags
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Remoting = require("Remoting")

local EntityReplicationRemoting
if RunService:IsServer() then
	EntityReplicationRemoting = Remoting.Server.new(ReplicatedStorage, "EntityReplication")
	EntityReplicationRemoting.EntityFired:DeclareEvent()
	EntityReplicationRemoting.EntityBroadcast:DeclareEvent()
else
	EntityReplicationRemoting = Remoting.Client.new(ReplicatedStorage, "EntityReplication")
end

return EntityReplicationRemoting
