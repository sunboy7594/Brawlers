--!strict
--[=[
	@class SkillRemoting

	스킬 관련 Remote 채널을 관리하는 공유 모듈.
	서버/클라이언트 모두 이 모듈을 require하여 사용합니다.

	채널 목록:
	- Cast:         (클라이언트 → 서버) 스킬 시전
	- CooldownSync: (서버 → 클라이언트) 쿨다운 동기화 (remaining: number)
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remoting = require("Remoting")

-- 서버/클라이언트 자동 분기
local SkillRemoting
if RunService:IsServer() then
	SkillRemoting = Remoting.Server.new(ReplicatedStorage, "Skill")
	-- 클라이언트 → 서버 방향 이벤트 사전 선언
	SkillRemoting.Cast:DeclareEvent()
	-- 서버 → 클라이언트 방향 이벤트 사전 선언
	SkillRemoting.CooldownSync:DeclareEvent()
else
	SkillRemoting = Remoting.Client.new(ReplicatedStorage, "Skill")
end

return SkillRemoting
