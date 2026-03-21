--!strict
--[=[
	@class Tank_RapidFirePunchDef

	탱크 연속 펀치 공격 정의.

	fireType = "hold":
	  마우스 다운 → line 인디케이터 표시 + fire 루프 시작.
	  마우스 업   → 루프 종료.

	resource = gauge:
	  maxGauge  100  / drainRate 20/s  (5초 풀연사)
	  regenRate 15/s / regenDelay 1.0s

	interval = 0.18:
	  약 0.18초 간격 연사 (~5.5발/s).
]=]

local require = require(script.Parent.loader).load(script)

local AbilityTypes = require("AbilityTypes")

return {
	id = "Tank_RapidFirePunch",
	rarity = "COMMON",
	class = "TANK",
	fireType = "hold",

	resource = {
		resourceType = "gauge",
		maxGauge = 100,
		minGauge = 10, -- 루프 진입 시 최소 10 이상 필요
		drainRate = 20, -- 발사 중 초당 소모
		regenRate = 15, -- 비발사 중 초당 재생
		regenDelay = 1.0, -- 발사 종료 후 재생 시작까지 대기 (초)
	},

	interval = 0.18,

	entityDef = "Tank_RapidFirePunchEntityDef",
} :: AbilityTypes.AbilityDef
