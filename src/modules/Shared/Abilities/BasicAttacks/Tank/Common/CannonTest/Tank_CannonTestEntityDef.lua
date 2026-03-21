--!strict
--[=[
	@class Tank_CannonTestEffectDef

	탱크 캐논 기본공격 이펙트 정의. (Shared / 클라이언트 연출 전용)

	ReplicatedStorage.AbilityEffects.CannonBall 모델 필요.

	서버 히트판정은 Tank_CannonTestServer에서 ProjectileHit.fire()로 독립 처리.
	이 파일은 클라이언트 연출(EntityPlayer)용으로만 사용.
]=]

local require = require(script.Parent.loader).load(script)

local EntityColorUtils = require("EntityColorUtils")
local EntityUtils = require("EntityUtils")
local PROJECTILE_SPEED = 40
local MAX_RANGE = 100
local EXPLOSION_LIFETIME = 1.5

return {
	CannonBall = {
		model = "Tank_CannonBall",
		tags = { "projectile" },

		move = EntityUtils.Arc({
			speed = PROJECTILE_SPEED,
			height = 10, -- hight → height
			distance = MAX_RANGE, -- maxRange → distance
		}),

		onMove = EntityUtils.RotateTo({
			axis = Vector3.new(1, 0, 0),
			speed = 360,
		}),

		-- enemy + obstacle(벽) 둘 다 판정
		hitDetect = EntityUtils.Box({
			size = Vector3.new(4, 4, 4),
			relations = { "enemy", "obstacle" },
		}),

		onHit = EntityUtils.Sequence({
			EntityUtils.LockHit(), -- ← 첫 줄에 추가
			EntityUtils.SpawnEntity("Tank_CannonTestEntityDef", "CannonExplosion"),
			EntityUtils.Animate(EntityUtils.FadeTo({ from = 0, to = 1, duration = 1.0, speed = 20 })),
			EntityUtils.Despawn({ delay = 1.0 }),
		}),

		-- 사거리 초과 시 fade out 후 소멸
		onMiss = EntityUtils.Sequence({
			EntityUtils.Animate(EntityUtils.FadeTo({ from = 0, to = 1, duration = 0.25, speed = 10 })),
			EntityUtils.Despawn({ delay = 0.25 }),
		}),

		colorFilter = EntityColorUtils.Highlight({
			fillTransparency = 0.5,
			depthMode = "Occluded",
		}),
	},

	CannonExplosion = {
		model = "Tank_CannonExplosion",
		tags = { "projectile" },

		-- 수명 타이머 + 스케일 커지고 fade out
		onSpawn = EntityUtils.Sequence({
			EntityUtils.AutoDespawn(EXPLOSION_LIFETIME),
			EntityUtils.Animate(EntityUtils.TransformSequence({
				-- 0.5초 동안 커짐
				EntityUtils.ScaleTo({
					from = Vector3.new(0.1, 0.1, 0.1),
					target = Vector3.new(10, 10, 10),
					duration = 0.5,
					speed = 10,
				}),
				-- 0.5초 후부터 fade out
				EntityUtils.FadeTo({
					from = 0,
					to = 1,
					duration = 1.0,
					speed = 5,
					delay = 0.5,
				}),
			})),
		}),

		onMiss = EntityUtils.Despawn(),

		colorFilter = EntityColorUtils.Highlight({
			fillTransparency = 0.5,
			depthMode = "Occluded",
		}),
	},
}
