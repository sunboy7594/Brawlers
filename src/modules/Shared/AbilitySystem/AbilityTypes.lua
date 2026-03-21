--!strict
--[=[
	@class AbilityTypes

	Ability 시스템 공통 타입 및 상수. (Shared)

	FireType:
	  stack  : [다운] StartAim → [업] Fire 1회 → interval(화면고정)
	  hold   : [다운] StartAim + Fire루프 → [업] 루프종료 → interval(화면고정X)
	  toggle : [다운] StartAim → [업] Fire루프 시작 → [두번째다운] or gauge0 → interval(화면고정X)

	ResourceType:
	  stack  : maxStack개까지 독립 재생 (쿨타임=maxStack:1, reloadTime:cooldownTime)
	  gauge  : drainRate로 소모, regenDelay 후 regenRate로 재생

	interval:
	  stack  : 발사 직후 ~ 다음 StartAim 가능. 화면고정. 20% 경과 후 예약 가능.
	  hold   : 루프 종료 후 ~ 다음 StartAim 가능. 화면고정X. 예약 불가.
	  toggle : 루프 시작 직후 ~ 두번째 [다운] 가능. 화면고정X. 20% 경과 후 예약 가능.

	INTERVAL_QUEUE_THRESHOLD = 0.8:
	  remaining / interval <= 0.8  →  20% 이상 경과 → 예약 발사 허용

	minGauge:
	  발사 시작 시에만 체크. 루프 지속 중에는 currentGauge > 0이면 계속 발사.
]=]

-- ⚠️ 주의: 클라이언트/서버 양쪽에서 반드시 이 값을 참조해야 합니다.
--          한쪽만 바꾸면 예약 타이밍이 어긋납니다.
local INTERVAL_QUEUE_THRESHOLD = 0.8

export type FireType = "stack" | "hold" | "toggle"

export type StackResource = {
	resourceType: "stack",
	maxStack: number,
	reloadTime: number, -- 1개 재생 시간 (초)
}

export type GaugeResource = {
	resourceType: "gauge",
	maxGauge: number, -- 기준: 100.0
	minGauge: number, -- 발사 시작 가능 최소 게이지 (루프 진입 시에만 체크)
	drainRate: number, -- 발사 중 초당 소모
	regenRate: number, -- 비발사 중 초당 재생
	regenDelay: number, -- 발사 종료 후 재생 시작까지 대기 (초)
}

export type AbilityResource = StackResource | GaugeResource

export type AbilityDef = {
	id: string,
	rarity: string,
	class: string,
	fireType: FireType,
	resource: AbilityResource,
	interval: number,
	entityDef: string?,
	blockAimTypes: { string }?, -- ← 추가: firing/interval 중 조준을 막을 abilityType 목록
}

local AbilityTypes = {}
AbilityTypes.INTERVAL_QUEUE_THRESHOLD = INTERVAL_QUEUE_THRESHOLD

return AbilityTypes
