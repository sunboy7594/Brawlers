--!strict
--[=[
	@class Tank_PunchServer

	탱크 주먹 공격 서버 모듈.

	onFire 배열의 함수들은 sctx를 받고, { Model } 반환 시
	BasicAttackService가 victims로 합산합니다.
]=]

local require = require(script.Parent.loader).load(script)

local InstantHit = require("InstantHit")

-- sctx 타입 (참조용, 실제 타입은 BasicAttackService에 정의)
type ServerContext = {
	attacker: Model?,
	origin: Vector3,
	direction: Vector3,
	comboCount: number,
	aimTime: number,
	idleTime: number,
	victims: { Model }?,
}

return {
	onFire = {
		function(sctx: ServerContext): { Model }
			if not sctx.attacker then
				return {}
			end

			-- 콤보에 따른 판정 분기
			if sctx.comboCount == 3 then
				-- 3콤보: 더 넓은 범위
				return InstantHit.apply(sctx.attacker, sctx.origin, sctx.direction, {
					shape = "cone",
					range = 10,
					angle = 120,
					damage = 60,
					knockback = 25,
				}) :: { Model }
			else
				-- 1, 2콤보: 기본 펀치
				return InstantHit.apply(sctx.attacker, sctx.origin, sctx.direction, {
					shape = "cone",
					range = 8,
					angle = 90,
					damage = 40,
					knockback = 15,
				}) :: { Model }
			end
		end,
	},

	onHitConfirmed = {
		function(_sctx: ServerContext)
			-- TODO: 서버 측 히트 후처리 (버프, 스턴 적용 등)
		end,
	},
}
