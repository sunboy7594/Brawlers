--!strict
--[=[
	@class TankPunch

	탱크 주먹 공격 서버 모듈.
	BasicAttackService의 ATTACK_REGISTRY에 등록됩니다.

	판정:
	- shape: cone (부채꼴)
	- range: 8 studs
	- angle: 90도
	- damage: 40
	- knockback: 15
]=]

local require = require(script.Parent.loader).load(script)

local InstantHit = require("InstantHit")

return {
	--[=[
		공격을 실행하고 적중된 캐릭터 목록을 반환합니다.

		@param attacker Model     공격자 캐릭터
		@param origin Vector3     판정 기준점 (HumanoidRootPart 위치)
		@param direction Vector3  공격 방향 (수평 정규화)
		@param aimTime number     조준 유지 시간 (초) — 향후 차지 데미지 등에 활용 가능
		@return { Model }         적중된 캐릭터 목록
	]=]
	onFire = function(attacker: Model, origin: Vector3, direction: Vector3, _aimTime: number): { Model }
		-- 즉시 판정 (delay 없음) → { Model } 반환 보장
		local result = InstantHit.apply(attacker, origin, direction, {
			shape = "cone",
			range = 8,
			angle = 90,
			damage = 40,
			knockback = 15,
		})
		return result :: { Model }
	end,
}
