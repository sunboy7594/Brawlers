--!strict
--[=[
	@class DynamicIndicator

	이름(id) 기반 멀티 shape 인디케이터.

	생성:
	  DynamicIndicator.new({
	      innerCone  = "cone",
	      outerCone  = "cone",   -- 같은 shape도 다른 id면 독립 인스턴스
	      baseCircle = "circle",
	      trail      = "arc",
	  })

	update:
	  ind:update("innerCone",  { range = 4, angleMin = -30, angleMax = 30 })
	  ind:update("baseCircle", { radius = 6, innerRadius = 2 })

	show / hide:
	  ind:show("innerCone")   -- innerCone만 표시
	  ind:show("outerCone")   -- outerCone도 동시에 표시
	  ind:hide("innerCone")
	  ind:showAll()
	  ind:hideAll()

	destroy:
	  ind:destroy()           -- 전체 파괴
	  ind:destroy("innerCone") -- 특정 shape만 파괴

	─── Cone ────────────────────────────────────────────────────
	  angleMin / angleMax (도, 전방 기준)
	  예) 중앙 90도  → angleMin=-45, angleMax=45
	  예) 오른쪽 90도 → angleMin=0,  angleMax=90
	  예) 전방향     → angleMin=-180, angleMax=180

	─── Circle ──────────────────────────────────────────────────
	  innerRadius=0 → 꽉 찬 원, >0 → 도넛
	  실시간 변경 자연스럽게 전환.
	  segments는 생성 시 고정 (기본 24).

	─── Arc ─────────────────────────────────────────────────────
	  direction + range 로 착탄 방향/거리 설정.
	  height = 포물선 최대 높이 (nil이면 range * 0.35 자동)
	  y(t) = 4 * height * t * (1-t),  t ∈ [0, 1]
	  x(t) = range * t
	  speed / gravity 입력 불필요.

	─── 투명도 레이어 ────────────────────────────────────────────
	  _baseT   : 기본 (show/hide)
	  _effectT : 런타임 오버라이드 (update transparency)
	  최종 = math.max(baseT, effectT)
]=]

local require = require(script.Parent.loader).load(script)

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local PART_Y = 0.06
local PART_HEIGHT = 0.15
local CONE_SEGMENTS = 10
local CIRCLE_SEGMENTS = 24
local ARC_SEGMENTS = 12

local DEFAULT_COLOR = Color3.fromRGB(160, 160, 160)
local DEFAULT_TRANSPARENCY = 0

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
		arcRadius = 0.3,
		arcSegments = ARC_SEGMENTS,
		color = DEFAULT_COLOR,
		transparency = DEFAULT_TRANSPARENCY,
	},
}

-- ─── 내부 타입 ────────────────────────────────────────────────────────────────

type ShapeEntry = {
	shape: string,
	parts: { BasePart },
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

-- ─── Part 헬퍼 ───────────────────────────────────────────────────────────────

local function makePart(folder: Folder, color: Color3, cylinder: boolean?): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 1
	if cylinder then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Parent = folder
	return p
end

-- ─── Shape 생성 ──────────────────────────────────────────────────────────────

local function createCone(folder: Folder, cfg: { [string]: any }): { BasePart }
	local parts: { BasePart } = {}
	local segAngle = (cfg.angleMax - cfg.angleMin) / CONE_SEGMENTS
	for _ = 1, CONE_SEGMENTS do
		local p = makePart(folder, cfg.color)
		local w = cfg.range * 2 * math.tan(math.rad(segAngle / 2))
		p.Size = Vector3.new(w, PART_HEIGHT, cfg.range)
		table.insert(parts, p)
	end
	return parts
end

local function createCircle(folder: Folder, cfg: { [string]: any }): { BasePart }
	local parts: { BasePart } = {}
	local segs = cfg.segments or CIRCLE_SEGMENTS
	for _ = 1, segs do
		table.insert(parts, makePart(folder, cfg.color))
	end
	return parts
end

local function createLine(folder: Folder, cfg: { [string]: any }): { BasePart }
	local p = makePart(folder, cfg.color)
	p.Size = Vector3.new(cfg.width, PART_HEIGHT, cfg.range)
	return { p }
end

local function createArc(folder: Folder, cfg: { [string]: any }): { BasePart }
	local parts: { BasePart } = {}
	local segs = cfg.arcSegments or ARC_SEGMENTS
	for _ = 1, segs do
		local p = makePart(folder, cfg.color, true)
		local r = cfg.arcRadius
		p.Size = Vector3.new(PART_HEIGHT, r * 2, r * 2)
		table.insert(parts, p)
	end
	return parts
end

local CREATORS: { [string]: (Folder, { [string]: any }) -> { BasePart } } = {
	cone = createCone,
	circle = createCircle,
	line = createLine,
	arc = createArc,
}

-- ─── 위치 업데이트 ───────────────────────────────────────────────────────────

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

local function posUpdateArc(parts: { BasePart }, origin: Vector3, direction: Vector3, cfg: { [string]: any })
	-- 수평 방향
	local dirH = Vector3.new(direction.X, 0, direction.Z)
	dirH = if dirH.Magnitude < 0.001 then Vector3.new(0, 0, -1) else dirH.Unit

	local R = cfg.range
	local H = if cfg.height ~= nil then cfg.height else R * 0.35
	local segs = #parts
	local r = cfg.arcRadius

	-- 포물선: x(t) = R*t,  y(t) = 4H*t*(1-t),  t ∈ [0,1]
	for i, part in parts do
		local t0 = (i - 1) / segs
		local t1 = i / segs
		local tMid = (t0 + t1) / 2

		-- 현재 세그먼트 중점
		local x0 = R * tMid
		local y0 = 4 * H * tMid * (1 - tMid)

		-- 다음 점 (접선 방향 계산용)
		local x1 = R * t1
		local y1 = 4 * H * t1 * (1 - t1)

		local pos = Vector3.new(origin.X + dirH.X * x0, origin.Y + y0, origin.Z + dirH.Z * x0)
		local nextPos = Vector3.new(origin.X + dirH.X * x1, origin.Y + y1, origin.Z + dirH.Z * x1)

		local segVec = nextPos - pos
		local segLen = math.max(segVec.Magnitude, 0.01)

		part.Size = Vector3.new(segLen, r * 2, r * 2)
		part.CFrame = CFrame.lookAt(pos, nextPos)
			* CFrame.new(segLen / 2, 0, 0)
			* CFrame.fromEulerAnglesXYZ(0, 0, math.pi / 2)
	end
end

local POS_UPDATERS: { [string]: ({ BasePart }, Vector3, Vector3, { [string]: any }) -> () } = {
	cone = posUpdateCone,
	circle = posUpdateCircle,
	line = posUpdateLine,
	arc = posUpdateArc,
}

-- ─── 크기 리사이즈 ────────────────────────────────────────────────────────────

local SIZE_FIELDS: { [string]: { string } } = {
	cone = { "range", "angleMin", "angleMax" },
	circle = { "radius", "innerRadius" }, -- posUpdate에서 Size도 갱신
	line = { "range", "width" },
	arc = { "range", "height", "arcRadius" },
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

local function resizeArc(parts: { BasePart }, cfg: { [string]: any })
	local r = cfg.arcRadius
	for _, p in parts do
		p.Size = Vector3.new(p.Size.X, r * 2, r * 2)
	end
end

local RESIZERS: { [string]: (({ BasePart }, { [string]: any }) -> ())? } = {
	cone = resizeCone,
	circle = nil, -- posUpdateCircle에서 처리
	line = resizeLine,
	arc = resizeArc,
}

-- ─── 내부 유틸 ───────────────────────────────────────────────────────────────

local function applyTransparency(entry: ShapeEntry)
	local final = math.max(entry.baseT, entry.effectT)
	for _, p in entry.parts do
		p.Transparency = final
	end
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

local DynamicIndicator = {}
DynamicIndicator.__index = DynamicIndicator

--[=[
	인디케이터를 생성합니다.

	@param shapeMap { [string]: string }
	  key   = shape id (임의 이름)
	  value = shape 종류 ("cone" | "circle" | "line" | "arc")

	예)
	  DynamicIndicator.new({
	      innerCone  = "cone",
	      outerCone  = "cone",
	      baseCircle = "circle",
	  })
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

		local entry: ShapeEntry = {
			shape = shape,
			parts = CREATORS[shape](folder, cfg),
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

	@param id     string
	@param params { [string]: any }
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
		for _, p in entry.parts do
			p.Color = cfg.color
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
			resizer(entry.parts, cfg)
		end
	end

	-- 위치 갱신
	POS_UPDATERS[entry.shape](entry.parts, entry.origin, entry.direction, cfg)
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
	색상/투명도 일괄 변경 등에 사용.
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

	@param id string? (nil이면 전체)
]=]
function DynamicIndicator:destroy(id: string?)
	if id then
		local entry = self._entries[id]
		if not entry then
			return
		end
		for _, p in entry.parts do
			p:Destroy()
		end
		self._entries[id] = nil
	else
		for _, entry in self._entries do
			for _, p in entry.parts do
				p:Destroy()
			end
		end
		self._entries = {}
	end
end

return DynamicIndicator
