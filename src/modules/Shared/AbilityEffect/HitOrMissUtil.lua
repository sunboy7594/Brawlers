--!strict
--[=[
	@class HitOrMissUtil

	onHit / onMiss 콜백 팩토리 모음. (Shared)
	클라이언트 AbilityEffect, 서버 ProjectileHit 공용.

	onHit  타입: (handle: any, hitInfo: HitInfo) -> ()
	onMiss 타입: (handle: any) -> ()

	공통:
	  Despawn()             → 즉시 소멸 (onMiss 없음)
	  StopMove()            → 이동 중단, 위치 고정
	  FadeOut({ duration }) → 서서히 소멸 (클라이언트: 투명도 처리 / 서버: hitDetect 중단 후 제거)
	  SpawnEffect(def, name, options?) → 현재 위치에 2차 이펙트 소환 (클라이언트 전용)
	  Sequence({ ... })     → 여러 콜백 순서대로 실행

	onHit 전용:
	  Penetrate({ maxCount, onMaxHit? }) → N회까지 통과, 초과 시 onMaxHit 실행
	  TriggerMiss()                      → onHit 내에서 onMiss 즉시 발동

	onMiss 유발 조건:
	  - move 함수가 false 반환 (사거리 초과 등 자연 종료)
	  Despawn, FadeOut은 onMiss 발동하지 않음.

	서버 호환:
	  FadeOut: 서버에서는 투명도 처리 생략, _fadingOut 플래그 + duration 후 소멸만 적용.
	  SpawnEffect: 서버에서는 아무것도 하지 않음 (IS_CLIENT 체크).
	  나머지: 클라/서버 동일하게 동작.
]=]

local require = require(script.Parent.loader).load(script)

local RunService = game:GetService("RunService")

local HitOrMissUtil = {}

export type HitRelation = "enemy" | "self" | "team" | "wall"

export type HitInfo = {
	target   : Model,
	relation : HitRelation,
	position : Vector3,
}

export type HitCallback  = (handle: any, hitInfo: HitInfo) -> ()
export type MissCallback = (handle: any) -> ()

local IS_CLIENT = not RunService:IsServer()

function HitOrMissUtil.Despawn(): HitCallback & MissCallback
	return function(handle: any, _hitInfo: any?)
		if handle and handle.IsAlive and handle:IsAlive() then
			handle:_destroyNoMiss()
		end
	end :: any
end

function HitOrMissUtil.StopMove(): HitCallback & MissCallback
	return function(handle: any, _hitInfo: any?)
		if handle then
			handle._moveStopped = true
		end
	end :: any
end

function HitOrMissUtil.FadeOut(config: { duration: number }): HitCallback & MissCallback
	return function(handle: any, _hitInfo: any?)
		if not handle or not handle.IsAlive or not handle:IsAlive() then return end
		handle._fadingOut = true
		local elapsed = 0
		local conn: RBXScriptConnection
		conn = RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			local t = math.clamp(elapsed / config.duration, 0, 1)
			if IS_CLIENT and handle.part then
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

function HitOrMissUtil.SpawnEffect(
	defModuleName : string,
	effectName    : string,
	options       : { [string]: any }?
): HitCallback & MissCallback
	return function(handle: any, _hitInfo: any?)
		if not IS_CLIENT then return end
		local ok, AbilityEffectPlayer = pcall(require, "AbilityEffectPlayer")
		if not ok then
			warn("[HitOrMissUtil] AbilityEffectPlayer require 실패:", AbilityEffectPlayer)
			return
		end
		local spawnCF = handle.part and handle.part:GetPivot() or CFrame.identity
		local opts: { [string]: any } = options and table.clone(options) or {}
		opts.origin  = spawnCF
		opts.isOwner = handle.isOwner
		local player = AbilityEffectPlayer :: any
		player.Play(defModuleName, effectName, opts)
	end :: any
end

function HitOrMissUtil.Sequence(callbacks: { HitCallback | MissCallback }): HitCallback & MissCallback
	return function(handle: any, hitInfo: any?)
		for _, cb in callbacks do
			local fn = cb :: any
			fn(handle, hitInfo)
		end
	end :: any
end

function HitOrMissUtil.Penetrate(config: {
	maxCount : number,
	onMaxHit : HitCallback?,
}): HitCallback
	return function(handle: any, hitInfo: HitInfo)
		local count: number = (handle._penetrateCount or 0) + 1
		handle._penetrateCount = count
		if count >= config.maxCount then
			local cb = config.onMaxHit or HitOrMissUtil.Despawn()
			cb(handle, hitInfo)
		end
	end
end

function HitOrMissUtil.TriggerMiss(): HitCallback
	return function(handle: any, _hitInfo: HitInfo)
		if handle and handle.Miss then
			handle:Miss()
		end
	end
end

return HitOrMissUtil
