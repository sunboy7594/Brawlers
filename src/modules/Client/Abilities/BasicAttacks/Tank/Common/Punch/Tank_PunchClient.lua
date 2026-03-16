--!strict
--[=[
	@class Tank_PunchClient

	탱크 주먹 공격 클라이언트 모듈.

	훅 실행 타이밍:
	- onAimStart   : 조준 시작 1회
	- onAim        : 매 프레임
	- onFire       : 발사 확정 후 (애니메이션, 로컬 이펙트)
	- onHitChecked : 서버 히트 체크 완료 후 (사운드, 히트 이펙트)
]=]

-- state 타입 (참조용, 실제 타입은 BasicAttackClient에 정의)
type BasicAttackState = {
	currentAmmo: number,
	postDelayUntil: number,
	lastHitTime: number,
	aimTime: number,
	idleTime: number,
	fireComboCount: number,
	hitComboCount: number,
	direction: Vector3,
	origin: Vector3,
	indicator: any,
	animator: any?,
	victims: { any }?,
}

local COMBO_ANIMS = { "Punch1", "Punch2", "Punch3" }
local IDLE_COMBO_RESET = 3.0

return {
	shapes = { "cone" },

	-- ─── 조준 시작 ───────────────────────────────────────────────────────
	onAimStart = {
		function(_state: BasicAttackState) end,
	},

	-- ─── 매 프레임 ──────────────────────────────────────────────────────
	onAim = {},

	-- ─── 발사 확정 ──────────────────────────────────────────────────────
	onFire = {
		function(state: BasicAttackState)
			-- 오랫동안 공격 안 했으면 콤보 리셋
			if state.idleTime >= IDLE_COMBO_RESET then
				state.fireComboCount = 0
			end

			state.fireComboCount = (state.fireComboCount % #COMBO_ANIMS) + 1

			if state.animator then
				local animName = COMBO_ANIMS[state.fireComboCount]
				state.animator:PlayAnimation(animName, 0.4, nil, true)
			end
		end,
	},

	-- ─── 히트 체크 완료 ─────────────────────────────────────────────────
	onHitChecked = {},
}
