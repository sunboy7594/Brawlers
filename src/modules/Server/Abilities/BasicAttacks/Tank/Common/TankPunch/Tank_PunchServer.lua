--!strict
--[=[
	@class Tank_PunchServer

	탱크 주먹 공격 서버 모듈.

	onFire:
	- InstantHit.apply()에 state.onHit을 콜백으로 전달
	- 판정 완료 시 BasicAttackService의 onHit 콜백이 호출됨
	- 반환값 없음 (HitChecked 타이밍은 InstantHit → onHit 콜백이 담당)

	onHitChecked:
	- snapshot(Fire 시점 state 복사본)을 받음
	- 1, 2콤보: HitShake + HitStagger
	- 3콤보:    HitRecoil + HitKnockback (넉백 느낌)
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local BasicAttackRemoting = require("BasicAttackRemoting")
local InstantHit = require("InstantHit")

type BasicAttackState = {
	-- 장착 정보
	equippedAttackId: string?,

	-- 캐릭터
	humanoid: Humanoid?,
	rootPart: BasePart?,

	-- 탄약
	currentAmmo: number,
	maxAmmo: number,
	reloadTime: number,
	postDelay: number,

	-- 타이밍
	lastFireTime: number,
	postDelayUntil: number,
	lastRegenTime: number,
	lastHitTime: number,
	aimStartTime: number,

	-- 콤보
	fireComboCount: number,
	hitComboCount: number,

	-- 발사 컨텍스트
	attacker: Model?,
	origin: Vector3,
	direction: Vector3,
	aimTime: number,
	effectiveAimTime: number,
	idleTime: number,
	victims: { Model }?,

	-- 판정 콜백
	onHit: ((victims: { Model }) -> ())?,

	-- 예약 발사 취소 함수
	pendingFireCancel: (() -> ())?,
}

local IDLE_COMBO_RESET = 3.0

return {
	onFire = {
		function(state: BasicAttackState)
			if not state.attacker then
				return
			end

			if state.idleTime >= IDLE_COMBO_RESET then
				state.fireComboCount = 0
			end

			state.fireComboCount = (state.fireComboCount % 3) + 1

			if state.fireComboCount == 3 then
				-- 3콤보: 더 넓은 범위
				InstantHit.apply(state.attacker, state.origin, state.direction, {
					shape = "cone",
					range = 10,
					angle = 120,
					damage = 60,
					knockback = 25,
				}, state.onHit)
			else
				-- 1, 2콤보: 기본 펀치
				InstantHit.apply(state.attacker, state.origin, state.direction, {
					shape = "cone",
					range = 8,
					angle = 90,
					damage = 40,
					knockback = 15,
				}, state.onHit)
			end
		end,
	},

	onHitChecked = {
		function(snapshot: BasicAttackState)
			local victims = snapshot.victims
			if not victims or #victims == 0 then
				return
			end

			-- 콤보에 따라 피격 반응 분기
			local isHeavy = snapshot.fireComboCount == 3

			local payload = if isHeavy
				then { animName = "HitKnockback", cameraAnimName = "HitRecoil" }
				else { animName = "HitStagger", cameraAnimName = "HitShake" }

			for _, victimModel in victims do
				local victimPlayer = Players:GetPlayerFromCharacter(victimModel)
				if victimPlayer then
					BasicAttackRemoting.HitReaction:FireClient(victimPlayer, payload)
				end
			end
		end,
	},
}
