--!strict
--[=[
	@class Tank_CannonTestClient

	line / arc / circle 인디케이터 시각 테스트용 기본공격.
	실제 히트 판정 없음.

	shapes:
	  shot  (line)   : 직사 방향 표시
	  trail (arc)    : 포물선 궤적 + 착탄 링
	  zone  (circle) : 플레이어 주변 근접 범위 링

	색상/투명도는 BasicAttackClient의 Heartbeat에서 리소스 상태에 따라
	updateAll로 일괄 처리하므로 onAim에서 별도 설정 불필요.
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

-- ─── 설정 ────────────────────────────────────────────────────────────────────

-- line
local LINE_RANGE = 15
local LINE_WIDTH = 1

-- arc
local ARC_RANGE          = 20
local ARC_BEAM_WIDTH     = 0.25
local ARC_RING_RADIUS    = 3
local ARC_RING_INNER     = 1

-- circle (플레이어 발 아래 근접 링)
local ZONE_RADIUS        = 3
local ZONE_INNER_RADIUS  = 1.5

return {
	shapes = {
		shot  = "line",
		trail = "arc",
		zone  = "circle",
	},

	onAimStart = {
		function(state: BasicAttackState)
			-- 초기값 설정 후 표시
			state.indicator:update("shot", {
				range = LINE_RANGE,
				width = LINE_WIDTH,
			})
			state.indicator:update("trail", {
				range          = ARC_RANGE,
				beamWidth      = ARC_BEAM_WIDTH,
				arcRadius      = ARC_RING_RADIUS,
				arcInnerRadius = ARC_RING_INNER,
			})
			state.indicator:update("zone", {
				radius      = ZONE_RADIUS,
				innerRadius = ZONE_INNER_RADIUS,
			})
			state.indicator:showAll()
		end,
	},

	onAim = {
		function(state: BasicAttackState)
			-- 위치/방향만 업데이트 (색상/투명도는 BasicAttackClient Heartbeat에서 처리)
			state.indicator:update("shot", {
				origin    = state.origin,
				direction = state.direction,
			})
			state.indicator:update("trail", {
				origin    = state.origin,
				direction = state.direction,
			})
			state.indicator:update("zone", {
				origin    = state.origin,
				direction = state.direction,
			})
		end,
	},

	onFire = {
		function(_state: BasicAttackState)
			-- 테스트용: 히트 판정 없음
		end,
	},

	onCancel = {
		function(state: BasicAttackState)
			state.indicator:hideAll()
		end,
	},

	onHitChecked = {},
}
