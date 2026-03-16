--!strict
--[=[
	@class DynamicIndicator

	모든 인디케이터 shape를 통합한 단일 클래스.
	생성 시 넘긴 shape 목록만 Parts를 생성.
	shapes = nil이면 전체 shape 생성.

	update(params)로 shape 전환 포함 모든 시각 요소 런타임 변경 가능.

	투명도는 두 레이어로 직접 관리:
	  _baseT   : 기본 가시성 (show/hide, cfg.transparency)
	  _effectT : 런타임 오버라이드 (postDelay 등)
	최종 Transparency = math.max(base, effect) 직접 적용.

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
local CONE_SEGMENTS = 10

local DEFAULT_COLOR = Color3.fromRGB(160, 160, 160)
local DEFAULT_TRANSPARENCY = 0

local DEFAULTS = {
	cone = { range = 8, angle = 360, color = DEFAULT_COLOR, transparency = DEFAULT_TRANSPARENCY },
	circle = { radius = 5, color = DEFAULT_COLOR, transparency = DEFAULT_TRANSPARENCY },
	line = { range = 10, width = 3, color = DEFAULT_COLOR, transparency = DEFAULT_TRANSPARENCY },
	arc = {
		maxRange = 20,
		speed = 30,
		gravity = 196,
		arcRadius = 2,
		color = DEFAULT_COLOR,
		transparency = DEFAULT_TRANSPARENCY,
	},
}

local ALL_SHAPES: { string } = { "cone", "circle", "line", "arc" }

-- ─── 타입 ────────────────────────────────────────────────────────────────────

type ShapeData = {
	parts: { BasePart },
	config: { [string]: any },
}

export type DynamicIndicator = {
	_shapes: { [string]: ShapeData },
	_activeShape: string,
	_origin: Vector3,
	_direction: Vector3,
	_baseT: { [string]: number }, -- shape별 기본 투명도
	_effectT: { [string]: number }, -- shape별 이펙트 투명도
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

local function makePart(folder: Folder, color: Color3): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 1 -- 초기 숨김; 투명도는 _applyTransparency로만 제어
	p.Parent = folder
	return p
end

local function createCone(folder: Folder, cfg: { [string]: any }): { BasePart }
	local parts: { BasePart } = {}
	local segAngle = cfg.angle / CONE_SEGMENTS
	for _ = 1, CONE_SEGMENTS do
		local p = makePart(folder, cfg.color)
		local segWidth = cfg.range * 2 * math.tan(math.rad(segAngle / 2))
		p.Size = Vector3.new(segWidth, PART_HEIGHT, cfg.range)
		table.insert(parts, p)
	end
	return parts
end

local function createCircle(folder: Folder, cfg: { [string]: any }): { BasePart }
	local p = makePart(folder, cfg.color)
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(PART_HEIGHT, cfg.radius * 2, cfg.radius * 2)
	return { p }
end

local function createLine(folder: Folder, cfg: { [string]: any }): { BasePart }
	local p = makePart(folder, cfg.color)
	p.Size = Vector3.new(cfg.width, PART_HEIGHT, cfg.range)
	return { p }
end

local function createArc(folder: Folder, cfg: { [string]: any }): { BasePart }
	local p = makePart(folder, cfg.color)
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(PART_HEIGHT, cfg.arcRadius * 2, cfg.arcRadius * 2)
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
	local dirH = Vector3.new(direction.X, 0, direction.Z)
	if dirH.Magnitude < 0.001 then
		dirH = Vector3.new(0, 0, -1)
	else
		dirH = dirH.Unit
	end

	local halfAngle = cfg.angle / 2
	local segAngle = cfg.angle / CONE_SEGMENTS

	for i, part in parts do
		local segCenterDeg = -halfAngle + segAngle * (i - 0.5)
		local rad = math.rad(segCenterDeg)
		local cosR, sinR = math.cos(rad), math.sin(rad)

		-- dirH 기준으로 로컬 회전 (2D 회전 행렬)
		local segDir = Vector3.new(dirH.X * cosR - dirH.Z * sinR, 0, dirH.X * sinR + dirH.Z * cosR)

		local center = Vector3.new(origin.X + segDir.X * cfg.range / 2, PART_Y, origin.Z + segDir.Z * cfg.range / 2)

		part.CFrame = CFrame.lookAt(center, center + segDir)
	end
end

local function updateCirclePos(parts: { BasePart }, origin: Vector3, _direction: Vector3, _cfg: { [string]: any })
	parts[1].CFrame = CFrame.new(origin.X, PART_Y, origin.Z) * CFrame.fromEulerAnglesXYZ(0, 0, math.pi / 2)
end

local function updateLinePos(parts: { BasePart }, origin: Vector3, direction: Vector3, cfg: { [string]: any })
	local dirH = Vector3.new(direction.X, 0, direction.Z)
	if dirH.Magnitude < 0.001 then
		dirH = Vector3.new(0, 0, -1)
	else
		dirH = dirH.Unit
	end
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
	local dirH = Vector3.new(direction.X, 0, direction.Z)
	if dirH.Magnitude < 0.001 then
		dirH = Vector3.new(0, 0, -1)
	else
		dirH = dirH.Unit
	end
	local vy = direction.Y * speed
	local vh = math.sqrt(math.max(0, speed * speed - vy * vy))
	local t = if gravity > 0 then (vy + math.sqrt(math.max(0, vy * vy + 2 * gravity * 3))) / gravity else 1
	local horizontal = math.min(vh * t, maxRange)
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
		local segWidth = cfg.range * 2 * math.tan(math.rad(segAngle / 2))
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

--[=[
	내부: shape의 최종 투명도를 적용합니다.
	final = math.max(_baseT[shape], _effectT[shape])
]=]
function DynamicIndicator:_applyTransparency(shapeName: string)
	local shapeData = self._shapes[shapeName]
	if not shapeData then
		return
	end
	local base = self._baseT[shapeName] or 1
	local effect = self._effectT[shapeName] or 0
	local final = math.max(base, effect)
	for _, p in shapeData.parts do
		p.Transparency = final
	end
end

function DynamicIndicator.new(shapes: { string }?): DynamicIndicator
	local self = setmetatable({} :: any, DynamicIndicator)
	local folder = getFolder()

	self._baseT = {}
	self._effectT = {}

	local shapeList: { string } = shapes or ALL_SHAPES
	self._shapes = {}
	self._activeShape = shapeList[1]
	self._origin = Vector3.zero
	self._direction = Vector3.new(0, 0, -1)

	for _, shapeName in shapeList do
		local defaults = DEFAULTS[shapeName]
		assert(defaults, "DynamicIndicator: unknown shape '" .. shapeName .. "'")

		local cfg: { [string]: any } = {}
		for k, v in defaults do
			cfg[k] = v
		end

		local parts = CREATORS[shapeName](folder, cfg)
		self._shapes[shapeName] = { parts = parts, config = cfg }

		-- 모든 shape 초기 숨김
		self._baseT[shapeName] = 1
		self._effectT[shapeName] = 0
		-- makePart에서 이미 Transparency=1로 생성됨
	end

	-- activeShape는 기본 투명도로 표시
	local activeData = self._shapes[self._activeShape]
	if activeData then
		self._baseT[self._activeShape] = activeData.config.transparency
		self:_applyTransparency(self._activeShape)
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
		local oldName = self._activeShape
		-- 이전 shape 숨김 + effect 리셋
		self._baseT[oldName] = 1
		self._effectT[oldName] = 0
		self:_applyTransparency(oldName)

		self._activeShape = params.shape
		local new = self._shapes[self._activeShape]
		if new then
			self._baseT[self._activeShape] = new.config.transparency
			self:_applyTransparency(self._activeShape)
		end
	end

	local shapeData = self._shapes[self._activeShape]
	if not shapeData then
		return
	end

	local cfg = shapeData.config
	local parts = shapeData.parts

	-- origin / direction
	if params.origin then
		self._origin = params.origin
	end
	if params.direction then
		self._direction = params.direction
	end

	-- 색상
	if params.color then
		cfg.color = params.color
		for _, p in parts do
			p.Color = cfg.color
		end
	end

	-- 투명도 오버라이드 (effectT)
	-- 0 → effectT=0 → math.max(base, 0) = base → 자연스럽게 baseT로 복귀
	if params.transparency ~= nil then
		self._effectT[self._activeShape] = params.transparency
		self:_applyTransparency(self._activeShape)
	end

	-- 크기 관련
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

	-- 위치
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
	self._baseT[self._activeShape] = shapeData.config.transparency
	self:_applyTransparency(self._activeShape)
end

--[=[
	모든 shape의 Parts를 숨깁니다.
]=]
function DynamicIndicator:hide()
	for shapeName in self._shapes do
		self._baseT[shapeName] = 1
		self:_applyTransparency(shapeName)
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
