--!strict
--[=[
	@class Tank_CannonTestEffectDef

	탱크 캐논 기본공격 이펙트 정의. (Shared / 클라이언트 연출 전용)

	ReplicatedStorage.AbilityEffects.CannonBall 모델 필요.

	서버 히트판정은 Tank_CannonTestServer에서 ProjectileHit.fire()로 독립 처리.
	이 파일은 클라이언트 연출(AbilityEffectPlayer)용으로만 사용.
]=]

local require = require(script.Parent.loader).load(script)

local RunService = game:GetService("RunService")

local HitDetectionUtil = require("HitDetectionUtil")
local HitOrMissUtil    = require("HitOrMissUtil")
local MoverUtil        = require("MoverUtil")
local TransformUtil    = require("TransformUtil")

-- 클라이언트 전용: 서버에서는 nil 반환
local AbilityEffectColorUtils = not RunService:IsServer() and require("AbilityEffectColorUtils") or nil

local PROJECTILE_SPEED = 40
local MAX_RANGE        = 100

return {
	models = { "CannonBall", "CannonExplosion" },

	CannonBall = {
		model = "CannonBall",

		move = MoverUtil.Linear({
			speed    = PROJECTILE_SPEED,
			maxRange = MAX_RANGE,
			mode     = "linear",
		}),

		onMove = TransformUtil.Rotate({
			axis  = Vector3.new(1, 0, 0),
			speed = 360,
		}),

		-- 클라이언트 연출용 hitDetect
		hitDetect = HitDetectionUtil.Box({ size = Vector3.new(4, 4, 4) }),

		onHit = HitOrMissUtil.Sequence({
			HitOrMissUtil.SpawnEffect("Tank_CannonTestEffectDef", "CannonExplosion"),
			HitOrMissUtil.Despawn(),
		}),

		onMiss = HitOrMissUtil.FadeOut({ duration = 0.3 }),

		colorFilter = AbilityEffectColorUtils and AbilityEffectColorUtils.Highlight(0.5) or nil,
	},

	CannonExplosion = {
		model = "CannonExplosion",
		move  = nil,

		onMove = TransformUtil.Sequence({
			TransformUtil.ScaleTo({
				from     = Vector3.new(1, 1, 1),
				target   = Vector3.new(2.5, 2.5, 2.5),
				duration = 0.2,
				mode     = "spring",
				speed    = 20,
				damper   = 0.7,
			}),
			TransformUtil.Fade({
				from     = 0,
				to       = 1,
				duration = 0.4,
				mode     = "linear",
				speed    = 1,
			}),
		}),

		onMiss      = HitOrMissUtil.Despawn(),
		colorFilter = nil,
	},
}
