--!strict
--[=[
	@class Tank_PunchClient
]=]

local require = require(script.Parent.loader).load(script)

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
}

local COMBO_ANIMS = { "Punch1", "Punch2", "Punch3" }
local IDLE_COMBO_RESET = 3.0

local ANGLE_MIN = 10
local ANGLE_MAX = 360
local ANGLE_EXPAND_TIME = 3.0 -- 10→360 까지 걸리는 시간 (초)

return {
	shapes = { cone = "cone" },

	onAimStart = {
		function(state)
			state.indicator:update("cone", { angleMin = -ANGLE_MIN / 2, angleMax = ANGLE_MIN / 2 })
		end,
	},

	onAim = {
		function(state)
			local now = os.clock()
			local canFire = state.currentStack > 0 and now >= state.intervalUntil

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
		function(state)
			-- 각도 리셋
			state.indicator:update("cone", { angleMin = -ANGLE_MIN / 2, angleMax = ANGLE_MIN / 2 })

			if state.idleTime >= IDLE_COMBO_RESET then
				state.fireComboCount = 0
			end
			state.fireComboCount = (state.fireComboCount % #COMBO_ANIMS) + 1

			if state.animator then
				local animName = COMBO_ANIMS[state.fireComboCount]
				state.animator:PlayAnimation(animName, 0.4, nil, true)

				-- 스턴 등 공격불가 시 애니메이션 중단 등록
				if state.fireMaid then
					state.fireMaid:GiveTask(function()
						state.animator:StopAnimation(animName)
					end)
				end
			end
		end,
	},

	onCancel = {
		function(state)
			-- 인디케이터 각도 리셋 (조준 취소 시 잔상 방지)
			state.indicator:update("cone", { angleMin = -ANGLE_MIN / 2, angleMax = ANGLE_MIN / 2 })
		end,
	},

	onHitChecked = {},
}
