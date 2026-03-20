--!strict
--[=[
	@class Tank_CannonTestServer

	탱크 캐논 테스트 기본공격 서버 모듈.

	onFire:
	  ProjectileHit.fire()로 서버 독립 투사체 판정.
	  origin    = 서버 HRP 기준으로 직접 계산.
	  aimRatio  = state.aimTime 기준으로 서버가 직접 계산.
	  클라이언트에서 받은 값(origin, params) 일절 사용 안 함.

	onHitChecked:
	  적 맞춰면 damage 30 적용.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local HitDetectionUtil = require("HitDetectionUtil")
local HitOrMissUtil    = require("HitOrMissUtil")
local MoverUtil        = require("MoverUtil")
local PlayerStateUtils = require("PlayerStateUtils")
local ProjectileHit    = require("ProjectileHit")

-- 클라이언트(Tank_CannonTestClient)와 반드시 동일하게 유지
local PROJECTILE_SPEED  = 40
local MAX_RANGE         = 100
local BASE_HIT_SIZE     = 3
local MAX_HIT_SIZE      = 6
local ANGLE_EXPAND_TIME = 3.0

local DAMAGE = 30

type BasicAttackState = {
	attacker              : Model?,
	rootPart              : BasePart?,
	attackerPlayer        : Player?,
	direction             : Vector3,
	aimTime               : number,
	latency               : number,
	onHit                 : any?,
	fireMaid              : any?,
	teamService           : any?,
	victims               : any?,
	hitMap                : any?,
	playerStateController : any?,
}

return {
	onFire = {
		function(state: BasicAttackState)
			local hrp = state.rootPart
			if not hrp or not state.attacker then return end

			-- ✅ 서버 독립 origin: HRP 위치 + 검증된 direction
			local origin = CFrame.new(hrp.Position, hrp.Position + state.direction)

			-- ✅ 서버 독립 aimRatio: state.aimTime으로 직접 계산
			local aimRatio = math.clamp(state.aimTime / ANGLE_EXPAND_TIME, 0, 1)
			local hitSize  = BASE_HIT_SIZE + (MAX_HIT_SIZE - BASE_HIT_SIZE) * aimRatio

			ProjectileHit.fire(
				state.attacker,
				origin,
				{
					move = MoverUtil.Linear({
						speed    = PROJECTILE_SPEED,
						maxRange = MAX_RANGE,
						mode     = "linear",
					}),
					hitDetect = HitDetectionUtil.Box({
						size = Vector3.new(hitSize, hitSize, hitSize),
					}),
					onHit   = HitOrMissUtil.Despawn(),
					onMiss  = nil,
					params  = nil,
					latency = state.latency,
					delay   = 0,
				},
				state.fireMaid,
				state.teamService,
				state.attackerPlayer
			)
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
