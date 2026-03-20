--!strict
--[=[
	@class ProjectileHit

	투사체 판정 유틸리티. 서버 전용.
	InstantHit.verdict()와 동일한 이름/패턴.

	ProjectileDef 필드:
	  move         : 이동 함수 (MoverUtil.Linear 등)
	  hitDetect    : 박스 판정 함수
	  onHitResult  : ((HitMapResult) -> ())?  → state.onHit (onHitChecked 트리거)
	  onHit        : ((handle, hitInfo) -> ())?  → HitOrMissUtil 시각 콜백 (Despawn 등)
	  onMiss       : ((handle) -> ())?
	  latency      : 레이턴시 보정값
	  delay        : 발사 지연

	delay + latency 보정:
	  effectiveDelay = max(0, delay - latency)
	  forwardTime    = max(0, latency - delay)
]=]

local require = require(script.Parent.loader).load(script)

local RunService = game:GetService("RunService")

local HitDetectionUtil = require("HitDetectionUtil")
local InstantHit       = require("InstantHit")
local Maid             = require("Maid")
local cancellableDelay = require("cancellableDelay")

export type ProjectileDef = {
	move         : (dt: number, handle: any, params: { [string]: any }?) -> boolean,
	hitDetect    : HitDetectionUtil.HitDetectFunction,
	onHitResult  : ((InstantHit.HitMapResult) -> ())?,
	onHit        : ((handle: any, hitInfo: HitDetectionUtil.HitInfo) -> ())?,
	onMiss       : ((handle: any) -> ())?,
	params       : { [string]: any }?,
	latency      : number,
	delay        : number?,
}

local _handles   : { [string]: any }    = {}
local _counter   : number               = 0
local _heartbeat : RBXScriptConnection? = nil

local ProjectileHandle   = {}
ProjectileHandle.__index = ProjectileHandle

local function newHandle(
	attacker       : Model,
	origin         : CFrame,
	def            : ProjectileDef,
	teamService    : any?,
	attackerPlayer : Player?
): any
	local self = setmetatable({}, ProjectileHandle) :: any
	self._alive          = true
	self._maid           = Maid.new()
	self._moveStopped    = false
	self._fadingOut      = false
	self._penetrateCount = 0
	self._moveElapsed    = 0
	self._moveOrigin     = origin.Position
	self._moveDir        = origin.LookVector
	self._sweepBase      = nil
	self._def            = def
	self._onHit          = def.onHit
	self._onMiss         = def.onMiss
	self.isOwner         = false

	local fakePart = {
		_cf            = origin,
		GetPivot       = function(fp: any): CFrame return fp._cf end,
		PivotTo        = function(fp: any, cf: CFrame)
			fp._cf        = cf
			self._moveDir = cf.LookVector
		end,
		GetDescendants = function(): { any } return {} end,
	}
	self.part = fakePart

	self._teamContext = {
		attackerChar   = attacker,
		attackerPlayer = attackerPlayer,
		color          = nil,
		isEnemy        = function(a: Player, b: Player): boolean
			return if teamService then teamService:IsEnemy(a, b) else true
		end,
	}
	return self
end

function ProjectileHandle:IsAlive(): boolean
	return self._alive
end

function ProjectileHandle:Miss()
	if not self._alive then return end
	if self._onMiss then self._onMiss(self) end
	self:_destroyNoMiss()
end

function ProjectileHandle:_destroyNoMiss()
	if not self._alive then return end
	self._alive = false
	self._maid:Destroy()
end

function ProjectileHandle:Destroy()
	self:_destroyNoMiss()
end

local function toHitMapResult(hits: { HitDetectionUtil.HitInfo }): InstantHit.HitMapResult
	local vs: InstantHit.VictimSet = { enemies = {}, teammates = {}, self = nil }
	for _, hitInfo in hits do
		if hitInfo.relation == "enemy" then table.insert(vs.enemies, hitInfo.target)
		elseif hitInfo.relation == "team" then table.insert(vs.teammates, hitInfo.target)
		elseif hitInfo.relation == "self" then vs.self = hitInfo.target
		end
	end
	return { hit = vs }
end

local function tickHandle(handle: any, dt: number): boolean
	if not handle._alive then return false end

	local continues = true
	if not handle._moveStopped and handle._def.move then
		continues = handle._def.move(dt, handle, handle._def.params)
	end

	if not handle._fadingOut and handle._def.hitDetect then
		local hits = HitDetectionUtil.Detect(
			handle._def.hitDetect,
			handle._moveElapsed,
			handle,
			handle._def.params
		)
		if #hits > 0 then
			if handle._def.onHitResult then
				handle._def.onHitResult(toHitMapResult(hits))
			end
			if handle._onHit and handle._alive then
				for _, hitInfo in hits do
					handle._onHit(handle, hitInfo)
					if not handle._alive then break end
				end
			end
			return false
		end
	end

	if not continues then
		handle:Miss()
		return false
	end
	return handle._alive
end

local function ensureHeartbeat()
	if _heartbeat then return end
	_heartbeat = RunService.Heartbeat:Connect(function(dt: number)
		local toRemove: { string } = {}
		for id, handle in _handles do
			if not tickHandle(handle, dt) then
				table.insert(toRemove, id)
			end
		end
		for _, id in toRemove do _handles[id] = nil end
		if next(_handles) == nil then
			(_heartbeat :: RBXScriptConnection):Disconnect()
			_heartbeat = nil
		end
	end)
end

local function simB(handle: any, forwardTime: number): boolean
	if forwardTime <= 0 then return false end
	local steps  = 10
	local stepDt = forwardTime / steps
	for _ = 1, steps do
		if not tickHandle(handle, stepDt) then return true end
	end
	return false
end

local ProjectileHit = {}

--[=[
	투사체 판정을 시작합니다. InstantHit.verdict()와 동일한 패턴.

	@param attacker       Model
	@param origin         CFrame    서버 독립 계산값
	@param def            ProjectileDef
	@param fireMaid       any?      effectiveDelay 취소용 (발사 후 영향 없음)
	@param teamService    any?
	@param attackerPlayer Player?
	@return ProjectileHandle? (즉시 발사 시) | nil (delay 중)
]=]
function ProjectileHit.verdict(
	attacker       : Model,
	origin         : CFrame,
	def            : ProjectileDef,
	fireMaid       : any?,
	teamService    : any?,
	attackerPlayer : Player?
): any?
	local latency = def.latency
	local delay   = def.delay or 0

	local effectiveDelay = math.max(0, delay - latency)
	local forwardTime    = math.max(0, latency - delay)

	local function launch(): any?
		local handle = newHandle(attacker, origin, def, teamService, attackerPlayer)
		if simB(handle, forwardTime) then return nil end
		if handle._alive then
			_counter += 1
			local id = tostring(_counter)
			_handles[id] = handle
			handle._maid:GiveTask(function() _handles[id] = nil end)
			ensureHeartbeat()
		end
		return handle
	end

	if effectiveDelay > 0 then
		local cancel = cancellableDelay(effectiveDelay, function() launch() end)
		if fireMaid then fireMaid:GiveTask(cancel) end
		return nil
	end

	return launch()
end

return ProjectileHit
