--!strict
--[=[
	@class BasicAttackRemoting

	기본 공격 관련 Remote 채널.

	채널 목록:
	- AimStarted:    (클라이언트 → 서버) 조준 시작 알림 (서버의 aimStartTime 기록용)
	- Fire:          (클라이언트 → 서버) 개별 발사 (direction: Vector3, sentAt: number, clientOrigin: Vector3?)
	                 clientOrigin: 발사 시점 클라이언트 HRP 위치 (레이턴시 보정용, 신뢰함)
	                 서버 rootPart와 8 studs 이상 차이 시 서버 위치로 폴백
	                 stack: 1회 발사 / hold,toggle: 루프 내 매 틱 발사
	- FireEnd:       (클라이언트 → 서버) hold/toggle 발사 루프 종료 알림
	                 서버가 isFiring=false, regenDelay 타이머 시작
	- ResourceSync:  (서버 → 클라이언트) 리소스 보정 신호
	                 클라이언트가 병렬 추적 중인 값을 서버 기준으로 재조정
	                 stack: 발사마다 + 장전 틱마다
	                   payload: { resourceType="stack", currentStack, maxStack, reloadTime, interval }
	                 gauge: 발사마다 + 소진 시 + max 도달 시
	                   payload: { resourceType="gauge", currentGauge, maxGauge, minGauge, drainRate, regenRate, regenDelay, interval }
	                 currentGauge=0 or currentStack=0 수신 시 클라이언트가 즉시 루프 캔슬
	- HitChecked:    (서버 → 공격자만) 히트 체크 알림 (victimUserIds: { number })
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
	BasicAttackRemoting.FireEnd:DeclareEvent()
	BasicAttackRemoting.ResourceSync:DeclareEvent()
	BasicAttackRemoting.HitChecked:DeclareEvent()
else
	BasicAttackRemoting = Remoting.Client.new(ReplicatedStorage, "BasicAttack")
end

return BasicAttackRemoting
