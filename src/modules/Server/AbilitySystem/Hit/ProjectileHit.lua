--!strict
--[=[
	@class ProjectileHit

	투사체 판정 유틸리티. 서버 전용.
	InstantHit.verdict()와 동일한 스타일.

	ProjectileDef 필드:
	  move         : 이동 함수 (MoverUtil.Linear 등)
	  hitDetect    : 박스 판정 함수 (HitDetectionUtil.Box 등)
	  onHitResult  : ((HitMapResult) -> ())?  ← state.onHit (onHitChecked 트리거)
	  onHit        : ((handle, hitInfo) -> ())?  ← HitOrMissUtil 시각 콜백 (Despawn 등)
	  onMiss       : ((handle) -> ())?  ← 미스 시 콜백
	  params       : 추가 파라미터
	  latency      : 레이턴시 보정값
	  delay        : 발사 지연 (fireMaid로 취소 가능)

	히트 시 실행 순서:
	  1. onHitResult(HitMapResult) → onHitChecked 트리거 (데미지 등)
	  2. onHit(handle, hitInfo)    → HitOrMissUtil 콜백 (Despawn 등)
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
	onHitResult  : ((InstantHit.HitMapResult) -> ())?,  -- state.onHit → onHitChecked 트리거
	onHit        : ((handle: any, hitInfo: HitDetectionUtil.HitInfo) -> ())?,  -- HitOrMissUtil 콜백
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

-- HitInfo[] → HitMapResult 변환 (onHitResult 콜백용)
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

	-- 이동
	local continues = true
	if not handle._moveStopped and handle._def.move then
		handle._moveElapsed += dt
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
			-- 1. onHitResult: HitMapResult → BasicAttackService onHitChecked (데미지 등)
			if handle._def.onHitResult then
				handle._def.onHitResult(toHitMapResult(hits))
			end

			-- 2. onHit: per-hit HitOrMissUtil 콜백 (Despawn 등)
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

local function simB(handle: any): boolean
	local latency = handle._def.latency
	if latency <= 0 then return false end
	local steps  = 10
	local stepDt = latency / steps
	for _ = 1, steps do
		if not tickHandle(handle, stepDt) then return true end
	end
	return false
end

local ProjectileHit = {}

--[=[
	투사체 판정을 시작합니다.

	def.onHitResult = state.onHit  → 히트 시 onHitChecked 트리거 (데미지 적용)
	def.onHit       = HitOrMissUtil.Despawn() 등  → 시각 처리

	def.delay > 0이면 cancellableDelay 후 발사.
	  발사 전 fireMaid 파괴 시 delay 취소.
	  발사 후 handle은 독립 수명.
]=]
function ProjectileHit.fire(
	attacker       : Model,
	origin         : CFrame,
	def            : ProjectileDef,
	fireMaid       : any?,
	teamService    : any?,
	attackerPlayer : Player?
): any?
	local function launch(): any?
		local handle = newHandle(attacker, origin, def, teamService, attackerPlayer)
		if simB(handle) then return nil end
		if handle._alive then
			_counter += 1
			local id = tostring(_counter)
			_handles[id] = handle
			handle._maid:GiveTask(function() _handles[id] = nil end)
			ensureHeartbeat()
		end
		return handle
	end

	local delay = def.delay
	if delay and delay > 0 then
		local cancel = cancellableDelay(delay, function() launch() end)
		if fireMaid then fireMaid:GiveTask(cancel) end
		return nil
	end
	return launch()
end

return ProjectileHit
