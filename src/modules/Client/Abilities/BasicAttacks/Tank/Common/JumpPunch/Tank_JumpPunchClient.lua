--!strict
--[=[
	@class Tank_JumpPunchClient

	탱크 점프 펀치 클라이언트 모듈.
	조준 인디케이터 + 애니메이션 + lerp alpha 조절 담당.

	lerp alpha:
	  onFire: 0.2로 낮춤 (큰 이동 구간)
	  fireMaid 정리 시 자동 복원 (ResetLerpAlpha)
]=]

local require = require(script.Parent.loader).load(script)

local LINE_RANGE = 15
local LINE_WIDTH = 1.5

local JUMP_ANIM_DURATION = 15 / 28 + 0.5 -- arc 시간 + 여유

local LERP_ALPHA_JUMP = 0.2 -- 점프 중 낮은 lerp (빠른 이동)

type BasicAttackState = {
	origin: Vector3,
	direction: Vector3,
	effectiveAimTime: number,
	fireComboCount: number,
	isFiring: boolean,
	indicator: any,
	animator: any?,
	fireMaid: any?,
	teamContext: { color: Color3?, [string]: any }?,
	cloneBroadcastClient: any?, -- BasicAttackClient에서 주입
}

return {
	shapes = {
		aimLine = "line",
	},

	onAimStart = {
		function(state: BasicAttackState)
			state.indicator:update("aimLine", {
				origin = state.origin,
				direction = state.direction,
				range = LINE_RANGE,
				width = LINE_WIDTH,
			})
			state.indicator:show("aimLine")
		end,
	},

	onAim = {
		function(state: BasicAttackState)
			state.indicator:update("aimLine", {
				origin = state.origin,
				direction = state.direction,
			})
		end,
	},

	onFire = {
		function(state: BasicAttackState)
			state.indicator:hideAll()

			-- 점프 구간 동안 lerp alpha 낮춤
			local cbc = state.cloneBroadcastClient
			if cbc then
				cbc:SetLerpAlpha(LERP_ALPHA_JUMP)
				if state.fireMaid then
					state.fireMaid:GiveTask(function()
						cbc:ResetLerpAlpha()
					end)
				end
			end

			if state.animator then
				state.animator:PlayAnimation("JumpPunch", JUMP_ANIM_DURATION, nil, true)
				if state.fireMaid then
					state.fireMaid:GiveTask(function()
						state.animator:StopAnimation("JumpPunch")
					end)
				end
			end
		end,
	},

	onCancel = {
		function(state: BasicAttackState)
			state.indicator:hideAll()

			-- 취소 시에도 lerp 복원
			local cbc = state.cloneBroadcastClient
			if cbc then
				cbc:ResetLerpAlpha()
			end
		end,
	},

	onHitChecked = {},
}
