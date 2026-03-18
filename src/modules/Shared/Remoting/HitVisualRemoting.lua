--!strict
--[=[
	@class HitVisualRemoting

	히트 비주얼 원격 채널.

	채널:
	- HitVisual: (서버 → 전체 클라이언트) 히트 비주얼 발동
	  payload: HitVisualPayload
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remoting = require("Remoting")

local HitVisualRemoting
if RunService:IsServer() then
	HitVisualRemoting = Remoting.Server.new(ReplicatedStorage, "HitVisual")
	HitVisualRemoting.HitVisual:DeclareEvent()
else
	HitVisualRemoting = Remoting.Client.new(ReplicatedStorage, "HitVisual")
end

return HitVisualRemoting
