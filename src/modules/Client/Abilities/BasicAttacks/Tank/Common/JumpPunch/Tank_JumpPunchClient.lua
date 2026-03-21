--!strict
--[=[
	@class Tank_JumpPunchClient

	탱크 점프 펀치 클라이언트 모듈.

	실제 HRP 이동은 HRPMoveClient가 서버 신호를 받아 자동 처리.
	이 모듈은 조준 인디케이터 + 애니메이션만 담당.

	동작 흐름:
	  [조준]
	    onAimStart → line 인디케이터 show
	    onAim      → origin/direction 갱신

	  [fire]
	    onFire:
	      - 인디케이터 hide
	      - JumpPunch 애니메이션 재생
	      - (HRPMoveClient가 서버 신호 받으면 자동으로 로컬 arc 시작)

	  [취소]
	    onCancel → 인디케이터 hide
]=]

local require = require(script.Parent.loader).load(script)

local LINE_RANGE = 15
local LINE_WIDTH = 1.5

type BasicAttackState = {
	origin          : Vector3,
	direction       : Vector3,
	effectiveAimTime: number,
	fireComboCount  : number,
	isFiring        : boolean,
	indicator       : any,
	animator        : any?,
	fireMaid        : any?,
	teamContext     : { color: Color3?, [string]: any }?,
}

return {
	shapes = {
		aimLine = "line",
	},

	onAimStart = {
		function(state: BasicAttackState)
			state.indicator:update("aimLine", {
				origin    = state.origin,
				direction = state.direction,
				range     = LINE_RANGE,
				width     = LINE_WIDTH,
			})
			state.indicator:show("aimLine")
		end,
	},

	onAim = {
		function(state: BasicAttackState)
			state.indicator:update("aimLine", {
				origin    = state.origin,
				direction = state.direction,
			})
		end,
	},

	onFire = {
		function(state: BasicAttackState)
			state.indicator:hideAll()

			-- 점프+내려찍기 애니메이션
			-- (실제 HRP 이동은 HRPMoveClient가 서버 신호 수신 후 자동 처리)
			if state.animator then
				state.animator:PlayAnimation("JumpPunch", 0.15, nil, true)
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
