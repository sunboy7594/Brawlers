--!strict
--[=[
	@class Tank_CannonServer

	탱크 캐논 기본공격 서버 모듈.

	onFire:
	- ProjectileHit.setPendingOnHit로 state.onHit 저장
	- ProjectileHitService가 RegisterProjectile 수신 시 takePendingOnHit로 픽업
	- 투사체 충돌 검증 후 onHit(hitMap) → onHitChecked 후크 실행

	onHitChecked:
	- 적을 맞추면 damage 30 적용
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local PlayerStateUtils = require("PlayerStateUtils")
local ProjectileHit = require("ProjectileHit")

local DAMAGE = 30

type BasicAttackState = {
	attacker       : Model?,
	attackerPlayer : Player?,
	onHit          : any?,
	fireMaid       : any?,
	victims        : any?,
	hitMap         : any?,
	playerStateController : any?,
}

return {
	onFire = {
		function(state: BasicAttackState)
			if not state.attackerPlayer then return end

			-- state.onHit을 저장해 둔.
			-- ProjectileHitService가 RegisterProjectile 수신 시 takePendingOnHit로 가져감.
			-- 이후 투사체 충돌 검증 통과 시 onHit(hitMap) → onHitChecked 실행.
			ProjectileHit.setPendingOnHit(state.attackerPlayer.UserId, state.onHit)
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
