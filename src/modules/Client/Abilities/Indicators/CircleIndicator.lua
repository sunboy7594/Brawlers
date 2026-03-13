--!strict
--[=[
	@class CircleIndicator

	원형 범위를 시각화하는 인디케이터.
	Cylinder shape Part를 사용합니다.

	config: { range: number }
	색상: 주황색
]=]

local require = require(script.Parent.loader).load(script)

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local PART_Y = 0.06 -- 지형 고저차 없음, 점프 없음 → Y 고정
local COLOR = Color3.fromRGB(255, 140, 0) -- 주황색
local TRANSPARENCY = 0.45
local PART_HEIGHT = 0.15 -- Cylinder 높이

-- ─── 타입 정의 ───────────────────────────────────────────────────────────────

export type CircleIndicatorConfig = {
	range: number, -- 원 반지름
}

export type CircleIndicator = {
	_part: BasePart,
	_config: CircleIndicatorConfig,
	update: (self: CircleIndicator, origin: Vector3, direction: Vector3) -> (),
	show: (self: CircleIndicator) -> (),
	hide: (self: CircleIndicator) -> (),
	destroy: (self: CircleIndicator) -> (),
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

local CircleIndicator = {}
CircleIndicator.__index = CircleIndicator

function CircleIndicator.new(config: CircleIndicatorConfig): CircleIndicator
	local self = setmetatable({} :: any, CircleIndicator)
	self._config = config

	-- Cylinder: 직경 = range * 2, 높이 = PART_HEIGHT
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Neon
	part.Color = COLOR
	part.Transparency = TRANSPARENCY
	part.Size = Vector3.new(PART_HEIGHT, config.range * 2, config.range * 2)
	part.Visible = false
	part.Parent = getIndicatorsFolder()

	self._part = part
	return self
end

-- 매 프레임 호출: origin을 중심으로 원형 인디케이터 위치를 갱신합니다.
-- direction은 원형이므로 위치 갱신에만 사용됩니다.
function CircleIndicator:update(origin: Vector3, _direction: Vector3)
	local config = self._config :: CircleIndicatorConfig
	local part = self._part :: BasePart
	-- Cylinder는 X축이 높이 방향이므로 눕히기 위해 Z축 90도 회전
	part.CFrame = CFrame.new(Vector3.new(origin.X, PART_Y, origin.Z))
		* CFrame.fromEulerAnglesXYZ(0, 0, math.pi / 2)
end

function CircleIndicator:show()
	(self._part :: BasePart).Visible = true
end

function CircleIndicator:hide()
	(self._part :: BasePart).Visible = false
end

function CircleIndicator:destroy()
	(self._part :: BasePart):Destroy()
end

return CircleIndicator
