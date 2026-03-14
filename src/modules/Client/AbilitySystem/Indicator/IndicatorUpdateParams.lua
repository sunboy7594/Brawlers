--!strict
--[=[
	@class IndicatorUpdateParams

	DynamicIndicator:update()에 넘기는 파라미터 타입. (Client 전용)
	nil 필드는 생성 시 config 기본값 유지.
	shape 변경 시 해당 shape의 Parts로 즉시 전환.
]=]

export type IndicatorShape = "cone" | "circle" | "line" | "arc"

export type IndicatorUpdateParams = {
	-- ─── 공통 ─────────────────────────────────────────────────────────────
	origin: Vector3?,
	direction: Vector3?,
	color: Color3?,
	transparency: number?,
	shape: IndicatorShape?, -- nil이면 현재 shape 유지

	-- ─── Cone ─────────────────────────────────────────────────────────────
	range: number?, -- 부채꼴 반지름
	angle: number?, -- 부채꼴 전체 각도 (도 단위)

	-- ─── Line ─────────────────────────────────────────────────────────────
	width: number?, -- 직선 폭 (range 공유)

	-- ─── Circle ───────────────────────────────────────────────────────────
	radius: number?, -- 원 반지름

	-- ─── Arc ──────────────────────────────────────────────────────────────
	maxRange: number?, -- 포물선 최대 도달 거리
	speed: number?, -- 투사체 수평 속도
	gravity: number?, -- 중력 가속도
	arcRadius: number?, -- 착탄 표시 원 반지름
}

return {}
