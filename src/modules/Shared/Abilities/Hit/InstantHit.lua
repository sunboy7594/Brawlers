--!strict
--[=[
	@class InstantHit

	범위 판정 유틸리티. 서버/클라이언트 공용.
	실제 데미지 적용(TakeDamage)은 서버에서만 호출할 것.

	지원 shape:
	- "cone":   부채꼴 (range, angle 필요)
	- "circle": 원형 (range 필요)
	- "line":   직선 (range, width 필요)
]=]

local InstantHit = {}

-- ─── 타입 정의 ───────────────────────────────────────────────────────────────

export type HitConfig = {
	shape: "cone" | "circle" | "line",
	range: number,
	angle: number?, -- cone 전용 (도 단위)
	width: number?, -- line 전용
	damage: number,
	knockback: number?,
	delay: number?, -- 생략 시 0 (즉시 판정), delay > 0이면 취소 함수 반환
}

-- ─── 내부 유틸 ───────────────────────────────────────────────────────────────

-- 구 범위 내 캐릭터를 수집합니다. 공격자 자신은 제외합니다.
local function getCharactersInSphere(origin: Vector3, range: number, attacker: Model): { Model }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attacker }

	local parts = workspace:GetPartBoundsInRadius(origin, range, params)
	local seen: { [Model]: boolean } = {}
	local result: { Model } = {}

	for _, part in parts do
		local char = part:FindFirstAncestorOfClass("Model")
		if not char or char == attacker or seen[char] then
			continue
		end
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			seen[char] = true
			table.insert(result, char)
		end
	end

	return result
end

-- 부채꼴 필터: 방향 기준 각도 내에 있는 캐릭터만 남깁니다.
local function filterCone(
	origin: Vector3,
	direction: Vector3,
	chars: { Model },
	range: number,
	angleDeg: number
): { Model }
	local halfRad = math.rad(angleDeg / 2)
	-- 수평 방향만 비교 (Y축 무시)
	local dirH = Vector3.new(direction.X, 0, direction.Z)
	if dirH.Magnitude < 0.001 then
		return chars
	end
	dirH = dirH.Unit

	local result: { Model } = {}
	for _, char in chars do
		local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then
			continue
		end

		local toTarget = rootPart.Position - origin
		local horizontal = Vector3.new(toTarget.X, 0, toTarget.Z)

		-- 거리 재검증 (수평 기준)
		if horizontal.Magnitude > range then
			continue
		end

		-- 아주 가까우면 각도 관계없이 적중 처리
		if horizontal.Magnitude < 0.001 then
			table.insert(result, char)
			continue
		end

		local dot = horizontal.Unit:Dot(dirH)
		local ang = math.acos(math.clamp(dot, -1, 1))
		if ang <= halfRad then
			table.insert(result, char)
		end
	end

	return result
end

-- 직선 필터: 직선 범위 내(폭 포함) 캐릭터만 남깁니다.
local function filterLine(
	origin: Vector3,
	direction: Vector3,
	chars: { Model },
	range: number,
	width: number
): { Model }
	local halfWidth = width / 2
	local dirH = Vector3.new(direction.X, 0, direction.Z)
	if dirH.Magnitude < 0.001 then
		return {}
	end
	dirH = dirH.Unit

	local result: { Model } = {}
	for _, char in chars do
		local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then
			continue
		end

		local toTarget = rootPart.Position - origin
		local toTargetH = Vector3.new(toTarget.X, 0, toTarget.Z)

		-- 전방 투영 거리
		local forward = toTargetH:Dot(dirH)
		if forward < 0 or forward > range then
			continue
		end

		-- 직선에서의 수직 거리
		local side = (toTargetH - dirH * forward).Magnitude
		if side <= halfWidth then
			table.insert(result, char)
		end
	end

	return result
end

-- 데미지 및 넉백을 적용합니다. 서버에서만 실제 효과가 발생합니다.
local function applyEffects(attacker: Model, hits: { Model }, config: HitConfig)
	for _, char in hits do
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:TakeDamage(config.damage)
		end

		-- 넉백 적용 (HumanoidRootPart에 임펄스)
		local knockback = config.knockback
		if knockback and knockback > 0 then
			local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local attackerRoot = attacker:FindFirstChild("HumanoidRootPart") :: BasePart?
			if rootPart and attackerRoot then
				local dir = (rootPart.Position - attackerRoot.Position)
				local dirH = Vector3.new(dir.X, 0, dir.Z)
				if dirH.Magnitude > 0.001 then
					rootPart:ApplyImpulse(dirH.Unit * knockback * (rootPart.AssemblyMass))
				end
			end
		end
	end
end

-- shape에 따라 판정을 수행하고 적중 캐릭터 목록을 반환합니다.
local function doHit(attacker: Model, origin: Vector3, direction: Vector3, config: HitConfig): { Model }
	local candidates = getCharactersInSphere(origin, config.range, attacker)

	local hits: { Model }
	if config.shape == "cone" then
		hits = filterCone(origin, direction, candidates, config.range, config.angle or 90)
	elseif config.shape == "line" then
		hits = filterLine(origin, direction, candidates, config.range, config.width or 2)
	else
		-- circle: 이미 구 범위 내에 있으므로 그대로 사용
		hits = candidates
	end

	applyEffects(attacker, hits, config)
	return hits
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	범위 판정을 실행합니다.

	delay == 0 또는 생략: 즉시 판정 후 적중 캐릭터 목록({ Model }) 반환.
	delay > 0: 지연 판정 예약 후 취소 함수(() -> ()) 반환. 스킬 중단 시 취소 함수를 호출하세요.

	@param attacker Model     공격자 (자기 자신 제외)
	@param origin Vector3     판정 기준점
	@param direction Vector3  공격 방향 (정규화 권장)
	@param config HitConfig
	@return { Model } | () -> ()
]=]
function InstantHit.apply(
	attacker: Model,
	origin: Vector3,
	direction: Vector3,
	config: HitConfig
): { Model } | (() -> ())
	local delay = config.delay or 0

	if delay <= 0 then
		-- 즉시 판정
		return doHit(attacker, origin, direction, config)
	else
		-- 지연 판정: 취소 가능한 예약
		local cancelled = false

		task.delay(delay, function()
			if cancelled then
				return
			end
			doHit(attacker, origin, direction, config)
		end)

		-- 취소 함수 반환
		return function()
			cancelled = true
		end
	end
end

return InstantHit
