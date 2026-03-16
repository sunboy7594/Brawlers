--!strict
--[=[
	@class InstantHit

	범위 판정 유틸리티. 서버 전용.

	변경 이력:
	- applyEffects: humanoid:TakeDamage() → HpService:ApplyDamage() 위임.
	  Player 캐릭터면 HpService, NPC면 기존 TakeDamage 유지.
	- init(hpService): HpService 인스턴스 주입. HpService.Init에서 단 1회 호출.

	HpService 주입 이유:
	InstantHit은 ServiceBag 외부 유틸 모듈이므로 GetService를 쓸 수 없음.
	HpService가 자신의 Init에서 InstantHit.init(self)를 호출하여 인스턴스를 전달.

	지원 shape:
	- "cone":   부채꼴 (range, angle 필요)
	- "circle": 원형 (range 필요)
	- "line":   직선 (range, width 필요)

	apply() 반환값:
	- 항상 취소함수 () -> () 반환 (delay 없어도 동일)
	- onHit 콜백: 판정 완료 시점에 호출 (delay 있든 없든)
]=]

local Players = game:GetService("Players")

local InstantHit = {}

-- HpService 인스턴스 (HpService.Init에서 주입됨)
local _hpService: any = nil

-- ─── 타입 정의 ───────────────────────────────────────────────────────────────

export type HitConfig = {
	shape: "cone" | "circle" | "line",
	range: number,
	angle: number?, -- cone 전용 (도 단위)
	width: number?, -- line 전용
	damage: number,
	knockback: number?,
	delay: number?, -- 생략 시 0 (즉시 판정)
}

-- ─── 주입 API ────────────────────────────────────────────────────────────────

--[=[
	HpService 인스턴스를 주입합니다.
	HpService.Init에서 단 1회 호출. 그 외에서는 호출하지 말 것.
]=]
function InstantHit.init(hpService: any)
	_hpService = hpService
end

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

-- 부채꼴 필터
local function filterCone(
	origin: Vector3,
	direction: Vector3,
	chars: { Model },
	range: number,
	angleDeg: number
): { Model }
	local halfRad = math.rad(angleDeg / 2)
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

		if horizontal.Magnitude > range then
			continue
		end

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

-- 직선 필터
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

		local forward = toTargetH:Dot(dirH)
		if forward < 0 or forward > range then
			continue
		end

		local side = (toTargetH - dirH * forward).Magnitude
		if side <= halfWidth then
			table.insert(result, char)
		end
	end

	return result
end

-- 대미지 및 넉백을 적용합니다.
-- Player 캐릭터 → HpService:ApplyDamage (HP 시스템 통합)
-- NPC           → humanoid:TakeDamage   (기존 방식 유지)
local function applyEffects(attacker: Model, hits: { Model }, config: HitConfig)
	for _, char in hits do
		-- HP 처리
		local player = Players:GetPlayerFromCharacter(char)
		if player and _hpService then
			_hpService:ApplyDamage(player, config.damage)
		else
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:TakeDamage(config.damage)
			end
		end

		-- 넉백
		local knockback = config.knockback
		if knockback and knockback > 0 then
			local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local attackerRoot = attacker:FindFirstChild("HumanoidRootPart") :: BasePart?
			if rootPart and attackerRoot then
				local dir = rootPart.Position - attackerRoot.Position
				local dirH = Vector3.new(dir.X, 0, dir.Z)
				if dirH.Magnitude > 0.001 then
					rootPart:ApplyImpulse(dirH.Unit * knockback * rootPart.AssemblyMass)
				end
			end
		end
	end
end

-- shape에 따라 판정 후 적중 목록 반환
local function doHit(attacker: Model, origin: Vector3, direction: Vector3, config: HitConfig): { Model }
	local candidates = getCharactersInSphere(origin, config.range, attacker)

	local hits: { Model }
	if config.shape == "cone" then
		hits = filterCone(origin, direction, candidates, config.range, config.angle or 90)
	elseif config.shape == "line" then
		hits = filterLine(origin, direction, candidates, config.range, config.width or 2)
	else
		-- circle
		hits = candidates
	end

	applyEffects(attacker, hits, config)
	return hits
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	범위 판정을 실행합니다.

	항상 취소함수 () -> () 를 반환합니다.
	- delay 없음: 즉시 판정 후 onHit 호출, 반환된 취소함수는 no-op
	- delay > 0: 지연 판정 예약, 취소함수 호출 시 판정 취소

	onHit: 판정 완료 시점에 호출되는 콜백. victims: { Model }을 받음.
	       nil이면 판정만 하고 콜백 없음.
]=]
function InstantHit.apply(
	attacker: Model,
	origin: Vector3,
	direction: Vector3,
	config: HitConfig,
	onHit: ((victims: { Model }) -> ())?
): () -> ()
	local delay = config.delay or 0

	local function execute()
		local hits = doHit(attacker, origin, direction, config)
		if onHit then
			onHit(hits)
		end
	end

	if delay <= 0 then
		execute()
		return function() end -- no-op
	else
		local cancelled = false

		task.delay(delay, function()
			if cancelled then
				return
			end
			execute()
		end)

		return function()
			cancelled = true
		end
	end
end

return InstantHit
