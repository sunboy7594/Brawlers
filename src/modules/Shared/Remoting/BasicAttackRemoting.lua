--!strict
--[=[
	@class BasicAttackRemoting

	기본 공격 관련 Remote 채널.

	채널 목록:
	- AimStarted:    (클라이언트 → 서버) 조준 시작 알림 (서버의 aimStartTime 기록용)
	- Fire:          (클라이언트 → 서버) 공격 발사 (direction: Vector3)
	- AmmoChanged:   (서버 → 클라이언트) 탄약 변경 알림
	                 (current, max, reloadTime, postDelay: number)
	- HitConfirmed:  (서버 → 모든 클라이언트) 히트 확정 알림
	                 (attackerUserId: number, victims: { number }, comboCount: number)
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remoting = require("Remoting")

local BasicAttackRemoting
if RunService:IsServer() then
	BasicAttackRemoting = Remoting.Server.new(ReplicatedStorage, "BasicAttack")
	BasicAttackRemoting.AimStarted:DeclareEvent()
	BasicAttackRemoting.Fire:DeclareEvent()
	BasicAttackRemoting.AmmoChanged:DeclareEvent()
	BasicAttackRemoting.HitChecked:DeclareEvent() -- HitConfirmed → HitChecked
else
	BasicAttackRemoting = Remoting.Client.new(ReplicatedStorage, "BasicAttack")
end

return BasicAttackRemoting
