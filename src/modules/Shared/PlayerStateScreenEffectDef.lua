--!strict
--[=[
	@class PlayerStateScreenEffectDef

	tag name → 화면 이펙트 정의.
	PlayerStateClient가 screen_* tag를 받아 여기서 조회 후 화면 연출을 실행합니다.

	intensity (0~1):
	  tag에서 전달된 intensity를 그대로 화면 효과 강도로 사용.

	flash: true면 순간 플래시 후 fade.
	loop:  true면 duration 동안 지속 유지.
]=]

local PlayerStateDefs = require("PlayerStateDefs")
local Tag = PlayerStateDefs.Tag

type ScreenEffectMapping = {
	vfx:   string,
	flash: boolean?,
	loop:  boolean?,
}

local PlayerStateScreenEffectDef: { [string]: ScreenEffectMapping } = {

	[Tag.ScreenHitRed] = {
		vfx   = "hit_red",
		flash = true,
	},

	[Tag.ScreenBlind] = {
		vfx  = "blind",
		loop = true,
	},

	[Tag.ScreenStun] = {
		vfx  = "stun_distort",
		loop = true,
	},

	[Tag.ScreenFreeze] = {
		vfx  = "freeze_blue",
		loop = true,
	},

	[Tag.ScreenBurn] = {
		vfx  = "burn_red",
		loop = true,
	},

	[Tag.ScreenPoison] = {
		vfx  = "poison_green",
		loop = true,
	},
}

return PlayerStateScreenEffectDef
