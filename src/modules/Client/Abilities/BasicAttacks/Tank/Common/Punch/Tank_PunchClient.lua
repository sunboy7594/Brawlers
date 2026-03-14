--!strict
--[=[
	@class Tank_PunchClient

	탱크 주먹 공격 클라이언트 모듈.

	훅 실행 타이밍:
	- onAimStart : 조준 시작 1회
	- onAim      : 매 프레임 (IndicatorUpdateParams 반환 시 인디케이터에 반영)
	- onFire     : 발사 확정 후 (애니메이션, 로컬 이펙트)
	- onHitConfirmed : 서버 히트 확정 후 (사운드, 히트 이펙트)
]=]

-- ctx 타입 참조용
type ClientContext = {
	aimTime: number,
	idleTime: number,
	comboCount: number,
	direction: Vector3,
	origin: Vector3,
	indicator: any,
	animator: any?,
	victims: { any }?,
}

-- 콤보 카운터 (모듈 클로저로 관리)
local COMBO_ANIMS = { "Punch1", "Punch2", "Punch3" }

return {
	-- DynamicIndicator가 생성할 shape 목록
	-- nil이면 전체 shape 생성
	shapes = { "cone" },

	-- ─── 조준 시작 ───────────────────────────────────────────────────────
	onAimStart = {
		function(_ctx: ClientContext)
			-- TODO: 차지 사운드 시작 등
		end,
	},

	-- ─── 매 프레임 ──────────────────────────────────────────────────────
	onAim = {
		-- function(ctx: ClientContext)
		-- 	-- ammo 없음 / postDelay 중은 BasicAttackClient Heartbeat에서 처리
		-- 	-- 정상 조준 가능할 때만 커스텀 색상 연출
		-- 	if not ctx.hasAmmo or ctx.isPostDelay then
		-- 		return
		-- 	end

		-- 	local t = math.clamp(ctx.aimTime / 1.0, 0, 1)
		-- 	ctx.indicator:update({
		-- 		color = Color3.new(1, 1 - t * 0.8, 0),
		-- 		transparency = 0.45 - t * 0.1,
		-- 	})
		-- end,
	},

	-- ─── 발사 확정 ──────────────────────────────────────────────────────
	onFire = {
		function(ctx: ClientContext)
			-- 콤보 애니메이션 재생
			if ctx.animator then
				local animName = COMBO_ANIMS[((ctx.comboCount - 1) % #COMBO_ANIMS) + 1]
				ctx.animator:PlayAnimation(animName, 0.4)
			end
			-- TODO: 로컬 이펙트 재생
		end,
	},

	-- ─── 히트 확정 ──────────────────────────────────────────────────────
	onHitConfirmed = {
		function(ctx: ClientContext)
			-- ctx.victims: 피격된 Player 목록
			-- TODO: 히트 사운드, 히트 이펙트 재생
			if ctx.victims and #ctx.victims > 0 then
				-- 히트 연출
			end
		end,
	},
}
