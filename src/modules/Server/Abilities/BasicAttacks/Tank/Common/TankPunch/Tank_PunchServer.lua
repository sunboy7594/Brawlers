--!strict
--[=[
	@class Tank_PunchServer

	탱크 주먹 공격 서버 모듈.

	onFire:
	- InstantHit.apply()에 state.onHit을 콜백으로 전달
	- 1,2콤보: damage 20, cone range 8 / angle 90
	- 3콤보:   damage 40, cone range 10 / angle 120

	onHitChecked:
	- snapshot.playerStateController + PlayerStateUtils 사용
	- 1,2콤보: damage effect (anim_hit + screen_hit_red)
	- 3콤보:   knockback effect (anim_knockback + cam_knockback)
	           knockback 방향 = attacker → victim 수평 방향으로 계산
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local InstantHit = require("InstantHit")
local PlayerStateUtils = require("PlayerStateUtils")

type BasicAttackState = {
	currentStack: number,
	intervalUntil: number,
	effectiveAimTime: number,
	origin: Vector3,
	direction: Vector3,
	idleTime: number,
	fireComboCount: number,
	indicator: any,
	animator: any?,
	fireMaid: any?,
	victims: { any }?,
	-- 서버 모듈만 추가로 필요한 것
	attacker: Model?,
	onHit: ((victims: { Model }) -> ())?,
	playerStateController: any?,
	attackerStates: { any }?,
}

local IDLE_COMBO_RESET = 3.0

return {
	onFire = {
		function(state)
			if not state.attacker then
				return
			end

			if state.idleTime >= IDLE_COMBO_RESET then
				state.fireComboCount = 0
			end

			state.fireComboCount = (state.fireComboCount % 3) + 1

			if state.fireComboCount == 3 then
				-- 3콤보: 더 넓은 범위, 높은 대미지
				InstantHit.apply(state.attacker, state.origin, state.direction, {
					shape = "cone",
					range = 10,
					angle = 120,
					damage = 40,
					knockback = 0,
				}, state.onHit)
			else
				-- 1, 2콤보: 기본 펀치
				InstantHit.apply(state.attacker, state.origin, state.direction, {
					shape = "cone",
					range = 8,
					angle = 90,
					damage = 20,
					knockback = 0,
				}, state.onHit)
			end
		end,
	},

	onHitChecked = {
		function(snapshot)
			local victims = snapshot.victims
			if not victims or #victims == 0 then
				return
			end

			local psc = snapshot.playerStateController
			if not psc then
				return
			end

			local attacker = snapshot.attacker
			local attackerPlayer = Players:GetPlayerFromCharacter(attacker)
			local isHeavy = snapshot.fireComboCount == 3

			for _, victimModel in victims do
				local victimPlayer = Players:GetPlayerFromCharacter(victimModel)
				if not victimPlayer then
					continue
				end

				if isHeavy then
					-- 3콤보: 물리 넉백 + 넉백 애니메이션
					local knockbackDir = Vector3.new(0, 0, -1)
					if attacker then
						local attackerRoot = attacker:FindFirstChild("HumanoidRootPart") :: BasePart?
						local victimRoot = victimModel:FindFirstChild("HumanoidRootPart") :: BasePart?
						if attackerRoot and victimRoot then
							local diff = victimRoot.Position - attackerRoot.Position
							local horizontal = Vector3.new(diff.X, 0, diff.Z)
							if horizontal.Magnitude > 0.001 then
								knockbackDir = horizontal.Unit
							end
						end
					end

					PlayerStateUtils.PlayPlayerState(psc, victimPlayer, "knockback", {
						direction = knockbackDir,
						knockbackForce = 100,
						source = attackerPlayer,
						intensity = 0.8,
					})
				else
					-- 1, 2콤보: 약한 피격 반응
					PlayerStateUtils.PlayPlayerState(psc, victimPlayer, "damage", {
						amount = 0,
						source = attackerPlayer,
						intensity = 0.2,
						duration = 0.25,
					})
				end
			end
		end,
	},
}
