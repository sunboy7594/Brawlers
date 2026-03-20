--!strict
--[=[
	@class Tank_CannonTestEffectDef

	탱크 쾐논 기본공격 이펝트 정의. (Shared / 클라이언트 연출 전용)

	ReplicatedStorage.AbilityEffects.CannonBall 모델 필요.

	서버 히트판정은 Tank_CannonTestServer에서 ProjectileHit.fire()로 독립 처리.
	이 파일은 클라이언트 연출(EntityPlayer)용으로만 사용.
]=]

local require = require(script.Parent.loader).load(script)

local EntityUtils      = require("EntityUtils")
local EntityColorUtils = require("EntityColorUtils")

local PROJECTILE_SPEED = 40
local MAX_RANGE        = 100

return {
	CannonBall = {
		model = "CannonBall",
		tags  = { "projectile" },

		move = EntityUtils.Linear({
			speed    = PROJECTILE_SPEED,
			maxRange = MAX_RANGE,
		}),

		onMove = EntityUtils.RotateTo({
			axis  = Vector3.new(1, 0, 0),
			speed = 360,
		}),

		hitDetect = EntityUtils.Box({ size = Vector3.new(4, 4, 4) }),

		onHit = EntityUtils.Sequence({
			EntityUtils.SpawnEntity("Tank_CannonTestEffectDef", "CannonExplosion"),
			EntityUtils.Despawn(),
		}),

		onMiss = EntityUtils.FadeTo({
			from     = 0,
			to       = 1,
			duration = 0.3,
			speed    = 1,
		}),

		colorFilter = EntityColorUtils.Highlight({
			fillTransparency = 0.5,
			depthMode        = "Occluded",
		}),
	},

	CannonExplosion = {
		model = "CannonExplosion",
		tags  = nil,
		move  = nil,

		onMove = EntityUtils.TransformSequence({
			EntityUtils.ScaleTo({
				from     = Vector3.new(1, 1, 1),
				target   = Vector3.new(2.5, 2.5, 2.5),
				duration = 0.2,
				mode     = "spring",
				speed    = 20,
				damper   = 0.7,
			}),
			EntityUtils.FadeTo({
				from     = 0,
				to       = 1,
				duration = 0.4,
				speed    = 1,
			}),
		}),

		onMiss      = EntityUtils.Despawn(),
		colorFilter = nil,
	},
}
