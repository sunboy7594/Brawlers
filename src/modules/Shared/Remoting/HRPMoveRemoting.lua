--!strict
--[=[
	@class HRPMoveRemoting

	HRP 이동 Remote 채널.

	채널 목록:
	- PlayMove: (서버 → 클라이언트) HRP 이동 시작
	            전달: entityDefModule (string), defName (string), originCF (CFrame)
	- StopMove: (서버 → 클라이언트) HRP 이동 강제 중단
	            전달: 없음 (해당 플레이어의 현재 HRP 이동 중단)
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remoting = require("Remoting")

local HRPMoveRemoting
if RunService:IsServer() then
	HRPMoveRemoting = Remoting.Server.new(ReplicatedStorage, "HRPMove")
	HRPMoveRemoting.PlayMove:DeclareEvent()
	HRPMoveRemoting.StopMove:DeclareEvent()
else
	HRPMoveRemoting = Remoting.Client.new(ReplicatedStorage, "HRPMove")
end

return HRPMoveRemoting
