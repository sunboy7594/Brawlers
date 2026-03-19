--!strict
--[=[
	@class AbilityEffectHitOrMissUtil

	Hit/Miss 콜백 팩토리 모음. Shared.

	타입:
	  OnHitFn  = (handle, hitInfo) -> ()
	  OnMissFn = (handle) -> ()

	onMiss 발동 조건:
	  - move 자연 종료 (사거리/시간 초과)
	onMiss 미발동:
	  - Despawn() / FadeOut() 호출 (자체 소멸)
	  - abilityEffectMaid:Destroy() 강제 종료

	SpawnEffect은 AbilityEffectPlayer 의존성 때문에
	_spawnEffectFn 주입 패턴 사용.
	AbilityEffectPlayer:Init() 시 setSpawnEffectFn() 호출 필요.
]=]

local require = require(script.Parent.loader).load(script)

local AbilityEffectTransformUtil = require("AbilityEffectTransformUtil")

local AbilityEffectHitOrMissUtil = {}

-- ─── SpawnEffect 의존성 주입 ──────────────────────────────────────────────────
-- AbilityEffectPlayer가 초기화 시 setSpawnEffectFn()으로 등록

local _spawnEffectFn: (
	(defModuleName: string, effectName: string, options: any) -> ()
)? = nil

function AbilityEffectHitOrMissUtil.setSpawnEffectFn(
	fn: (defModuleName: string, effectName: string, options: any) -> ()
)
	_spawnEffectFn = fn
end

-- ─── Despawn: 즉시 소멸 (onMiss 없음) ────────────────────────────────────────

function AbilityEffectHitOrMissUtil.Despawn(): (handle: any, hitInfo: any?) -> ()
	return function(handle: any, _hitInfo: any?)
		handle:Destroy()
	end
end

-- ─── FadeOut: 서서히 소멸 (onMiss 없음) ──────────────────────────────────────
-- onHit 비활성화, move/onMove 계속 진행, duration 후 소멸

function AbilityEffectHitOrMissUtil.FadeOut(config: {
	duration: number,
}): (handle: any, hitInfo: any?) -> ()
	return function(handle: any, _hitInfo: any?)
		if not handle._alive then return end
		handle._hitEnabled  = false
		handle._isFadingOut = true

		if handle.part then
			AbilityEffectTransformUtil.ApplyFade(handle.part, {
				to       = 1,
				duration = config.duration,
				mode     = "linear",
				speed    = 1,
			}, handle._maid)
		end

		-- duration 후 소멸 (onMiss 없음)
		handle._maid:GiveTask(task.delay(config.duration, function()
			if handle._alive then
				handle:Destroy()
			end
		end))
	end
end

-- ─── StopMove: 이동 중단 (모델 유지) ─────────────────────────────────────────

function AbilityEffectHitOrMissUtil.StopMove(): (handle: any, hitInfo: any?) -> ()
	return function(handle: any, _hitInfo: any?)
		handle._moveActive = false
	end
end

-- ─── SpawnEffect: 현재 위치에 2차 이펙트 소환 ────────────────────────────────

function AbilityEffectHitOrMissUtil.SpawnEffect(
	defModuleName: string,
	effectName: string,
	overrideOptions: any?
): (handle: any, hitInfo: any?) -> ()
	return function(handle: any, hitInfo: any?)
		if not _spawnEffectFn then return end

		local pos = if hitInfo and hitInfo.position
			then hitInfo.position
			else if handle.part
				then handle.part:GetPivot().Position
				else handle.spawnCFrame.Position

		local dir    = handle.spawnCFrame.LookVector
		local origin = CFrame.new(pos, pos + dir)

		local opts  = overrideOptions or {}
		opts.origin  = origin
		opts.isOwner = handle.isOwner
		opts.firedAt = handle.firedAt
		_spawnEffectFn(defModuleName, effectName, opts)
	end
end

-- ─── TriggerMiss: onHit 내에서 onMiss 즉시 실행 ──────────────────────────────

function AbilityEffectHitOrMissUtil.TriggerMiss(): (handle: any, hitInfo: any?) -> ()
	return function(handle: any, _hitInfo: any?)
		handle:Miss()
	end
end

-- ─── Penetrate: N회 관통 ─────────────────────────────────────────────────────
-- maxCount 히트까지는 관통, 초과 시 onMaxHit 실행 (기본: Despawn)

function AbilityEffectHitOrMissUtil.Penetrate(config: {
	maxCount: number,
	onMaxHit: ((handle: any, hitInfo: any?) -> ())?,
}): (handle: any, hitInfo: any?) -> ()
	return function(handle: any, hitInfo: any?)
		handle._hitCount = (handle._hitCount or 0) + 1
		if handle._hitCount >= config.maxCount then
			local maxHitFn = config.onMaxHit or AbilityEffectHitOrMissUtil.Despawn()
			maxHitFn(handle, hitInfo)
		end
		-- 미만이면 관통 (아무것도 안 함)
	end
end

-- ─── Sequence: 여러 콜백 순서 실행 ───────────────────────────────────────────
-- 각 콜백 실행 후 handle._alive 체크하여 파괴된 경우 중단

function AbilityEffectHitOrMissUtil.Sequence(
	callbacks: { (handle: any, hitInfo: any?) -> () }
): (handle: any, hitInfo: any?) -> ()
	return function(handle: any, hitInfo: any?)
		for _, fn in callbacks do
			if not handle._alive then break end
			fn(handle, hitInfo)
		end
	end
end

return AbilityEffectHitOrMissUtil
