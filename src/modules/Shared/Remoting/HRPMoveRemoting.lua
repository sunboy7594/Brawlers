--!strict
--[=[
	@class HRPMoveRemoting

	HRP(HumanoidRootPart) 직접 이동 관련 Remote 채널.
	서버가 HRP 이동을 권한 부여하고, 클라이언트가 로컬에서 실행 후 착지를 보고.

	채널:
	- Move:          (서버 → 클라이언트) HRP 이동 권한 부여
	                 전달: token(string), defModule(string), defName(string),
	                       origin(CFrame), params({ [string]: any }?)
	- LandingReport: (클라이언트 → 서버) 이동 완료 후 착지 위치 보고
	                 전달: token(string), actualPos(Vector3)
	                 서버는 token 유효성 + 위치 오차 검증 후 강제 보정
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Remoting = require("Remoting")

local HRPMoveRemoting
if RunService:IsServer() then
	HRPMoveRemoting = Remoting.Server.new(ReplicatedStorage, "HRPMove")
	HRPMoveRemoting.Move:DeclareEvent()
	HRPMoveRemoting.LandingReport:DeclareEvent()
else
	HRPMoveRemoting = Remoting.Client.new(ReplicatedStorage, "HRPMove")
end

return HRPMoveRemoting
