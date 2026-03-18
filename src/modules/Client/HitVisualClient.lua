--!strict
--[=[
	@class HitVisualClient

	히트 비주얼 클라이언트 서비스.

	HitVisualRemoting.HitVisual 수신 시:
	- 공격자 팀 인덱스를 기반으로 색상 결정
	  (내 팀=파랑, 적팀=인덱스 순 빨강~노랑, 팀없음모드=자신파랑/나머지빨강)
	- 각 shape별로 직육면체 파트 세그먼트 생성
	- 세그먼트마다 진행방향으로 독립 Raycast(wallCheck=true인 shape만)
	- SurfaceGui + UIGradient로 sweep 애니메이션
	- 0.25초 후 파트 전체 소멸

	그라디언트 sweep 방식:
	- UIGradient Transparency: [0:1, 0.35:0.3, 0.65:0.3, 1:1] (중앙 불투명 밴드)
	- Offset을 Vector2(-0.65,0) → Vector2(0.65,0)로 TweenService 이동
	  → 밴드가 파트 앞→뒤 방향으로 sweep

	수직면(end cap) 처리:
	- Back face(출발점): 단색, 불투명 → 투명 Tween
	- Front face(끝점): 단색, 투명 → 불투명 Tween

	파트 두께 프리셋:
	- "Thick" = 2.5 스터드
	- "Normal" = 1.5 스터드
	- "Thin" = 0.5 스터드
	- 숫자: 직접 스터드 값

	파트 높이 모드:
	- "Floor": 파트 바닥면이 지면과 맞닿게 (Raycast로 지면 탐지)
	- "Air": HRP Y 기준 파트 중앙 정렬
	- 숫자: HRP Y + 오프셋 기준 파트 중앙

	색상 팔레트 (적팀, 내팀 제외 인덱스 순):
	- 1번째 적팀: 빨강  (1, 0.2, 0.2)
	- 2번째 적팀: 주황  (1, 0.5, 0.1)
	- 3번째 적팀: 노랑  (1, 0.9, 0.1)
	- 4번째 적팀: 분홍  (1, 0.4, 0.7)
	- 이후: 빨강으로 순환
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local HitVisualRemoting = require("HitVisualRemoting")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local DURATION = 0.25 -- 전체 연출 시간 (초)

-- 최대 불투명도 (0=완전불투명, 0.3=약간투명)
local MAX_TRANSPARENCY = 0.3

-- 두께 프리셋 (스터드)
local THICK_PRESETS = {
	Thick = 2.5,
	Normal = 1.5,
	Thin = 0.5,
}

-- 세그먼트 수 (cone/circle)
local CONE_SEGMENTS = 10
local CIRCLE_SEGMENTS = 16

-- 지면 감지 Raycast 거리
local FLOOR_RAYCAST_DIST = 50

-- 적팀 색상 팔레트
local ENEMY_COLORS: { Color3 } = {
	Color3.new(1, 0.2, 0.2), -- 빨강
	Color3.new(1, 0.5, 0.1), -- 주황
	Color3.new(1, 0.9, 0.1), -- 노랑
	Color3.new(1, 0.4, 0.7), -- 분홍
}

local MY_TEAM_COLOR = Color3.new(0.2, 0.5, 1) -- 파랑
local NO_TEAM_ENEMY_COLOR = Color3.new(1, 0.2, 0.2) -- 팀없음 모드 적 색상

-- UIGradient 투명도 시퀀스 (중앙 불투명 밴드)
local GRADIENT_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.35, MAX_TRANSPARENCY),
	NumberSequenceKeypoint.new(0.65, MAX_TRANSPARENCY),
	NumberSequenceKeypoint.new(1, 1),
})

-- Sweep 시작/끝 Offset
local SWEEP_START = Vector2.new(-0.65, 0)
local SWEEP_END = Vector2.new(0.65, 0)

-- Sweep TweenInfo
local SWEEP_TWEEN_INFO = TweenInfo.new(DURATION, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)

-- End cap TweenInfo
local CAP_TWEEN_INFO = TweenInfo.new(DURATION, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)

-- 벽 체크 RaycastParams
local WALL_RAYCAST_PARAMS = RaycastParams.new()
WALL_RAYCAST_PARAMS.CollisionGroup = "HitCheck"

-- ─── 서비스 타입 ─────────────────────────────────────────────────────────────

export type HitVisualClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
	},
	{} :: typeof({ __index = {} })
))

local HitVisualClient = {}
HitVisualClient.ServiceName = "HitVisualClient"
HitVisualClient.__index = HitVisualClient

-- ─── 초기화 ──────────────────────────────────────────────────────────────────

function HitVisualClient.Init(self: HitVisualClient, serviceBag: ServiceBag.ServiceBag): ()
	self._serviceBag = serviceBag
	self._maid = Maid.new()
end

function HitVisualClient.Start(self: HitVisualClient): ()
	self._maid:GiveTask(HitVisualRemoting.HitVisual:Connect(function(payload: unknown)
		self:_onHitVisual(payload)
	end))
end

-- ─── 색상 결정 ───────────────────────────────────────────────────────────────

--[=[
	공격자 팀 인덱스 기반으로 색상 결정.
	attackerTeamIndex: nil → 팀없음 모드
]=]
local function resolveColor(attackerUserId: number, attackerTeamIndex: number?): Color3
	local localPlayer = Players.LocalPlayer

	-- 팀없음 모드
	if attackerTeamIndex == nil then
		if attackerUserId == localPlayer.UserId then
			return MY_TEAM_COLOR
		else
			return NO_TEAM_ENEMY_COLOR
		end
	end

	-- 내 팀 인덱스 추출 (팀 이름에서 숫자 파싱: "Team1" → 1)
	local myTeamIndex: number? = nil
	local myTeam = localPlayer.Team
	if myTeam then
		local n = tonumber(myTeam.Name:match("(%d+)$"))
		myTeamIndex = n
	end

	-- 내 팀이면 파랑
	if myTeamIndex and attackerTeamIndex == myTeamIndex then
		return MY_TEAM_COLOR
	end

	-- 적팀: 내 팀 인덱스를 제외한 순서로 색상 배정
	-- 최대 팀 수 추정: Teams 서비스 참조
	local Teams = game:GetService("Teams")
	local allTeams = Teams:GetTeams()
	table.sort(allTeams, function(a, b)
		local na = tonumber(a.Name:match("(%d+)$")) or 0
		local nb = tonumber(b.Name:match("(%d+)$")) or 0
		return na < nb
	end)

	local enemyOrder = 0
	for _, team in allTeams do
		local idx = tonumber(team.Name:match("(%d+)$"))
		if idx == myTeamIndex then
			continue
		end
		enemyOrder += 1
		if idx == attackerTeamIndex then
			local colorIdx = ((enemyOrder - 1) % #ENEMY_COLORS) + 1
			return ENEMY_COLORS[colorIdx]
		end
	end

	-- fallback
	return ENEMY_COLORS[1]
end

-- ─── 두께 해석 ───────────────────────────────────────────────────────────────

local function resolveThick(thick: any): number
	if type(thick) == "number" then
		return math.max(0.05, thick)
	elseif type(thick) == "string" then
		return THICK_PRESETS[thick] or THICK_PRESETS.Normal
	end
	return THICK_PRESETS.Normal
end

-- ─── 파트 Y 위치 계산 ────────────────────────────────────────────────────────

local function resolvePartY(origin: Vector3, thickStud: number, heightMode: any): number
	if type(heightMode) == "number" then
		-- HRP Y + 오프셋 기준 중앙
		return origin.Y + heightMode
	elseif heightMode == "Floor" then
		-- 지면 감지 후 파트 바닥면이 지면과 맞닿게
		local rayResult = workspace:Raycast(
			origin + Vector3.new(0, 1, 0),
			Vector3.new(0, -FLOOR_RAYCAST_DIST, 0),
			WALL_RAYCAST_PARAMS
		)
		local groundY = if rayResult then rayResult.Position.Y else (origin.Y - 3)
		-- 파트 중앙이 (지면Y + 두께/2)가 되도록
		return groundY + thickStud / 2
	else
		-- "Air": HRP Y가 파트 중앙
		return origin.Y
	end
end

-- ─── SurfaceGui 생성 헬퍼 ────────────────────────────────────────────────────

--[=[
	Sweep GUI: 진행방향과 평행한 면에 부착.
	UIGradient Offset을 SWEEP_START → SWEEP_END로 Tween.
	gradientDir에 따라 Rotation 및 Offset 방향 결정.
]=]
local function addSweepGui(part: BasePart, face: Enum.NormalId, color: Color3, gradientDir: string)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 50
	sg.AlwaysOnTop = false
	sg.Parent = part

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.Parent = sg

	local gradient = Instance.new("UIGradient")
	gradient.Transparency = GRADIENT_TRANSPARENCY
	gradient.Color = ColorSequence.new(color)

	-- gradientDir에 따른 Rotation 및 sweep 방향 결정
	-- Face별 좌표계:
	--   Top/Bottom: Rotation=0 → 수평(파트 X축), Rotation=90 → 수직(파트 Z축 방향)
	--   Front/Back/Left/Right: Rotation=0 → 수평

	-- "outward" 기본: 파트 앞방향(-Z)으로 sweep
	-- Face.Top: Rotation=90으로 Z방향 sweep, Offset.Y 이동
	-- Face.Bottom: Rotation=90, Offset.Y 이동 (방향 반전)
	-- Face.Left: Rotation=0, Offset.X 이동 (역방향)
	-- Face.Right: Rotation=0, Offset.X 이동

	local startOffset: Vector2
	local endOffset: Vector2
	local rotation: number

	if face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		rotation = 90
		if gradientDir == "outward" then
			-- Top: SurfaceGui +Y = 파트 -Z (forward/outward)
			-- 밴드가 backward→forward로 sweep: Offset.Y: -0.65 → 0.65
			startOffset = Vector2.new(0, -0.65)
			endOffset = Vector2.new(0, 0.65)
		elseif gradientDir == "inward" then
			startOffset = Vector2.new(0, 0.65)
			endOffset = Vector2.new(0, -0.65)
		elseif gradientDir == "up" then
			rotation = 0
			startOffset = Vector2.new(-0.65, 0)
			endOffset = Vector2.new(0.65, 0)
		else -- "down"
			rotation = 0
			startOffset = Vector2.new(0.65, 0)
			endOffset = Vector2.new(-0.65, 0)
		end
	elseif face == Enum.NormalId.Left then
		rotation = 0
		if gradientDir == "outward" then
			-- Left face: SurfaceGui +X = 파트 +Z (backward/inward)
			-- outward sweep: 오른쪽→왼쪽 (inward→outward)
			startOffset = Vector2.new(0.65, 0)
			endOffset = Vector2.new(-0.65, 0)
		elseif gradientDir == "inward" then
			startOffset = Vector2.new(-0.65, 0)
			endOffset = Vector2.new(0.65, 0)
		elseif gradientDir == "up" then
			rotation = 90
			startOffset = Vector2.new(0, -0.65)
			endOffset = Vector2.new(0, 0.65)
		else -- "down"
			rotation = 90
			startOffset = Vector2.new(0, 0.65)
			endOffset = Vector2.new(0, -0.65)
		end
	elseif face == Enum.NormalId.Right then
		rotation = 0
		if gradientDir == "outward" then
			-- Right face: SurfaceGui +X = 파트 -Z (forward/outward)
			startOffset = Vector2.new(-0.65, 0)
			endOffset = Vector2.new(0.65, 0)
		elseif gradientDir == "inward" then
			startOffset = Vector2.new(0.65, 0)
			endOffset = Vector2.new(-0.65, 0)
		elseif gradientDir == "up" then
			rotation = 90
			startOffset = Vector2.new(0, -0.65)
			endOffset = Vector2.new(0, 0.65)
		else -- "down"
			rotation = 90
			startOffset = Vector2.new(0, 0.65)
			endOffset = Vector2.new(0, -0.65)
		end
	else
		-- fallback
		rotation = 0
		startOffset = SWEEP_START
		endOffset = SWEEP_END
	end

	gradient.Rotation = rotation
	gradient.Offset = startOffset
	gradient.Parent = frame

	-- Tween: Offset sweep
	local tween = TweenService:Create(gradient, SWEEP_TWEEN_INFO, { Offset = endOffset })
	tween:Play()
end

--[=[
	End cap GUI: 진행방향과 수직인 면(앞/뒷면)에 부착.
	Back face(출발점): 불투명→투명 (fade out)
	Front face(끝점): 투명→불투명 (fade in)
]=]
local function addCapGui(part: BasePart, face: Enum.NormalId, color: Color3, isFront: boolean)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 50
	sg.AlwaysOnTop = false
	sg.Parent = part

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Parent = sg

	local startT: number
	local endT: number
	if isFront then
		-- 끝면: 투명→불투명
		startT = 1
		endT = MAX_TRANSPARENCY
	else
		-- 출발면: 불투명→투명
		startT = MAX_TRANSPARENCY
		endT = 1
	end

	frame.BackgroundTransparency = startT
	local tween = TweenService:Create(frame, CAP_TWEEN_INFO, { BackgroundTransparency = endT })
	tween:Play()
end

-- ─── 파트 생성 ───────────────────────────────────────────────────────────────

--[=[
	기본 비주얼 파트 생성.
	size: Vector3 (length, thickness, width)
	cf:   CFrame (위치 + 방향)
]=]
local function createPart(size: Vector3, cf: CFrame): BasePart
	local part = Instance.new("Part")
	part.Size = size
	part.CFrame = cf
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	-- 파트 자체는 완전 투명, SurfaceGui만 보임
	part.Transparency = 1
	part.Parent = workspace
	return part
end

--[=[
	세그먼트에 SurfaceGui 적용.
	isFirst: 출발 방향 쪽 끝 세그먼트 (Back cap 추가)
	isLast:  도착 방향 쪽 끝 세그먼트 (Front cap 추가)
	addLeftFace/addRightFace: 콘 끝 세그먼트에 측면 추가
]=]
local function applySegmentGui(
	part: BasePart,
	color: Color3,
	gradientDir: string,
	isFirst: boolean,
	isLast: boolean,
	addLeftFace: boolean?,
	addRightFace: boolean?
)
	-- 진행방향 평행면 (Top, Bottom)은 항상 sweep
	addSweepGui(part, Enum.NormalId.Top, color, gradientDir)
	addSweepGui(part, Enum.NormalId.Bottom, color, gradientDir)

	-- 측면 sweep (콘 끝 세그먼트)
	if addLeftFace then
		addSweepGui(part, Enum.NormalId.Left, color, gradientDir)
	end
	if addRightFace then
		addSweepGui(part, Enum.NormalId.Right, color, gradientDir)
	end

	-- End caps
	if isFirst then
		-- Back face = 출발점 → fade out
		addCapGui(part, Enum.NormalId.Back, color, false)
	end
	if isLast then
		-- Front face = 끝점 → fade in
		addCapGui(part, Enum.NormalId.Front, color, true)
	end
end

-- ─── 세그먼트별 벽 거리 계산 ─────────────────────────────────────────────────

--[=[
	세그먼트 방향으로 raycast해서 유효 거리 반환.
	wallCheck=false이면 maxRange 그대로 반환.
]=]
local function getEffectiveRange(origin: Vector3, segDir: Vector3, maxRange: number, wallCheck: boolean): number
	if not wallCheck then
		return maxRange
	end
	local result = workspace:Raycast(origin, segDir * maxRange, WALL_RAYCAST_PARAMS)
	if result then
		return math.max(0.1, result.Distance)
	end
	return maxRange
end

-- ─── Shape별 파트 생성 ───────────────────────────────────────────────────────

--[=[
	Cone 비주얼 파트 생성.
	segments를 angleMin~angleMax 사이에 균등 배치.
]=]
local function spawnCone(
	origin: Vector3,
	direction: Vector3,
	config: {
		range: number?,
		angleMin: number?,
		angleMax: number?,
		innerRadius: number?,
		wallCheck: boolean?,
	},
	color: Color3,
	thickStud: number,
	partY: number,
	gradientDir: string
): { BasePart }
	local range = config.range or 8
	local angleMin = config.angleMin or -45
	local angleMax = config.angleMax or 45
	local innerRange = config.innerRadius or 0 -- cone에서는 innerRadius를 innerRange로 사용
	local wallCheck = config.wallCheck ~= false

	-- 수평 방향 정규화
	local dirH = Vector3.new(direction.X, 0, direction.Z)
	if dirH.Magnitude < 0.001 then
		dirH = Vector3.new(0, 0, -1)
	else
		dirH = dirH.Unit
	end

	local parts: { BasePart } = {}
	local angleStep = (angleMax - angleMin) / CONE_SEGMENTS

	for i = 0, CONE_SEGMENTS - 1 do
		-- 세그먼트 중앙 각도
		local midAngle = angleMin + angleStep * (i + 0.5)
		local rad = math.rad(midAngle)

		-- 세그먼트 방향 (Y축 회전)
		local cosA = math.cos(rad)
		local sinA = math.sin(rad)
		local segDir = Vector3.new(dirH.X * cosA - dirH.Z * sinA, 0, dirH.X * sinA + dirH.Z * cosA)

		-- 유효 거리
		local effectiveRange = getEffectiveRange(origin, segDir, range, wallCheck)
		local segLength = effectiveRange - innerRange
		if segLength <= 0 then
			continue
		end

		-- 파트 중앙 위치
		local centerDist = innerRange + segLength / 2
		local centerXZ = Vector3.new(origin.X + segDir.X * centerDist, partY, origin.Z + segDir.Z * centerDist)

		-- 세그먼트 폭: 각도 범위를 외곽 반지름에서의 호 길이로 추정
		local angRad = math.rad(angleStep)
		local segWidth = effectiveRange * math.tan(angRad / 2) * 2 + 0.05

		-- 파트 크기: X=폭, Y=두께, Z=길이
		local partSize = Vector3.new(segWidth, thickStud, segLength)

		-- CFrame: 세그먼트 방향으로 lookAt
		local cf = CFrame.lookAt(centerXZ, centerXZ + segDir)

		local part = createPart(partSize, cf)

		local isFirst = (i == 0)
		local isLast = (i == CONE_SEGMENTS - 1)
		local addLeft = (i == 0) -- 가장 왼쪽 세그먼트
		local addRight = (i == CONE_SEGMENTS - 1) -- 가장 오른쪽 세그먼트

		-- innerRange > 0이면 Back cap 위치가 innerRange 지점
		applySegmentGui(part, color, gradientDir, isFirst, isLast, addLeft, addRight)

		table.insert(parts, part)
	end

	return parts
end

--[=[
	Circle 비주얼 파트 생성.
	innerRadius > 0이면 그라디언트 시작점이 innerRadius 지점.
]=]
local function spawnCircle(
	origin: Vector3,
	config: { radius: number?, innerRadius: number?, wallCheck: boolean? },
	color: Color3,
	thickStud: number,
	partY: number,
	gradientDir: string
): { BasePart }
	local radius = config.radius or 5
	local innerRadius = config.innerRadius or 0
	local wallCheck = config.wallCheck ~= false

	local parts: { BasePart } = {}
	local angleStep = 360 / CIRCLE_SEGMENTS

	for i = 0, CIRCLE_SEGMENTS - 1 do
		local midAngle = angleStep * (i + 0.5)
		local rad = math.rad(midAngle)

		local segDir = Vector3.new(math.sin(rad), 0, math.cos(rad))

		local effectiveRadius = getEffectiveRange(origin, segDir, radius, wallCheck)
		local segLength = effectiveRadius - innerRadius
		if segLength <= 0 then
			continue
		end

		local centerDist = innerRadius + segLength / 2
		local centerXZ = Vector3.new(origin.X + segDir.X * centerDist, partY, origin.Z + segDir.Z * centerDist)

		-- 세그먼트 폭: 외곽 반지름 기준 호 길이
		local angRad = math.rad(angleStep)
		local segWidth = effectiveRadius * math.tan(angRad / 2) * 2 + 0.05

		local partSize = Vector3.new(segWidth, thickStud, segLength)
		local cf = CFrame.lookAt(centerXZ, centerXZ + segDir)

		local part = createPart(partSize, cf)

		-- Circle은 좌우 측면이 인접 세그먼트와 맞닿으므로 Top/Bottom만
		-- First/Last cap은 원이므로 적용 안 함 (연속 링)
		applySegmentGui(part, color, gradientDir, false, false, false, false)

		table.insert(parts, part)
	end

	return parts
end

--[=[
	Line 비주얼 파트 생성.
]=]
local function spawnLine(
	origin: Vector3,
	direction: Vector3,
	config: { range: number?, width: number?, wallCheck: boolean? },
	color: Color3,
	thickStud: number,
	partY: number,
	gradientDir: string
): { BasePart }
	local range = config.range or 10
	local width = config.width or 2
	local wallCheck = config.wallCheck ~= false

	local dirH = Vector3.new(direction.X, 0, direction.Z)
	if dirH.Magnitude < 0.001 then
		dirH = Vector3.new(0, 0, -1)
	else
		dirH = dirH.Unit
	end

	local effectiveRange = getEffectiveRange(origin, dirH, range, wallCheck)
	local centerXZ = Vector3.new(origin.X + dirH.X * effectiveRange / 2, partY, origin.Z + dirH.Z * effectiveRange / 2)

	local partSize = Vector3.new(width, thickStud, effectiveRange)
	local cf = CFrame.lookAt(centerXZ, centerXZ + dirH)

	local part = createPart(partSize, cf)
	applySegmentGui(part, color, gradientDir, true, true, false, false)

	return { part }
end

--[=[
	Arc 비주얼 파트 생성. (착탄 원형)
]=]
local function spawnArc(
	origin: Vector3,
	direction: Vector3,
	config: { range: number?, arcRadius: number?, wallCheck: boolean? },
	color: Color3,
	thickStud: number,
	partY: number,
	gradientDir: string
): { BasePart }
	local range = config.range or 20
	local arcRadius = config.arcRadius or 3

	local dirH = Vector3.new(direction.X, 0, direction.Z)
	if dirH.Magnitude < 0.001 then
		dirH = Vector3.new(0, 0, -1)
	else
		dirH = dirH.Unit
	end

	-- 착탄 지점을 origin으로 사용
	local landingOrigin = Vector3.new(origin.X + dirH.X * range, origin.Y, origin.Z + dirH.Z * range)

	-- Circle과 동일한 방식으로 착탄 원형 생성
	return spawnCircle(
		landingOrigin,
		{ radius = arcRadius, innerRadius = 0, wallCheck = false },
		color,
		thickStud,
		partY,
		gradientDir
	)
end

-- ─── 메인 핸들러 ─────────────────────────────────────────────────────────────

function HitVisualClient:_onHitVisual(payload: unknown)
	if type(payload) ~= "table" then
		return
	end
	local data = payload :: {
		attackerUserId: number,
		attackerTeamIndex: number?,
		origin: Vector3,
		direction: Vector3,
		hitMap: { [string]: { shape: string, [string]: any } },
		visualConfig: { thick: any, heightMode: any, gradientDir: string },
	}

	-- 유효성 검사
	if typeof(data.origin) ~= "Vector3" then
		return
	end
	if typeof(data.direction) ~= "Vector3" then
		return
	end
	if type(data.hitMap) ~= "table" then
		return
	end
	if type(data.visualConfig) ~= "table" then
		return
	end

	local color = resolveColor(data.attackerUserId, data.attackerTeamIndex)
	local thickStud = resolveThick(data.visualConfig.thick)
	local gradientDir = data.visualConfig.gradientDir or "outward"

	-- 이 공격에서 생성된 모든 파트 추적 (DURATION 후 삭제)
	local allParts: { BasePart } = {}

	for _, config in data.hitMap do
		if type(config) ~= "table" then
			continue
		end

		-- 파트 Y 위치 (shape별로 독립 계산)
		local partY = resolvePartY(data.origin, thickStud, data.visualConfig.heightMode)

		local newParts: { BasePart }
		local shape = config.shape

		if shape == "cone" then
			newParts = spawnCone(data.origin, data.direction, config, color, thickStud, partY, gradientDir)
		elseif shape == "circle" then
			newParts = spawnCircle(data.origin, config, color, thickStud, partY, gradientDir)
		elseif shape == "line" then
			newParts = spawnLine(data.origin, data.direction, config, color, thickStud, partY, gradientDir)
		elseif shape == "arc" then
			newParts = spawnArc(data.origin, data.direction, config, color, thickStud, partY, gradientDir)
		else
			newParts = {}
		end

		for _, p in newParts do
			table.insert(allParts, p)
		end
	end

	-- DURATION 후 파트 전체 삭제
	if #allParts > 0 then
		task.delay(DURATION, function()
			for _, part in allParts do
				if part and part.Parent then
					part:Destroy()
				end
			end
		end)
	end
end

-- ─── 소멸 ────────────────────────────────────────────────────────────────────

function HitVisualClient.Destroy(self: HitVisualClient)
	self._maid:Destroy()
end

return HitVisualClient
