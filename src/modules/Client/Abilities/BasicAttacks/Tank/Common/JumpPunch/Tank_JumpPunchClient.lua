--!strict
--[=[
	@class Tank_JumpPunchClient

	탱크 점프 펀치 클라이언트 모듈.
	실제 HRP 이동은 HRPMoveClient가 서버 신호 수신 후 로컬에서 처리.
	이 모듈은 조준 인디케이터 + 애니메이션만 담당.
]=]

local require = require(script.Parent.loader).load(script)

local LINE_RANGE = 15
local LINE_WIDTH = 1.5

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

			if state.animator then
				-- duration nil: fireMaid 소멸 때까지 애니메이션 유지
				state.animator:PlayAnimation("JumpPunch", nil, nil, true)
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
		end,
	},

	onHitChecked = {},
}
