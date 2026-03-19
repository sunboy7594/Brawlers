--!strict
--[=[
	@class AbilityEffectHitOrMissUtil

	onHit / onMiss 콜백 팩토리 모음. (Shared)

	onHit  타입: (handle: any, hitInfo: HitInfo) -> ()
	onMiss 타입: (handle: any) -> ()

	공통:
	  Despawn()             → 즉시 소멸 (onMiss 없음)
	  StopMove()            → 이동 중단, 위치 고정
	  FadeOut({ duration }) → 서서히 소멸 (onMiss 없음)
	  SpawnEffect(def, name, options?) → 현재 위치에 2차 이펙트 소환
	  Sequence({ ... })     → 여러 콜백 순서대로 실행

	onHit 전용:
	  Penetrate({ maxCount, onMaxHit? }) → N회까지 통과, 초과 시 onMaxHit 실행
	  TriggerMiss()                      → onHit 내에서 onMiss 즉시 발동

	onMiss 유발 조건:
	  - move 함수가 false 반환 (사거리 초과 등 자연 종료)
	  Despawn, FadeOut은 onMiss 발동하지 않음.
]=]

local RunService = game:GetService("RunService")

local AbilityEffectHitOrMissUtil = {}

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type HitRelation = "enemy" | "self" | "team" | "wall"

export type HitInfo = {
	target   : Model,
	relation : HitRelation,
	position : Vector3,
}

export type HitCallback  = (handle: any, hitInfo: HitInfo) -> ()
export type MissCallback = (handle: any) -> ()

-- ─── 내부 ────────────────────────────────────────────────────────────────────

-- 서버에선 AbilityEffectPlayer를 쓸 수 없으므로 SpawnEffect는 클라이언트 전용
-- 서버 시뮬에서는 SpawnEffect 호출 시 아무것도 하지 않음
local IS_CLIENT = not game:GetService("RunService"):IsServer()

-- ─── 공통 유틸 ───────────────────────────────────────────────────────────────

--[=[
	즉시 소멸. onMiss 없음.
]=]
function AbilityEffectHitOrMissUtil.Despawn(): HitCallback & MissCallback
	return function(handle: any, _hitInfo: any?)
		if handle and handle.IsAlive and handle:IsAlive() then
			handle:_destroyNoMiss()
		end
	end :: any
end

--[=[
	이동 중단, 위치 고정.
]=]
function AbilityEffectHitOrMissUtil.StopMove(): HitCallback & MissCallback
	return function(handle: any, _hitInfo: any?)
		if handle then
			handle._moveStopped = true
		end
	end :: any
end

--[=[
	서서히 소멸. onMiss 없음.
	이동/onMove는 계속 진행, duration 후 onHit 발동 불가 상태로 소멸.
]=]
function AbilityEffectHitOrMissUtil.FadeOut(config: { duration: number }): HitCallback & MissCallback
	return function(handle: any, _hitInfo: any?)
		if not handle or not handle.IsAlive or not handle:IsAlive() then return end
		handle._fadingOut = true
		local elapsed = 0
		local conn: RBXScriptConnection
		conn = RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			local t = math.clamp(elapsed / config.duration, 0, 1)
			if handle.part then
				for _, d in handle.part:GetDescendants() do
					if d:IsA("BasePart") then
						(d :: BasePart).Transparency = t
					end
				end
			end
			if t >= 1 then
				conn:Disconnect()
				if handle:IsAlive() then
					handle:_destroyNoMiss()
				end
			end
		end)
		handle._maid:GiveTask(conn)
	end :: any
end

--[=[
	현재 위치에 2차 이펙트 소환. 클라이언트 전용.
	서버에서는 아무것도 하지 않음.
]=]
function AbilityEffectHitOrMissUtil.SpawnEffect(
	defModuleName : string,
	effectName    : string,
	options       : { [string]: any }?
): HitCallback & MissCallback
	return function(handle: any, _hitInfo: any?)
		if not IS_CLIENT then return end
		local ok, AbilityEffectPlayer = pcall(require, script.Parent.Parent.Client.AbilityEffect.AbilityEffectPlayer)
		if not ok then
			warn("[AbilityEffectHitOrMissUtil] AbilityEffectPlayer require 실패:", AbilityEffectPlayer)
			return
		end
		local spawnCF = handle.part and handle.part:GetPivot() or CFrame.identity
		local opts = options or {}
		opts.origin = spawnCF
		opts.isOwner = handle.isOwner
		;(AbilityEffectPlayer :: any).Play(defModuleName, effectName, opts)
	end :: any
end

--[=[
	여러 콜백 순서대로 실행.
]=]
function AbilityEffectHitOrMissUtil.Sequence(callbacks: { HitCallback | MissCallback }): HitCallback & MissCallback
	return function(handle: any, hitInfo: any?)
		for _, cb in callbacks do
			;(cb :: any)(handle, hitInfo)
		end
	end :: any
end

-- ─── onHit 전용 ──────────────────────────────────────────────────────────────

--[=[
	N회까지 히트 통과. maxCount 초과 시 onMaxHit 실행.
	onMaxHit = nil이면 Despawn() 자동.
]=]
function AbilityEffectHitOrMissUtil.Penetrate(config: {
	maxCount : number,
	onMaxHit : HitCallback?,
}): HitCallback
	return function(handle: any, hitInfo: HitInfo)
		local count: number = (handle._penetrateCount or 0) + 1
		handle._penetrateCount = count
		if count >= config.maxCount then
			local cb = config.onMaxHit or AbilityEffectHitOrMissUtil.Despawn()
			cb(handle, hitInfo)
		end
		-- maxCount 미만이면 아무것도 안 함 (통과)
	end
end

--[=[
	onHit 내에서 onMiss를 즉시 발동.
	벽에 맞았을 때 히트 처리 없이 소멸 처리 등에 사용.
]=]
function AbilityEffectHitOrMissUtil.TriggerMiss(): HitCallback
	return function(handle: any, _hitInfo: HitInfo)
		if handle and handle.Miss then
			handle:Miss()
		end
	end
end

return AbilityEffectHitOrMissUtil
