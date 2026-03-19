--!strict
--[=[
	@class AbilityEffectTransformUtil

	파트 변환(크기/회전/투명도/흔들기) 유틸. (Shared)

	두 가지 사용 방법:
	  1. 팩토리 방식 (DefModule onMove 필드에 사용)
	     AbilityEffectTransformUtil.Rotate({ axis=Vector3.new(1,0,0), speed=360 })
	     → (model, dt) -> () 반환, Heartbeat 루프에서 호출됨

	  2. Apply 방식 (커스텀 onHit/onMiss 내에서 직접 호출)
	     AbilityEffectTransformUtil.ApplyFade(model, { to=0, duration=0.5, mode="linear", speed=1 }, maid)
	     → 즉시 시작, duration 후 자동 정리

	Sequence:
	  여러 onMove 콜백을 합칩니다.
	  AbilityEffectTransformUtil.Sequence({ Rotate(...), Fade(...) })
]=]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AbilityEffectTransformUtil = {}

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type OnMoveCallback = (model: Model, dt: number) -> ()

export type ModeConfig = {
	mode   : ("linear" | "spring")?,
	speed  : number,
	damper : number?,
}

-- ─── 내부 유틸 ───────────────────────────────────────────────────────────────

local function getAllBaseParts(model: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d :: BasePart)
		end
	end
	return parts
end

local function setTransparency(model: Model, t: number)
	for _, part in getAllBaseParts(model) do
		part.Transparency = t
	end
end

local function setSize(model: Model, scale: Vector3)
	local primary = model.PrimaryPart
	if not primary then return end
	local baseSize: Vector3 = (model :: any)._baseSize or primary.Size
	;(model :: any)._baseSize = baseSize
	primary.Size = Vector3.new(baseSize.X * scale.X, baseSize.Y * scale.Y, baseSize.Z * scale.Z)
end

local function lerpNumber(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- ─── 팩토리: Sequence ────────────────────────────────────────────────────────

function AbilityEffectTransformUtil.Sequence(callbacks: { OnMoveCallback }): OnMoveCallback
	return function(model: Model, dt: number)
		for _, cb in callbacks do
			cb(model, dt)
		end
	end
end

-- ─── 팩토리: Rotate ──────────────────────────────────────────────────────────

export type RotateConfig = {
	axis        : Vector3,
	speed       : number,         -- 도/초
	randomAngle : number?,        -- 초기 랜덤 오프셋 (도)
}

function AbilityEffectTransformUtil.Rotate(config: RotateConfig): OnMoveCallback
	local totalAngle = 0
	local initialized = false
	return function(model: Model, dt: number)
		if not initialized then
			initialized = true
			if config.randomAngle and config.randomAngle > 0 then
				totalAngle = math.random() * config.randomAngle
			end
		end
		totalAngle += config.speed * dt
		local primary = model.PrimaryPart
		if not primary then return end
		local rad = math.rad(totalAngle)
		local axis = config.axis.Unit
		model:PivotTo(model:GetPivot() * CFrame.fromAxisAngle(axis, rad - math.rad(totalAngle - config.speed * dt)))
	end
end

-- ─── 팩토리: Fade ────────────────────────────────────────────────────────────

export type FadeConfig = {
	from     : number,
	to       : number,
	duration : number?,
	mode     : ("linear" | "spring")?,
	speed    : number,
	damper   : number?,
}

function AbilityEffectTransformUtil.Fade(config: FadeConfig): OnMoveCallback
	local elapsed = 0
	local current = config.from
	local velocity = 0
	return function(model: Model, dt: number)
		elapsed += dt
		local target = config.to
		if config.duration then
			local t = math.clamp(elapsed / config.duration, 0, 1)
			target = lerpNumber(config.from, config.to, t)
		end
		if config.mode == "spring" then
			local damper = config.damper or 1
			local acc = -config.speed * config.speed * (current - target) - 2 * damper * config.speed * velocity
			velocity += acc * dt
			current += velocity * dt
		else
			local t = math.clamp(elapsed / math.max(config.duration or 1, 0.001), 0, 1)
			current = lerpNumber(config.from, config.to, t)
		end
		current = math.clamp(current, math.min(config.from, config.to), math.max(config.from, config.to))
		setTransparency(model, current)
	end
end

-- ─── 팩토리: ScaleTo ─────────────────────────────────────────────────────────

export type ScaleToConfig = {
	from     : Vector3?,
	target   : Vector3,
	duration : number?,
	mode     : ("linear" | "spring")?,
	speed    : number,
	damper   : number?,
}

function AbilityEffectTransformUtil.ScaleTo(config: ScaleToConfig): OnMoveCallback
	local elapsed = 0
	local initialized = false
	local currentScale = config.from or Vector3.one
	local velX, velY, velZ = 0, 0, 0
	return function(model: Model, dt: number)
		if not initialized then
			initialized = true
			currentScale = config.from or Vector3.one
		end
		elapsed += dt
		local t = config.duration and math.clamp(elapsed / config.duration, 0, 1) or 1
		if config.mode == "spring" then
			local damper = config.damper or 1
			local s = config.speed
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
			local from = config.from or Vector3.one
			currentScale = from:Lerp(config.target, t)
		end
		setSize(model, currentScale)
	end
end

-- ─── 팩토리: ScalePulse ──────────────────────────────────────────────────────

export type ScalePulseConfig = {
	peak     : Vector3,
	duration : number,
	mode     : ("linear" | "spring")?,
	speed    : number,
	damper   : number?,
}

function AbilityEffectTransformUtil.ScalePulse(config: ScalePulseConfig): OnMoveCallback
	-- 0 → peak (반절) → Vector3.one (나머지 반절)
	local elapsed = 0
	return function(model: Model, dt: number)
		elapsed += dt
		local t = math.clamp(elapsed / config.duration, 0, 1)
		local scale: Vector3
		if t < 0.5 then
			scale = Vector3.one:Lerp(config.peak, t * 2)
		else
			scale = config.peak:Lerp(Vector3.one, (t - 0.5) * 2)
		end
		setSize(model, scale)
	end
end

-- ─── Apply: ApplyFade ────────────────────────────────────────────────────────

function AbilityEffectTransformUtil.ApplyFade(
	model    : Model,
	config   : FadeConfig,
	maid     : any?
)
	local elapsed = 0
	local current = config.from
	local velocity = 0
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if config.mode == "spring" then
			local damper = config.damper or 1
			local acc = -config.speed * config.speed * (current - config.to)
				- 2 * damper * config.speed * velocity
			velocity += acc * dt
			current += velocity * dt
		else
			local t = config.duration and math.clamp(elapsed / config.duration, 0, 1) or 1
			current = lerpNumber(config.from, config.to, t)
		end
		current = math.clamp(current, math.min(config.from, config.to), math.max(config.from, config.to))
		if not model.Parent then conn:Disconnect() return end
		setTransparency(model, current)
		local done = config.duration and elapsed >= config.duration
		if done then conn:Disconnect() end
	end)
	if maid then maid:GiveTask(conn) end
end

-- ─── Apply: ApplyScaleTo ─────────────────────────────────────────────────────

function AbilityEffectTransformUtil.ApplyScaleTo(
	model  : Model,
	config : ScaleToConfig,
	maid   : any?
)
	local cb = AbilityEffectTransformUtil.ScaleTo(config)
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt)
		if not model.Parent then conn:Disconnect() return end
		cb(model, dt)
	end)
	if maid then maid:GiveTask(conn) end
end

-- ─── Apply: ApplyShake ───────────────────────────────────────────────────────

export type ShakeConfig = {
	intensity : number,
	duration  : number,
	frequency : number?,
}

function AbilityEffectTransformUtil.ApplyShake(
	model  : Model,
	config : ShakeConfig,
	maid   : any?
)
	local elapsed = 0
	local freq = config.frequency or 20
	local originalCF = model:GetPivot()
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if not model.Parent or elapsed >= config.duration then
			model:PivotTo(originalCF)
			conn:Disconnect()
			return
		end
		local decay = 1 - elapsed / config.duration
		local offset = Vector3.new(
			math.sin(elapsed * freq * 1.1) * config.intensity * decay,
			math.sin(elapsed * freq * 0.9) * config.intensity * decay * 0.5,
			math.sin(elapsed * freq * 1.3) * config.intensity * decay
		)
		model:PivotTo(originalCF * CFrame.new(offset))
	end)
	if maid then maid:GiveTask(conn) end
end

return AbilityEffectTransformUtil
