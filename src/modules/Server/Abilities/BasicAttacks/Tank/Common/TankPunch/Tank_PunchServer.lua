--!strict
--[=[
	@class Tank_PunchServer

	탱크 주먹 공격 서버 모듈.

	onFire:
	- InstantHit.apply()에 state.onHit을 콜백으로 전달
	- 1,2콤보: damage 20, cone range 8 / angle 90
	- 3콤보:   damage 40, cone range 10 / angle 120

	onHitChecked:
	- snapshot.playerStateService로 ChangePlayerState 호출
	- 1,2콤보: anim_hit + cam_shake (intensity 낮게)
	- 3콤보:   knockback component (실제 물리 넉백) + anim_knockback + cam_knockback
	           knockback 방향 = attacker → victim 수평 방향으로 계산
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local InstantHit = require("InstantHit")

type BasicAttackState = {
	equippedAttackId: string?,
	humanoid: Humanoid?,
	rootPart: BasePart?,
	currentAmmo: number,
	maxAmmo: number,
	reloadTime: number,
	postDelay: number,
	lastFireTime: number,
	postDelayUntil: number,
	lastRegenTime: number,
	lastHitTime: number,
	aimStartTime: number,
	fireComboCount: number,
	hitComboCount: number,
	attacker: Model?,
	origin: Vector3,
	direction: Vector3,
	aimTime: number,
	effectiveAimTime: number,
	idleTime: number,
	victims: { Model }?,
	onHit: ((victims: { Model }) -> ())?,
	pendingFireCancel: (() -> ())?,
	playerStateService: any?,
}

local IDLE_COMBO_RESET = 3.0

return {
	onFire = {
		function(state: BasicAttackState)
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
					knockback = 0, -- 물리 넉백은 onHitChecked의 knockback component가 담당
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
		function(snapshot: BasicAttackState)
			local victims = snapshot.victims
			if not victims or #victims == 0 then
				return
			end

			local pss = snapshot.playerStateService
			if not pss then
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
					-- 3콤보: 실제 물리 넉백 + 넉백 애니메이션
					-- 공격자 → 피격자 수평 방향 계산
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

					pss:ChangePlayerState(victimPlayer, {
						source = attackerPlayer,
						force = false,
						tags = {
							{ name = "anim_knockback", duration = 0.5, intensity = 0.8 },
							{ name = "cam_knockback", duration = 0.4, intensity = 0.7 },
						},
						components = {
							{ type = "knockback", direction = knockbackDir, force = 100 },
						},
					})
				else
					-- 1, 2콤보: 약한 피격 반응만 (대미지는 InstantHit에서 처리)
					pss:ChangePlayerState(victimPlayer, {
						source = attackerPlayer,
						force = false,
						tags = {
							{ name = "anim_hit", duration = 0.25, intensity = 0.2 },
							{ name = "cam_shake", duration = 0.2, intensity = 0.15 },
						},
						components = {},
					})
				end
			end
		end,
	},
}
