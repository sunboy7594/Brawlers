--!strict
--[=[
	@class AbilityEffectControllerClient

	AbilityEffect 생명주기를 관리하는 핵심 클래스. (Client)

	역할:
	- 소환된 모델(part)과 수명 관리
	- Heartbeat 루프: move → hitDetect → onMove 순서로 매 프레임 실행
	- Hit / Miss / Destroy API 제공
	- _destroyNoMiss: FadeOut, Despawn 등 onMiss 없이 정리

	수명 흐름:
	  생성 → Heartbeat 루프
	    move() → false → onMiss() → _destroyNoMiss()
	    hitDetect() → HitInfo → onHit(handle, hitInfo)
	    _moveStopped = true → move 건너뜀, hitDetect 계속
	    _fadingOut = true → hitDetect 건너뜀
	  외부 강제 종료: Destroy() → onMiss 없이 정리
]=]

local require = require(script.Parent.loader).load(script)

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AbilityEffectHitDetectionUtil = require("AbilityEffectHitDetectionUtil")
local Maid = require("Maid")

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type HitRelation = AbilityEffectHitDetectionUtil.HitRelation
export type HitInfo = AbilityEffectHitDetectionUtil.HitInfo

export type MoveFunction = (dt: number, handle: any, params: { [string]: any }?) -> boolean
export type OnMoveCallback = (model: Model, dt: number) -> ()
export type HitCallback = (handle: any, hitInfo: HitInfo) -> ()
export type MissCallback = (handle: any) -> ()
export type ColorFilter = (model: Model, color: Color3) -> () -> ()

export type TeamContext = {
	attackerChar: Model?,
	attackerPlayer: Player?,
	color: Color3?,
	isEnemy: (a: Player, b: Player) -> boolean,
}

export type SpawnConfig = {
	offsetRange: (Vector3 | { Vector3 })?,
	directionRange: (Vector3 | { Vector3 })?,
}

export type AbilityEffectDef = {
	model: string?,
	move: MoveFunction?,
	onMove: OnMoveCallback?,
	onHit: HitCallback?,
	onMiss: MissCallback?,
	hitDetect: AbilityEffectHitDetectionUtil.HitDetectFunction?,
	colorFilter: ColorFilter?,
	spawnConfig: SpawnConfig?,
}

export type AbilityEffectHandle = typeof(setmetatable(
	{} :: {
		part: Model?,
		spawnCFrame: CFrame,
		isOwner: boolean,
		firedAt: number,
		_alive: boolean,
		_maid: any,
		_moveStopped: boolean,
		_fadingOut: boolean,
		_penetrateCount: number,
		_moveElapsed: number,
		_moveOrigin: Vector3,
		_moveDir: Vector3?,
		_sweepBase: CFrame?,
		_onHit: HitCallback?,
		_onMiss: MissCallback?,
		_teamContext: TeamContext?,
	},
	{} :: typeof({ __index = {} })
))

-- ─── 내부 유틸 ───────────────────────────────────────────────────────────────

local function randInRange(v: Vector3 | { Vector3 }): Vector3
	if typeof(v) == "Vector3" then
		local vv = v :: Vector3
		return Vector3.new(
			(math.random() * 2 - 1) * vv.X,
			(math.random() * 2 - 1) * vv.Y,
			(math.random() * 2 - 1) * vv.Z
		)
	else
		local arr = v :: { Vector3 }
		local a, b = arr[1], arr[2]
		return Vector3.new(
			a.X + math.random() * (b.X - a.X),
			a.Y + math.random() * (b.Y - a.Y),
			a.Z + math.random() * (b.Z - a.Z)
		)
	end
end

local function randDirection(base: Vector3, range: Vector3 | { Vector3 }): Vector3
	local euler = randInRange(range)
	local rot = CFrame.Angles(math.rad(euler.X), math.rad(euler.Y), math.rad(euler.Z))
	local result = (rot * CFrame.new(base)).LookVector
	return result.Magnitude > 0.001 and result.Unit or base
end

-- ─── 클래스 ──────────────────────────────────────────────────────────────────

local AbilityEffectControllerClient = {}
AbilityEffectControllerClient.__index = AbilityEffectControllerClient

function AbilityEffectControllerClient.new(
	def: AbilityEffectDef,
	origin: CFrame,
	color: Color3?,
	params: { [string]: any }?,
	isOwner: boolean?,
	teamContext: TeamContext?
): AbilityEffectHandle
	local self = setmetatable({}, AbilityEffectControllerClient) :: any
	self._alive = true
	self._maid = Maid.new()
	self.isOwner = isOwner ~= false
	self.firedAt = Workspace:GetServerTimeNow()
	self._moveStopped = false
	self._fadingOut = false
	self._penetrateCount = 0
	self._moveElapsed = 0
	self._onHit = def.onHit
	self._onMiss = def.onMiss
	self._teamContext = teamContext -- handle에 저장

	-- ─── spawnConfig 적용 ────────────────────────────────────────────────────
	local spawnCF = origin
	if def.spawnConfig then
		local sc = def.spawnConfig
		if sc.offsetRange then
			spawnCF = spawnCF * CFrame.new(randInRange(sc.offsetRange))
		end
		if sc.directionRange then
			local newDir = randDirection(spawnCF.LookVector, sc.directionRange)
			spawnCF = CFrame.new(spawnCF.Position, spawnCF.Position + newDir)
		end
	end
	self.spawnCFrame = spawnCF
	self._moveOrigin = spawnCF.Position

	-- ─── 모델 소환 ───────────────────────────────────────────────────────────
	if def.model then
		local effectsFolder = game:GetService("ReplicatedStorage"):FindFirstChild("AbilityEffects", true)
		local template = effectsFolder and effectsFolder:FindFirstChild(def.model)
		if template and template:IsA("Model") then
			local model = (template :: Model):Clone()
			model:PivotTo(spawnCF)
			model.Parent = workspace
			self.part = model
			self._maid:GiveTask(model)
			if def.colorFilter and color then
				local cleanup = def.colorFilter(model, color)
				if cleanup then
					self._maid:GiveTask(cleanup)
				end
			end
		end
	end

	-- ─── Heartbeat 루프 ──────────────────────────────────────────────────────
	local elapsed = 0

	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt: number)
		if not self._alive then
			conn:Disconnect()
			return
		end

		elapsed += dt
		self._moveElapsed = elapsed

		-- move
		if not self._moveStopped and def.move then
			local continues = def.move(dt, self, params)
			if not continues then
				conn:Disconnect()
				self:Miss()
				return
			end
		end

		-- onMove
		if def.onMove and self.part then
			def.onMove(self.part, dt)
		end

		-- hitDetect
		if not self._fadingOut and def.hitDetect then
			local hits = AbilityEffectHitDetectionUtil.Detect(
				def.hitDetect,
				elapsed,
				self, -- handle._teamContext에서 꺼냄
				params
			)
			for _, hitInfo in hits do
				if self._onHit then
					self._onHit(self, hitInfo)
				end
				if not self._alive then
					break
				end
			end
		end
	end)

	self._maid:GiveTask(conn)
	return self :: AbilityEffectHandle
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

function AbilityEffectControllerClient:IsAlive(): boolean
	return self._alive
end

function AbilityEffectControllerClient:Miss()
	if not self._alive then
		return
	end
	if self._onMiss then
		self._onMiss(self)
	end
	self:_destroyNoMiss()
end

function AbilityEffectControllerClient:_destroyNoMiss()
	if not self._alive then
		return
	end
	self._alive = false
	self._maid:Destroy()
end

function AbilityEffectControllerClient:Destroy()
	self:_destroyNoMiss()
end

return AbilityEffectControllerClient
