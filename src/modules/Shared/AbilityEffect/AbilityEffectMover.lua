--!strict
--[=[
	@class AbilityEffectMover

	투사체 이동 함수 팩토리 모음. (Shared)

	반환 타입 MoveFunction:
	  (dt: number, handle: any, params: { [string]: any }?) -> boolean
	  true  = 계속 이동
	  false = 수명 종료 → Controller가 onMiss 호출

	mode:
	  "linear" → speed (스터드/초) 기반 등속
	  "spring" → speed = SpringSpeed, damper = SpringDamper

	randomAngle:
	  발사 방향 기준 최대 편차 각도 (도)
	  내부적으로 발사 방향 수직 평면에서 균등분포 랜덤 회전 적용
]=]

local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()

local AbilityEffectMover = {}

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
	local rotated = (direction * math.cos(angle)
		+ perp * math.sin(angle) * math.cos(phi)
		+ direction:Cross(perp) * math.sin(angle) * math.sin(phi))
	return rotated.Magnitude > 0.001 and rotated.Unit or direction
end

local function lerpNumber(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- ─── Spring 상태 (서버/클라 공통) ─────────────────────────────────────────────
-- Nevermore Spring을 쓰지 않고 단순 지수 감쇠로 근사
local function springStep(current: number, target: number, velocity: number, speed: number, damper: number, dt: number): (number, number)
	local stiffness = speed * speed
	local dampingForce = 2 * damper * speed
	local acc = -stiffness * (current - target) - dampingForce * velocity
	velocity = velocity + acc * dt
	current = current + velocity * dt
	return current, velocity
end

-- ─── Linear ──────────────────────────────────────────────────────────────────

function AbilityEffectMover.Linear(config: LinearConfig): MoveFunction
	return function(dt: number, handle: any, _params: { [string]: any }?): boolean
		local elapsed: number = (handle :: any)._moveElapsed or 0
		local dir: Vector3    = (handle :: any)._moveDir

		-- 첫 프레임: 방향 초기화
		if elapsed == 0 and not (handle :: any)._moveDir then
			local cf = handle.part and handle.part:GetPivot() or CFrame.identity
			local baseDir = cf.LookVector
			if config.randomAngle and config.randomAngle > 0 then
				baseDir = applyRandomAngle(baseDir, config.randomAngle)
			end
			dir = baseDir;
			(handle :: any)._moveDir = dir
		end

		elapsed += dt
		;(handle :: any)._moveElapsed = elapsed

		local dist = config.speed * elapsed
		if dist >= config.maxRange then
			return false
		end

		if handle.part then
			local currentPos = (handle :: any)._moveOrigin + dir * dist
			handle.part:PivotTo(CFrame.new(currentPos, currentPos + dir))
		end

		return true
	end
end

-- ─── Arc ─────────────────────────────────────────────────────────────────────

function AbilityEffectMover.Arc(config: ArcConfig): MoveFunction
	return function(dt: number, handle: any, _params: { [string]: any }?): boolean
		local elapsed: number = (handle :: any)._moveElapsed or 0

		if elapsed == 0 then
			local cf = handle.part and handle.part:GetPivot() or CFrame.identity;
			(handle :: any)._moveDir    = cf.LookVector;
			(handle :: any)._moveOrigin = cf.Position
		end

		elapsed += dt
		;(handle :: any)._moveElapsed = elapsed

		local totalTime = config.distance / config.speed
		local t = math.clamp(elapsed / totalTime, 0, 1)

		local origin: Vector3 = (handle :: any)._moveOrigin
		local dir: Vector3    = (handle :: any)._moveDir

		local horizontal = origin + dir * (config.distance * t)
		-- 포물선 높이: 4h * t * (1 - t)
		local verticalY = 4 * config.height * t * (1 - t)
		local newPos = Vector3.new(horizontal.X, origin.Y + verticalY, horizontal.Z)

		if handle.part then
			-- 진행 방향을 다음 위치 기준으로 계산
			local nextT = math.min(t + 0.01, 1)
			local nextH = origin + dir * (config.distance * nextT)
			local nextVY = 4 * config.height * nextT * (1 - nextT)
			local nextPos = Vector3.new(nextH.X, origin.Y + nextVY, nextH.Z)
			local lookDir = (nextPos - newPos)
			if lookDir.Magnitude > 0.001 then
				handle.part:PivotTo(CFrame.new(newPos, newPos + lookDir.Unit))
			else
				handle.part:PivotTo(CFrame.new(newPos))
			end
		end

		return t < 1
	end
end

-- ─── Sweep ───────────────────────────────────────────────────────────────────

function AbilityEffectMover.Sweep(config: SweepConfig): MoveFunction
	return function(dt: number, handle: any, _params: { [string]: any }?): boolean
		local elapsed: number = (handle :: any)._moveElapsed or 0

		if elapsed == 0 then
			local cf = handle.part and handle.part:GetPivot() or CFrame.identity;
			(handle :: any)._moveOrigin = cf.Position;
			(handle :: any)._sweepBase  = cf
		end

		elapsed += dt
		;(handle :: any)._moveElapsed = elapsed

		local t = math.clamp(elapsed / config.duration, 0, 1)
		local angle = math.rad(lerpNumber(config.angleMin, config.angleMax, t))

		if handle.part then
			local baseCF: CFrame = (handle :: any)._sweepBase
			local origin: Vector3 = (handle :: any)._moveOrigin
			local swept = baseCF * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -config.range)
			handle.part:PivotTo(CFrame.new(swept.Position, swept.Position + swept.LookVector))
		end

		return t < 1
	end
end

return AbilityEffectMover
