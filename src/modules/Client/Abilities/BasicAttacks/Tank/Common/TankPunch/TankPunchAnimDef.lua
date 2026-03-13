--!strict
--[=[
	@class TankPunchAnimDef

	탱커 주먹 공격 절차적 애니메이션 정의.
	BasicMovementAnimDefs와 동일한 패턴으로 작성합니다.

	aim:  조준 자세 (홀드 중 유지)
	fire: 발사 모션 (휘두르기, 1회성)
]=]

return {
	aim = {
		-- TODO: 조준 자세 정의
		-- BasicMovementAnimDefs의 makeIdle 패턴 참고
	},
	fire = {
		-- TODO: 휘두르기 모션 정의
		-- BasicMovementAnimDefs의 makeRun 패턴 참고
	},
}
