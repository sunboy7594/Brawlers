--!strict
--[=[
	@class Tank_RapidFirePunchServer

	탱크 연속 펀치 서버 모듈.

	onFire:
	  InstantHit.verdict() 로 직선(line) shape 판정.
	  range = 12 / width = 2.0
	  state.latency 전달로 클라이언트 sentAt 기준 보정.

	onHitChecked(snapshot, state):
	  hit 확정 시 enemies 에게 damage 12 적용.
	  (발당 낮은 데미지 × 높은 연사 속도 = 총 DPS 균형)

	onMissChecked:
	  현재 미처리.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local InstantHit       = require("InstantHit")
local PlayerStateUtils = require("PlayerStateUtils")

-- ─── 상수 ───────────────────────────────────────────────────────────────────

local LINE_RANGE  = 12
local LINE_WIDTH  = 2.0
local DAMAGE      = 12   -- 발당 데미지

-- ─── 타입 ───────────────────────────────────────────────────────────────────

type BasicAttackState = {
	attacker             : Model?,
	origin               : Vector3,
	direction            : Vector3,
	latency              : number,
	fireComboCount       : number,
	fireMaid             : any?,
	onHitResult          : ((hitMap: any?, handle: any?, hitInfo: any?) -> ())?,
	teamService          : any?,
	attackerPlayer       : Player?,
	playerStateController: any?,
	attackerStates       : { any }?,
	victims              : any?,
	hitMap               : any?,
}

-- ─── 모듈 ───────────────────────────────────────────────────────────────────

return {
	onFire = {
		function(state: BasicAttackState)
			if not state.attacker then return end

			-- line shape: 전방 직선 범위 판정
			InstantHit.verdict(
				state.attacker,
				state.origin,
				state.direction,
				{
					main = {
						shape  = "line",
						range  = LINE_RANGE,
						width  = LINE_WIDTH,
					},
				},
				state.onHitResult,
				state.fireMaid,
				state.teamService,
				state.attackerPlayer,
				state.latency
			)
		end,
	},

	onHitChecked = {
		function(snapshot: BasicAttackState, _state: BasicAttackState)
			local victims = snapshot.victims
			if not victims then return end

			-- enemies 가 1명 이상일 때만 처리
			local hitMap = snapshot.hitMap
			local enemies = if hitMap and hitMap.main
				then hitMap.main.enemies
				else (victims.enemies or {})

			if #enemies == 0 then return end

			local psc = snapshot.playerStateController
			if not psc then return end

			local attackerPlayer = Players:GetPlayerFromCharacter(snapshot.attacker)

			for _, victimModel in enemies do
				local victimPlayer = Players:GetPlayerFromCharacter(victimModel)
				if not victimPlayer then continue end

				PlayerStateUtils.PlayPlayerState(psc, victimPlayer, "damage", {
					amount    = DAMAGE,
					source    = attackerPlayer,
					intensity = 0.2,   -- 약한 피격 리액션 (연속 타격이므로 작게)
					duration  = 0.12,
				})
			end
		end,
	},

	onMissChecked = {},
}