--!strict
--[=[
	@class ArcIndicator

	포물선 착탄 지점을 예측하여 표시하는 인디케이터.
	Cylinder shape Part를 착탄 지점에 배치합니다.

	config: { maxRange: number, speed: number, gravity: number, radius: number }
	색상: 붉은색
]=]

local require = require(script.Parent.loader).load(script)

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local PART_Y = 0.06 -- 지형 고저차 없음, 점프 없음 → Y 고정
local COLOR = Color3.fromRGB(220, 50, 50) -- 붉은색
local TRANSPARENCY = 0.40
local CYLINDER_HEIGHT = 0.15 -- Cylinder 높이

-- ─── 타입 정의 ───────────────────────────────────────────────────────────────

export type ArcIndicatorConfig = {
	maxRange: number, -- 최대 도달 거리 (studs)
	speed: number,    -- 투사체 수평 속도 (studs/s)
	gravity: number,  -- 중력 가속도 (studs/s²)
	radius: number,   -- 착탄 지점 표시 반지름
}

export type ArcIndicator = {
	_part: BasePart,
	_config: ArcIndicatorConfig,
	update: (self: ArcIndicator, origin: Vector3, direction: Vector3) -> (),
	show: (self: ArcIndicator) -> (),
	hide: (self: ArcIndicator) -> (),
	destroy: (self: ArcIndicator) -> (),
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

-- ─── 포물선 착탄 지점 계산 ───────────────────────────────────────────────────

-- origin.Y 높이에서 수평 발사 시 지면(Y=0)에 닿는 거리를 계산합니다.
-- 지형 고저차 없음, 지면 Y = 0 가정.
local function calcLandingPos(
	origin: Vector3,
	direction: Vector3,
	speed: number,
	gravity: number,
	maxRange: number
): Vector3
	local startHeight = math.max(origin.Y, 0.01)

	-- 수직 운동: y = startHeight - 0.5 * g * t^2 = 0
	-- → t = sqrt(2 * startHeight / g)
	local fallTime = math.sqrt(2 * startHeight / gravity)
	local horizontal = math.min(speed * fallTime, maxRange)

	local dirH = Vector3.new(direction.X, 0, direction.Z)
	if dirH.Magnitude < 0.001 then
		return Vector3.new(origin.X, PART_Y, origin.Z)
	end
	dirH = dirH.Unit

	return Vector3.new(
		origin.X + dirH.X * horizontal,
		PART_Y,
		origin.Z + dirH.Z * horizontal
	)
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

local ArcIndicator = {}
ArcIndicator.__index = ArcIndicator

function ArcIndicator.new(config: ArcIndicatorConfig): ArcIndicator
	local self = setmetatable({} :: any, ArcIndicator)
	self._config = config

	-- 착탄 지점 표시용 Cylinder
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Neon
	part.Color = COLOR
	part.Transparency = TRANSPARENCY
	-- Cylinder: X축이 높이 방향, Y/Z가 반지름
	part.Size = Vector3.new(CYLINDER_HEIGHT, config.radius * 2, config.radius * 2)
	part.Visible = false
	part.Parent = getIndicatorsFolder()

	self._part = part
	return self
end

-- 매 프레임 호출: 포물선 착탄 지점을 계산하고 인디케이터를 이동합니다.
function ArcIndicator:update(origin: Vector3, direction: Vector3)
	local config = self._config :: ArcIndicatorConfig
	local part = self._part :: BasePart

	local landingPos = calcLandingPos(origin, direction, config.speed, config.gravity, config.maxRange)

	-- Cylinder를 눕히기 위해 Z축 90도 회전
	part.CFrame = CFrame.new(landingPos) * CFrame.fromEulerAnglesXYZ(0, 0, math.pi / 2)
end

function ArcIndicator:show()
	(self._part :: BasePart).Visible = true
end

function ArcIndicator:hide()
	(self._part :: BasePart).Visible = false
end

function ArcIndicator:destroy()
	(self._part :: BasePart):Destroy()
end

return ArcIndicator
