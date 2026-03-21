--!strict
--[=[
	@class Tank_RapidFirePunchEntityDef

	탱크 연속 펀치 연출 엔티티 정의. (Shared / 클라이언트 연출 전용)

	"PunchBolt":
	  - model = "Tank_PunchBolt"
	    ReplicatedStorage.Entities.Tank_PunchBolt 모델이 있으면 사용.
	    없으면 EntityController 의 fakePart로 동작 (연출은 유지됨).
	  - 직선 등속으로 날아가다 사거리(12) 도달 시 fade out 소멸.
	  - 팀 색상 Highlight 오버레이 적용.
	  - 히트 시 즉시 Despawn.
	  - onMove: FadeTo로 spawn 직후 fade-in 연출.

	서버 히트 판정은 Tank_RapidFirePunchServer 에서
	InstantHit.verdict(line) 으로 독립 처리.
	이 파일은 클라이언트 연출(EntityPlayer)용으로만 사용.
]=]

local require = require(script.Parent.loader).load(script)

local EntityColorUtils = require("EntityColorUtils")
local EntityUtils = require("EntityUtils")

local BOLT_SPEED = 55 -- 스터드/초
local MAX_RANGE = 12 -- 최대 사거리 (스터드)

return {
	PunchBolt = {
		model = "Tank_PunchBolt", -- ReplicatedStorage.Entities 아래 모델명
		tags = { "punch_bolt" },

		-- 직선 등속 이동
		move = EntityUtils.Linear({
			speed = BOLT_SPEED,
			maxRange = MAX_RANGE,
		}),

		-- 이동 중 회전 (타격감 강조)
		-- onMove = {},
		-- EntityUtils.RotateTo({
		-- 	axis = Vector3.new(0, 0, 0),
		-- 	speed = 720,
		-- }),

		-- spawn 직후 fade-in
		onSpawn = EntityUtils.Animate(EntityUtils.FadeTo({
			from = 1,
			to = 0,
			duration = 0.08,
			speed = 30,
		})),

		-- 적/벽 충돌 시 즉시 소멸
		hitDetect = EntityUtils.Box({
			size = Vector3.new(1.8, 1.8, 1.8),
			relations = { "enemy", "obstacle" },
		}),

		onHit = EntityUtils.Sequence({
			EntityUtils.LockHit(),
			EntityUtils.Despawn({ delay = 0 }),
		}),

		-- 사거리 초과 시 짧게 fade out 후 소멸
		onMiss = EntityUtils.Sequence({
			EntityUtils.Animate(EntityUtils.FadeTo({
				from = 0,
				to = 1,
				duration = 0.08,
				speed = 20,
			})),
			EntityUtils.Despawn({ delay = 0.08 }),
		}),

		-- 팀 색상 오버레이
		colorFilter = EntityColorUtils.Highlight({
			fillTransparency = 0.2,
			outlineTransparency = 0,
			depthMode = "AlwaysOnTop",
		}),
	},
}
