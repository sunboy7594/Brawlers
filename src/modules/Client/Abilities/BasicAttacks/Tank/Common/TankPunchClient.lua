--!strict
--[=[
	@class TankPunchClient

	탱크 주먹 공격 클라이언트 모듈.
	BasicAttackClient의 ATTACK_REGISTRY에 등록됩니다.

	- indicator: 부채꼴 인디케이터 (range=8, angle=90)
	- onAim: 매 프레임 조준 콜백 (nil = 없음)
	- onHitConfirmed: 서버 적중 확정 시 호출 (이펙트/사운드 재생용)
]=]

local require = require(script.Parent.loader).load(script)

local ConeIndicator = require("ConeIndicator")

return {
	-- 부채꼴 범위 인디케이터 (range=8, angle=90도)
	indicator = ConeIndicator.new({ range = 8, angle = 90 }),

	-- 매 프레임 조준 콜백 (aimTime: number) → nil이면 사용 안 함
	onAim = nil,

	-- 서버에서 적중 확정 시 호출 (이펙트/사운드 재생용)
	-- victims: { Model } — 맞은 캐릭터 목록
	onHitConfirmed = function(_victims: { Model })
		-- TODO: 히트 이펙트 및 사운드 재생 구현 예정
	end,
}
