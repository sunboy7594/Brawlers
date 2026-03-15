--!strict
--[=[
	@class Tank_PunchServer

	탱크 주먹 공격 서버 모듈.

	onFire 배열의 함수들은 state를 받고, { Model } 반환 시
	BasicAttackService가 victims로 합산합니다.
]=]

local require = require(script.Parent.loader).load(script)

local InstantHit = require("InstantHit")

-- state 타입 (참조용, 실제 타입은 BasicAttackService에 정의)
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
}

local IDLE_COMBO_RESET = 3.0

return {
	onFire = {
		function(state: BasicAttackState): { Model }
			if not state.attacker then
				return {}
			end

			-- 오랫동안 공격 안 했으면 콤보 리셋
			if state.idleTime >= IDLE_COMBO_RESET then
				state.fireComboCount = 0
			end

			state.fireComboCount = (state.fireComboCount % 3) + 1

			if state.fireComboCount == 3 then
				-- 3콤보: 더 넓은 범위
				return InstantHit.apply(state.attacker, state.origin, state.direction, {
					shape = "cone",
					range = 10,
					angle = 120,
					damage = 60,
					knockback = 25,
				}) :: { Model }
			else
				-- 1, 2콤보: 기본 펀치
				return InstantHit.apply(state.attacker, state.origin, state.direction, {
					shape = "cone",
					range = 8,
					angle = 90,
					damage = 40,
					knockback = 15,
				}) :: { Model }
			end
		end,
	},

	onHitChecked = {},
}
