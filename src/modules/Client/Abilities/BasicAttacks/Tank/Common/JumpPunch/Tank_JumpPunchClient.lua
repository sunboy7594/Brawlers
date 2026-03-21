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

-- arc 시간(15/28 ≈ 0.54s) + 여유(0.5s)
-- 이 시간이 지나면 AnimationControllerClient가 자동으로 애니메이션 종료 → defaultC0 복귀
local JUMP_ANIM_DURATION = 15 / 28 + 0.5

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

			if state.animator then
				-- JUMP_ANIM_DURATION 후 자동 만료 → defaultC0 복귀
				-- fireMaid 소멸 시에도 StopAnimation 호출 (어느 쪽이 먼저든 정상 종료)
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
		end,
	},

	onHitChecked = {},
}
