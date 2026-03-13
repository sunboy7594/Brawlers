--!strict
--[=[
	@class TankBasicAttackDefs

	탱크 기본 공격 정의 테이블.
	maxAmmo: 최대 탄약 수
	reloadTime: 탄약 1개 재생 시간 (초)
]=]

return {
	Punch = {
		rarity = "COMMON",
		class = "TANK",
		maxAmmo = 3,
		reloadTime = 1.5,
	},
}
