--!strict
--[=[
	@class EntityUtils

	EntityController용 유틸 팩토리 모음. (Shared)

	─── Move ─────────────────────────────────────────────────────────────────
	Linear(config)         → 직선 등속
	Arc(config)            → 포물선
	Sweep(config)          → 호 스윕

	─── Detect ───────────────────────────────────────────────────────────────
	Box(config)            → 직육면체 판정
	Sphere(config)         → 구형 판정

	─── Hit 전용 ──────────────────────────────────────────────────────────────
	Penetrate(config)      → N회 통과
	TriggerMiss()          → onHit 내에서 onMiss 강제

	─── 공용 콜백 ──────────────────────────────────────────────────────────────
	Despawn(config?)       → delay 포함 즉시 소멸
	Sequence(callbacks)    → 순서 실행
	StopMove()             → 이동 중단
	SpawnEntity(...)       → 그 자리에서 새 엔티티 생성
	FireEntity(...)        → 새 방향으로 엔티티 발사

	─── Transform ────────────────────────────────────────────────────────────
	RotateTo(config)       → 방향 기준 회전 (도/초)
	RandomRotateTo(config) → 랜덤 회전
	ScaleTo(config)        → 크기 변화
	FadeTo(config)         → 투명도 변화
	MoveTo(config)         → 위치 오프셋 이동
	RandomOffsetTo(config) → 랜덤 위치 편차
	Stop()                 → transform 정지 (TransformSequence 내에서 사용)
	Resume()               → 정지 후 재개
	TransformSequence(cbs) → 여러 onMove 합치기

	모든 유틸에 delay?: number 옵션 포함.
]=]

local RunService = game:GetService("RunService")

local EntityUtils = {}

-- ─── 내부 유틸 ───────────────────────────────────────────────────────────────

local function lerpNumber(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function getAllBaseParts(model: any): { BasePart }
	local parts: { BasePart } = {}
	if typeof(model) ~= "Instance" then return parts end
	for _, d in (model :: Instance):GetDescendants() do
		if d:IsA("BasePart") then table.insert(parts, d :: BasePart) end
	end
	return parts
end

local function setTransparency(model: any, t: number)
	for _, part in getAllBaseParts(model) do
		part.Transparency = t
	end
end

local function setSize(model: any, scale: Vector3)
	if typeof(model) ~= "Instance" then return end
	local m = model :: any
	local primary = m.PrimaryPart
	if not primary then return end
	local baseSize: Vector3 = m._baseSize or primary.Size
	m._baseSize = baseSize
	primary.Size = Vector3.new(baseSize.X * scale.X, baseSize.Y * scale.Y, baseSize.Z * scale.Z)
end

-- ─── Move ────────────────────────────────────────────────────────────────────

export type LinearConfig = {
	speed       : number,
	maxRange    : number,
	randomAngle : number?,
	delay       : number?,
}

function EntityUtils.Linear(config: LinearConfig)
	return function(dt: number, handle: any, _params: { [string]: any }?): boolean
		local h       = handle :: any
		local elapsed = h._moveElapsed or 0
		local delay   = config.delay or 0
		if elapsed < delay then return true end

		if not h._moveDir then
			local cf      = h.part and h.part:GetPivot() or CFrame.identity
			local baseDir = cf.LookVector
			if config.randomAngle and config.randomAngle > 0 then
				local angle = math.rad(math.random() * config.randomAngle)
				local phi   = math.random() * math.pi * 2
				local perp  = baseDir:Cross(Vector3.new(0, 1, 0))
				if perp.Magnitude < 0.001 then perp = baseDir:Cross(Vector3.new(1, 0, 0)) end
				perp = perp.Unit
				local rotated = baseDir * math.cos(angle)
					+ perp * math.sin(angle) * math.cos(phi)
					+ baseDir:Cross(perp) * math.sin(angle) * math.sin(phi)
				baseDir = rotated.Magnitude > 0.001 and rotated.Unit or cf.LookVector
			end
			h._moveDir = baseDir
		end
		if not h._moveOrigin then
			h._moveOrigin = h.part and h.part:GetPivot().Position or Vector3.zero
		end

		local activeElapsed = elapsed - delay
		local dist          = config.speed * activeElapsed
		if dist >= config.maxRange then return false end

		local dir: Vector3    = h._moveDir
		local origin: Vector3 = h._moveOrigin
		local currentPos      = origin + dir * dist
		h.part:PivotTo(CFrame.new(currentPos, currentPos + dir))
		return true
	end
end

export type ArcConfig = {
	distance : number,
	height   : number,
	speed    : number,
	delay    : number?,
}

function EntityUtils.Arc(config: ArcConfig)
	return function(dt: number, handle: any, _params: { [string]: any }?): boolean
		local h       = handle :: any
		local elapsed = h._moveElapsed or 0
		local delay   = config.delay or 0
		if elapsed < delay then return true end

		if not h._moveDir or not h._moveOrigin then
			local cf   = h.part and h.part:GetPivot() or CFrame.identity
			h._moveDir    = cf.LookVector
			h._moveOrigin = cf.Position
		end

		local activeElapsed = elapsed - delay
		local totalTime     = config.distance / config.speed
		local t             = math.clamp(activeElapsed / totalTime, 0, 1)

		local origin: Vector3 = h._moveOrigin
		local dir: Vector3    = h._moveDir
		local horizontal      = origin + dir * (config.distance * t)
		local verticalY       = 4 * config.height * t * (1 - t)
		local newPos          = Vector3.new(horizontal.X, origin.Y + verticalY, horizontal.Z)

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

		return t < 1
	end
end

export type SweepConfig = {
	range       : number,
	angleMin    : number,
	angleMax    : number,
	duration    : number,
	randomAngle : number?,
	delay       : number?,
}

function EntityUtils.Sweep(config: SweepConfig)
	return function(dt: number, handle: any, _params: { [string]: any }?): boolean
		local h       = handle :: any
		local elapsed = h._moveElapsed or 0
		local delay   = config.delay or 0
		if elapsed < delay then return true end

		if not h._sweepBase then
			local cf      = h.part and h.part:GetPivot() or CFrame.identity
			h._moveOrigin = cf.Position
			h._sweepBase  = cf
		end

		local activeElapsed = elapsed - delay
		local t             = math.clamp(activeElapsed / config.duration, 0, 1)
		local angle         = math.rad(lerpNumber(config.angleMin, config.angleMax, t))

		local baseCF: CFrame = h._sweepBase
		local swept = baseCF * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -config.range)
		h.part:PivotTo(CFrame.new(swept.Position, swept.Position + swept.LookVector))
		return t < 1
	end
end

-- ─── Detect ──────────────────────────────────────────────────────────────────

export type GrowConfig = {
	from     : Vector3,
	to       : Vector3,
	duration : number,
	mode     : ("linear" | "spring")?,
	speed    : number,
	damper   : number?,
}

export type BoxConfig = {
	size         : Vector3,
	offset       : CFrame?,
	activateAt   : number?,
	deactivateAt : number?,
	sizeGrow     : GrowConfig?,
	relations    : { string }?,
}

export type SphereConfig = {
	radius       : number,
	offset       : CFrame?,
	activateAt   : number?,
	deactivateAt : number?,
	relations    : { string }?,
}

function EntityUtils.Box(config: BoxConfig): BoxConfig
	return config
end

function EntityUtils.Sphere(config: SphereConfig): SphereConfig
	return config
end

-- ─── Hit 전용 콜백 ───────────────────────────────────────────────────────────

function EntityUtils.Penetrate(config: { maxCount: number, onMaxHit: any? })
	return function(handle: any, hitInfo: any)
		local count: number = (handle._penetrateCount or 0) + 1
		handle._penetrateCount = count
		if count >= config.maxCount then
			local cb = config.onMaxHit or EntityUtils.Despawn()
			cb(handle, hitInfo)
		end
	end
end

function EntityUtils.TriggerMiss()
	return function(handle: any, _hitInfo: any)
		if handle and handle.Miss then
			handle:Miss()
		end
	end
end

-- ─── 공용 콜백 ───────────────────────────────────────────────────────────────

function EntityUtils.Despawn(config: { delay: number? }?)
	local delay = config and config.delay or 0
	return function(handle: any, _hitInfo: any?)
		if not handle or not handle.IsAlive or not handle:IsAlive() then return end
		if delay and delay > 0 then
			local elapsed = 0
			local conn: RBXScriptConnection
			conn = RunService.Heartbeat:Connect(function(dt)
				elapsed += dt
				if elapsed >= delay then
					conn:Disconnect()
					if handle:IsAlive() then handle:_destroyNoMiss() end
				end
			end)
			handle._maid:GiveTask(conn)
		else
			handle:_destroyNoMiss()
		end
	end
end

function EntityUtils.Sequence(callbacks: { any })
	return function(handle: any, hitInfo: any?)
		for _, cb in callbacks do
			cb(handle, hitInfo)
		end
	end
end

function EntityUtils.StopMove()
	return function(handle: any, _hitInfo: any?)
		if handle then handle._moveStopped = true end
	end
end

function EntityUtils.SpawnEntity(defModule: string, defName: string, options: { [string]: any }?)
	return function(handle: any, _hitInfo: any?)
		local ok, EntityPlayer = pcall(require, "EntityPlayer")
		if not ok then
			warn("[EntityUtils.SpawnEntity] EntityPlayer 로드 실패:", EntityPlayer)
			return
		end
		local spawnCF  = handle.part and handle.part:GetPivot() or CFrame.identity
		local opts: { [string]: any } = options and table.clone(options) or {}
		opts.origin  = opts.origin  or spawnCF
		opts.ownerId = handle.ownerId
		;(EntityPlayer :: any).Play(defModule, defName, opts)
	end
end

function EntityUtils.FireEntity(defModule: string, defName: string, options: { [string]: any }?)
	return function(handle: any, _hitInfo: any?)
		local ok, EntityPlayer = pcall(require, "EntityPlayer")
		if not ok then
			warn("[EntityUtils.FireEntity] EntityPlayer 로드 실패:", EntityPlayer)
			return
		end
		local spawnCF  = handle.part and handle.part:GetPivot() or CFrame.identity
		local opts: { [string]: any } = options and table.clone(options) or {}
		opts.origin  = opts.origin  or spawnCF
		opts.ownerId = handle.ownerId
		;(EntityPlayer :: any).Play(defModule, defName, opts)
	end
end

-- ─── Transform ───────────────────────────────────────────────────────────────

export type RotateToConfig = {
	axis  : Vector3,
	speed : number,
	delay : number?,
}

function EntityUtils.RotateTo(config: RotateToConfig)
	return function(model: any, dt: number, _params: { [string]: any }?)
		if typeof(model) ~= "Instance" then return end
		local m = model :: any
		local delta = math.rad(config.speed * dt)
		m:PivotTo(m:GetPivot() * CFrame.fromAxisAngle(config.axis.Unit, delta))
	end
end

export type RandomRotateToConfig = {
	maxAngle : number,
	duration : number?,
	delay    : number?,
}

function EntityUtils.RandomRotateTo(config: RandomRotateToConfig)
	local initialized = false
	local targetAngle = 0
	local rotElapsed  = 0
	local totalElapsed = 0
	return function(model: any, dt: number, _params: { [string]: any }?)
		if typeof(model) ~= "Instance" then return end
		totalElapsed += dt
		local delay = config.delay or 0
		if totalElapsed < delay then return end
		if not initialized then
			initialized = true
			targetAngle = (math.random() * 2 - 1) * config.maxAngle
		end
		rotElapsed += dt
		local t = config.duration and math.clamp(rotElapsed / config.duration, 0, 1) or 1
		local m = model :: any
		m:PivotTo(m:GetPivot() * CFrame.Angles(0, math.rad(targetAngle * t), 0))
	end
end

export type ScaleToConfig = {
	from     : Vector3?,
	target   : Vector3,
	duration : number?,
	mode     : ("linear" | "spring")?,
	speed    : number,
	damper   : number?,
	delay    : number?,
}

function EntityUtils.ScaleTo(config: ScaleToConfig)
	local initialized  = false
	local currentScale = config.from or Vector3.new(1, 1, 1)
	local velX, velY, velZ = 0, 0, 0
	local rotElapsed   = 0
	local totalElapsed = 0
	return function(model: any, dt: number, _params: { [string]: any }?)
		totalElapsed += dt
		local delay = config.delay or 0
		if totalElapsed < delay then return end
		if not initialized then
			initialized = true
			currentScale = config.from or Vector3.new(1, 1, 1)
		end
		rotElapsed += dt
		if config.mode == "spring" then
			local damper = config.damper or 1
			local s      = config.speed
			local function step(cur: number, vel: number, tgt: number): (number, number)
				local acc = -s * s * (cur - tgt) - 2 * damper * s * vel
				return cur + (vel + acc * dt) * dt, vel + acc * dt
			end
			local nx, vx = step(currentScale.X, velX, config.target.X)
			local ny, vy = step(currentScale.Y, velY, config.target.Y)
			local nz, vz = step(currentScale.Z, velZ, config.target.Z)
			currentScale = Vector3.new(nx, ny, nz)
			velX, velY, velZ = vx, vy, vz
		else
			local t    = config.duration and math.clamp(rotElapsed / config.duration, 0, 1) or 1
			local from = config.from or Vector3.new(1, 1, 1)
			currentScale = from:Lerp(config.target, t)
		end
		setSize(model, currentScale)
	end
end

export type FadeToConfig = {
	from     : number,
	to       : number,
	duration : number?,
	mode     : ("linear" | "spring")?,
	speed    : number,
	damper   : number?,
	delay    : number?,
}

function EntityUtils.FadeTo(config: FadeToConfig)
	local current      = config.from
	local velocity     = 0
	local rotElapsed   = 0
	local totalElapsed = 0
	return function(model: any, dt: number, _params: { [string]: any }?)
		totalElapsed += dt
		local delay = config.delay or 0
		if totalElapsed < delay then return end
		rotElapsed += dt
		if config.mode == "spring" then
			local damper = config.damper or 1
			local acc    = -config.speed * config.speed * (current - config.to)
				- 2 * damper * config.speed * velocity
			velocity += acc * dt
			current  += velocity * dt
		else
			local t = config.duration
				and math.clamp(rotElapsed / config.duration, 0, 1)
				or 1
			current = lerpNumber(config.from, config.to, t)
		end
		current = math.clamp(
			current,
			math.min(config.from, config.to),
			math.max(config.from, config.to)
		)
		setTransparency(model, current)
	end
end

export type MoveToConfig = {
	offset   : Vector3,
	duration : number?,
	mode     : ("linear" | "spring")?,
	speed    : number,
	damper   : number?,
	delay    : number?,
}

function EntityUtils.MoveTo(config: MoveToConfig)
	local initialized   = false
	local origin: CFrame = CFrame.identity
	local velX, velY, velZ = 0, 0, 0
	local currentOffset = Vector3.zero
	local rotElapsed    = 0
	local totalElapsed  = 0
	return function(model: any, dt: number, _params: { [string]: any }?)
		if typeof(model) ~= "Instance" then return end
		totalElapsed += dt
		local delay = config.delay or 0
		if totalElapsed < delay then return end
		if not initialized then
			initialized = true
			origin = (model :: any):GetPivot()
		end
		rotElapsed += dt
		if config.mode == "spring" then
			local damper = config.damper or 1
			local s      = config.speed
			local function step(cur: number, vel: number, tgt: number): (number, number)
				local acc = -s * s * (cur - tgt) - 2 * damper * s * vel
				return cur + (vel + acc * dt) * dt, vel + acc * dt
			end
			local nx, vx = step(currentOffset.X, velX, config.offset.X)
			local ny, vy = step(currentOffset.Y, velY, config.offset.Y)
			local nz, vz = step(currentOffset.Z, velZ, config.offset.Z)
			currentOffset = Vector3.new(nx, ny, nz)
			velX, velY, velZ = vx, vy, vz
		else
			local t = config.duration
				and math.clamp(rotElapsed / config.duration, 0, 1)
				or 1
			currentOffset = Vector3.zero:Lerp(config.offset, t)
		end
		;(model :: any):PivotTo(origin * CFrame.new(currentOffset))
	end
end

export type RandomOffsetToConfig = {
	range    : Vector3,
	duration : number?,
	delay    : number?,
}

function EntityUtils.RandomOffsetTo(config: RandomOffsetToConfig)
	local initialized   = false
	local targetOffset  = Vector3.zero
	local origin: CFrame = CFrame.identity
	local rotElapsed    = 0
	local totalElapsed  = 0
	return function(model: any, dt: number, _params: { [string]: any }?)
		if typeof(model) ~= "Instance" then return end
		totalElapsed += dt
		local delay = config.delay or 0
		if totalElapsed < delay then return end
		if not initialized then
			initialized = true
			origin = (model :: any):GetPivot()
			targetOffset = Vector3.new(
				(math.random() * 2 - 1) * config.range.X,
				(math.random() * 2 - 1) * config.range.Y,
				(math.random() * 2 - 1) * config.range.Z
			)
		end
		rotElapsed += dt
		local t = config.duration
			and math.clamp(rotElapsed / config.duration, 0, 1)
			or 1
		local currentOffset = Vector3.zero:Lerp(targetOffset, t)
		;(model :: any):PivotTo(origin * CFrame.new(currentOffset))
	end
end

local _stopped: { [any]: boolean } = {}

function EntityUtils.Stop()
	return function(model: any, _dt: number, _params: { [string]: any }?)
		_stopped[model] = true
	end
end

function EntityUtils.Resume()
	return function(model: any, _dt: number, _params: { [string]: any }?)
		_stopped[model] = nil
	end
end

function EntityUtils.TransformSequence(callbacks: { (any, number, { [string]: any }?) -> () })
	return function(model: any, dt: number, params: { [string]: any }?)
		if _stopped[model] then return end
		for _, cb in callbacks do
			cb(model, dt, params)
		end
	end
end

return EntityUtils
