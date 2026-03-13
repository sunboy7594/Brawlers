--!strict
--[=[
	@class ClassRemoting

	직업 클래스 관련 Remote 채널을 관리하는 공유 모듈.
	서버/클라이언트 모두 이 모듈을 require하여 사용합니다.

	채널 목록:
	- ClassChanged:      (서버 → 클라이언트) 직업 클래스 변경 확정 알림 (className: string)
	- RequestClassChange: (클라이언트 → 서버) 클래스 변경 요청 (className: string) → (success: boolean, result: string)
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remoting = require("Remoting")

-- 서버/클라이언트 자동 분기
local ClassRemoting
if RunService:IsServer() then
	ClassRemoting = Remoting.Server.new(ReplicatedStorage, "Class")
	-- 서버 → 클라이언트 방향 이벤트 사전 선언
	ClassRemoting.ClassChanged:DeclareEvent()
	-- 클라이언트 → 서버 방향 함수 사전 선언
	ClassRemoting.RequestClassChange:DeclareMethod()
else
	ClassRemoting = Remoting.Client.new(ReplicatedStorage, "Class")
end

return ClassRemoting
