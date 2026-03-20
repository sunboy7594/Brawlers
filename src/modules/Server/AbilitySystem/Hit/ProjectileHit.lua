--!strict
--[=[
	@class ProjectileHit

	투사체 판정 유틸리티. 서버 전용.

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
	    → 서버는 클라이언트가 delay 후 발사하는 것을 latency만큼 앞당김
	    → InstantHit.verdict와 동일한 방식

	fast-forward (simB):
	  forwardTime = max(0, latency - delay)
	    → delay=0        : forwardTime = latency (기존과 동일)
	    → delay>=latency : forwardTime = 0 (클라이언트와 동시 발사, 보정 불필요)
	    → 0<delay<latency: forwardTime = latency - delay

	  타임라인:
	    t=0         클라이언트: Fire Remote 전송
	    t=delay     클라이언트: 투사체 시각 발사
	    t=latency   서버: Fire Remote 수신 → onFire 실행
	    t=latency+effectiveDelay = max(latency,delay)
	                서버: 투사체 발사 (클라이언트와 동일 시점)
	  서버 발사 직후 클라이언트 투사체가 이미 forwardTime만큼 날아있으므로 simB로 보상.
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

	-- 이동 (_moveElapsed는 MoverUtil가 내부에서 관리 — 여기서 pre-increment 하지 않음)
	local continues = true
	if not handle._moveStopped and handle._def.move then
		continues = handle._def.move(dt, handle, handle._def.params)
	end

	-- 히트 판정
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

-- forwardTime: 클라이언트 투사체가 이미 날아간 시간만큼 fast-forward
-- delay=0        → forwardTime = latency
-- delay>=latency → forwardTime = 0  (클라이언트와 동시 발사)
-- 0<delay<latency → forwardTime = latency - delay
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

function ProjectileHit.fire(
	attacker       : Model,
	origin         : CFrame,
	def            : ProjectileDef,
	fireMaid       : any?,
	teamService    : any?,
	attackerPlayer : Player?
): any?
	local latency = def.latency
	local delay   = def.delay or 0

	-- ✅ effectiveDelay: latency만큼 delay를 앞당김 (InstantHit.verdict와 동일)
	local effectiveDelay = math.max(0, delay - latency)

	-- ✅ forwardTime: 서버가 발사할 때 클라이언트 투사체가 이미 날아간 시간
	local forwardTime = math.max(0, latency - delay)

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
