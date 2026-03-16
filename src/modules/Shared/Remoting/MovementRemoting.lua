--!strict
--[=[
	@class MovementRemoting

	이동 관련 Remote 채널을 관리하는 공유 모듈.
	서버/클라이언트 모두 이 모듈을 require하여 사용합니다.

	채널 목록:
	- IsRunning: (클라이언트 → 서버) Shift 달리기 상태 전송 (isRunning: boolean)
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remoting = require("Remoting")

-- 서버/클라이언트 자동 분기
local MovementRemoting
if RunService:IsServer() then
	MovementRemoting = Remoting.Server.new(ReplicatedStorage, "Movement")
	-- 클라이언트 → 서버 방향 이벤트 사전 선언
	MovementRemoting.IsRunning:DeclareEvent()
else
	MovementRemoting = Remoting.Client.new(ReplicatedStorage, "Movement")
end

return MovementRemoting
