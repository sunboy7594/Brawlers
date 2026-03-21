--!strict
--[=[
	@class EntityUtils

	EntityController용 유틸 팩토리 모음. (Shared)

	─── Move ─────────────────────────────────────────────────────────────────
	Linear(config)         → 직선 등속
	Arc(config)            → 포물선
	Sweep(config)          → 호 스윗

	─── Detect ───────────────────────────────────────────────────────────────
	Box(config)            → 직육면체 판정
	Sphere(config)         → 구형 판정

	─── Hit 전용 ──────────────────────────────────────────────────────────────
	Penetrate(config)      → N회 통과
	TriggerMiss()          → onHit 내에서 onMiss 강제

	─── 공용 콜백 ──────────────────────────────────────────────────────────────
	Despawn(config?)       → delay 포함 즉시 소멸
	AutoDespawn(duration)  → onSpawn에서 사용. duration 후 자동 소멸 (move=nil 엔티티 수명 관리)
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

-- Quenty 로더 로드 (SpawnEntity/FireEntity에서 EntityPlayer require 필요)
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
-- EntityUtils.ScaleTo() 같은 팩토리를 호출할 때마다 고유 키를 부여.
-- 같은 def가 require 캐싱으로 공유되더라도 각 handle이 독립 상태를 가짐.
local _cbCounter = 0
local function newStateKey(): string
	_cbCounter += 1
	return "_s" .. tostring(_cbCounter)
end

-- ─── 내부 유틸 ───────────────────────────────────────────────────────────────

local function lerpNumber(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function getAllBaseParts(model: any): { BasePart }
	local parts: { BasePart } = {}
	if typeof(model) ~= "Instance" then
		return parts
	end
	for _, d in (model :: Instance):GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d :: BasePart)
		end
	end
	return parts
end

-- setTransparency 위에 추가
local _highlightOriginals: { [any]: { fill: number, outline: number } } = {}

local function setTransparency(model: any, t: number)
	if typeof(model) ~= "Instance" then
		return
	end
	for _, d in (model :: Instance):GetDescendants() do
		if d:IsA("BasePart") then
			(d :: BasePart).Transparency = t
		elseif d.ClassName == "Highlight" then
			local hl = d :: any
			if not _highlightOriginals[hl] then
				_highlightOriginals[hl] = {
					fill = hl.FillTransparency,
					outline = hl.OutlineTransparency,
				}
				-- 소멸 시 자동 정리
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

local function setSize(model: any, scale: Vector3)
	if typeof(model) ~= "Instance" then
		return
	end
	local m = model :: any
	local primary = m.PrimaryPart
	if not primary then
		return
	end
	local baseSize: Vector3 = m._baseSize or primary.Size
	m._baseSize = baseSize
	primary.Size = Vector3.new(baseSize.X * scale.X, baseSize.Y * scale.Y, baseSize.Z * scale.Z)
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
}

function EntityUtils.Arc(config: ArcConfig)
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

		local activeElapsed = elapsed - delay
		local totalTime = config.distance / config.speed
		local t = math.clamp(activeElapsed / totalTime, 0, 1)

		local origin: Vector3 = h._moveOrigin
		local dir: Vector3 = h._moveDir
		local horizontal = origin + dir * (config.distance * t)
		local verticalY = 4 * config.height * t * (1 - t)
		local newPos = Vector3.new(horizontal.X, origin.Y + verticalY, horizontal.Z)

		local nextT = math.min(t + 0.01, 1)
		local nextH = origin + dir * (config.distance * nextT)
		local nextVY = 4 * config.height * nextT * (1 - nextT)
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
		if not handle or not handle.IsAlive or not handle:IsAlive() then
			return
		end
		if delay and delay > 0 then
			handle._deferredDespawn = true -- ← 추가: EntityController 자동소멸 방지
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

--[=[
	AutoDespawn(duration)
	  onSpawn 콜백으로 사용. move=nil인 이펙트 엔티티에 수명을 부여합니다.
	  duration 초 후 자동으로 _destroyNoMiss() 호출.

	  예)
	    onSpawn = EntityUtils.AutoDespawn(1.5),
]=]
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

--[=[
	Animate(onMoveCb)
	  onHit / onMiss / onSpawn 에서 onMove 시그니처 콜백을 매 프레임 실행.
	  handle이 살아있는 동안 Heartbeat로 구동, 소멸 시 _maid가 자동 해제.

	  dt가 필요한 Transform 계열(FadeTo, ScaleTo, RotateTo, MoveTo 등) 전부 사용 가능.
	  각 유틸의 delay 옵션도 그대로 동작.

	  예)
	    onMiss = EntityUtils.Animate(
	        EntityUtils.FadeTo({ from = 0, to = 1, duration = 0.3, speed = 10 })
	    ),

	    onHit = EntityUtils.Sequence({
	        EntityUtils.SpawnEntity("FxDef", "Explosion"),
	        EntityUtils.Animate(EntityUtils.TransformSequence({
	            EntityUtils.ScaleTo({ target = Vector3.new(2,2,2), duration = 0.2, speed = 10 }),
	            EntityUtils.FadeTo({ from = 0, to = 1, duration = 0.2, speed = 10, delay = 0.1 }),
	        })),
	        EntityUtils.Despawn({ delay = 0.2 }),
	    }),
]=]
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

--[=[
	RotateTo(config)
	  방향 기준 회전 (도/초).
	  delay 수정: totalElapsed + handle per-instance 상태로 delay 정상 동작.
]=]
function EntityUtils.RotateTo(config: RotateToConfig)
	local sk = newStateKey()
	return function(model: any, dt: number, _params: { [string]: any }?, handle: any?)
		if typeof(model) ~= "Instance" then
			return
		end
		-- handle 없으면 delay 없이 즉시 회전 (하위 호환)
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

-- _stopped: 약한 참조 테이블 (model GC 시 자동 해제, 메모리 누수 방지)
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

-- handle을 각 콜백에 전달하여 per-instance 상태가 정상 동작하도록 함
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
