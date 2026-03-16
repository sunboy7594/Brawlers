--!strict
--[=[
	@class Tank_PunchClient
]=]

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

local ANGLE_MIN = 10
local ANGLE_MAX = 360
local ANGLE_EXPAND_TIME = 3.0 -- 10→360 까지 걸리는 시간 (초)

return {
	-- id = "cone" 으로 DynamicIndicator에 전달
	shapes = { cone = "cone" },

	onAimStart = {
		function(state: BasicAttackState)
			state.indicator:update("cone", { angleMin = -ANGLE_MIN / 2, angleMax = ANGLE_MIN / 2 })
		end,
	},

	onAim = {
		function(state: BasicAttackState)
			local now = os.clock()
			local canFire = state.currentAmmo > 0 and now >= state.postDelayUntil

			if canFire then
				local t = math.clamp(state.effectiveAimTime / ANGLE_EXPAND_TIME, 0, 1)
				local angle = ANGLE_MIN + (ANGLE_MAX - ANGLE_MIN) * t
				state.indicator:update("cone", {
					origin = state.origin,
					direction = state.direction,
					angleMin = -angle / 2,
					angleMax = angle / 2,
				})
			else
				state.indicator:update("cone", {
					origin = state.origin,
					direction = state.direction,
				})
			end
		end,
	},

	onFire = {
		function(state: BasicAttackState)
			-- 각도 리셋
			state.indicator:update("cone", { angleMin = -ANGLE_MIN / 2, angleMax = ANGLE_MIN / 2 })

			if state.idleTime >= IDLE_COMBO_RESET then
				state.fireComboCount = 0
			end
			state.fireComboCount = (state.fireComboCount % #COMBO_ANIMS) + 1

			if state.animator then
				state.animator:PlayAnimation(COMBO_ANIMS[state.fireComboCount], 0.4, nil, true)
			end
		end,
	},

	onHitChecked = {},
}
