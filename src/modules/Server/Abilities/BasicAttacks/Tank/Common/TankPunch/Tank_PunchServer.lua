--!strict
--[=[
	@class Tank_PunchServer

	탱크 주먹 공격 서버 모듈.

	onFire:
	- InstantHit.apply()에 state.onHit을 콜백으로 전달
	- 판정 완료 시 BasicAttackService의 onHit 콜백이 호출됨
	- 반환값 없음 (HitChecked 타이밍은 InstantHit → onHit 콜백이 담당)

	onHitChecked:
	- snapshot(Fire 시점 state 복사본)을 받음
	- HitReaction 등 피격자 신호가 필요하면 여기서 BasicAttackRemoting.HitReaction:FireClient()
]=]

local require = require(script.Parent.loader).load(script)

local InstantHit = require("InstantHit")

type BasicAttackState = {
	attacker: Model?,
	origin: Vector3,
	direction: Vector3,
	aimTime: number,
	idleTime: number,
	lastHitTime: number,
	fireComboCount: number,
	hitComboCount: number,
	currentAmmo: number,
	victims: { Model }?,
	onHit: ((victims: { Model }) -> ())?,
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
				-- 3콤보: 더 넓은 범위
				InstantHit.apply(state.attacker, state.origin, state.direction, {
					shape = "cone",
					range = 10,
					angle = 120,
					damage = 60,
					knockback = 25,
				}, state.onHit)
			else
				-- 1, 2콤보: 기본 펀치
				InstantHit.apply(state.attacker, state.origin, state.direction, {
					shape = "cone",
					range = 8,
					angle = 90,
					damage = 40,
					knockback = 15,
				}, state.onHit)
			end
		end,
	},

	onHitChecked = {
		-- snapshot을 받음 (Fire 시점 컨텍스트)
		-- 피격자에게 HitReaction 보낼 필요 있으면 여기서 처리
		-- 예: BasicAttackRemoting.HitReaction:FireClient(victimPlayer, { attackId = snapshot.equippedAttackId, ... })
	},
}
