--[=[
    훅 실행 타이밍:
    - onAimStart : 조준 시작 1회
    - onAim      : 매 프레임
    - onFire     : 발사 확정 후 (애니메이션, 로컬 이펙트)
    - onHitChecked : 서버 히트 체크 완료 후 (사운드, 히트 이펙트)
]=]

local COMBO_ANIMS = { "Punch1", "Punch2", "Punch3" }

return {
	shapes = { "cone" },

	onAimStart = {
		function(_ctx: ClientContext) end,
	},

	onAim = {},

	onFire = {
		function(ctx: ClientContext)
			if ctx.idleTime >= 3.0 then
				ctx.comboCount = 0
			end

			if ctx.animator then
				local animName = COMBO_ANIMS[(ctx.comboCount % #COMBO_ANIMS) + 1]
				ctx.animator:PlayAnimation(animName, 0.4, nil, true)
			end
		end,
	},

	onHitChecked = {
		function(ctx: ClientContext)
			if ctx.victims and #ctx.victims > 0 then
				-- 히트 이펙트
			end
		end,
	},
}
