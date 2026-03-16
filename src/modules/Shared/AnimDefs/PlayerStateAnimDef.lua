--!strict
--[=[
	@class PlayerStateAnimDef

	tag name → 캐릭터 AnimDef 키 매핑.
	PlayerStateClient가 anim_* tag를 받아 여기서 조회 후 EntityAnimator에 재생합니다.

	intensity (0~1) 활용:
	  anim_hit       → 0~0.5: HitStagger, 0.5~1.0: HitKnockback
	  anim_knockback → 0~0.5: KnockbackLight, 0.5~1.0: KnockbackHeavy
	  그 외 tag    → AnimDef의 spring speed/angle 등 파라미터 스케일링에 활용

	loopAnimKey:
	  nil이면 단발 재생.
	  있으면 animKey 재생 후 loopAnimKey로 전환,
	  tag duration 만료 시 루프 종료.

	special:
	  "ragdoll" 등 AnimDef 없이 별도 로직으로 처리.
]=]

local PlayerStateDefs = require("PlayerStateDefs")
local Tag = PlayerStateDefs.Tag

type AnimMapping = {
	variants: {
		{ threshold: number, animKey: string?, loopAnimKey: string?, special: string? }
	},
}

local PlayerStateAnimDef: { [string]: AnimMapping } = {

	[Tag.AnimHit] = {
		variants = {
			{ threshold = 0.0, animKey = "HitStagger" },
			{ threshold = 0.5, animKey = "HitKnockback" },
		},
	},

	[Tag.AnimStun] = {
		variants = {
			{ threshold = 0.0, animKey = "StunEnter", loopAnimKey = "StunLoop" },
		},
	},

	[Tag.AnimAirborne] = {
		variants = {
			{ threshold = 0.0, animKey = "AirborneEnter", loopAnimKey = "AirborneLoop" },
		},
	},

	[Tag.AnimRagdoll] = {
		variants = {
			{ threshold = 0.0, special = "ragdoll" },
		},
	},

	[Tag.AnimFreeze] = {
		variants = {
			{ threshold = 0.0, animKey = "FreezeEnter", loopAnimKey = "FreezeLoop" },
		},
	},

	[Tag.AnimKnockback] = {
		variants = {
			{ threshold = 0.0, animKey = "KnockbackLight" },
			{ threshold = 0.5, animKey = "KnockbackHeavy" },
		},
	},

	[Tag.AnimExhausted] = {
		variants = {
			{ threshold = 0.0, animKey = "ExhaustedEnter", loopAnimKey = "ExhaustedLoop" },
		},
	},
}

type ResolvedAnim = {
	animKey:     string?,
	loopAnimKey: string?,
	special:     string?,
}

function PlayerStateAnimDef.resolve(tagName: string, intensity: number): ResolvedAnim?
	local mapping = PlayerStateAnimDef[tagName]
	if not mapping then
		return nil
	end
	local chosen = mapping.variants[1]
	for _, variant in mapping.variants do
		if intensity >= variant.threshold then
			chosen = variant
		end
	end
	return {
		animKey     = chosen.animKey,
		loopAnimKey = chosen.loopAnimKey,
		special     = chosen.special,
	}
end

return PlayerStateAnimDef
