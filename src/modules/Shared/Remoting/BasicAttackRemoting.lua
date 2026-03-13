--!strict
--[=[
	@class BasicAttackRemoting

	기본 공격 관련 Remote 채널을 관리하는 공유 모듈.
	서버/클라이언트 모두 이 모듈을 require하여 사용합니다.

	채널 목록:
	- Fire:        (클라이언트 → 서버) 공격 발사 (direction: Vector3, aimTime: number)
	- AmmoChanged: (서버 → 클라이언트) 탄약 변경 알림 (current: number, max: number, reloadTime: number)
	  reloadTime을 같이 보내는 이유: 클라이언트가 자체적으로 장전 progress를 계산해 UI에 표시하기 위함
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remoting = require("Remoting")

-- 서버/클라이언트 자동 분기
local BasicAttackRemoting
if RunService:IsServer() then
	BasicAttackRemoting = Remoting.Server.new(ReplicatedStorage, "BasicAttack")
	-- 클라이언트 → 서버 방향 이벤트 사전 선언
	BasicAttackRemoting.Fire:DeclareEvent()
	-- 서버 → 클라이언트 방향 이벤트 사전 선언
	BasicAttackRemoting.AmmoChanged:DeclareEvent()
else
	BasicAttackRemoting = Remoting.Client.new(ReplicatedStorage, "BasicAttack")
end

return BasicAttackRemoting
