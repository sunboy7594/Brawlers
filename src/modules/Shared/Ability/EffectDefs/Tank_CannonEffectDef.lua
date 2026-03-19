--!strict
--[=[
	@class Tank_CannonEffectDef

	탱크 캐논 기본공격 이펙트 정의. (Shared)

	ReplicatedStorage.AbilityEffects.CannonBall 모델 필요.

	투사체 흐름:
	  Linear 직선 이동 → Box 판정
	  히트: SpawnEffect(Explosion) → Despawn
	  미스: FadeOut

	params 지원:
	  params.aimRatio (0~1): effectiveAimTime에 비례해 판정 크기 확대

	AbilityEffectColorUtils:
	  클라이언트 전용 모듈이므로 서버에서는 nil. 랜더링에만 사용됨.
]=]

local require = require(script.Parent.loader).load(script)

local RunService = game:GetService("RunService")

local AbilityEffectHitDetectionUtil = require("AbilityEffectHitDetectionUtil")
local AbilityEffectHitOrMissUtil   = require("AbilityEffectHitOrMissUtil")
local AbilityEffectMover           = require("AbilityEffectMover")
local AbilityEffectTransformUtil   = require("AbilityEffectTransformUtil")

-- 클라이언트 전용: 서버에서는 nil 반환
local AbilityEffectColorUtils = not RunService:IsServer() and require("AbilityEffectColorUtils") or nil

local PROJECTILE_SPEED = 40
local MAX_RANGE        = 100
local BASE_HIT_SIZE    = 3
local MAX_HIT_SIZE     = 6

return {
	models = { "CannonBall", "CannonExplosion" },

	CannonBall = {
		model = "CannonBall",

		move = AbilityEffectMover.Linear({
			speed    = PROJECTILE_SPEED,
			maxRange = MAX_RANGE,
			mode     = "linear",
		}),

		onMove = AbilityEffectTransformUtil.Rotate({
			axis  = Vector3.new(1, 0, 0),
			speed = 360,
		}),

		hitDetect = function(elapsed: number, _handle: any, params: { [string]: any }?)
			local aimRatio = params and params.aimRatio or 0
			local size = BASE_HIT_SIZE + (MAX_HIT_SIZE - BASE_HIT_SIZE) * aimRatio
			return AbilityEffectHitDetectionUtil.Box({
				size = Vector3.new(size, size, size),
			})
		end,

		onHit = AbilityEffectHitOrMissUtil.Sequence({
			AbilityEffectHitOrMissUtil.SpawnEffect("Tank_CannonEffectDef", "CannonExplosion"),
			AbilityEffectHitOrMissUtil.Despawn(),
		}),

		onMiss = AbilityEffectHitOrMissUtil.FadeOut({ duration = 0.3 }),

		-- 서버에서는 nil, 클라이언트에서만 Highlight 적용
		colorFilter = AbilityEffectColorUtils and AbilityEffectColorUtils.Highlight(0.5) or nil,
	},

	CannonExplosion = {
		model = "CannonExplosion",
		move  = nil,

		onMove = AbilityEffectTransformUtil.Sequence({
			AbilityEffectTransformUtil.ScaleTo({
				from     = Vector3.one,
				target   = Vector3.new(2.5, 2.5, 2.5),
				duration = 0.2,
				mode     = "spring",
				speed    = 20,
				damper   = 0.7,
			}),
			AbilityEffectTransformUtil.Fade({
				from     = 0,
				to       = 1,
				duration = 0.4,
				mode     = "linear",
				speed    = 1,
			}),
		}),

		onMiss      = AbilityEffectHitOrMissUtil.Despawn(),
		colorFilter = nil,
	},
}
