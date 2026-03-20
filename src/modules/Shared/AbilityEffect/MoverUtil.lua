--!strict
--[=[
	@class MoverUtil

	이동 함수 팩토리 모음. (Shared)
	클라이언트 AbilityEffect, 서버 ProjectileHit 공용.

	반환 타입 MoveFunction:
	  (dt: number, handle: any, params: { [string]: any }?) -> boolean
	  true  = 계속 이동
	  false = 수명 종료 → onMiss 호출

	mode:
	  "linear" → speed (스터드/초) 기반 등속
	  "spring" → speed = SpringSpeed, damper = SpringDamper

	randomAngle:
	  발사 방향 기준 최대 편차 각도 (도)
	  연출 전용 — 서버 ProjectileHit에서는 사용 비권장.
]=]

local MoverUtil = {}

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type MoveFunction = (dt: number, handle: any, params: { [string]: any }?) -> boolean

export type LinearConfig = {
	speed       : number,
	maxRange    : number,
	mode        : ("linear" | "spring")?,
	damper      : number?,
	randomAngle : number?,
}

export type ArcConfig = {
	distance : number,
	height   : number,
	speed    : number,
	mode     : ("linear" | "spring")?,
	damper   : number?,
}

export type SweepConfig = {
	range       : number,
	angleMin    : number,
	angleMax    : number,
	duration    : number,
	mode        : ("linear" | "spring")?,
	damper      : number?,
	randomAngle : number?,
}

-- ─── 내부 유틸 ───────────────────────────────────────────────────────────────

local function applyRandomAngle(direction: Vector3, maxAngleDeg: number): Vector3
	if maxAngleDeg <= 0 then return direction end
	local angle = math.rad(math.random() * maxAngleDeg)
	local phi   = math.random() * math.pi * 2
	local perp  = direction:Cross(Vector3.new(0, 1, 0))
	if perp.Magnitude < 0.001 then
		perp = direction:Cross(Vector3.new(1, 0, 0))
	end
	perp = perp.Unit
	local rotated = direction * math.cos(angle)
		+ perp * math.sin(angle) * math.cos(phi)
		+ direction:Cross(perp) * math.sin(angle) * math.sin(phi)
	return rotated.Magnitude > 0.001 and rotated.Unit or direction
end

local function lerpNumber(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- ─── Linear ──────────────────────────────────────────────────────────────────

function MoverUtil.Linear(config: LinearConfig): MoveFunction
	return function(dt: number, handle: any, _params: { [string]: any }?): boolean
		local h = handle :: any
		local elapsed: number = h._moveElapsed or 0

		if not h._moveDir then
			local cf = h.part and h.part:GetPivot() or CFrame.identity
			local baseDir = cf.LookVector
			if config.randomAngle and config.randomAngle > 0 then
				baseDir = applyRandomAngle(baseDir, config.randomAngle)
			end
			h._moveDir = baseDir
		end
		if not h._moveOrigin then
			h._moveOrigin = h.part and h.part:GetPivot().Position or Vector3.zero
		end

		elapsed += dt
		h._moveElapsed = elapsed

		local dir: Vector3    = h._moveDir
		local origin: Vector3 = h._moveOrigin
		local dist = config.speed * elapsed

		if dist >= config.maxRange then
			return false
		end

		if h.part and dir and origin then
			local currentPos = origin + dir * dist
			h.part:PivotTo(CFrame.new(currentPos, currentPos + dir))
		end

		return true
	end
end

-- ─── Arc ─────────────────────────────────────────────────────────────────────

function MoverUtil.Arc(config: ArcConfig): MoveFunction
	return function(dt: number, handle: any, _params: { [string]: any }?): boolean
		local h = handle :: any
		local elapsed: number = h._moveElapsed or 0

		if not h._moveDir or not h._moveOrigin then
			local cf = h.part and h.part:GetPivot() or CFrame.identity
			h._moveDir    = cf.LookVector
			h._moveOrigin = cf.Position
		end

		elapsed += dt
		h._moveElapsed = elapsed

		local totalTime = config.distance / config.speed
		local t = math.clamp(elapsed / totalTime, 0, 1)

		local origin: Vector3 = h._moveOrigin
		local dir: Vector3    = h._moveDir

		if not origin or not dir then return true end

		local horizontal = origin + dir * (config.distance * t)
		local verticalY  = 4 * config.height * t * (1 - t)
		local newPos     = Vector3.new(horizontal.X, origin.Y + verticalY, horizontal.Z)

		if h.part then
			local nextT   = math.min(t + 0.01, 1)
			local nextH   = origin + dir * (config.distance * nextT)
			local nextVY  = 4 * config.height * nextT * (1 - nextT)
			local nextPos = Vector3.new(nextH.X, origin.Y + nextVY, nextH.Z)
			local lookDir = nextPos - newPos
			if lookDir.Magnitude > 0.001 then
				h.part:PivotTo(CFrame.new(newPos, newPos + lookDir.Unit))
			else
				h.part:PivotTo(CFrame.new(newPos))
			end
		end

		return t < 1
	end
end

-- ─── Sweep ───────────────────────────────────────────────────────────────────

function MoverUtil.Sweep(config: SweepConfig): MoveFunction
	return function(dt: number, handle: any, _params: { [string]: any }?): boolean
		local h = handle :: any
		local elapsed: number = h._moveElapsed or 0

		if not h._sweepBase then
			local cf = h.part and h.part:GetPivot() or CFrame.identity
			h._moveOrigin = cf.Position
			h._sweepBase  = cf
		end

		elapsed += dt
		h._moveElapsed = elapsed

		local t     = math.clamp(elapsed / config.duration, 0, 1)
		local angle = math.rad(lerpNumber(config.angleMin, config.angleMax, t))

		if h.part and h._sweepBase then
			local baseCF: CFrame = h._sweepBase
			local swept = baseCF * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -config.range)
			h.part:PivotTo(CFrame.new(swept.Position, swept.Position + swept.LookVector))
		end

		return t < 1
	end
end

return MoverUtil
