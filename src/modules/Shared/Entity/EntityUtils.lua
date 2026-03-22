--!strict
--[=[
	@class EntityUtils

	EntityController용 유틸 팩토리 모음. (Shared)

	─── Move ─────────────────────────────────────────────────────────────────
	Linear(config)         → 직선 등속
	Arc(config)            → 포물선. rotate?: boolean (기본 true)
	Sweep(config)          → 호 스윕

	─── Detect ───────────────────────────────────────────────────────────────
	Box(config)            → 직육면체 판정
	Sphere(config)         → 구형 판정

	─── Hit 전용 ──────────────────────────────────────────────────────────────
	Penetrate(config)      → N회 통과
	TriggerMiss()          → onHit 내에서 onMiss 강제

	─── 공용 콜백 ──────────────────────────────────────────────────────────────
	Despawn(config?)       → delay 포함 즉시 소멸
	AutoDespawn(duration)  → onSpawn에서 사용. duration 후 자동 소멸
	AnchorPart()           → onSpawn에서 사용. PlatformStand 차단. maid 소멸 시 자동 복원.
	Sequence(callbacks)    → 순서 실행
	StopMove()             → 이동 중단
	SpawnEntity(...)       → 그 자리에서 새 엔티티 생성
	FireEntity(...)        → 새 방향으로 엔티티 발사
	Animate(onMoveCb)      → onHit/onMiss/onSpawn에서 dt 기반 Transform 유틸 구동

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

	─── per-instance 상태 관리 ────────────────────────────────────────────────
	ScaleTo/FadeTo/RotateTo/RandomRotateTo/MoveTo/RandomOffsetTo는 클로저 로컬 변수 대신
	handle에 고유 키(_s<N>)로 상태를 저장합니다.
	이로 인해 require 캐싱에 의한 클로저 공유 버그가 해결됩니다.
	(EntityController.tickHandle이 onMove에 handle을 4번째 인자로 전달)
]=]

local require = require(script.Parent.loader).load(script)

local RunService = game:GetService("RunService")

local EntityUtils = {}

-- EntityPlayer lazy 로드 (순환 참조 방지)
local _entityPlayer: any = nil
local function getEntityPlayer(): any
	if not _entityPlayer then
		_entityPlayer = require("EntityPlayer")
	end
	return _entityPlayer
end

-- ─── per-instance 상태 키 생성 ───────────────────────────────────────────────
local _cbCounter = 0
local function newStateKey(): string
	_cbCounter += 1
	return "_s" .. tostring(_cbCounter)
end

-- ─── 내부 유틸 ───────────────────────────────────────────────────────────────

local function lerpNumber(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local _highlightOriginals: { [any]: { fill: number, outline: number } } = {}

local function setTransparency(model: any, t: number)
	if typeof(model) ~= "Instance" then
		return
	end
	local hasHighlight = false
	for _, d in (model :: Instance):GetDescendants() do
		if d.ClassName == "Highlight" then
			hasHighlight = true
			break
		end
	end
	for _, d in (model :: Instance):GetDescendants() do
		if d:IsA("BasePart") then
			local bp = d :: BasePart
			if not _highlightOriginals[bp] then
				_highlightOriginals[bp] = {
					fill = bp.Transparency,
					material = bp.Material,
				}
				if hasHighlight then
					bp.Material = Enum.Material.Glass
				end
				bp.Destroying:Connect(function()
					_highlightOriginals[bp] = nil
				end)
			end
			local orig = _highlightOriginals[bp]
			bp.Transparency = orig.fill + (1 - orig.fill) * t
		elseif d.ClassName == "Highlight" then
			local hl = d :: any
			if not _highlightOriginals[hl] then
				_highlightOriginals[hl] = {
					fill = hl.FillTransparency,
					outline = hl.OutlineTransparency,
				}
				hl.Destroying:Connect(function()
					_highlightOriginals[hl] = nil
				end)
			end
			local orig = _highlightOriginals[hl]
			hl.FillTransparency = orig.fill + (1 - orig.fill) * t
			hl.OutlineTransparency = orig.outline + (1 - orig.outline) * t
		end
	end
end

local _modelScales: { [any]: number } = {}

local function setSize(model: any, scale: Vector3)
	if typeof(model) ~= "Instance" then
		return
	end
	local m = model :: any
	if not m.ScaleTo then
		return
	end

	if not _modelScales[m] then
		_modelScales[m] = 1
		(m :: Instance).Destroying:Connect(function()
			_modelScales[m] = nil
		end)
	end

	local uniformScale = scale.X
	local prev = _modelScales[m]
	local delta = uniformScale / prev
	_modelScales[m] = uniformScale

	m:ScaleTo(m:GetScale() * delta)
end

-- ─── Move ────────────────────────────────────────────────────────────────────

export type LinearConfig = {
	speed: number,
	maxRange: number,
	randomAngle: number?,
	delay: number?,
}

function EntityUtils.Linear(config: LinearConfig)
	return function(dt: number, handle: any, _params: { [string]: any }?): boolean
		local h = handle :: any
		local elapsed = h._moveElapsed or 0
		local delay = config.delay or 0
		if elapsed < delay then
			return true
		end

		if not h._moveDir then
			local cf = h.part and h.part:GetPivot() or CFrame.identity
			local baseDir = cf.LookVector
			if config.randomAngle and config.randomAngle > 0 then
				local angle = math.rad(math.random() * config.randomAngle)
				local phi = math.random() * math.pi * 2
				local perp = baseDir:Cross(Vector3.new(0, 1, 0))
				if perp.Magnitude < 0.001 then
					perp = baseDir:Cross(Vector3.new(1, 0, 0))
				end
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
		local dist = config.speed * activeElapsed
		if dist >= config.maxRange then
			return false
		end

		local dir: Vector3 = h._moveDir
		local origin: Vector3 = h._moveOrigin
		local currentPos = origin + dir * dist
		h.part:PivotTo(CFrame.new(currentPos, currentPos + dir))
		return true
	end
end

export type ArcConfig = {
	distance: number,
	height: number,
	speed: number,
	delay: number?,
	rotate: boolean?,
}

function EntityUtils.Arc(config: ArcConfig)
	local shouldRotate = config.rotate ~= false

	return function(dt: number, handle: any, _params: { [string]: any }?): boolean
		local h = handle :: any
		local elapsed = h._moveElapsed or 0
		local delay = config.delay or 0
		if elapsed < delay then
			return true
		end

		if not h._moveDir or not h._moveOrigin then
			local cf = h.part and h.part:GetPivot() or CFrame.identity
			h._moveDir = cf.LookVector
			h._moveOrigin = cf.Position
		end

		local distance = config.distance
		local height = config.height
		local origin: Vector3 = h._moveOrigin
		local dir: Vector3 = h._moveDir

		local activeElapsed = elapsed - delay
		local totalTime = distance / config.speed
		local t = math.clamp(activeElapsed / math.max(totalTime, 0.001), 0, 1)

		local horizontal = origin + dir * (distance * t)
		local verticalY = 4 * height * t * (1 - t)
		local newPos = Vector3.new(horizontal.X, origin.Y + verticalY, horizontal.Z)

		if shouldRotate then
			local nextT = math.min(t + 0.01, 1)
			local nextH = origin + dir * (distance * nextT)
			local nextVY = 4 * height * nextT * (1 - nextT)
			local nextPos = Vector3.new(nextH.X, origin.Y + nextVY, nextH.Z)
			local lookDir = nextPos - newPos
			if lookDir.Magnitude > 0.001 then
				h.part:PivotTo(CFrame.new(newPos, newPos + lookDir.Unit))
			else
				h.part:PivotTo(CFrame.new(newPos))
			end
		else
			h.part:PivotTo(CFrame.new(newPos, newPos + dir))
		end

		return t < 1
	end
end

export type SweepConfig = {
	range: number,
	angleMin: number,
	angleMax: number,
	duration: number,
	randomAngle: number?,
	delay: number?,
}

function EntityUtils.Sweep(config: SweepConfig)
	return function(dt: number, handle: any, _params: { [string]: any }?): boolean
		local h = handle :: any
		local elapsed = h._moveElapsed or 0
		local delay = config.delay or 0
		if elapsed < delay then
			return true
		end

		if not h._sweepBase then
			local cf = h.part and h.part:GetPivot() or CFrame.identity
			h._moveOrigin = cf.Position
			h._sweepBase = cf
		end

		local activeElapsed = elapsed - delay
		local t = math.clamp(activeElapsed / config.duration, 0, 1)
		local angle = math.rad(lerpNumber(config.angleMin, config.angleMax, t))

		local baseCF: CFrame = h._sweepBase
		local swept = baseCF * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -config.range)
		h.part:PivotTo(CFrame.new(swept.Position, swept.Position + swept.LookVector))
		return t < 1
	end
end

-- ─── Detect ──────────────────────────────────────────────────────────────────

export type GrowConfig = {
	from: Vector3,
	to: Vector3,
	duration: number,
	mode: ("linear" | "spring")?,
	speed: number,
	damper: number?,
}

export type BoxConfig = {
	size: Vector3,
	offset: CFrame?,
	activateAt: number?,
	deactivateAt: number?,
	sizeGrow: GrowConfig?,
	relations: { string }?,
}

export type SphereConfig = {
	radius: number,
	offset: CFrame?,
	activateAt: number?,
	deactivateAt: number?,
	relations: { string }?,
	_isSphere: boolean?,
}

function EntityUtils.Box(config: BoxConfig): BoxConfig
	return config
end

function EntityUtils.Sphere(config: SphereConfig): SphereConfig
	config._isSphere = true
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

function EntityUtils.LockHit()
	return function(handle: any, _hitInfo: any?)
		if handle then
			handle._fadingOut = true
		end
	end
end

function EntityUtils.Despawn(config: { delay: number? }?)
	local delay = config and config.delay or 0
	return function(handle: any, _hitInfo: any?)
		if not handle or not handle.IsAlive or not handle:IsAlive() then
			return
		end
		if delay and delay > 0 then
			handle._deferredDespawn = true
			local elapsed = 0
			local conn: RBXScriptConnection
			conn = RunService.Heartbeat:Connect(function(dt)
				elapsed += dt
				if elapsed >= delay then
					conn:Disconnect()
					if handle:IsAlive() then
						handle:_destroyNoMiss()
					end
				end
			end)
			handle._maid:GiveTask(conn)
		else
			handle:_destroyNoMiss()
		end
	end
end

function EntityUtils.AutoDespawn(duration: number)
	return function(handle: any)
		if not handle or not handle._maid then
			return
		end
		local elapsed = 0
		local conn: RBXScriptConnection
		conn = RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed >= duration then
				conn:Disconnect()
				if handle.IsAlive and handle:IsAlive() then
					handle:_destroyNoMiss()
				end
			end
		end)
		handle._maid:GiveTask(conn)
	end
end

--[=[
	AnchorPart()
	  onSpawn 콜백으로 사용.
	  HRP 이동 중 Humanoid 상태머신(PlatformStand)을 차단합니다.
	  handle._maid 소멸 시 PlatformStand 자동 복원.
]=]
function EntityUtils.AnchorPart()
	return function(handle: any)
		local part = handle.part
		if not part or typeof(part) ~= "Instance" then
			return
		end

		local bp: BasePart?
		if (part :: Instance):IsA("BasePart") then
			bp = part :: BasePart
		else
			bp = (part :: Instance):FindFirstChild("HumanoidRootPart") :: BasePart?
		end
		if not bp then
			return
		end

		local humanoid: Humanoid?
		local model = bp.Parent
		if model and (model :: Instance):IsA("Model") then
			humanoid = (model :: Instance):FindFirstChildOfClass("Humanoid") :: Humanoid?
		end

		local wasPlatformStand = false
		if humanoid then
			wasPlatformStand = humanoid.PlatformStand
			humanoid.PlatformStand = true
		end

		handle._maid:GiveTask(function()
			if humanoid and (humanoid :: Instance).Parent then
				humanoid.PlatformStand = wasPlatformStand
			end
		end)
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
		if handle then
			handle._moveStopped = true
		end
	end
end

function EntityUtils.SpawnEntity(defModule: string, defName: string, options: { [string]: any }?)
	return function(handle: any, _hitInfo: any?)
		local ep = getEntityPlayer()
		local spawnCF = handle.part and handle.part:GetPivot() or CFrame.identity
		local opts: { [string]: any } = options and table.clone(options) or {}
		opts.origin = opts.origin or spawnCF
		opts.attackerPlayerId = opts.attackerPlayerId or handle.ownerId
		opts.color = opts.color or handle._spawnColor
		ep.Play(defModule, defName, opts)
	end
end

function EntityUtils.FireEntity(defModule: string, defName: string, options: { [string]: any }?)
	return function(handle: any, _hitInfo: any?)
		local ep = getEntityPlayer()
		local spawnCF = handle.part and handle.part:GetPivot() or CFrame.identity
		local opts: { [string]: any } = options and table.clone(options) or {}
		opts.origin = opts.origin or spawnCF
		opts.attackerPlayerId = opts.attackerPlayerId or handle.ownerId
		opts.color = opts.color or handle._spawnColor
		ep.Play(defModule, defName, opts)
	end
end

function EntityUtils.Animate(onMoveCb: (model: any, dt: number, params: any?, handle: any?) -> ())
	return function(handle: any, _hitInfo: any?)
		if not handle or not handle._maid then
			return
		end
		local conn: RBXScriptConnection
		conn = RunService.Heartbeat:Connect(function(dt)
			if not handle.IsAlive or not handle:IsAlive() then
				conn:Disconnect()
				return
			end
			onMoveCb(handle.part, dt, handle._params, handle)
		end)
		handle._maid:GiveTask(conn)
	end
end

-- ─── Transform ───────────────────────────────────────────────────────────────

export type RotateToConfig = {
	axis: Vector3,
	speed: number,
	delay: number?,
}

function EntityUtils.RotateTo(config: RotateToConfig)
	local sk = newStateKey()
	return function(model: any, dt: number, _params: { [string]: any }?, handle: any?)
		if typeof(model) ~= "Instance" then
			return
		end
		if handle then
			local s: any = handle[sk]
			if not s then
				s = { totalElapsed = 0 }
				handle[sk] = s
			end
			s.totalElapsed += dt
			if s.totalElapsed < (config.delay or 0) then
				return
			end
		end
		local m = model :: any
		local delta = math.rad(config.speed * dt)
		m:PivotTo(m:GetPivot() * CFrame.fromAxisAngle(config.axis.Unit, delta))
	end
end

export type RandomRotateToConfig = {
	maxAngle: number,
	duration: number?,
	delay: number?,
}

function EntityUtils.RandomRotateTo(config: RandomRotateToConfig)
	local sk = newStateKey()
	return function(model: any, dt: number, _params: { [string]: any }?, handle: any?)
		if typeof(model) ~= "Instance" then
			return
		end
		if not handle then
			return
		end
		local s: any = handle[sk]
		if not s then
			s = { initialized = false, targetAngle = 0, rotElapsed = 0, totalElapsed = 0 }
			handle[sk] = s
		end
		s.totalElapsed += dt
		local delay = config.delay or 0
		if s.totalElapsed < delay then
			return
		end
		if not s.initialized then
			s.initialized = true
			s.targetAngle = (math.random() * 2 - 1) * config.maxAngle
		end
		s.rotElapsed += dt
		local t = config.duration and math.clamp(s.rotElapsed / config.duration, 0, 1) or 1
		local m = model :: any
		m:PivotTo(m:GetPivot() * CFrame.Angles(0, math.rad(s.targetAngle * t), 0))
	end
end

export type ScaleToConfig = {
	from: Vector3?,
	target: Vector3,
	duration: number?,
	mode: ("linear" | "spring")?,
	speed: number,
	damper: number?,
	delay: number?,
}

function EntityUtils.ScaleTo(config: ScaleToConfig)
	local sk = newStateKey()
	return function(model: any, dt: number, _params: { [string]: any }?, handle: any?)
		if not handle then
			return
		end
		local s: any = handle[sk]
		if not s then
			s = {
				initialized = false,
				currentScale = config.from or Vector3.new(1, 1, 1),
				velX = 0,
				velY = 0,
				velZ = 0,
				rotElapsed = 0,
				totalElapsed = 0,
			}
			handle[sk] = s
		end
		s.totalElapsed += dt
		local delay = config.delay or 0
		if s.totalElapsed < delay then
			return
		end
		if not s.initialized then
			s.initialized = true
			s.currentScale = config.from or Vector3.new(1, 1, 1)
		end
		s.rotElapsed += dt
		if config.mode == "spring" then
			local damper = config.damper or 1
			local sp = config.speed
			local function step(cur: number, vel: number, tgt: number): (number, number)
				local acc = -sp * sp * (cur - tgt) - 2 * damper * sp * vel
				return cur + (vel + acc * dt) * dt, vel + acc * dt
			end
			local nx, vx = step(s.currentScale.X, s.velX, config.target.X)
			local ny, vy = step(s.currentScale.Y, s.velY, config.target.Y)
			local nz, vz = step(s.currentScale.Z, s.velZ, config.target.Z)
			s.currentScale = Vector3.new(nx, ny, nz)
			s.velX, s.velY, s.velZ = vx, vy, vz
		else
			local t = config.duration and math.clamp(s.rotElapsed / config.duration, 0, 1) or 1
			local from = config.from or Vector3.new(1, 1, 1)
			s.currentScale = from:Lerp(config.target, t)
		end
		setSize(model, s.currentScale)
	end
end

export type FadeToConfig = {
	from: number,
	to: number,
	duration: number?,
	mode: ("linear" | "spring")?,
	speed: number,
	damper: number?,
	delay: number?,
}

function EntityUtils.FadeTo(config: FadeToConfig)
	local sk = newStateKey()
	return function(model: any, dt: number, _params: { [string]: any }?, handle: any?)
		if not handle then
			return
		end
		local s: any = handle[sk]
		if not s then
			s = { current = config.from, velocity = 0, rotElapsed = 0, totalElapsed = 0 }
			handle[sk] = s
		end
		s.totalElapsed += dt
		local delay = config.delay or 0
		if s.totalElapsed < delay then
			return
		end
		s.rotElapsed += dt
		if config.mode == "spring" then
			local damper = config.damper or 1
			local acc = -config.speed * config.speed * (s.current - config.to) - 2 * damper * config.speed * s.velocity
			s.velocity += acc * dt
			s.current += s.velocity * dt
		else
			local t = config.duration and math.clamp(s.rotElapsed / config.duration, 0, 1) or 1
			s.current = lerpNumber(config.from, config.to, t)
		end
		s.current = math.clamp(s.current, math.min(config.from, config.to), math.max(config.from, config.to))
		setTransparency(model, s.current)
	end
end

export type MoveToConfig = {
	offset: Vector3,
	duration: number?,
	mode: ("linear" | "spring")?,
	speed: number,
	damper: number?,
	delay: number?,
}

function EntityUtils.MoveTo(config: MoveToConfig)
	local sk = newStateKey()
	return function(model: any, dt: number, _params: { [string]: any }?, handle: any?)
		if typeof(model) ~= "Instance" then
			return
		end
		if not handle then
			return
		end
		local s: any = handle[sk]
		if not s then
			s = {
				initialized = false,
				origin = CFrame.identity,
				velX = 0,
				velY = 0,
				velZ = 0,
				currentOffset = Vector3.zero,
				rotElapsed = 0,
				totalElapsed = 0,
			}
			handle[sk] = s
		end
		s.totalElapsed += dt
		local delay = config.delay or 0
		if s.totalElapsed < delay then
			return
		end
		if not s.initialized then
			s.initialized = true
			s.origin = (model :: any):GetPivot()
		end
		s.rotElapsed += dt
		if config.mode == "spring" then
			local damper = config.damper or 1
			local sp = config.speed
			local function step(cur: number, vel: number, tgt: number): (number, number)
				local acc = -sp * sp * (cur - tgt) - 2 * damper * sp * vel
				return cur + (vel + acc * dt) * dt, vel + acc * dt
			end
			local nx, vx = step(s.currentOffset.X, s.velX, config.offset.X)
			local ny, vy = step(s.currentOffset.Y, s.velY, config.offset.Y)
			local nz, vz = step(s.currentOffset.Z, s.velZ, config.offset.Z)
			s.currentOffset = Vector3.new(nx, ny, nz)
			s.velX, s.velY, s.velZ = vx, vy, vz
		else
			local t = config.duration and math.clamp(s.rotElapsed / config.duration, 0, 1) or 1
			s.currentOffset = Vector3.new(0, 0, 0):Lerp(config.offset, t)
		end
		(model :: any):PivotTo(s.origin * CFrame.new(s.currentOffset))
	end
end

export type RandomOffsetToConfig = {
	range: Vector3,
	duration: number?,
	delay: number?,
}

function EntityUtils.RandomOffsetTo(config: RandomOffsetToConfig)
	local sk = newStateKey()
	return function(model: any, dt: number, _params: { [string]: any }?, handle: any?)
		if typeof(model) ~= "Instance" then
			return
		end
		if not handle then
			return
		end
		local s: any = handle[sk]
		if not s then
			s = {
				initialized = false,
				targetOffset = Vector3.zero,
				origin = CFrame.identity,
				rotElapsed = 0,
				totalElapsed = 0,
			}
			handle[sk] = s
		end
		s.totalElapsed += dt
		local delay = config.delay or 0
		if s.totalElapsed < delay then
			return
		end
		if not s.initialized then
			s.initialized = true
			s.origin = (model :: any):GetPivot()
			s.targetOffset = Vector3.new(
				(math.random() * 2 - 1) * config.range.X,
				(math.random() * 2 - 1) * config.range.Y,
				(math.random() * 2 - 1) * config.range.Z
			)
		end
		s.rotElapsed += dt
		local t = config.duration and math.clamp(s.rotElapsed / config.duration, 0, 1) or 1
		local currentOffset = Vector3.new(0, 0, 0):Lerp(s.targetOffset, t);
		(model :: any):PivotTo(s.origin * CFrame.new(currentOffset))
	end
end

local _stopped: { [any]: boolean } = setmetatable({}, { __mode = "k" } :: any)

function EntityUtils.Stop()
	return function(model: any, _dt: number, _params: { [string]: any }?, _handle: any?)
		_stopped[model] = true
	end
end

function EntityUtils.Resume()
	return function(model: any, _dt: number, _params: { [string]: any }?, _handle: any?)
		_stopped[model] = nil
	end
end

function EntityUtils.TransformSequence(callbacks: { (any, number, { [string]: any }?, any?) -> () })
	return function(model: any, dt: number, params: { [string]: any }?, handle: any?)
		if _stopped[model] then
			return
		end
		for _, cb in callbacks do
			cb(model, dt, params, handle)
		end
	end
end

return EntityUtils
