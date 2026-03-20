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

-- CannonExplosion 수명: ScaleTo(0.5s) + FadeTo(1.0s) + 여유
local EXPLOSION_LIFETIME = 1.5

return {
	CannonBall = {
		model = "CannonBall",
		tags = { "projectile" },

		move = EntityUtils.Linear({
			speed = PROJECTILE_SPEED,
			maxRange = MAX_RANGE,
		}),

		onMove = EntityUtils.RotateTo({
			axis = Vector3.new(1, 0, 0),
			speed = 360,
		}),

		hitDetect = EntityUtils.Box({ size = Vector3.new(4, 4, 4) }),

		onHit = EntityUtils.Sequence({
			EntityUtils.SpawnEntity("Tank_CannonTestEffectDef", "CannonExplosion"),
			EntityUtils.Despawn(),
		}),

		-- onMiss: FadeTo는 onMove 전용 (model, dt, params) 콜백 → onMiss(handle)로 호출하면 dt=nil 에러
		-- Despawn으로 대체 (fade-out 연출은 추후 FadeOutMiss 유틸 구현 후 교체)
		onMiss = EntityUtils.Despawn(),

		colorFilter = EntityColorUtils.Highlight({
			fillTransparency = 0.5,
			depthMode = "Occluded",
		}),
	},

	CannonExplosion = {
		model = "CannonExplosion",
		tags = nil,
		move = nil,

		-- move=nil이면 Miss()가 자동 호출되지 않으므로
		-- onSpawn에서 수명 타이머를 걸어 줌
		onSpawn = EntityUtils.AutoDespawn(EXPLOSION_LIFETIME),

		onMove = EntityUtils.TransformSequence({
			EntityUtils.ScaleTo({
				from = Vector3.new(1, 1, 1),
				target = Vector3.new(2.5, 2.5, 2.5),
				duration = 0.5,
				mode = "spring",
				speed = 20,
				damper = 0.7,
			}),
			EntityUtils.FadeTo({
				from = 0,
				to = 1,
				duration = 1.0,
				speed = 1,
			}),
		}),

		onMiss = EntityUtils.Despawn(),
		colorFilter = nil,
	},
}
