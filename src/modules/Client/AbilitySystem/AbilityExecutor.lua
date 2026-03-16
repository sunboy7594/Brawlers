--!strict
--[=[
	@class AbilityExecutor

	어빌리티 클라이언트 모듈의 훅 배열을 실행하는 순수 유틸리티.
	abilityState를 저장하지 않으며, 실행 시점에 인자로만 받음.

	사용처:
	- AimControllerClient : OnAimStart, OnAim, OnFire
	- BasicAttackClient   : OnHitChecked
	- SkillClient         : OnHitChecked
	- UltimateClient      : OnHitChecked
]=]

local AbilityExecutor = {}

--[=[
	훅 배열을 순회하며 abilityState를 인자로 실행합니다.
	hookList가 nil이면 아무것도 하지 않습니다.
]=]
function AbilityExecutor.Run(hookList: { (abilityState: any) -> () }?, abilityState: any)
	if not hookList then
		return
	end
	for _, fn in hookList do
		fn(abilityState)
	end
end

function AbilityExecutor.OnAimStart(clientModule: any, abilityState: any)
	AbilityExecutor.Run(clientModule.onAimStart, abilityState)
end

function AbilityExecutor.OnAim(clientModule: any, abilityState: any)
	AbilityExecutor.Run(clientModule.onAim, abilityState)
end

function AbilityExecutor.OnFire(clientModule: any, abilityState: any)
	AbilityExecutor.Run(clientModule.onFire, abilityState)
end

function AbilityExecutor.OnHitChecked(clientModule: any, abilityState: any)
	AbilityExecutor.Run(clientModule.onHitChecked, abilityState)
end

return AbilityExecutor
