--!strict
--[=[
	@class PlayerStateAnimDef

	tag name → 캐릭터 AnimDef 키 매핑.
	PlayerStateClient가 anim_* tag를 받아 여기서 조회 후 EntityAnimator에 재생합니다.

	animKey:
	  HitReactionAnimDef의 키. intensity는 AnimDef 내부 파라미터 스케일링에 활용됨.

	loop:
	  false(또는 nil) → tag.duration 동안 1회 재생후 종료.
	  true → tag.duration 동안 반복 재생. EntityAnimator가 duration 만료 시 자동 종료.

	special:
	  "ragdoll" 등 AnimDef 없이 별도 로직으로 처리.

	─── intensity 기준 동작 ─────────────────────────────────────
	  anim_hit      : 0~0.5 → HitStagger, 0.5~1.0 → HitKnockback
	  anim_knockback: intensity를 AnimDef에 그대로 전달 → 각도/속도 스케일링
	  그 외     : AnimDef 내부에서 intensity 기반 spring speed/angle 스케일링
]=]

local PlayerStateDefs = require("PlayerStateDefs")
local Tag = PlayerStateDefs.Tag

type AnimMapping = {
	-- intensity 구간별 animKey 목록
	-- intensity >= threshold인 것 중 가장 큰 threshold 선택
	variants: { { threshold: number, animKey: string?, loop: boolean?, special: string? } },
}

local PlayerStateAnimDef: { [string]: AnimMapping } = {

	-- 0~0.5: 일반 피격, 0.5~1: 강한 피격
	[Tag.AnimHit] = {
		variants = {
			{ threshold = 0.0, animKey = "HitStagger" },
			{ threshold = 0.5, animKey = "HitKnockback" },
		},
	},

	-- intensity → 스턴 루프 속도/각도 스케일링
	[Tag.AnimStun] = {
		variants = {
			{ threshold = 0.0, animKey = "Stun", loop = true },
		},
	},

	-- intensity → 에어본 루프 속도 스케일링
	[Tag.AnimAirborne] = {
		variants = {
			{ threshold = 0.0, animKey = "Airborne", loop = true },
		},
	},

	[Tag.AnimRagdoll] = {
		variants = {
			{ threshold = 0.0, special = "ragdoll" },
		},
	},

	-- intensity → 빙결 루프 속도 스케일링
	[Tag.AnimFreeze] = {
		variants = {
			{ threshold = 0.0, animKey = "Freeze", loop = true },
		},
	},

	-- intensity → 넘백 각도/속도 스케일링 (AnimDef 내부에서 활용)
	[Tag.AnimKnockback] = {
		variants = {
			{ threshold = 0.0, animKey = "Knockback" },
		},
	},

	-- intensity → 탈진 루프 속도 스케일링
	[Tag.AnimExhausted] = {
		variants = {
			{ threshold = 0.0, animKey = "Exhausted", loop = true },
		},
	},
}

-- ─── 타입 ────────────────────────────────────────────────────────────────

export type ResolvedAnim = {
	animKey: string?,
	loop: boolean?,
	special: string?,
}

--[=[
	intensity에 따라 사용할 animKey/loop/special을 반환합니다.
]=]
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
		animKey = chosen.animKey,
		loop = chosen.loop,
		special = chosen.special,
	}
end

return PlayerStateAnimDef
