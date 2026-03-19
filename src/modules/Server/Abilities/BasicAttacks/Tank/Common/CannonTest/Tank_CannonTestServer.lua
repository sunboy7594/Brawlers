--!strict
--[=[
	@class Tank_CannonTestServer

	탱크 캐논 테스트 기본공격 서버 모듈.

	onFire:
	  AbilityEffectSimulatorService에 onHit 콜백 등록.
	  Register(AbilityEffectReplicationRemoting) 수신 시
	  Simulator가 판정 후 onHit 호출 → onHitChecked 실행.

	onHitChecked:
	  적 맞춰면 damage 30 적용.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local PlayerStateUtils = require("PlayerStateUtils")

local DAMAGE = 30

type BasicAttackState = {
	attacker              : Model?,
	attackerPlayer        : Player?,
	onHit                 : any?,
	fireMaid              : any?,
	latency               : number,
	victims               : any?,
	hitMap                : any?,
	playerStateController : any?,
}

return {
	onFire = {
		function(state: BasicAttackState)
			-- state.onHit은 BasicAttackService._executeFire에서 이미 설정됨.
			-- AbilityEffectSimulatorService에도 BasicAttackService가 등록해두어,
			-- Register 수신 시 Simulator가 pickup → 판정 → state.onHit 호출.
			-- 서버 모듈에서는 별도로 할 일 없음.
		end,
	},

	onHitChecked = {
		function(snapshot: BasicAttackState)
			local victims = snapshot.victims
			if not victims or #victims.enemies == 0 then return end

			local psc = snapshot.playerStateController
			if not psc then return end

			local attackerPlayer = Players:GetPlayerFromCharacter(snapshot.attacker)

			for _, victimModel in victims.enemies do
				local victimPlayer = Players:GetPlayerFromCharacter(victimModel)
				if not victimPlayer then continue end

				PlayerStateUtils.PlayPlayerState(psc, victimPlayer, "damage", {
					amount    = DAMAGE,
					source    = attackerPlayer,
					intensity = 0.3,
					duration  = 0.2,
				})
			end
		end,
	},
}
