--!strict
--[=[
	@class PlayerStateDefs

	PlayerState 시스템 전체에서 공유하는 상수 및 타입 정의.

	─── 함수 구조 ──────────────────────────────────────────────

	[단발]
	PlayerStateService:ChangePlayerState(target, effectDef)
	  effectDef의 각 component를 1회 적용.
	  component duration = 해당 효과가 지속되는 시간.

	[반복]
	PlayerStateService:RepeatChangePlayerState(target, effectDef, totalDuration, count)
	  effectDef를 count회, totalDuration 동안 반복 적용.
	  interval = totalDuration / count (자동 계산)
	  예) 0.5초 스턴을 10초 동안 6회 반복:
	      RepeatChangePlayerState(target, {
	          components = {
	              { type = "moveLock",   duration = 0.5 },
	              { type = "attackLock", duration = 0.5 },
	          },
	          tags = {
	              { name = "anim_stun", duration = 0.5, intensity = 0.7 },
	          },
	      }, 10.0, 6)
	      → interval = 10/6 ≈ 1.67초마다 한 번씩 0.5초 스턴

	─── EffectDef 구조 ─────────────────────────────────────────────
	{
	    force      = false,          -- true면 ignoreCC/ignoreDamage 무시 강제 적용
	    source     = player,         -- 효과 출잘. nil이면 환경/자해
	    tags       = { TagEntry },   -- 클라이언트 연출 힌트. 없으면 아무 연출 없음
	    components = { Component },  -- 실제 효과 목록
	}

	─── TagEntry 구조 ──────────────────────────────────────────────
	{
	    name:      string,  -- tag 식별자
	    duration:  number,  -- 연출 지속시간 (필수)
	    intensity: number,  -- 연출 강도 0~1 (필수)
	                        -- anim:   모션 크기/속도
	                        -- cam:    흔들림/밀림 강도
	                        -- screen: 화면 효과 강도
	                        -- vfx:    파티클 밀도/크기
	}

	─── id 규칙 (damage, vulnerable component에만 의미있음) ─────────
	  id=nil   → 항상 새 인스턴스 (중첩)
	  id="foo" → 같은 id 재호출 시 duration만 리셋 (연장)

	─── 보호 처리 ────────────────────────────────────────────────────────
	  대상에 ignoreCC     → force=false effect의 cc계열 component 무시
	  대상에 ignoreDamage → force=false effect의 damage component 무시
	  force=true          → 위 두 경우 모두 뚫고 강제 적용
	  cc계열: slow, moveLock, attackLock, knockback, cameraLock

	─── 연출 def 파일 분리 ────────────────────────────────────────────
	  PlayerStateAnimDef         → 캐릭터 애니메이션 (anim_*)
	  PlayerStateCameraAnimDef   → 카메라 연출 (cam_*)
	  PlayerStateScreenEffectDef → 화면 이펙트 (screen_*)
	  PlayerStateVfxDef          → VFX 파티클 (vfx_*)
]=]

local PlayerStateDefs = {}

PlayerStateDefs.ComponentType = {
	Damage = "damage",
	Slow = "slow",
	MoveLock = "moveLock",
	AttackLock = "attackLock",
	Knockback = "knockback",
	ReceiveDamageMult = "receiveDamageMult",
	DealDamageMult = "dealDamageMult",
	IgnoreCC = "ignoreCC",
	IgnoreDamage = "ignoreDamage",
	Cleanse = "cleanse",
	CameraLock = "cameraLock",
	Vulnerable = "vulnerable",
}

PlayerStateDefs.CC_TYPES = {
	[PlayerStateDefs.ComponentType.Slow] = true,
	[PlayerStateDefs.ComponentType.MoveLock] = true,
	[PlayerStateDefs.ComponentType.AttackLock] = true,
	[PlayerStateDefs.ComponentType.Knockback] = true,
	[PlayerStateDefs.ComponentType.CameraLock] = true,
}

PlayerStateDefs.Tag = {
	AnimHit = "anim_hit",
	AnimStun = "anim_stun",
	AnimAirborne = "anim_airborne",
	AnimRagdoll = "anim_ragdoll",
	AnimFreeze = "anim_freeze",
	AnimKnockback = "anim_knockback",
	AnimExhausted = "anim_exhausted",
	CamShake = "cam_shake",
	CamRecoil = "cam_recoil",
	CamKnockback = "cam_knockback",
	CamMotionSickness = "cam_motion_sickness",
	ScreenHitRed = "screen_hit_red",
	ScreenBlind = "screen_blind",
	ScreenStun = "screen_stun",
	ScreenFreeze = "screen_freeze",
	ScreenBurn = "screen_burn",
	ScreenPoison = "screen_poison",
	VfxBurn = "vfx_burn",
	VfxPoison = "vfx_poison",
	VfxBleed = "vfx_bleed",
	VfxShock = "vfx_shock",
	VfxFreeze = "vfx_freeze",
	VfxSlow = "vfx_slow",
	VfxStunStars = "vfx_stun_stars",
	VfxShield = "vfx_shield",
	VfxHyperArmor = "vfx_hyperarmor",
	VfxVulnerable = "vfx_vulnerable",
}

export type TagEntry = {
	name: string,
	duration: number,
	intensity: number,
}

export type Component =
	{ type: "damage", id: string?, amount: number, duration: number? }
	| { type: "slow", multiplier: number, duration: number? }
	| { type: "moveLock", duration: number? }
	| { type: "attackLock", duration: number? }
	| { type: "knockback", direction: Vector3, force: number, duration: number? }
	| { type: "receiveDamageMult", multiplier: number, duration: number? }
	| { type: "dealDamageMult", multiplier: number, duration: number? }
	| { type: "ignoreCC", duration: number? }
	| { type: "ignoreDamage", duration: number? }
	| { type: "cleanse", duration: number? }
	| { type: "cameraLock", duration: number? }
	| { type: "vulnerable", id: string?, onHit: EffectDef, duration: number? }

export type EffectDef = {
	force: boolean?,
	source: Player?,
	tags: { TagEntry }?,
	components: { Component }?,
}

export type RepeatParams = {
	totalDuration: number,
	count: number,
}

return PlayerStateDefs
