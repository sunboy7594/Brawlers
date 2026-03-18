--!strict
--[=[
	@class PlayerStateUtils

	PlayerStateControllerService의 편의 래퍼.
	effect 이름과 파라미터만으로 tags + components를 자동 구성합니다.

	─── 사용법 ─────────────────────────────────────────────────────────────────
	-- 단발
	PlayerStateUtils.PlayPlayerState(psc, target, "stun", {
	    duration  = 2.0,
	    source    = attackerPlayer,
	    force     = false,
	    intensity = 0.8,
	})

	-- 반복 (burn, poison 등 도트 피해)
	PlayerStateUtils.PlayPlayerStateRepeat(psc, target, "burn", {
	    amount        = 5,
	    totalDuration = 10.0,
	    count         = 6,
	    source        = attackerPlayer,
	})

	-- builder 이름으로 현재 적용된 effect 조회
	local applied = PlayerStateUtils.GetAppliedBuilders(psc, target)
	-- → { { builderName="burn", id="ps_3", remaining=7.2 }, ... }

	─── 지원 effect ─────────────────────────────────────────────────────────────
	"stun"              moveLock + attackLock  /  anim_stun, screen_stun, vfx_stun_stars
	"slow"              slow(multiplier)       /  vfx_slow
	"knockback"         knockback(dir, force)  /  anim_knockback, cam_knockback
	"airborne"          moveLock + attackLock  /  anim_airborne
	"freeze"            moveLock + attackLock  /  anim_freeze, screen_freeze, vfx_freeze
	"burn"              damage(amount)         /  vfx_burn, screen_burn
	"poison"            damage(amount)         /  vfx_poison, screen_poison
	"damage"            damage(amount)         /  anim_hit, screen_hit_red
	"hyperArmor"        ignoreCC               /  vfx_hyperarmor
	"ignoreDamage"      ignoreDamage
	"receiveDamageMult" receiveDamageMult(multiplier)
	"dealDamageMult"    dealDamageMult(multiplier)
	"cleanse"           cleanse
	"vulnerable"        vulnerable(onHit)      /  vfx_vulnerable
]=]

local require = require(script.Parent.loader).load(script)

local PlayerStateControllerService = require("PlayerStateControllerService")
local PlayerStateDefs = require("PlayerStateDefs")

local Tag = PlayerStateDefs.Tag

-- ─── 파라미터 타입 ───────────────────────────────────────────────────────────

export type Params = {
	-- 공통
	duration: number?,
	force: boolean?,
	source: Player?,
	intensity: number?,

	-- effect별
	multiplier: number?,
	amount: number?,
	direction: Vector3?,
	knockbackForce: number?,

	-- PlayPlayerStateRepeat 전용
	totalDuration: number?,
	count: number?,

	-- vulnerable 전용
	onHit: PlayerStateDefs.EffectDef?,
}

-- ─── 내부 상수 ───────────────────────────────────────────────────────────────

local DEFAULT_INTENSITY = 0.7

-- ─── Effect 빌더 테이블 ──────────────────────────────────────────────────────

type Builder = (params: Params) -> PlayerStateDefs.EffectDef

local BUILDERS: { [string]: Builder } = {

	stun = function(p)
		local dur = p.duration or 1.0
		local i = p.intensity or DEFAULT_INTENSITY
		return {
			force = p.force,
			source = p.source,
			components = {
				{ type = "moveLock", duration = dur },
				{ type = "attackLock", duration = dur },
			},
			tags = {
				{ name = Tag.AnimStun, duration = dur, intensity = i },
				{ name = Tag.ScreenStun, duration = dur, intensity = i },
				{ name = Tag.VfxStunStars, duration = dur, intensity = i },
			},
		}
	end,

	slow = function(p)
		local dur = p.duration
		local i = p.intensity or DEFAULT_INTENSITY
		local mult = p.multiplier or 0.5
		return {
			force = p.force,
			source = p.source,
			components = {
				{ type = "slow", multiplier = mult, duration = dur },
			},
			tags = if dur
				then {
					{ name = Tag.VfxSlow, duration = dur, intensity = i },
				}
				else nil,
		}
	end,

	knockback = function(p)
		local dur = p.duration or 0.3
		local i = p.intensity or DEFAULT_INTENSITY
		local dir = p.direction or Vector3.new(0, 0, -1)
		local force = p.knockbackForce or 50
		return {
			force = p.force,
			source = p.source,
			components = {
				{ type = "knockback", direction = dir, force = force },
			},
			tags = {
				{ name = Tag.AnimKnockback, duration = dur, intensity = i },
				{ name = Tag.CamKnockback, duration = dur, intensity = i },
			},
		}
	end,

	airborne = function(p)
		local dur = p.duration or 1.0
		local i = p.intensity or DEFAULT_INTENSITY
		return {
			force = p.force,
			source = p.source,
			components = {
				{ type = "moveLock", duration = dur },
				{ type = "attackLock", duration = dur },
			},
			tags = {
				{ name = Tag.AnimAirborne, duration = dur, intensity = i },
			},
		}
	end,

	freeze = function(p)
		local dur = p.duration or 2.0
		local i = p.intensity or DEFAULT_INTENSITY
		return {
			force = p.force,
			source = p.source,
			components = {
				{ type = "moveLock", duration = dur },
				{ type = "attackLock", duration = dur },
			},
			tags = {
				{ name = Tag.AnimFreeze, duration = dur, intensity = i },
				{ name = Tag.ScreenFreeze, duration = dur, intensity = i },
				{ name = Tag.VfxFreeze, duration = dur, intensity = i },
			},
		}
	end,

	burn = function(p)
		local dur = p.duration or 0.5
		local i = p.intensity or DEFAULT_INTENSITY
		local amount = p.amount or 5
		return {
			force = p.force,
			source = p.source,
			components = {
				{ type = "damage", amount = amount },
			},
			tags = {
				{ name = Tag.VfxBurn, duration = dur, intensity = i },
				{ name = Tag.ScreenBurn, duration = dur, intensity = i },
			},
		}
	end,

	poison = function(p)
		local dur = p.duration or 0.5
		local i = p.intensity or DEFAULT_INTENSITY
		local amount = p.amount or 3
		return {
			force = p.force,
			source = p.source,
			components = {
				{ type = "damage", amount = amount },
			},
			tags = {
				{ name = Tag.VfxPoison, duration = dur, intensity = i },
				{ name = Tag.ScreenPoison, duration = dur, intensity = i },
			},
		}
	end,

	damage = function(p)
		local dur = p.duration or 0.3
		local i = p.intensity or DEFAULT_INTENSITY
		local amount = p.amount or 10
		return {
			force = p.force,
			source = p.source,
			components = {
				{ type = "damage", amount = amount },
			},
			tags = {
				{ name = Tag.AnimHit, duration = dur, intensity = i },
				{ name = Tag.ScreenHitRed, duration = dur, intensity = i },
			},
		}
	end,

	hyperArmor = function(p)
		local dur = p.duration
		local i = p.intensity or DEFAULT_INTENSITY
		return {
			force = p.force,
			source = p.source,
			components = {
				{ type = "ignoreCC", duration = dur },
			},
			tags = if dur
				then {
					{ name = Tag.VfxHyperArmor, duration = dur, intensity = i },
				}
				else nil,
		}
	end,

	ignoreDamage = function(p)
		return {
			force = p.force,
			source = p.source,
			components = {
				{ type = "ignoreDamage", duration = p.duration },
			},
		}
	end,

	receiveDamageMult = function(p)
		return {
			force = p.force,
			source = p.source,
			components = {
				{ type = "receiveDamageMult", multiplier = p.multiplier or 1.5, duration = p.duration },
			},
		}
	end,

	dealDamageMult = function(p)
		return {
			force = p.force,
			source = p.source,
			components = {
				{ type = "dealDamageMult", multiplier = p.multiplier or 1.5, duration = p.duration },
			},
		}
	end,

	cleanse = function(p)
		return {
			force = p.force,
			source = p.source,
			components = { { type = "cleanse" } },
		}
	end,

	vulnerable = function(p)
		local dur = p.duration
		local i = p.intensity or DEFAULT_INTENSITY
		return {
			force = p.force,
			source = p.source,
			components = {
				{ type = "vulnerable", onHit = p.onHit or {}, duration = dur },
			},
			tags = if dur
				then {
					{ name = Tag.VfxVulnerable, duration = dur, intensity = i },
				}
				else nil,
		}
	end,
}

-- ─── 공개 API ────────────────────────────────────────────────────────────────

local PlayerStateUtils = {}

--[=[
	단발 effect 적용.
	builderName을 effectDef에 메타데이터로 첨부 (GetAppliedBuilders 역추적용).
	@return string id
]=]
function PlayerStateUtils.PlayPlayerState(
	service: PlayerStateControllerService.PlayerStateControllerService,
	target: Player,
	builderName: string,
	params: Params?
): string
	local p: Params = params or {}
	local builder = BUILDERS[builderName]
	assert(builder, "[PlayerStateUtils] Unknown builderName: " .. tostring(builderName))
	local effectDef = builder(p);
	(effectDef :: any)._builderName = builderName
	return service:Play(target, effectDef)
end

--[=[
	반복 effect 적용 (burn, poison 등 도트).
	totalDuration / count = interval 자동 계산.
	@return () -> ()  취소 함수
]=]
function PlayerStateUtils.PlayPlayerStateRepeat(
	service: PlayerStateControllerService.PlayerStateControllerService,
	target: Player,
	builderName: string,
	params: Params?
): () -> ()
	local p: Params = params or {}
	local builder = BUILDERS[builderName]
	assert(builder, "[PlayerStateUtils] Unknown builderName: " .. tostring(builderName))
	local effectDef = builder(p);
	(effectDef :: any)._builderName = builderName
	local totalDuration = p.totalDuration or 5.0
	local count = p.count or 5
	return service:PlayRepeat(target, effectDef, totalDuration, count)
end

--[=[
	현재 대상에게 적용된 effect를 builder 이름으로 반환합니다.
	effectDef에 첨부된 _builderName 메타데이터를 읽습니다.
	PlayPlayerState/PlayPlayerStateRepeat으로 적용된 effect만 인식됩니다.

	@return { { builderName: string, id: string, remaining: number? } }
]=]
function PlayerStateUtils.GetAppliedBuilders(
	service: PlayerStateControllerService.PlayerStateControllerService,
	target: Player
): { { builderName: string, id: string, remaining: number? } }
	local activeEffects = service:GetActiveEffects(target)
	local result: { { builderName: string, id: string, remaining: number? } } = {}

	for _, view in activeEffects do
		local builderName = (view.effectDef :: any)._builderName
		if builderName and type(builderName) == "string" then
			table.insert(result, {
				builderName = builderName,
				id = view.id,
				remaining = view.remaining,
			})
		end
	end

	return result
end

return PlayerStateUtils
