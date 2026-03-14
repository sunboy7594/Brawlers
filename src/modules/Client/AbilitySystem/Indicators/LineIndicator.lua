--!strict
--[=[
	@class LineIndicator

	직선(직사각형) 범위를 시각화하는 인디케이터.

	config: { range: number, width: number }
	색상: 하늘색
]=]

local require = require(script.Parent.loader).load(script)

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local PART_Y = 0.06 -- 지형 고저차 없음, 점프 없음 → Y 고정
local COLOR = Color3.fromRGB(0, 200, 255) -- 하늘색
local TRANSPARENCY = 0.45
local PART_HEIGHT = 0.15

-- ─── 타입 정의 ───────────────────────────────────────────────────────────────

export type LineIndicatorConfig = {
	range: number, -- 직선 길이
	width: number, -- 직선 폭
}

export type LineIndicator = {
	_part: BasePart,
	_config: LineIndicatorConfig,
	update: (self: LineIndicator, origin: Vector3, direction: Vector3) -> (),
	show: (self: LineIndicator) -> (),
	hide: (self: LineIndicator) -> (),
	destroy: (self: LineIndicator) -> (),
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

-- ─── 공개 API ────────────────────────────────────────────────────────────────

local LineIndicator = {}
LineIndicator.__index = LineIndicator

function LineIndicator.new(config: LineIndicatorConfig): LineIndicator
	local self = setmetatable({} :: any, LineIndicator)
	self._config = config

	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = COLOR
	part.Transparency = TRANSPARENCY
	part.Size = Vector3.new(config.width, PART_HEIGHT, config.range)
	part.Parent = getIndicatorsFolder()

	self._part = part
	return self
end

-- 매 프레임 호출: origin에서 direction 방향으로 직선 인디케이터 위치를 갱신합니다.
function LineIndicator:update(origin: Vector3, direction: Vector3)
	local config = self._config :: LineIndicatorConfig
	local part = self._part :: BasePart

	-- 수평 방향 정규화
	local dirH = Vector3.new(direction.X, 0, direction.Z)
	if dirH.Magnitude < 0.001 then
		return
	end
	dirH = dirH.Unit

	-- Part 중심: origin에서 range/2 만큼 앞
	local centerPos = Vector3.new(origin.X + dirH.X * config.range / 2, PART_Y, origin.Z + dirH.Z * config.range / 2)

	part.CFrame = CFrame.lookAt(centerPos, centerPos + dirH)
end

function LineIndicator:show()
	for _, part in self._parts :: { BasePart } do
		part.Transparency = TRANSPARENCY -- self._part → part
	end
end

function LineIndicator:hide()
	for _, part in self._parts :: { BasePart } do
		part.Transparency = 1 -- self._part → part
	end
end

function LineIndicator:destroy()
	(self._part :: BasePart):Destroy()
end

return LineIndicator
