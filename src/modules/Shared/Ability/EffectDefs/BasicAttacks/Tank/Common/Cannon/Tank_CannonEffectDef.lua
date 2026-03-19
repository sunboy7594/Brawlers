--!strict
--[=[
	@class Tank_CannonEffectDef

	탱크 캐논 기본공격 이펙트 정의.

	template:
	  ReplicatedStorage.AbilityEffects.CannonBall 모델을 사용합니다.
	  Studio에서 ReplicatedStorage > AbilityEffects > CannonBall (Model) 을 배치하세요.

	hasSelfHit = false:
	  이 EffectDef는 순수 비주얼 담당.
	  실제 충돌 판정은 Tank_CannonClient의 Heartbeat 루프 + ProjectileHit 서버 검증이 담당.

	move:
	  현재 nil → 파트가 origin에 소환만 됨.
	  AbilityEffectMoveUtils 완성 후 아래처럼 교체하세요:
	    move = AbilityEffectMoveUtils.Linear(40, 100)
	  또는 직접 MoveFactory를 작성할 수도 있습니다:
	    move = function(handle)
	        local elapsed = 0
	        return function(dt)
	            elapsed += dt
	            local pos = handle.part:GetPivot().Position + direction * 40 * dt
	            handle.part:PivotTo(CFrame.new(pos))
	            return elapsed * 40 < 100
	        end
	    end

	colorFilter:
	  AbilityEffectColorUtils.Highlight(0.5) → 반투명 팀 색상 오버레이.
	  AbilityEffectColorUtils.SelectionBox()  → 외곽선만. 실험 후 교체 가능.
]=]

local require = require(script.Parent.loader).load(script)

local AbilityEffectColorUtils = require("AbilityEffectColorUtils")

local Tank_CannonEffectDef = {

	CannonBall = {
		-- ReplicatedStorage.AbilityEffects.CannonBall 모델
		template    = "CannonBall",

		-- 순수 비주얼: 충돌 판정은 외부(Tank_CannonClient + ProjectileHit)가 담당
		hasSelfHit  = false,

		-- 이동 없음: 파트가 origin에 소환만 됨
		-- TODO: AbilityEffectMoveUtils.Linear(40, 100) 으로 교체
		move        = nil,

		-- 팀 색상 반투명 오버레이 (Highlight 방식)
		-- 실험 후 AbilityEffectColorUtils.SelectionBox()로 교체 가능
		colorFilter = AbilityEffectColorUtils.Highlight(0.5),

		-- 추후 파티클 추가 시 여기에
		particles = nil,
	},

}

return Tank_CannonEffectDef
