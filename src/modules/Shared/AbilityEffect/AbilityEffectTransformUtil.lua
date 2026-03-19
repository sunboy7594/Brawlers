--!strict
--[=[
	@class AbilityEffectTransformUtil

	모델 변환(스케일/회전/투명도) 유틸. Shared.

	팩토리 방식 (DefModule onMove 필드용):
	  OnMoveFactory = (handle) -> (model: Model, dt: number) -> ()
	  Rotate, ScaleTo, Fade, Sequence

	단발 콜백 방식 (DefModule onHit/onMiss 필드용):
	  ScalePulse, Shake
	  (handle, hitInfo?) -> () 형태, handle._maid에 연결

	직접 사용 (커스텀 콜백 내에서):
	  Apply~ 계열: 즉시 시작, maid에 연결 가능, 선형/스프링 모두 지원
]=]

local require = require(script.Parent.loader).load(script)

local RunService = game:GetService("RunService")

local Spring = require("Spring")

local AbilityEffectTransformUtil = {}

export type OnMoveFactory = (handle: any) -> (model: Model, dt: number) -> ()

-- ─── 내부 유틸 ────────────────────────────────────────────────────────────────

local function getOriginalSizes(model: Model): { [BasePart]: Vector3 }
	local t: { [BasePart]: Vector3 } = {}
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			t[desc :: BasePart] = (desc :: BasePart).Size
		end
	end
	if model:IsA("BasePart") then
		t[model :: any] = (model :: any).Size
	end
	return t
end

local function applyScale(model: Model, origSizes: { [BasePart]: Vector3 }, scale: Vector3)
	for part, origSize in origSizes do
		if part.Parent then
			part.Size = Vector3.new(
				origSize.X * scale.X,
				origSize.Y * scale.Y,
				origSize.Z * scale.Z
			)
		end
	end
end

local function applyTransparency(model: Model, alpha: number)
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			(desc :: BasePart).Transparency = alpha
		end
	end
	if model:IsA("BasePart") then
		(model :: any).Transparency = alpha
	end
end

local function readTransparency(model: Model): number
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			return (desc :: BasePart).Transparency
		end
	end
	if model:IsA("BasePart") then
		return (model :: any).Transparency
	end
	return 0
end

-- ─── 팩토리: Rotate (연속 회전, onMove용) ────────────────────────────────────

function AbilityEffectTransformUtil.Rotate(config: {
	axis: Vector3?,
	speed: number, -- 도/초
}): OnMoveFactory
	return function(_handle)
		local axis = config.axis or Vector3.new(0, 1, 0)
		return function(model: Model, dt: number)
			local deltaAngle = math.rad(config.speed * dt)
			model:PivotTo(model:GetPivot() * CFrame.fromAxisAngle(axis, deltaAngle))
		end
	end
end

-- ─── 팩토리: ScaleTo (크기 변화, onMove용) ────────────────────────────────────

function AbilityEffectTransformUtil.ScaleTo(config: {
	target: Vector3,
	duration: number?,
	mode: ("linear" | "spring")?,
	speed: number,
	damper: number?,
}): OnMoveFactory
	return function(_handle)
		local elapsed    = 0
		local origSizes: { [BasePart]: Vector3 }? = nil
		local spring: any? = nil
		local startScale = Vector3.new(1, 1, 1)

		return function(model: Model, dt: number)
			if not origSizes then
				origSizes = getOriginalSizes(model)
			end

			local scale: Vector3
			if config.mode == "spring" then
				if not spring then
					spring = Spring.new(startScale)
					spring.Speed  = config.speed
					spring.Damper = config.damper or 1.0
					spring.Target = config.target
				end
				scale = spring.Position
			else
				elapsed += dt
				local dur = config.duration or 0.001
				scale = startScale:Lerp(config.target, math.clamp(elapsed / dur, 0, 1))
			end
			applyScale(model, origSizes :: { [BasePart]: Vector3 }, scale)
		end
	end
end

-- ─── 팩토리: Fade (투명도 변화, onMove용) ─────────────────────────────────────

function AbilityEffectTransformUtil.Fade(config: {
	from: number,
	to: number,
	duration: number,
	mode: ("linear" | "spring")?,
	speed: number,
	damper: number?,
}): OnMoveFactory
	return function(_handle)
		local elapsed  = 0
		local spring: any? = nil

		return function(model: Model, dt: number)
			local alpha: number
			if config.mode == "spring" then
				if not spring then
					spring = Spring.new(config.from)
					spring.Speed  = config.speed
					spring.Damper = config.damper or 1.0
					spring.Target = config.to
				end
				alpha = spring.Position
			else
				elapsed += dt
				local t = math.clamp(elapsed / config.duration, 0, 1)
				alpha = config.from + (config.to - config.from) * t
			end
			applyTransparency(model, alpha)
		end
	end
end

-- ─── 팩토리: ScalePulse (onHit/onMiss용 시간기반) ────────────────────────────
-- handle._maid에 Heartbeat 등록. duration 동안 peak까지 커졌다가 복귀.

function AbilityEffectTransformUtil.ScalePulse(config: {
	peak: Vector3,
	duration: number,
	mode: ("linear" | "spring")?,
	speed: number,
	damper: number?,
}): (handle: any, hitInfo: any?) -> ()
	return function(handle: any, _hitInfo: any?)
		if not handle.part then return end
		local model    = handle.part
		local origSizes = getOriginalSizes(model)
		local elapsed  = 0
		local halfDur  = config.duration / 2

		local conn: RBXScriptConnection
		conn = RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if not model.Parent or elapsed >= config.duration then
				applyScale(model, origSizes, Vector3.new(1, 1, 1))
				conn:Disconnect()
				return
			end
			local scale: Vector3
			if elapsed < halfDur then
				scale = Vector3.new(1, 1, 1):Lerp(config.peak, elapsed / halfDur)
			else
				scale = config.peak:Lerp(Vector3.new(1, 1, 1), (elapsed - halfDur) / halfDur)
			end
			applyScale(model, origSizes, scale)
		end)
		handle._maid:GiveTask(conn)
	end
end

-- ─── 팩토리: Shake (onHit/onMiss용 진동) ─────────────────────────────────────

function AbilityEffectTransformUtil.Shake(config: {
	intensity: number,
	duration: number,
	frequency: number?,
}): (handle: any, hitInfo: any?) -> ()
	return function(handle: any, _hitInfo: any?)
		if not handle.part then return end
		local model       = handle.part
		local origPivot   = model:GetPivot()
		local elapsed     = 0
		local freq        = config.frequency or 30

		local conn: RBXScriptConnection
		conn = RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if not model.Parent or elapsed >= config.duration then
				if model.Parent then model:PivotTo(origPivot) end
				conn:Disconnect()
				return
			end
			local decay  = 1 - elapsed / config.duration
			local ox = math.sin(elapsed * freq * 2.3) * config.intensity * decay
			local oy = math.sin(elapsed * freq * 1.7) * config.intensity * decay * 0.5
			model:PivotTo(origPivot * CFrame.new(ox, oy, 0))
		end)
		handle._maid:GiveTask(conn)
	end
end

-- ─── 팩토리: Sequence (onMove용 복수 합성) ────────────────────────────────────

function AbilityEffectTransformUtil.Sequence(factories: { OnMoveFactory }): OnMoveFactory
	return function(handle: any)
		local fns: { (model: Model, dt: number) -> () } = {}
		for _, factory in factories do
			table.insert(fns, factory(handle))
		end
		return function(model: Model, dt: number)
			for _, fn in fns do
				fn(model, dt)
			end
		end
	end
end

-- ─── 직접 사용: ApplyFade ─────────────────────────────────────────────────────

function AbilityEffectTransformUtil.ApplyFade(
	model: Model,
	config: {
		to: number,
		duration: number?,
		mode: ("linear" | "spring")?,
		speed: number,
		damper: number?,
	},
	maid: any?
): RBXScriptConnection
	local startAlpha = readTransparency(model)
	local elapsed  = 0
	local spring: any? = nil

	if config.mode == "spring" then
		spring = Spring.new(startAlpha)
		spring.Speed  = config.speed
		spring.Damper = config.damper or 1.0
		spring.Target = config.to
	end

	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt)
		if not model.Parent then conn:Disconnect() return end
		local alpha: number
		if spring then
			alpha = spring.Position
			if math.abs(alpha - config.to) < 0.002 then
				applyTransparency(model, config.to)
				conn:Disconnect() return
			end
		else
			elapsed += dt
			local dur = config.duration or 0.001
			local t   = math.clamp(elapsed / dur, 0, 1)
			alpha = startAlpha + (config.to - startAlpha) * t
			if t >= 1 then conn:Disconnect() end
		end
		applyTransparency(model, alpha)
	end)

	if maid then maid:GiveTask(conn) end
	return conn
end

-- ─── 직접 사용: ApplyScaleTo ──────────────────────────────────────────────────

function AbilityEffectTransformUtil.ApplyScaleTo(
	model: Model,
	config: {
		target: Vector3,
		duration: number?,
		mode: ("linear" | "spring")?,
		speed: number,
		damper: number?,
	},
	maid: any?
): RBXScriptConnection
	local origSizes  = getOriginalSizes(model)
	local startScale = Vector3.new(1, 1, 1)
	local elapsed    = 0
	local spring: any? = nil

	if config.mode == "spring" then
		spring = Spring.new(startScale)
		spring.Speed  = config.speed
		spring.Damper = config.damper or 1.0
		spring.Target = config.target
	end

	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt)
		if not model.Parent then conn:Disconnect() return end
		local scale: Vector3
		if spring then
			scale = spring.Position
			if (scale - config.target).Magnitude < 0.01 then
				applyScale(model, origSizes, config.target)
				conn:Disconnect() return
			end
		else
			elapsed += dt
			local dur = config.duration or 0.001
			local t   = math.clamp(elapsed / dur, 0, 1)
			scale = startScale:Lerp(config.target, t)
			if t >= 1 then conn:Disconnect() end
		end
		applyScale(model, origSizes, scale)
	end)

	if maid then maid:GiveTask(conn) end
	return conn
end

-- ─── 직접 사용: ApplyRotate ───────────────────────────────────────────────────

function AbilityEffectTransformUtil.ApplyRotate(
	model: Model,
	config: {
		axis: Vector3?,
		speed: number,  -- 도/초
		duration: number?,
	},
	maid: any?
): RBXScriptConnection
	local axis    = config.axis or Vector3.new(0, 1, 0)
	local elapsed = 0

	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt)
		if not model.Parent then conn:Disconnect() return end
		elapsed += dt
		if config.duration and elapsed >= config.duration then
			conn:Disconnect() return
		end
		model:PivotTo(model:GetPivot() * CFrame.fromAxisAngle(axis, math.rad(config.speed * dt)))
	end)

	if maid then maid:GiveTask(conn) end
	return conn
end

-- ─── 직접 사용: ApplyShake ────────────────────────────────────────────────────

function AbilityEffectTransformUtil.ApplyShake(
	model: Model,
	config: {
		intensity: number,
		duration: number,
		frequency: number?,
	},
	maid: any?
): RBXScriptConnection
	local origPivot = model:GetPivot()
	local elapsed   = 0
	local freq      = config.frequency or 30

	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt)
		if not model.Parent then conn:Disconnect() return end
		elapsed += dt
		if elapsed >= config.duration then
			model:PivotTo(origPivot)
			conn:Disconnect() return
		end
		local decay = 1 - elapsed / config.duration
		local ox = math.sin(elapsed * freq * 2.3) * config.intensity * decay
		local oy = math.sin(elapsed * freq * 1.7) * config.intensity * decay * 0.5
		model:PivotTo(origPivot * CFrame.new(ox, oy, 0))
	end)

	if maid then maid:GiveTask(conn) end
	return conn
end

return AbilityEffectTransformUtil
