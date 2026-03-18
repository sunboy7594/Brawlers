--!strict
--[=[
	@class PlayerStateVfxDef

	tag name → VFX 파티클 정의.
	PlayerStateClient가 vfx_* tag를 받아 여기서 조회 후 파티클/이펙트를 실행합니다.

	intensity (0~1):
	  ParticleEmitter의 Rate/Size/Speed 등 스케일링에 활용.

	particleId: Roblox 에셋 ID (나중에 실제 ID로 교체)
	attachTo:   캐릭터 파트 이름. nil이면 HumanoidRootPart
	loop:       true면 duration 동안 파티클 유지, false면 단발 Emit
	emitCount:  loop=false일 때 Emit 횟수 (intensity로 스케일)
	billboard:  true면 BillboardGui 방식
]=]

local require = require(script.Parent.loader).load(script)

local PlayerStateDefs = require("PlayerStateDefs")
local Tag = PlayerStateDefs.Tag

type VfxMapping = {
	particleId: string?,
	attachTo: string?,
	loop: boolean?,
	emitCount: number?,
	billboard: boolean?,
}

local PlayerStateVfxDef: { [string]: VfxMapping } = {

	[Tag.VfxBurn] = {
		particleId = "rbxassetid://BURN_PARTICLE",
		loop = true,
	},

	[Tag.VfxPoison] = {
		particleId = "rbxassetid://POISON_PARTICLE",
		loop = true,
	},

	[Tag.VfxBleed] = {
		particleId = "rbxassetid://BLEED_PARTICLE",
		loop = false,
		emitCount = 10,
	},

	[Tag.VfxShock] = {
		particleId = "rbxassetid://SHOCK_PARTICLE",
		loop = true,
	},

	[Tag.VfxFreeze] = {
		particleId = "rbxassetid://FREEZE_PARTICLE",
		loop = true,
	},

	[Tag.VfxSlow] = {
		particleId = "rbxassetid://SLOW_PARTICLE",
		loop = true,
	},

	[Tag.VfxStunStars] = {
		billboard = true,
		attachTo = "Head",
		loop = true,
	},

	[Tag.VfxShield] = {
		billboard = true,
		loop = true,
	},

	[Tag.VfxHyperArmor] = {
		particleId = "rbxassetid://HYPERARMOR_PARTICLE",
		loop = true,
	},

	-- vulnerable → onHitReact로 교체됨
	[Tag.VfxOnHitReact] = {
		billboard = true,
		attachTo = "Head",
		loop = true,
	},
}

return PlayerStateVfxDef
