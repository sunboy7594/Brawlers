--!strict
--[=[
	@class DynamicIndicator

	모든 인디케이터 shape를 통합한 단일 클래스.
	생성 시 넘긴 shape 목록만 Parts를 생성.
	shapes = nil이면 전체 shape 생성.

	update(params)로 shape 전환 포함 모든 시각 요소 런타임 변경 가능.

	투명도는 TransparencyService를 통해 두 레이어로 관리:
	  _baseKey   : 기본 가시성 (show/hide, cfg.transparency)
	  _effectKey : 런타임 오버라이드 (postDelay 등)
	TransparencyService는 두 키 중 max 값을 최종 투명도로 적용.
	파트 원본 Transparency = 0이므로 Math.map(v, 0, 1, 0, 1) = v, 직관적으로 동작.

	사용 예:
	    local ind = DynamicIndicator.new({ "cone", "line" }, ts)
	    ind:update({ shape = "cone", range = 8, angle = 90, color = Color3.new(1,1,0) })
	    ind:show()
	    ind:hide()
	    ind:destroy()
]=]

local require = require(script.Parent.loader).load(script)

local TransparencyService = require("Transparencyservice")

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local PART_Y = 0.06
local PART_HEIGHT = 0.15
local CONE_SEGMENTS = 16 -- ← 5→16, 겹침 없이 틈 안 보임

local DEFAULT_COLOR = Color3.fromRGB(160, 160, 160)
local DEFAULT_TRANSPARENCY = 0.45

local DEFAULTS = {
	cone = { range = 8, angle = 90, color = DEFAULT_COLOR, transparency = DEFAULT_TRANSPARENCY },
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
	_ts: TransparencyService.TransparencyService,
	_baseKey: { [any]: any },
	_effectKey: { [any]: any },
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

-- 파트 원본 Transparency = 0. TransparencyService가 모든 투명도를 관리.
local function makePart(folder: Folder, color: Color3): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0 -- original = 0 → Math.map(v, 0, 1, 0, 1) = v
	p.Parent = folder
	return p
end

local function createCone(folder: Folder, cfg: { [string]: any }): { BasePart }
	local parts: { BasePart } = {}
	local segAngle = cfg.angle / CONE_SEGMENTS
	for _ = 1, CONE_SEGMENTS do
		local p = makePart(folder, cfg.color)
		-- +0.05 제거: 세그먼트 겹침 없음 → 투명 시 진해지는 문제 해결
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
		local segWidth = cfg.range * 2 * math.tan(math.rad(segAngle / 2)) -- +0.05 제거
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

-- ─── 내부 헬퍼 ───────────────────────────────────────────────────────────────

-- baseKey: 가시성 제어 (show/hide, cfg.transparency)
-- TransparencyService value=1 → 완전 숨김, value=cfg.transparency → 정상 표시
local function setBase(
	ts: TransparencyService.TransparencyService,
	key: { [any]: any },
	parts: { BasePart },
	value: number
)
	for _, p in parts do
		ts:SetTransparency(key, p, value)
	end
end

-- effectKey: 런타임 오버라이드 (postDelay 등)
-- value=0 → TransparencyService가 nil로 처리 → effectKey 리셋 → baseKey만 남음
local function setEffect(
	ts: TransparencyService.TransparencyService,
	key: { [any]: any },
	parts: { BasePart },
	value: number
)
	for _, p in parts do
		ts:SetTransparency(key, p, value)
	end
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

local DynamicIndicator = {}
DynamicIndicator.__index = DynamicIndicator

function DynamicIndicator.new(shapes: { string }?, ts: TransparencyService.TransparencyService): DynamicIndicator
	local self = setmetatable({} :: any, DynamicIndicator)
	local folder = getFolder()

	self._ts = ts
	self._baseKey = {} -- 고유 테이블 (TransparencyService 키)
	self._effectKey = {} -- 고유 테이블 (TransparencyService 키)

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
		setBase(ts, self._baseKey, parts, 1)
	end

	-- activeShape는 기본 투명도로 표시
	local activeData = self._shapes[self._activeShape]
	if activeData then
		setBase(ts, self._baseKey, activeData.parts, activeData.config.transparency)
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
		local old = self._shapes[self._activeShape]
		if old then
			setBase(self._ts, self._baseKey, old.parts, 1)
			setEffect(self._ts, self._effectKey, old.parts, 0) -- effectKey도 리셋
		end
		self._activeShape = params.shape
		local new = self._shapes[self._activeShape]
		if new then
			setBase(self._ts, self._baseKey, new.parts, new.config.transparency)
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

	-- 투명도 오버라이드 (effectKey)
	-- 0 → TransparencyService가 nil로 처리 → effectKey 리셋 → baseKey(cfg.transparency)로 복귀
	-- 이전 코드의 `if params.transparency` (0이 falsy라 리셋 불가 버그) 수정
	if params.transparency ~= nil then
		setEffect(self._ts, self._effectKey, parts, params.transparency)
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
	setBase(self._ts, self._baseKey, shapeData.parts, shapeData.config.transparency)
end

--[=[
	모든 shape의 Parts를 숨깁니다.
]=]
function DynamicIndicator:hide()
	for _, shapeData in self._shapes do
		setBase(self._ts, self._baseKey, shapeData.parts, 1)
	end
end

--[=[
	모든 Parts를 Destroy합니다.
	파트 Destroy 시 TransparencyService의 weakmap에서 자동 제거됩니다.
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
