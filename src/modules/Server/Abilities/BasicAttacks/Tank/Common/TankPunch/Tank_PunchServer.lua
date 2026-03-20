--!strict
--[=[
	@class Tank_PunchServer

	탱크 주먹 공격 서버 모듈.

	onFire:
	- InstantHit.verdict()로 멀티 shape 판정.
	- state.latency를 전달해 delay를 앞당김.
	- 1,2콤보: main  cone range 8  / angleMin=-45, angleMax=45
	- 3콤보:   inner cone range 5  / angleMin=-45, angleMax=45 (강타)
	           outer cone range 10 / angleMin=-60, angleMax=60 (날림)

	onHitChecked:
	- 1,2콤보: damage 20
	- 3콤보 inner: damage 40 + knockback
	- 3콤보 outer (inner 미포함): damage 20
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local InstantHit       = require("InstantHit")
local PlayerStateUtils = require("PlayerStateUtils")

type BasicAttackState = {
	currentStack          : number,
	intervalUntil         : number,
	effectiveAimTime      : number,
	origin                : Vector3,
	direction             : Vector3,
	idleTime              : number,
	fireComboCount        : number,
	latency               : number,
	indicator             : any,
	animator              : any?,
	fireMaid              : any?,
	victims               : InstantHit.VictimSet?,
	hitMap                : InstantHit.HitMapResult?,
	attacker              : Model?,
	onHit                 : ((results: InstantHit.HitMapResult) -> ())?,
	teamService           : any?,
	attackerPlayer        : Player?,
	playerStateController : any?,
	attackerStates        : { any }?,
}

local IDLE_COMBO_RESET = 3.0

return {
	onFire = {
		function(state: BasicAttackState)
			if not state.attacker then return end

			if state.idleTime >= IDLE_COMBO_RESET then
				state.fireComboCount = 0
			end
			state.fireComboCount = (state.fireComboCount % 3) + 1

			if state.fireComboCount == 3 then
				InstantHit.verdict(
					state.attacker, state.origin, state.direction,
					{
						inner = { shape = "cone", range = 5,  angleMin = -45, angleMax = 45 },
						outer = { shape = "cone", range = 10, angleMin = -60, angleMax = 60 },
					},
					state.onHit, state.fireMaid, state.teamService, state.attackerPlayer,
					state.latency
				)
			else
				InstantHit.verdict(
					state.attacker, state.origin, state.direction,
					{
						main = { shape = "cone", range = 8, angleMin = -45, angleMax = 45 },
					},
					state.onHit, state.fireMaid, state.teamService, state.attackerPlayer,
					state.latency
				)
			end
		end,
	},

	onHitChecked = {
		function(snapshot: BasicAttackState)
			local victims = snapshot.victims
			if not victims or (#victims.enemies == 0) then return end

			local psc = snapshot.playerStateController
			if not psc then return end

			local attacker       = snapshot.attacker
			local attackerPlayer = Players:GetPlayerFromCharacter(attacker)
			local isHeavy        = snapshot.fireComboCount == 3

			if isHeavy then
				local hitMap   = snapshot.hitMap
				local innerSet : { [Model]: boolean } = {}

				local innerEnemies = if hitMap and hitMap.inner then hitMap.inner.enemies else {}
				for _, victimModel in innerEnemies do
					innerSet[victimModel] = true
					local victimPlayer = Players:GetPlayerFromCharacter(victimModel)
					if not victimPlayer then continue end

					local knockbackDir = Vector3.new(0, 0, -1)
					if attacker then
						local ar = attacker:FindFirstChild("HumanoidRootPart") :: BasePart?
						local vr = victimModel:FindFirstChild("HumanoidRootPart") :: BasePart?
						if ar and vr then
							local d = vr.Position - ar.Position
							if d.Magnitude > 0.001 then knockbackDir = d.Unit end
						end
					end

					PlayerStateUtils.PlayPlayerState(psc, victimPlayer, "damage", {
						amount = 40, source = attackerPlayer, intensity = 0.6, duration = 0.2,
					})
					PlayerStateUtils.PlayPlayerState(psc, victimPlayer, "knockback", {
						direction = knockbackDir, force = 60, source = attackerPlayer,
					})
				end

				local outerEnemies = if hitMap and hitMap.outer then hitMap.outer.enemies else {}
				for _, victimModel in outerEnemies do
					if innerSet[victimModel] then continue end
					local victimPlayer = Players:GetPlayerFromCharacter(victimModel)
					if not victimPlayer then continue end
					PlayerStateUtils.PlayPlayerState(psc, victimPlayer, "damage", {
						amount = 20, source = attackerPlayer, intensity = 0.3, duration = 0.2,
					})
				end
			else
				for _, victimModel in victims.enemies do
					local victimPlayer = Players:GetPlayerFromCharacter(victimModel)
					if not victimPlayer then continue end
					PlayerStateUtils.PlayPlayerState(psc, victimPlayer, "damage", {
						amount = 20, source = attackerPlayer, intensity = 0.3, duration = 0.2,
					})
				end
			end
		end,
	},
}
