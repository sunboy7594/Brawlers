--!strict
--[=[
	@class BasicAttackRemoting

	기본 공격 관련 Remote 채널.

	채널 목록:
	- AimStarted:  (클라이언트 → 서버) 조준 시작 알림 (서버의 aimStartTime 기록용)
	- Fire:        (클라이언트 → 서버) 공격 발사 (direction: Vector3)
	- AmmoChanged: (서버 → 클라이언트) 탄약 변경 알림
	               (current, max, reloadTime, postDelay: number)
	- HitChecked:  (서버 → 공격자만) 히트 체크 알림
	               (victimUserIds: { number })
	- HitReaction: (서버 → 피격자만) 피격 반응 알림
	               각 공격기술 onHitChecked에서 필요 시 FireClient로 발송
	               전달 데이터는 공격기술 모듈이 결정
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
	BasicAttackRemoting.HitChecked:DeclareEvent()
else
	BasicAttackRemoting = Remoting.Client.new(ReplicatedStorage, "BasicAttack")
end

return BasicAttackRemoting
