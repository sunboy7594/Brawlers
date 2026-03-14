--!strict
--[=[
	@class DynamicIndicator

	모든 인디케이터 shape를 통합한 단일 클래스.
	생성 시 넘긴 shape 목록만 Parts를 생성.
	shapes = nil이면 전체 shape 생성.

	update(params)로 shape 전환 포함 모든 시각 요소 런타임 변경 가능.

	사용 예:
	    local ind = DynamicIndicator.new({ "cone", "line" })
	    ind:update({ shape = "cone", range = 8, angle = 90, color = Color3.new(1,1,0) })
	    ind:show()
	    ind:hide()
	    ind:destroy()
]=]

local require = require(script.Parent.loader).load(script)

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local PART_Y = 0.06
local PART_HEIGHT = 0.15
local CONE_SEGMENTS = 5

-- shape별 기본 config
local DEFAULTS = {
	cone = { range = 8, angle = 90, color = Color3.fromRGB(255, 220, 0), transparency = 0.45 },
	circle = { radius = 5, color = Color3.fromRGB(255, 140, 0), transparency = 0.45 },
	line = { range = 10, width = 3, color = Color3.fromRGB(0, 200, 255), transparency = 0.45 },
	arc = {
		maxRange = 20,
		speed = 30,
		gravity = 196,
		arcRadius = 2,
		color = Color3.fromRGB(220, 50, 50),
		transparency = 0.40,
	},
}

local ALL_SHAPES: { string } = { "cone", "circle", "line", "arc" }

-- ─── 타입 ────────────────────────────────────────────────────────────────────

type ShapeData = {
	parts: { BasePart },
	config: { [string]: any }, -- 현재 적용된 config (기본값 + 업데이트 누적)
}

export type DynamicIndicator = {
	_shapes: { [string]: ShapeData },
	_activeShape: string,
	_origin: Vector3,
	_direction: Vector3,
	update: (self: DynamicIndicator, params: any) -> (),
	show: (self: DynamicIndicator) -> (),
	hide: (self: DynamicIndicator) -> (),
	destroy: (self: DynamicIndicator) -> (),
}

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

-- ─── Shape 생성 ──────────────────────────────────────────────────────────────

local function makePart(folder: Folder, color: Color3, transparency: number): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	p.Parent = folder
	return p
end

local function createCone(folder: Folder, cfg: { [string]: any }): { BasePart }
	local parts: { BasePart } = {}
	local segAngle = cfg.angle / CONE_SEGMENTS
	for _ = 1, CONE_SEGMENTS do
		local p = makePart(folder, cfg.color, cfg.transparency)
		local segWidth = cfg.range * 2 * math.tan(math.rad(segAngle / 2)) + 0.05
		p.Size = Vector3.new(segWidth, PART_HEIGHT, cfg.range)
		table.insert(parts, p)
	end
	return parts
end

local function createCircle(folder: Folder, cfg: { [string]: any }): { BasePart }
	local p = makePart(folder, cfg.color, cfg.transparency)
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(PART_HEIGHT, cfg.radius * 2, cfg.radius * 2)
	p.Transparency = 1 -- 숨김 상태로 시작
	return { p }
end

local function createLine(folder: Folder, cfg: { [string]: any }): { BasePart }
	local p = makePart(folder, cfg.color, cfg.transparency)
	p.Size = Vector3.new(cfg.width, PART_HEIGHT, cfg.range)
	p.Transparency = 1
	return { p }
end

local function createArc(folder: Folder, cfg: { [string]: any }): { BasePart }
	local p = makePart(folder, cfg.color, cfg.transparency)
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(PART_HEIGHT, cfg.arcRadius * 2, cfg.arcRadius * 2)
	p.Transparency = 1
	return { p }
end

local CREATORS = {
	cone = createCone,
	circle = createCircle,
	line = createLine,
	arc = createArc,
}

-- ─── Shape 위치 업데이트 ──────────────────────────────────────────────────────

local function updateConePos(parts: { BasePart }, origin: Vector3, direction: Vector3, cfg: { [string]: any })
	local halfAngle = cfg.angle / 2
	local segAngle = cfg.angle / CONE_SEGMENTS
	local dirH = Vector3.new(direction.X, 0, direction.Z)
	if dirH.Magnitude < 0.001 then
		return
	end
	dirH = dirH.Unit

	for i, part in parts do
		local segCenterDeg = -halfAngle + segAngle * (i - 0.5)
		local rad = math.rad(segCenterDeg)
		local cos, sin = math.cos(rad), math.sin(rad)
		local segDir = Vector3.new(dirH.X * cos - dirH.Z * sin, 0, dirH.X * sin + dirH.Z * cos)
		local center = Vector3.new(origin.X + segDir.X * cfg.range / 2, PART_Y, origin.Z + segDir.Z * cfg.range / 2)
		part.CFrame = CFrame.lookAt(center, center + segDir)
	end
end

local function updateCirclePos(parts: { BasePart }, origin: Vector3, _direction: Vector3, _cfg: { [string]: any })
	parts[1].CFrame = CFrame.new(Vector3.new(origin.X, PART_Y, origin.Z)) * CFrame.fromEulerAnglesXYZ(0, 0, math.pi / 2)
end

local function updateLinePos(parts: { BasePart }, origin: Vector3, direction: Vector3, cfg: { [string]: any })
	local dirH = Vector3.new(direction.X, 0, direction.Z)
	if dirH.Magnitude < 0.001 then
		return
	end
	dirH = dirH.Unit
	local center = Vector3.new(origin.X + dirH.X * cfg.range / 2, PART_Y, origin.Z + dirH.Z * cfg.range / 2)
	parts[1].CFrame = CFrame.lookAt(center, center + dirH)
end

local function calcArcLanding(
	origin: Vector3,
	direction: Vector3,
	speed: number,
	gravity: number,
	maxRange: number
): Vector3
	local startHeight = math.max(origin.Y, 0.01)
	local fallTime = math.sqrt(2 * startHeight / gravity)
	local horizontal = math.min(speed * fallTime, maxRange)
	local dirH = Vector3.new(direction.X, 0, direction.Z)
	if dirH.Magnitude < 0.001 then
		return Vector3.new(origin.X, PART_Y, origin.Z)
	end
	dirH = dirH.Unit
	return Vector3.new(origin.X + dirH.X * horizontal, PART_Y, origin.Z + dirH.Z * horizontal)
end

local function updateArcPos(parts: { BasePart }, origin: Vector3, direction: Vector3, cfg: { [string]: any })
	local landing = calcArcLanding(origin, direction, cfg.speed, cfg.gravity, cfg.maxRange)
	parts[1].CFrame = CFrame.new(landing) * CFrame.fromEulerAnglesXYZ(0, 0, math.pi / 2)
end

local POS_UPDATERS = {
	cone = updateConePos,
	circle = updateCirclePos,
	line = updateLinePos,
	arc = updateArcPos,
}

-- ─── Shape 크기 갱신 ─────────────────────────────────────────────────────────

local function resizeCone(parts: { BasePart }, cfg: { [string]: any })
	local segAngle = cfg.angle / CONE_SEGMENTS
	for _, part in parts do
		local segWidth = cfg.range * 2 * math.tan(math.rad(segAngle / 2)) + 0.05
		part.Size = Vector3.new(segWidth, PART_HEIGHT, cfg.range)
	end
end

local function resizeCircle(parts: { BasePart }, cfg: { [string]: any })
	parts[1].Size = Vector3.new(PART_HEIGHT, cfg.radius * 2, cfg.radius * 2)
end

local function resizeLine(parts: { BasePart }, cfg: { [string]: any })
	parts[1].Size = Vector3.new(cfg.width, PART_HEIGHT, cfg.range)
end

local function resizeArc(parts: { BasePart }, cfg: { [string]: any })
	parts[1].Size = Vector3.new(PART_HEIGHT, cfg.arcRadius * 2, cfg.arcRadius * 2)
end

local RESIZERS = {
	cone = resizeCone,
	circle = resizeCircle,
	line = resizeLine,
	arc = resizeArc,
}

-- ─── 공개 API ────────────────────────────────────────────────────────────────

local DynamicIndicator = {}
DynamicIndicator.__index = DynamicIndicator

function DynamicIndicator.new(shapes: { string }?): DynamicIndicator
	local self = setmetatable({} :: any, DynamicIndicator)
	local folder = getFolder()

	local shapeList: { string } = shapes or ALL_SHAPES
	self._shapes = {}
	self._activeShape = shapeList[1]
	self._origin = Vector3.zero
	self._direction = Vector3.new(0, 0, -1)

	for _, shapeName in shapeList do
		local defaults = DEFAULTS[shapeName]
		assert(defaults, "DynamicIndicator: unknown shape '" .. shapeName .. "'")

		-- config 복사 (기본값)
		local cfg: { [string]: any } = {}
		for k, v in defaults do
			cfg[k] = v
		end

		local parts = CREATORS[shapeName](folder, cfg)
		self._shapes[shapeName] = { parts = parts, config = cfg }
	end

	return self :: DynamicIndicator
end

--[=[
	인디케이터를 업데이트합니다.
	params의 nil 필드는 현재 config 값을 유지합니다.
]=]
function DynamicIndicator:update(params: any)
	-- shape 전환
	if params.shape and params.shape ~= self._activeShape then
		-- 기존 shape 숨기기
		local old = self._shapes[self._activeShape]
		if old then
			for _, p in old.parts do
				p.Transparency = 1
			end
		end
		self._activeShape = params.shape
		-- 새 shape 보이기
		local new = self._shapes[self._activeShape]
		if new then
			for _, p in new.parts do
				p.Transparency = new.config.transparency
			end
		end
	end

	local shapeData = self._shapes[self._activeShape]
	if not shapeData then
		return
	end

	local cfg = shapeData.config
	local parts = shapeData.parts

	-- origin / direction 갱신
	if params.origin then
		self._origin = params.origin
	end
	if params.direction then
		self._direction = params.direction
	end

	-- 색상 / 투명도 갱신
	local needColorUpdate = false
	if params.color then
		cfg.color = params.color
		needColorUpdate = true
	end
	if params.transparency then
		cfg.transparency = params.transparency
		needColorUpdate = true
	end
	if needColorUpdate then
		for _, p in parts do
			p.Color = cfg.color
			p.Transparency = cfg.transparency
		end
	end

	-- 크기 관련 파라미터 갱신 (shape별)
	local needResize = false
	local sizeFields = { "range", "angle", "width", "radius", "maxRange", "speed", "gravity", "arcRadius" }
	for _, field in sizeFields do
		if params[field] ~= nil then
			cfg[field] = params[field]
			needResize = true
		end
	end
	if needResize then
		RESIZERS[self._activeShape](parts, cfg)
	end

	-- 위치 업데이트
	POS_UPDATERS[self._activeShape](parts, self._origin, self._direction, cfg)
end

--[=[
	활성 shape의 Parts를 표시합니다.
]=]
function DynamicIndicator:show()
	local shapeData = self._shapes[self._activeShape]
	if not shapeData then
		return
	end
	for _, p in shapeData.parts do
		p.Transparency = shapeData.config.transparency
	end
end

--[=[
	모든 shape의 Parts를 숨깁니다.
]=]
function DynamicIndicator:hide()
	for _, shapeData in self._shapes do
		for _, p in shapeData.parts do
			p.Transparency = 1
		end
	end
end

--[=[
	모든 Parts를 Destroy합니다.
]=]
function DynamicIndicator:destroy()
	for _, shapeData in self._shapes do
		for _, p in shapeData.parts do
			p:Destroy()
		end
	end
	self._shapes = {}
end

return DynamicIndicator
