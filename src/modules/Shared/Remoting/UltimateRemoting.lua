--!strict
--[=[
	@class UltimateRemoting

	궁극기 관련 Remote 채널을 관리하는 공유 모듈.
	서버/클라이언트 모두 이 모듈을 require하여 사용합니다.

	채널 목록:
	- Cast:         (클라이언트 → 서버) 궁극기 시전
	- CooldownSync: (서버 → 클라이언트) 쿨다운 동기화 (remaining: number)
	- ChargeSync:   (서버 → 클라이언트) 궁극기 게이지 동기화 (current: number, max: number)
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remoting = require("Remoting")

-- 서버/클라이언트 자동 분기
local UltimateRemoting
if RunService:IsServer() then
	UltimateRemoting = Remoting.Server.new(ReplicatedStorage, "Ultimate")
	-- 클라이언트 → 서버 방향 이벤트 사전 선언
	UltimateRemoting.Cast:DeclareEvent()
	-- 서버 → 클라이언트 방향 이벤트 사전 선언
	UltimateRemoting.CooldownSync:DeclareEvent()
	UltimateRemoting.ChargeSync:DeclareEvent()
else
	UltimateRemoting = Remoting.Client.new(ReplicatedStorage, "Ultimate")
end

return UltimateRemoting
