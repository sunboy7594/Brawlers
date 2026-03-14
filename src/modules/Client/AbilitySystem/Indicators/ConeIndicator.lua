--!strict
--[=[
	@class ConeIndicator

	부채꼴(원뿔) 범위를 시각화하는 인디케이터.
	사각형 Part로 부채꼴을 근사합니다.

	config: { range: number, angle: number }
	색상: 노란색
]=]

local require = require(script.Parent.loader).load(script)

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local PART_Y = 0.06 -- 지형 고저차 없음, 점프 없음 → Y 고정
local COLOR = Color3.fromRGB(255, 220, 0) -- 노란색
local TRANSPARENCY = 0.45
local PART_HEIGHT = 0.15 -- Part의 수직 두께

-- ─── 타입 정의 ───────────────────────────────────────────────────────────────

export type ConeIndicatorConfig = {
	range: number,
	angle: number, -- 도 단위 (전체 각도)
}

export type ConeIndicator = {
	_parts: { BasePart },
	_config: ConeIndicatorConfig,
	update: (self: ConeIndicator, origin: Vector3, direction: Vector3) -> (),
	show: (self: ConeIndicator) -> (),
	hide: (self: ConeIndicator) -> (),
	destroy: (self: ConeIndicator) -> (),
}

-- ─── 인디케이터 폴더 획득 ────────────────────────────────────────────────────

local function getIndicatorsFolder(): Folder
	local folder = workspace:FindFirstChild("_Indicators") :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "_Indicators"
		folder.Parent = workspace
	end
	return folder :: Folder
end

-- ─── 부채꼴 근사 Part 생성 ──────────────────────────────────────────────────

-- 부채꼴을 여러 개의 사각형 Part로 근사합니다.
-- 부채꼴 반지름(range), 전체 각도(angle)를 기준으로 fan 분할.
local SEGMENT_COUNT = 5 -- 분할 개수 (홀수 권장)

local function createFanParts(folder: Folder, config: ConeIndicatorConfig): { BasePart }
	local parts: { BasePart } = {}
	local halfAngle = config.angle / 2
	local segAngle = config.angle / SEGMENT_COUNT

	for i = 1, SEGMENT_COUNT do
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = COLOR
		part.Transparency = TRANSPARENCY
		-- 각 세그먼트는 얇은 직사각형: 폭은 segAngle 기준 호 길이, 길이는 range
		local segHalfAngleDeg = halfAngle - (i - 1) * segAngle
		local segWidth = config.range * 2 * math.tan(math.rad(segAngle / 2)) + 0.05 -- 약간 겹치게
		part.Size = Vector3.new(segWidth, PART_HEIGHT, config.range)
		part.Parent = folder
		table.insert(parts, part)
	end

	return parts
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

local ConeIndicator = {}
ConeIndicator.__index = ConeIndicator

function ConeIndicator.new(config: ConeIndicatorConfig): ConeIndicator
	local self = setmetatable({} :: any, ConeIndicator)
	self._config = config
	self._parts = createFanParts(getIndicatorsFolder(), config)
	return self
end

-- 매 프레임 호출: origin 기준으로 direction 방향의 부채꼴 위치를 갱신합니다.
function ConeIndicator:update(origin: Vector3, direction: Vector3)
	local config = self._config :: ConeIndicatorConfig
	local halfAngle = config.angle / 2
	local segAngle = config.angle / SEGMENT_COUNT

	-- 수평 방향 정규화
	local dirH = Vector3.new(direction.X, 0, direction.Z)
	if dirH.Magnitude < 0.001 then
		return
	end
	dirH = dirH.Unit

	local parts = self._parts :: { BasePart }
	for i, part in parts do
		-- 각 세그먼트의 중심 각도 계산
		local segCenterAngleDeg = -halfAngle + segAngle * (i - 0.5)
		local segCenterRad = math.rad(segCenterAngleDeg)

		-- 세그먼트 방향 (Y축 회전 적용)
		local cos = math.cos(segCenterRad)
		local sin = math.sin(segCenterRad)
		local segDir = Vector3.new(dirH.X * cos - dirH.Z * sin, 0, dirH.X * sin + dirH.Z * cos)

		-- Part 중심: origin에서 range/2 만큼 세그먼트 방향으로
		local centerPos =
			Vector3.new(origin.X + segDir.X * config.range / 2, PART_Y, origin.Z + segDir.Z * config.range / 2)

		part.CFrame = CFrame.lookAt(centerPos, centerPos + segDir)
	end
end

function ConeIndicator:show()
	for _, part in self._parts :: { BasePart } do
		part.Transparency = TRANSPARENCY -- self._part → part
	end
end

function ConeIndicator:hide()
	for _, part in self._parts :: { BasePart } do
		part.Transparency = 1 -- self._part → part
	end
end

function ConeIndicator:destroy()
	for _, part in self._parts :: { BasePart } do
		part:Destroy()
	end
	self._parts = {}
end

return ConeIndicator
