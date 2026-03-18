--!strict
--[=[
	@class DynamicIndicator

	이름(id) 기반 멀티 shape 인디케이터.

	생성:
	  DynamicIndicator.new({
	      innerCone  = "cone",
	      outerCone  = "cone",
	      baseCircle = "circle",
	      trail      = "arc",
	  })

	update:
	  ind:update("innerCone",  { range = 4, angleMin = -30, angleMax = 30 })
	  ind:update("baseCircle", { radius = 6, innerRadius = 2 })

	show / hide:
	  ind:show("innerCone")
	  ind:showAll()
	  ind:hideAll()

	destroy:
	  ind:destroy()
	  ind:destroy("innerCone")

	─── Cone ────────────────────────────────────────────────────
	  angleMin / angleMax (도, 전방 기준)
	  예) 중앙 90도  → angleMin=-45, angleMax=45
	  예) 전방향     → angleMin=-180, angleMax=180

	─── Circle ──────────────────────────────────────────────────
	  innerRadius=0 → 꽉 찬 원, >0 → 도넛 (양쪽 테두리 그라디언트)
	  segments는 생성 시 고정 (기본 24).

	─── Line ────────────────────────────────────────────────────
	  range / width

	─── Arc ─────────────────────────────────────────────────────
	  포물선 → Beam (FaceCamera 빌보드)
	  착탄 원 → Circle 세그먼트 24개 (SurfaceGui)

	  direction + range 로 착탄 방향/거리 설정.
	  height = 포물선 최대 높이 (nil이면 range * 0.35 자동)
	  beamWidth  = 포물선 빔 너비
	  arcRadius  = 착탄 원 바깥 반지름
	  arcInnerRadius = 착탄 원 안쪽 반지름 (0이면 꽉 찬 원)

	─── 투명도 레이어 ────────────────────────────────────────────
	  baseT   : 기본 (show/hide)
	  effectT : 런타임 오버라이드 (update transparency)
	  최종 = math.max(baseT, effectT)
	  → SurfaceGui UIGradient outerT / Beam NumberSequence 로 적용.
	    파트 자체는 0.999 고정.
]=]

local require = require(script.Parent.loader).load(script)

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local PART_Y = 0.06
local PART_HEIGHT = 0.15
local CONE_SEGMENTS = 10
local CIRCLE_SEGMENTS = 24

local DEFAULT_COLOR = Color3.fromRGB(160, 160, 160)
local DEFAULT_TRANSPARENCY = 0

-- ─── SurfaceGui 설정 ─────────────────────────────────────────────────────────

local GUI_PIXELS_PER_STUD = 50

-- 그라디언트 fade 구간 (0~1, SurfaceGui Top face 기준)
local GRADIENT_FADE_START = 0.7 -- 일반 세그먼트: 끝 70%부터 불투명해짐
local GRADIENT_FADE_START_LINE = 0.5 -- line: 더 일찍 fade
local GRADIENT_FADE_START_INNER = 0.2 -- donut 안쪽: fade 끝 (구간 짧게)
local GRADIENT_INNER_OPACITY = 0.6 -- donut 안쪽 테두리 투명도 (0=불투명, 1=완전투명)

-- UIGradient.Rotation (Top face 기준, 0 = 앞/바깥 방향)
local ROT_FORWARD = 0 -- 일반 세그먼트
local ROT_DIAG_LEFT = 0 -- 콘 왼끝 세그먼트 (필요 시 조정)
local ROT_DIAG_RIGHT = 0 -- 콘 오른끝 세그먼트 (필요 시 조정)

-- Beam 설정
local BEAM_FADE_START = 0.3 -- 빔: 이 지점부터 불투명해짐
local BEAM_SEGMENTS = 20

-- ─── 기본값 ──────────────────────────────────────────────────────────────────

local DEFAULTS: { [string]: { [string]: any } } = {
	cone = {
		range = 8,
		angleMin = -180,
		angleMax = 180,
		color = DEFAULT_COLOR,
		transparency = DEFAULT_TRANSPARENCY,
	},
	circle = {
		radius = 5,
		innerRadius = 0,
		segments = CIRCLE_SEGMENTS,
		color = DEFAULT_COLOR,
		transparency = DEFAULT_TRANSPARENCY,
	},
	line = {
		range = 10,
		width = 3,
		color = DEFAULT_COLOR,
		transparency = DEFAULT_TRANSPARENCY,
	},
	arc = {
		range = 20,
		height = nil, -- nil이면 range * 0.35 자동
		beamWidth = 0.3, -- 포물선 빔 너비
		arcRadius = 3, -- 착탄 원 바깥 반지름
		arcInnerRadius = 0, -- 착탄 원 안쪽 반지름
		arcSegments = CIRCLE_SEGMENTS,
		color = DEFAULT_COLOR,
		transparency = DEFAULT_TRANSPARENCY,
	},
}

-- ─── 내부 타입 ────────────────────────────────────────────────────────────────

type GradientEntry = {
	frame: Frame,
	gradient: UIGradient,
	fadeStart: number,
	isDonut: boolean,
}

type ArcBeamEntry = {
	beam: Beam,
	part0: BasePart, -- att0 앵커 (CFrame으로 빔 시작 방향 제어)
	part1: BasePart, -- att1 앵커 (CFrame으로 빔 끝 방향 제어)
}

type ShapeEntry = {
	shape: string,
	parts: { BasePart },
	gradients: { GradientEntry },
	arcBeam: ArcBeamEntry?,
	config: { [string]: any },
	origin: Vector3,
	direction: Vector3,
	baseT: number,
	effectT: number,
}

-- ─── 공개 타입 ────────────────────────────────────────────────────────────────

export type DynamicIndicator = typeof(setmetatable(
	{} :: {
		_entries: { [string]: ShapeEntry },
	},
	{} :: typeof({ __index = {} })
))

-- ─── 폴더 ────────────────────────────────────────────────────────────────────

local function getFolder(): Folder
	local f = workspace:FindFirstChild("_Indicators") :: Folder?
	if not f then
		f = Instance.new("Folder")
		f.Name = "_Indicators"
		f.Parent = workspace
	end
	return f :: Folder
end

-- ─── 그라디언트 시퀀스 헬퍼 ──────────────────────────────────────────────────

-- outerT: 끝 투명도. 0=불투명(표시), 1=완전투명(숨김)
local function makeGradientSeq(outerT: number, fadeStart: number?): NumberSequence
	local fs = fadeStart or GRADIENT_FADE_START
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(fs, 1),
		NumberSequenceKeypoint.new(1, outerT),
	})
end

-- donut: 안쪽/바깥 양쪽 테두리 강조
-- 안쪽은 더 짧은 fade 구간 + 더 낮은 불투명도
local function makeGradientSeqDonut(outerT: number, fadeStart: number?): NumberSequence
	local fs = fadeStart or GRADIENT_FADE_START
	local fe = GRADIENT_FADE_START_INNER -- 안쪽 fade 끝 (0.2)
	-- outerT=0(표시)일 때 안쪽은 INNER_OPACITY, 숨길 때 둘 다 1
	local innerT = math.max(outerT, GRADIENT_INNER_OPACITY)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, innerT), -- 안쪽 테두리 (흐릿)
		NumberSequenceKeypoint.new(fe, 1), -- 안쪽 fade 끝
		NumberSequenceKeypoint.new(fs, 1), -- 바깥 fade 시작
		NumberSequenceKeypoint.new(1, outerT), -- 바깥 테두리 (진하게)
	})
end

-- Beam 투명도 시퀀스: BEAM_FADE_START 이전은 투명, 이후 끝으로 갈수록 불투명
local function makeBeamTransparency(outerT: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(BEAM_FADE_START, 1),
		NumberSequenceKeypoint.new(1, outerT),
	})
end

-- ─── SurfaceGui 헬퍼 ─────────────────────────────────────────────────────────

local function makeGui(
	part: BasePart,
	color: Color3,
	rotation: number,
	fadeStart: number?,
	isDonut: boolean?
): GradientEntry
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = GUI_PIXELS_PER_STUD
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Parent = part

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	local donut = isDonut or false
	local fs = fadeStart or GRADIENT_FADE_START
	gradient.Transparency = if donut then makeGradientSeqDonut(0, fs) else makeGradientSeq(0, fs)
	gradient.Parent = frame

	return {
		frame = frame,
		gradient = gradient,
		fadeStart = fs,
		isDonut = donut,
	}
end

-- ─── Part 헬퍼 ───────────────────────────────────────────────────────────────

local function makePart(folder: Folder, cylinder: boolean?): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.new(1, 1, 1) -- SurfaceGui가 색상 담당
	p.Transparency = 0.999 -- 파트 숨김, SurfaceGui는 렌더
	if cylinder then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Parent = folder
	return p
end

-- ─── Shape 생성 ──────────────────────────────────────────────────────────────

local function createCone(folder: Folder, cfg: { [string]: any }): ({ BasePart }, { GradientEntry }, ArcBeamEntry?)
	local parts: { BasePart } = {}
	local guis: { GradientEntry } = {}
	local segAngle = (cfg.angleMax - cfg.angleMin) / CONE_SEGMENTS

	for i = 1, CONE_SEGMENTS do
		local p = makePart(folder)
		local w = cfg.range * 2 * math.tan(math.rad(segAngle / 2))
		p.Size = Vector3.new(w, PART_HEIGHT, cfg.range)

		local rot = if i == 1 then ROT_DIAG_LEFT elseif i == CONE_SEGMENTS then ROT_DIAG_RIGHT else ROT_FORWARD
		table.insert(parts, p)
		table.insert(guis, makeGui(p, cfg.color, rot))
	end

	return parts, guis, nil
end

local function createCircle(folder: Folder, cfg: { [string]: any }): ({ BasePart }, { GradientEntry }, ArcBeamEntry?)
	local parts: { BasePart } = {}
	local guis: { GradientEntry } = {}
	local segs = cfg.segments or CIRCLE_SEGMENTS
	local donut = cfg.innerRadius > 0

	for _ = 1, segs do
		local p = makePart(folder)
		table.insert(parts, p)
		table.insert(guis, makeGui(p, cfg.color, ROT_FORWARD, nil, donut))
	end

	return parts, guis, nil
end

local function createLine(folder: Folder, cfg: { [string]: any }): ({ BasePart }, { GradientEntry }, ArcBeamEntry?)
	local p = makePart(folder)
	p.Size = Vector3.new(cfg.width, PART_HEIGHT, cfg.range)
	return { p }, { makeGui(p, cfg.color, ROT_FORWARD, GRADIENT_FADE_START_LINE) }, nil
end

local function createArc(folder: Folder, cfg: { [string]: any }): ({ BasePart }, { GradientEntry }, ArcBeamEntry?)
	-- ── 포물선 Beam ──────────────────────────────────────────────
	local part0 = Instance.new("Part")
	part0.Anchored = true
	part0.CanCollide = false
	part0.CanQuery = false
	part0.CastShadow = false
	part0.Size = Vector3.new(0.05, 0.05, 0.05)
	part0.Transparency = 1
	part0.Parent = folder

	local part1 = Instance.new("Part")
	part1.Anchored = true
	part1.CanCollide = false
	part1.CanQuery = false
	part1.CastShadow = false
	part1.Size = Vector3.new(0.05, 0.05, 0.05)
	part1.Transparency = 1
	part1.Parent = folder

	local att0 = Instance.new("Attachment")
	att0.Parent = part0
	local att1 = Instance.new("Attachment")
	att1.Parent = part1

	local beam = Instance.new("Beam")
	beam.Attachment0 = att0
	beam.Attachment1 = att1
	beam.Width0 = cfg.beamWidth
	beam.Width1 = cfg.beamWidth
	beam.Segments = BEAM_SEGMENTS
	beam.FaceCamera = true
	beam.LightEmission = 0.5
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(cfg.color)
	beam.Transparency = makeBeamTransparency(1) -- 숨김
	beam.Parent = folder

	local arcBeam: ArcBeamEntry = {
		beam = beam,
		part0 = part0,
		part1 = part1,
	}

	-- ── 착탄 원 세그먼트 ─────────────────────────────────────────
	local parts: { BasePart } = {}
	local guis: { GradientEntry } = {}
	local segs = cfg.arcSegments or CIRCLE_SEGMENTS
	local donut = cfg.arcInnerRadius > 0

	for _ = 1, segs do
		local p = makePart(folder)
		table.insert(parts, p)
		table.insert(guis, makeGui(p, cfg.color, ROT_FORWARD, nil, donut))
	end

	return parts, guis, arcBeam
end

local CREATORS: {
	[string]: (Folder, { [string]: any }) -> ({ BasePart }, { GradientEntry }, ArcBeamEntry?),
} = {
	cone = createCone,
	circle = createCircle,
	line = createLine,
	arc = createArc,
}

-- ─── 위치 업데이트 (내부 헬퍼) ───────────────────────────────────────────────

local function posUpdateCone(parts: { BasePart }, origin: Vector3, direction: Vector3, cfg: { [string]: any })
	local dirH = Vector3.new(direction.X, 0, direction.Z)
	dirH = if dirH.Magnitude < 0.001 then Vector3.new(0, 0, -1) else dirH.Unit

	local totalAngle = cfg.angleMax - cfg.angleMin
	local segAngle = totalAngle / CONE_SEGMENTS

	for i, part in parts do
		local deg = cfg.angleMin + segAngle * (i - 0.5)
		local rad = math.rad(deg)
		local cosR, sinR = math.cos(rad), math.sin(rad)
		local segDir = Vector3.new(dirH.X * cosR - dirH.Z * sinR, 0, dirH.X * sinR + dirH.Z * cosR)
		local center = Vector3.new(origin.X + segDir.X * cfg.range / 2, PART_Y, origin.Z + segDir.Z * cfg.range / 2)
		part.CFrame = CFrame.lookAt(center, center + segDir)
	end
end

local function posUpdateCircle(parts: { BasePart }, origin: Vector3, _dir: Vector3, cfg: { [string]: any })
	local segs = #parts
	local segAngle = 360 / segs
	local midRadius = (cfg.radius + cfg.innerRadius) / 2
	local thickness = math.max(cfg.radius - cfg.innerRadius, 0.05)
	local segWidth = 2 * midRadius * math.sin(math.rad(segAngle / 2)) * 2

	for i, part in parts do
		local rad = math.rad(segAngle * (i - 1))
		local dx, dz = math.sin(rad), math.cos(rad)
		local center = Vector3.new(origin.X + dx * midRadius, PART_Y, origin.Z + dz * midRadius)
		part.CFrame = CFrame.lookAt(center, center + Vector3.new(dx, 0, dz))
		part.Size = Vector3.new(segWidth, PART_HEIGHT, thickness)
	end
end

local function posUpdateLine(parts: { BasePart }, origin: Vector3, direction: Vector3, cfg: { [string]: any })
	local dirH = Vector3.new(direction.X, 0, direction.Z)
	dirH = if dirH.Magnitude < 0.001 then Vector3.new(0, 0, -1) else dirH.Unit
	local center = Vector3.new(origin.X + dirH.X * cfg.range / 2, PART_Y, origin.Z + dirH.Z * cfg.range / 2)
	parts[1].CFrame = CFrame.lookAt(center, center + dirH)
end

-- arc 전용: 포물선 Beam + 착탄 원 세그먼트
local function posUpdateArc(entry: ShapeEntry)
	local parts = entry.parts
	local origin = entry.origin
	local direction = entry.direction
	local cfg = entry.config
	local arcBeam = entry.arcBeam

	local dirH = Vector3.new(direction.X, 0, direction.Z)
	dirH = if dirH.Magnitude < 0.001 then Vector3.new(0, 0, -1) else dirH.Unit

	local R = cfg.range
	local H = if cfg.height ~= nil then cfg.height else R * 0.35

	-- 착탄 위치
	local landPos = Vector3.new(origin.X + dirH.X * R, origin.Y, origin.Z + dirH.Z * R)

	-- ── Beam 위치/방향 ───────────────────────────────────────────
	if arcBeam then
		-- t=0 접선: (R*dirH, 4H)
		-- t=1 접선: (R*dirH, -4H)
		local t0Dir = (dirH * R + Vector3.new(0, 4 * H, 0)).Unit
		local t1Dir = (dirH * R - Vector3.new(0, 4 * H, 0)).Unit

		-- 베지어 근사: CurveSize = ||(R, 4H)|| / 3
		local curveSize = math.sqrt(R * R + 16 * H * H) / 3

		arcBeam.part0.CFrame = CFrame.lookAt(origin, origin + t0Dir)
		arcBeam.part1.CFrame = CFrame.lookAt(landPos, landPos + t1Dir)
		arcBeam.beam.CurveSize0 = curveSize
		arcBeam.beam.CurveSize1 = curveSize
	end

	-- ── 착탄 원 세그먼트 ────────────────────────────────────────
	local segs = #parts
	if segs == 0 then
		return
	end

	local segAngle = 360 / segs
	local innerR = cfg.arcInnerRadius or 0
	local outerR = cfg.arcRadius
	local midRadius = (outerR + innerR) / 2
	local thickness = math.max(outerR - innerR, 0.05)
	local segWidth = 2 * midRadius * math.sin(math.rad(segAngle / 2)) * 2

	for i, part in parts do
		local rad = math.rad(segAngle * (i - 1))
		local dx, dz = math.sin(rad), math.cos(rad)
		local center = Vector3.new(landPos.X + dx * midRadius, PART_Y, landPos.Z + dz * midRadius)
		part.CFrame = CFrame.lookAt(center, center + Vector3.new(dx, 0, dz))
		part.Size = Vector3.new(segWidth, PART_HEIGHT, thickness)
	end
end

-- ─── 크기 리사이즈 ────────────────────────────────────────────────────────────

local SIZE_FIELDS: { [string]: { string } } = {
	cone = { "range", "angleMin", "angleMax" },
	circle = { "radius", "innerRadius" },
	line = { "range", "width" },
	arc = { "range", "height", "beamWidth", "arcRadius", "arcInnerRadius" },
}

local function resizeCone(parts: { BasePart }, cfg: { [string]: any })
	local segAngle = (cfg.angleMax - cfg.angleMin) / CONE_SEGMENTS
	for _, p in parts do
		local w = cfg.range * 2 * math.tan(math.rad(segAngle / 2))
		p.Size = Vector3.new(w, PART_HEIGHT, cfg.range)
	end
end

local function resizeLine(parts: { BasePart }, cfg: { [string]: any })
	parts[1].Size = Vector3.new(cfg.width, PART_HEIGHT, cfg.range)
end

local function resizeArc(entry: ShapeEntry)
	if entry.arcBeam then
		entry.arcBeam.beam.Width0 = entry.config.beamWidth
		entry.arcBeam.beam.Width1 = entry.config.beamWidth
	end
	-- 착탄 원 크기는 posUpdateArc에서 처리
end

-- dispatch tables (entry를 받아 내부 헬퍼로 전달)
local POS_UPDATERS: { [string]: (ShapeEntry) -> () } = {
	cone = function(e)
		posUpdateCone(e.parts, e.origin, e.direction, e.config)
	end,
	circle = function(e)
		posUpdateCircle(e.parts, e.origin, e.direction, e.config)
	end,
	line = function(e)
		posUpdateLine(e.parts, e.origin, e.direction, e.config)
	end,
	arc = function(e)
		posUpdateArc(e)
	end,
}

local RESIZERS: { [string]: ((ShapeEntry) -> ())? } = {
	cone = function(e)
		resizeCone(e.parts, e.config)
	end,
	circle = nil, -- posUpdate에서 처리
	line = function(e)
		resizeLine(e.parts, e.config)
	end,
	arc = function(e)
		resizeArc(e)
	end,
}

-- ─── 투명도 적용 ──────────────────────────────────────────────────────────────

local function applyTransparency(entry: ShapeEntry)
	local final = math.max(entry.baseT, entry.effectT)

	-- SurfaceGui 그라디언트
	for _, g in entry.gradients do
		g.gradient.Transparency = if g.isDonut
			then makeGradientSeqDonut(final, g.fadeStart)
			else makeGradientSeq(final, g.fadeStart)
	end

	-- Beam (arc 전용)
	if entry.arcBeam then
		entry.arcBeam.beam.Transparency = makeBeamTransparency(final)
	end
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

local DynamicIndicator = {}
DynamicIndicator.__index = DynamicIndicator

--[=[
	인디케이터를 생성합니다.

	@param shapeMap { [string]: string }
	  key   = shape id
	  value = shape 종류 ("cone" | "circle" | "line" | "arc")
]=]
function DynamicIndicator.new(shapeMap: { [string]: string }): DynamicIndicator
	local self = setmetatable({} :: any, DynamicIndicator)
	local folder = getFolder()
	self._entries = {}

	for id, shape in shapeMap do
		local defaults = DEFAULTS[shape]
		assert(defaults, "DynamicIndicator: unknown shape '" .. shape .. "'")

		local cfg: { [string]: any } = {}
		for k, v in defaults do
			cfg[k] = v
		end

		local parts, gradients, arcBeam = CREATORS[shape](folder, cfg)

		local entry: ShapeEntry = {
			shape = shape,
			parts = parts,
			gradients = gradients,
			arcBeam = arcBeam,
			config = cfg,
			origin = Vector3.zero,
			direction = Vector3.new(0, 0, -1),
			baseT = 1,
			effectT = 0,
		}
		self._entries[id] = entry
	end

	return self :: DynamicIndicator
end

--[=[
	특정 id의 shape를 업데이트합니다.
	nil 필드는 현재 값 유지.
]=]
function DynamicIndicator:update(id: string, params: { [string]: any })
	local entry = self._entries[id]
	if not entry then
		warn("[DynamicIndicator] update: unknown id '" .. id .. "'")
		return
	end

	local cfg = entry.config

	if params.origin then
		entry.origin = params.origin
	end
	if params.direction then
		entry.direction = params.direction
	end

	-- 색상
	if params.color then
		cfg.color = params.color
		for _, g in entry.gradients do
			g.frame.BackgroundColor3 = params.color
		end
		if entry.arcBeam then
			entry.arcBeam.beam.Color = ColorSequence.new(params.color)
		end
	end

	-- 투명도 오버라이드
	if params.transparency ~= nil then
		entry.effectT = params.transparency
		applyTransparency(entry)
	end

	-- 크기 필드
	local needResize = false
	for _, field in SIZE_FIELDS[entry.shape] do
		if params[field] ~= nil then
			cfg[field] = params[field]
			needResize = true
		end
	end
	if needResize then
		local resizer = RESIZERS[entry.shape]
		if resizer then
			resizer(entry)
		end
	end

	-- innerRadius 변경 시 donut 여부 갱신
	if entry.shape == "circle" and params.innerRadius ~= nil then
		local donut = cfg.innerRadius > 0
		for _, g in entry.gradients do
			g.isDonut = donut
		end
		applyTransparency(entry)
	elseif entry.shape == "arc" and params.arcInnerRadius ~= nil then
		local donut = cfg.arcInnerRadius > 0
		for _, g in entry.gradients do
			g.isDonut = donut
		end
		applyTransparency(entry)
	end

	-- 위치 갱신
	POS_UPDATERS[entry.shape](entry)
end

--[=[
	특정 id의 shape를 표시합니다.
]=]
function DynamicIndicator:show(id: string)
	local entry = self._entries[id]
	if not entry then
		return
	end
	entry.baseT = entry.config.transparency
	applyTransparency(entry)
end

--[=[
	특정 id의 shape를 숨깁니다.
]=]
function DynamicIndicator:hide(id: string)
	local entry = self._entries[id]
	if not entry then
		return
	end
	entry.baseT = 1
	applyTransparency(entry)
end

--[=[
	모든 shape에 동일한 params를 적용합니다.
]=]
function DynamicIndicator:updateAll(params: { [string]: any })
	for id in self._entries do
		self:update(id, params)
	end
end

--[=[
	모든 shape를 표시합니다.
]=]
function DynamicIndicator:showAll()
	for _, entry in self._entries do
		entry.baseT = entry.config.transparency
		applyTransparency(entry)
	end
end

--[=[
	모든 shape를 숨깁니다.
]=]
function DynamicIndicator:hideAll()
	for _, entry in self._entries do
		entry.baseT = 1
		applyTransparency(entry)
	end
end

--[=[
	shape를 파괴합니다.
	id 없이 호출하면 전체 파괴.
	SurfaceGui는 파트 자식이므로 파트 파괴 시 자동 정리.

	@param id string? (nil이면 전체)
]=]
function DynamicIndicator:destroy(id: string?)
	local function destroyEntry(entry: ShapeEntry)
		for _, p in entry.parts do
			p:Destroy()
		end
		if entry.arcBeam then
			entry.arcBeam.beam:Destroy()
			entry.arcBeam.part0:Destroy()
			entry.arcBeam.part1:Destroy()
		end
	end

	if id then
		local entry = self._entries[id]
		if not entry then
			return
		end
		destroyEntry(entry)
		self._entries[id] = nil
	else
		for _, entry in self._entries do
			destroyEntry(entry)
		end
		self._entries = {}
	end
end

return DynamicIndicator
