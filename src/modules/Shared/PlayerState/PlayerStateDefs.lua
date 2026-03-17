--!strict
--[=[
	@class PlayerStateDefs

	PlayerState 시스템 전체에서 공유하는 상수 및 타입 정의.

	─── 함수 구조 ──────────────────────────────────────────────

	[단발]
	PlayerStateControllerService:Play(target, effectDef)
	  effectDef의 각 component를 1회 적용.
	  component duration = 해당 효과가 지속되는 시간.

	[반복]
	PlayerStateControllerService:PlayRepeat(target, effectDef, totalDuration, count)
	  effectDef를 count회, totalDuration 동안 반복 적용.
	  interval = totalDuration / count (자동 계산)
	  EffectApplied는 최초 1회 (tag duration = totalDuration으로 확장하여 전송).
	  EffectRemoved는 totalDuration 만료 또는 cancel 시 1회.

	─── EffectDef 구조 ─────────────────────────────────────────────
	{
	    force      = false,
	    source     = player,
	    tags       = { TagEntry },
	    components = { Component },
	}

	─── 보호 처리 ────────────────────────────────────────────────────────
	  대상에 ignoreCC     → force=false effect의 cc계열 component 무시
	  대상에 ignoreDamage → force=false effect의 damage component 무시
	  force=true          → 위 두 경우 모두 뚫고 강제 적용
	  cc계열: slow, moveLock, attackLock, knockback, cameraLock

	─── effect 열람 ────────────────────────────────────────────────
	  GetActiveEffects(target) → { ActiveEffectView }  (instance 단위)
	  GetActiveTags(target) → { ActiveTagView }
	  HasEffect(target, componentType) → boolean
	  HasTag(target, tagName) → boolean

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

--[=[
	단발(one-shot) 태그 목록.
	PlayerStateClient에서 중첩 방지 슬롯 관리를 건너뛰고 즉시 재생합니다.
	짧은 duration의 피격/넉백 연출이 해당됩니다.
]=]
PlayerStateDefs.ONESHOT_TAGS = {
	[PlayerStateDefs.Tag.AnimHit] = true,
	[PlayerStateDefs.Tag.AnimKnockback] = true,
	[PlayerStateDefs.Tag.CamShake] = true,
	[PlayerStateDefs.Tag.CamRecoil] = true,
	[PlayerStateDefs.Tag.CamKnockback] = true,
	[PlayerStateDefs.Tag.ScreenHitRed] = true,
}

export type TagEntry = {
	name: string,
	duration: number,
	intensity: number,
}

export type Component =
	{ type: "damage", amount: number, duration: number? }
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
	| { type: "vulnerable", onHit: EffectDef, duration: number? }

export type EffectDef = {
	force: boolean?,
	source: Player?,
	tags: { TagEntry }?,
	components: { Component }?,
}

--[=[
	EffectInstance 내부에서 각 component를 추적하는 상태.
	expiresAt = nil    → 영구 (명시적 제거 필요)
	expiresAt = 생성시각 → 즉시 처리된 컴포넌트 (damage, knockback, cleanse)
]=]
export type ComponentState = {
	component: Component,
	expiresAt: number?,
}

--[=[
	EffectInstance 내부에서 각 tag를 추적하는 상태.
]=]
export type TagState = {
	tag: TagEntry,
	expiresAt: number,
}

--[=[
	PlayRepeat 시 생성되는 반복 상태.
	fired: 현재까지 발사된 tick 수.
]=]
export type RepeatState = {
	totalDuration: number,
	count: number,
	interval: number,
	fired: number,
	startedAt: number,
	expiresAt: number,
}

--[=[
	GetActiveEffects가 반환하는 instance 단위 열람 뷰.
	id        : EffectApplied/EffectRemoved 클라이언트 통신용 식별자
	remaining : nil이면 영구 또는 repeat (repeatState.expiresAt 참조)
]=]
export type ActiveEffectView = {
	id: string,
	effectDef: EffectDef,
	components: { ComponentState },
	tags: { TagState },
	startedAt: number,
	remaining: number?,
	repeatState: RepeatState?,
}

--[=[
	GetActiveTags가 반환하는 tag 열람 뷰.
]=]
export type ActiveTagView = {
	name: string,
	expiresAt: number,
	remaining: number,
}

return PlayerStateDefs
