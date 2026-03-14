--!strict
--[=[
	@class AnimReplicationRemoting

	절차적 애니메이션 서버 복제용 Remote 채널. (Shared)

	채널 목록:
	- AnimChanged: (클라이언트 → 서버) 애니메이션 전환 알림
	  (animDefModuleName: string, animName: string, layer: number, defaultC0Map: { [string]: CFrame })
	- AnimStopped: (클라이언트 → 서버) 애니메이션 정지 알림
	  (animDefModuleName: string, animName: string)
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
else
	AnimReplicationRemoting = Remoting.Client.new(ReplicatedStorage, "AnimReplication")
end

return AnimReplicationRemoting
