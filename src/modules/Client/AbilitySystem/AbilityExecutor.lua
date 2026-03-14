--!strict
--[=[
	@class AbilityExecutor

	어빌리티 클라이언트 모듈의 훅 배열을 실행하는 순수 유틸리티.
	ctx를 저장하지 않으며, 실행 시점에 인자로만 받음.

	사용처:
	- AimController     : onAimStart, onAim, onFire
	- BasicAttackClient : onHitConfirmed
	- SkillClient       : onHitConfirmed
	- UltimateClient    : onHitConfirmed
]=]

local AbilityExecutor = {}

--[=[
	훅 배열을 순회하며 ctx를 인자로 실행합니다.
	hookList가 nil이면 아무것도 하지 않습니다.
]=]
function AbilityExecutor.run(hookList: { (ctx: any) -> () }?, ctx: any)
	if not hookList then
		return
	end
	for _, fn in hookList do
		fn(ctx)
	end
end

function AbilityExecutor.onAimStart(clientModule: any, ctx: any)
	AbilityExecutor.run(clientModule.onAimStart, ctx)
end

function AbilityExecutor.onAim(clientModule: any, ctx: any)
	AbilityExecutor.run(clientModule.onAim, ctx)
end

function AbilityExecutor.onFire(clientModule: any, ctx: any)
	AbilityExecutor.run(clientModule.onFire, ctx)
end

function AbilityExecutor.onHitConfirmed(clientModule: any, ctx: any)
	AbilityExecutor.run(clientModule.onHitConfirmed, ctx)
end

return AbilityExecutor
