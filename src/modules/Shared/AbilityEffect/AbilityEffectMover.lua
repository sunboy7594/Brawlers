--!strict
--[=[
	@class AbilityEffectMover

	투사체 이동 팩토리 모음. Shared.

	MoveFactory = (handle) -> (dt: number) -> boolean
	- true  = 계속 이동
	- false = 수명 종료 → Controller가 onMiss 호출

	spawnConfig의 방향/위치 랜덤은 AbilityEffectPlayer가 처리.
	이동자는 handle.spawnCFrame 기준으로 동작.
]=]

local require = require(script.Parent.loader).load(script)

local Spring = require("Spring")

local AbilityEffectMover = {}

export type MoveFactory = (handle: any) -> (dt: number) -> boolean

-- ─── Linear: 직선 이동 ────────────────────────────────────────────────────────

--[=[
	config:
	  speed   : number           -- 초당 스터드 (linear) or SpringSpeed (spring)
	  maxRange: number           -- 최대 사거리 (스터드)
	  mode    : "linear"|"spring" -- 기본 "linear"
	  damper  : number?          -- spring 모드 댐퍼 (기본 1.0)
]=]
function AbilityEffectMover.Linear(config: {
	speed: number,
	maxRange: number,
	mode: ("linear" | "spring")?,
	damper: number?,
}): MoveFactory
	return function(handle)
		local origin    = handle.spawnCFrame.Position
		local direction = handle.spawnCFrame.LookVector
		local elapsed   = 0

		if config.mode == "spring" then
			local spring = Spring.new(origin)
			spring.Speed  = config.speed
			spring.Damper = config.damper or 1.0
			spring.Target = origin + direction * config.maxRange

			return function(_dt: number): boolean
				local pos  = spring.Position
				local dist = (pos - origin).Magnitude
				if dist >= config.maxRange * 0.99 then
					return false
				end
				if handle.part then
					handle.part:PivotTo(CFrame.new(pos, pos + direction))
				end
				return true
			end
		else
			return function(dt: number): boolean
				elapsed += dt
				local dist = config.speed * elapsed
				if dist >= config.maxRange then
					return false
				end
				local newPos = origin + direction * dist
				if handle.part then
					handle.part:PivotTo(CFrame.new(newPos, newPos + direction))
				end
				return true
			end
		end
	end
end

-- ─── Arc: 포물선 투척 ──────────────────────────────────────────────────────────

--[=[
	config:
	  distance: number  -- 수평 도달 거리 (스터드)
	  height  : number  -- 최고 높이 (스터드)
	  speed   : number  -- 수평 속도 (초당 스터드)
	  mode    : "linear"|"spring" -- 기본 "linear"
	  damper  : number?
]=]
function AbilityEffectMover.Arc(config: {
	distance: number,
	height: number,
	speed: number,
	mode: ("linear" | "spring")?,
	damper: number?,
}): MoveFactory
	return function(handle)
		local origin  = handle.spawnCFrame.Position
		local forward = handle.spawnCFrame.LookVector
		local flatDir = Vector3.new(forward.X, 0, forward.Z)
		if flatDir.Magnitude > 0.001 then
			flatDir = flatDir.Unit
		else
			flatDir = Vector3.new(0, 0, -1)
		end

		local duration = config.distance / config.speed
		local elapsed  = 0

		return function(dt: number): boolean
			elapsed += dt
			local t = elapsed / duration
			if t >= 1 then
				return false
			end

			-- 포물선: y = height * 4*t*(1-t)
			local h   = origin + flatDir * (config.distance * t)
			local v   = config.height * 4 * t * (1 - t)
			local pos = Vector3.new(h.X, origin.Y + v, h.Z)

			-- 방향 계산 (다음 프레임 예측)
			local t2  = math.min(t + 0.01, 0.999)
			local h2  = origin + flatDir * (config.distance * t2)
			local v2  = config.height * 4 * t2 * (1 - t2)
			local pos2 = Vector3.new(h2.X, origin.Y + v2, h2.Z)

			if handle.part then
				local delta = pos2 - pos
				if delta.Magnitude > 0.001 then
					handle.part:PivotTo(CFrame.new(pos, pos + delta.Unit))
				else
					handle.part:PivotTo(CFrame.new(pos))
				end
			end
			return true
		end
	end
end

-- ─── Sweep: 원호 이동 (칼 휘두르기 등) ────────────────────────────────────────

--[=[
	config:
	  range   : number           -- 중심에서 거리 (스터드)
	  angleMin: number           -- 시작 각도 (도, 전방 기준)
	  angleMax: number           -- 끝 각도 (도)
	  duration: number           -- 소요 시간 (초) (linear 모드)
	  mode    : "linear"|"spring" -- 기본 "linear"
	  speed   : number?          -- spring 모드 SpringSpeed
	  damper  : number?          -- spring 모드 댐퍼
]=]
function AbilityEffectMover.Sweep(config: {
	range: number,
	angleMin: number,
	angleMax: number,
	duration: number,
	mode: ("linear" | "spring")?,
	speed: number?,
	damper: number?,
}): MoveFactory
	return function(handle)
		local origin  = handle.spawnCFrame.Position
		local baseDir = handle.spawnCFrame.LookVector
		local elapsed = 0

		if config.mode == "spring" then
			local startAngle = math.rad(config.angleMin)
			local endAngle   = math.rad(config.angleMax)
			local spring = Spring.new(startAngle)
			spring.Speed  = config.speed or 10
			spring.Damper = config.damper or 1.0
			spring.Target = endAngle

			return function(_dt: number): boolean
				local angle    = spring.Position
				local rotCF    = CFrame.Angles(0, angle, 0) * CFrame.new(Vector3.zero, baseDir)
				local dir      = rotCF.LookVector
				local newPos   = origin + dir * config.range
				if handle.part then
					handle.part:PivotTo(CFrame.new(newPos, newPos + dir))
				end
				-- spring이 목표에 충분히 수렴하면 종료
				if math.abs(angle - endAngle) < 0.005 then
					return false
				end
				return true
			end
		else
			return function(dt: number): boolean
				elapsed += dt
				local t = math.clamp(elapsed / config.duration, 0, 1)
				if t >= 1 then
					return false
				end

				local angle  = math.rad(config.angleMin + (config.angleMax - config.angleMin) * t)
				local rotCF  = CFrame.Angles(0, angle, 0) * CFrame.new(Vector3.zero, baseDir)
				local dir    = rotCF.LookVector
				local newPos = origin + dir * config.range
				if handle.part then
					handle.part:PivotTo(CFrame.new(newPos, newPos + dir))
				end
				return true
			end
		end
	end
end

return AbilityEffectMover
