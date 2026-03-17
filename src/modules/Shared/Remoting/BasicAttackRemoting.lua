--!strict
--[=[
	@class BasicAttackRemoting

	기본 공격 관련 Remote 채널.

	채널 목록:
	- AimStarted:      (클라이언트 → 서버) 조준 시작 알림 (서버의 aimStartTime 기록용)
	- Fire:            (클라이언트 → 서버) 개별 발사 (direction: Vector3)
	                   stack: 1회 발사 / hold,toggle: 루프 내 매 틱 발사
	- FireStart:       (클라이언트 → 서버) hold/toggle 발사 루프 시작 알림
	                   서버가 gauge drain 시작, isAttackLocked 상태 검증용
	- FireEnd:         (클라이언트 → 서버) hold/toggle 발사 루프 종료 알림
	                   서버가 gauge drain 중단, regenDelay 타이머 시작
	- ResourceChanged: (서버 → 클라이언트) 리소스 상태 변경 알림
	                   payload: { resourceType, interval, ...resource-specific }
	                   stack:   { resourceType="stack", currentStack, maxStack, reloadTime, interval }
	                   gauge:   { resourceType="gauge", currentGauge, maxGauge, drainRate, regenRate, regenDelay, interval }
	- HitChecked:      (서버 → 공격자만) 히트 체크 알림 (victimUserIds: { number })
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
	BasicAttackRemoting.FireStart:DeclareEvent()
	BasicAttackRemoting.FireEnd:DeclareEvent()
	BasicAttackRemoting.ResourceChanged:DeclareEvent()
	BasicAttackRemoting.HitChecked:DeclareEvent()
else
	BasicAttackRemoting = Remoting.Client.new(ReplicatedStorage, "BasicAttack")
end

return BasicAttackRemoting
