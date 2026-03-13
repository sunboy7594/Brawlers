--!strict
--[=[
    @class AnimationControllerClient

    Motor6D 기반 애니메이션 레이어 + 큐 시스템 (Procedural Animation)

    레이어 우선순위:
    - Layer 0 (BASE)     : idle, walk, run
    - Layer 1 (ACTION)   : climb, swim, roll
    - Layer 2 (OVERRIDE) : attack, interact

    Spring 변환 상수 (시각적으로 맞지 않으면 아래 두 상수만 조정):
    - SPRING_SPEED_SCALE  : sqrt(stiffness) * SCALE → Nevermore Speed
    - SPRING_DAMPER_SCALE : damping * SCALE → Nevermore Damper
]=]

local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local Spring = require("Spring")
local RunService = game:GetService("RunService")

-- ─── Spring 변환 상수 ─────────────────────────────────────────────────────────
-- stiffness=200 → Speed≈20, damping=1.6 → Damper≈1.0
local SPRING_SPEED_SCALE = 1.41
local SPRING_DAMPER_SCALE = 0.625

-- ─── 서비스 ──────────────────────────────────────────────────────────────────

local AnimationControllerClient = {}
AnimationControllerClient.ServiceName = "AnimationControllerClient"

AnimationControllerClient.Layer = {
	BASE = 0,
	ACTION = 1,
	OVERRIDE = 2,
}

type AnimEntry = {
	owner: string,
	layer: number,
	elapsed: number,
	duration: number,
	onUpdate: (joint: Motor6D, dt: number) -> (),
	onFinish: (() -> ())?,
}

-- CFrame 분해용 Spring 쌍 (Position: Vector3, Rotation: Vector3 euler)
type JointSprings = {
	pos: any, -- Spring<Vector3>
	rot: any, -- Spring<Vector3>
}

export type AnimationControllerClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_queue: { [Motor6D]: { AnimEntry } },
		_current: { [Motor6D]: AnimEntry },
		_defaultC0: { [Motor6D]: CFrame },
		_springs: { [Motor6D]: JointSprings },
		_modifiers: { [Motor6D]: { [string]: (CFrame, number) -> CFrame } },
		_cachedMoveDir: Vector3,
	},
	{} :: typeof({ __index = AnimationControllerClient })
))

function AnimationControllerClient.Init(self: AnimationControllerClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()

	local weakMeta = { __mode = "k" }
	self._queue = setmetatable({}, weakMeta)
	self._current = setmetatable({}, weakMeta)
	self._defaultC0 = setmetatable({}, weakMeta)
	self._springs = setmetatable({}, weakMeta)
	self._modifiers = setmetatable({}, weakMeta)
	self._cachedMoveDir = Vector3.new()
end

function AnimationControllerClient.Start(self: AnimationControllerClient): ()
	self._maid:GiveTask(RunService.RenderStepped:Connect(function(dt)
		self:_update(dt)
	end))
end

function AnimationControllerClient:RegisterJoint(joint: Motor6D)
	if not self._defaultC0[joint] then
		self._defaultC0[joint] = joint.C0
	end
	if not self._queue[joint] then
		self._queue[joint] = {}
	end
	-- Spring 쌍 초기화 (이미 있으면 재생성 안 함)
	if not self._springs[joint] then
		local rx0, ry0, rz0 = joint.C0:ToEulerAnglesXYZ()

		local posSpring = Spring.new(joint.C0.Position)
		posSpring.Speed = 20
		posSpring.Damper = 1

		local rotSpring = Spring.new(Vector3.new(rx0, ry0, rz0))
		rotSpring.Speed = 20
		rotSpring.Damper = 1

		self._springs[joint] = { pos = posSpring, rot = rotSpring }
	end
end

--[=[
	등록된 관절의 기본 C0를 반환합니다.
	AnimFactory에서 base로 사용하여 누적 회전을 방지합니다.
	@param joint Motor6D
	@return CFrame
]=]
function AnimationControllerClient:GetDefaultC0(joint: Motor6D): CFrame
	return self._defaultC0[joint] or joint.C0
end

--[=[
	HumanoidAnimatorClient가 매 프레임 호출해 캐싱된 로컬 이동 방향을 설정합니다.
	@param dir Vector3 -- 캐릭터 로컬 좌표계 기준 이동 방향
]=]
function AnimationControllerClient:SetMoveDir(dir: Vector3)
	self._cachedMoveDir = dir
end

--[=[
	프레임당 1회 캐싱된 로컬 이동 방향을 반환합니다.
	AnimDef 클로저에서 매 관절마다 직접 계산하는 대신 이 값을 사용하세요.
	@return Vector3
]=]
function AnimationControllerClient:GetMoveDir(): Vector3
	return self._cachedMoveDir
end

-- ─── 공개 API ─────────────────────────────────────────────────────────────────

function AnimationControllerClient:Play(
	owner: string,
	layer: number,
	joint: Motor6D,
	onUpdate: (joint: Motor6D, dt: number) -> (),
	duration: number?,
	onFinish: (() -> ())?
)
	self:RegisterJoint(joint)

	local entry: AnimEntry = {
		owner = owner,
		layer = layer,
		elapsed = 0,
		duration = duration or math.huge,
		onUpdate = onUpdate,
		onFinish = onFinish,
	}

	local current = self._current[joint]

	if not current then
		self._current[joint] = entry
	elseif layer > current.layer then
		table.insert(self._queue[joint], current)
		self._current[joint] = entry
	else
		local queue = self._queue[joint]
		local inserted = false
		for i, q in queue do
			if layer > q.layer then
				table.insert(queue, i, entry)
				inserted = true
				break
			end
		end
		if not inserted then
			table.insert(queue, entry)
		end
	end
end

function AnimationControllerClient:Stop(owner: string, joint: Motor6D)
	local current = self._current[joint]
	if current and current.owner == owner then
		if current.onFinish then
			current.onFinish()
		end
		self:_playNext(joint)
		return
	end

	local queue = self._queue[joint]
	if queue then
		for i, entry in ipairs(queue) do
			if entry.owner == owner then
				table.remove(queue, i)
				break
			end
		end
	end
end

function AnimationControllerClient:StopAll(owner: string, joints: { Motor6D })
	for _, joint in joints do
		self:Stop(owner, joint)
	end
end

function AnimationControllerClient:ApplyImpulse(joint: Motor6D, velocityImpulse: Vector3)
	local springs = self._springs[joint]
	if not springs then
		return
	end
	springs.pos:Impulse(velocityImpulse)
end

function AnimationControllerClient:SetModifier(
	owner: string,
	joint: Motor6D,
	callback: (current: CFrame, dt: number) -> CFrame
)
	self:RegisterJoint(joint)

	if not self._modifiers[joint] then
		self._modifiers[joint] = {}
	end
	self._modifiers[joint][owner] = callback
end

function AnimationControllerClient:RemoveModifier(owner: string, joint: Motor6D)
	if self._modifiers[joint] then
		self._modifiers[joint][owner] = nil
	end
end

-- ─── 내부: 업데이트 루프 ──────────────────────────────────────────────────────

function AnimationControllerClient:_playNext(joint: Motor6D)
	local queue = self._queue[joint]
	if queue and #queue > 0 then
		self._current[joint] = table.remove(queue, 1)
	else
		self._current[joint] = nil
	end
end

function AnimationControllerClient:_update(dt: number)
	-- 현재 재생 중인 애니메이션 업데이트
	for joint, entry in self._current do
		entry.elapsed += dt
		entry.onUpdate(joint, dt)

		if entry.elapsed >= entry.duration then
			if entry.onFinish then
				entry.onFinish()
			end
			self:_playNext(joint)
		end
	end

	-- 대기 중인 애니메이션 시간 경과 (duration 만료 체크)
	for _, queue in self._queue do
		for i = #queue, 1, -1 do
			local entry = queue[i]
			entry.elapsed += dt
			if entry.elapsed >= entry.duration then
				if entry.onFinish then
					entry.onFinish()
				end
				table.remove(queue, i)
			end
		end
	end

	-- 현재 애니메이션 없는 관절 → 기본 포즈로 spring 복귀
	for joint, defaultC0 in self._defaultC0 do
		if not self._current[joint] then
			self:spring(joint, defaultC0, 200, 0.8, dt)
		end
	end

	-- modifier 적용
	for joint, modifiers in self._modifiers do
		for _, callback in modifiers do
			if callback then
				joint.C0 = callback(joint.C0, dt)
			end
		end
	end
end

-- ─── 유틸리티 ────────────────────────────────────────────────────────────────

function AnimationControllerClient.angle(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x or 0), math.rad(y or 0), math.rad(z or 0))
end

function AnimationControllerClient:lerp(joint: Motor6D, targetC0: CFrame, lerpSpeed: number, dt: number)
	local alpha = 1 - math.exp(-lerpSpeed * dt * 60)
	joint.C0 = joint.C0:Lerp(targetC0, alpha)
end

--[=[
	Nevermore Spring을 이용해 joint.C0를 targetC0 방향으로 부드럽게 이동시킵니다.
]=]
function AnimationControllerClient:spring(
	joint: Motor6D,
	targetC0: CFrame,
	speed: number,
	damper: number,
	_dt: number -- Nevermore Spring은 lazy evaluation으로 dt 불필요, 시그니처 호환용
)
	self:RegisterJoint(joint)

	local springs = self._springs[joint]

	springs.pos.Speed = speed
	springs.pos.Damper = damper
	springs.rot.Speed = speed
	springs.rot.Damper = damper

	-- targetC0 분해 → Spring 타겟 설정
	local tx, ty, tz = targetC0:ToEulerAnglesXYZ()
	springs.pos.Target = targetC0.Position
	springs.rot.Target = Vector3.new(tx, ty, tz)

	-- Spring Position 읽기 (lazy evaluation: 내부적으로 현재 시각 기준 계산)
	local p = springs.pos.Position
	local r = springs.rot.Position

	joint.C0 = CFrame.new(p) * CFrame.fromEulerAnglesXYZ(r.X, r.Y, r.Z)
end

function AnimationControllerClient.Destroy(self: AnimationControllerClient)
	self._maid:Destroy()
end

return AnimationControllerClient
