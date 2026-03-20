--!strict
--[=[
	@class EntityController

	범용 엔티티 생명주기 관리. (Shared)
	클라이언트/서버 공용.

	글로벌 풀 + 단일 Heartbeat:
	  handle 생성 시 풀에 등록, Heartbeat에서 전체 tick.
	  틱 순서: move → hitDetect → onMove

	SimB (Simulate Behind):
	  firedAt 기반 latency 계산 후 fast-forward.

	fakePart:
	  part = nil일 때 자동 생성.
	  GetPivot() / PivotTo() / GetDescendants() 구현.

	글로벌 조회:
	  EntityController.GetHandlesByTag(tag)
	  EntityController.GetHandleById(id)
	  EntityController.GetHandlesByOwner(ownerId)
]=]

local require = require(script.Parent.loader).load(script)

local RunService = game:GetService("RunService")
local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")

local HitDetectionUtil = require("HitDetectionUtil")
local Maid             = require("Maid")

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type MoveFunction    = (dt: number, handle: any, params: { [string]: any }?) -> boolean
export type OnMoveCallback  = (model: any, dt: number, params: { [string]: any }?) -> ()
export type OnSpawnCallback = (handle: any) -> ()
export type HitCallback     = (handle: any, hitInfo: HitDetectionUtil.HitInfo) -> ()
export type MissCallback    = (handle: any) -> ()
export type ColorFilter     = (model: any, color: Color3?) -> () -> ()

export type TeamContext = {
	attackerChar   : Model?,
	attackerPlayer : Player?,
	isEnemy        : (a: Player, b: Player) -> boolean,
}

export type EntityDef = {
	model        : string?,
	modelOffset  : CFrame?,
	move         : MoveFunction?,
	onMove       : OnMoveCallback?,
	onSpawn      : OnSpawnCallback?,
	onHit        : HitCallback?,
	onMiss       : MissCallback?,
	hitDetect    : HitDetectionUtil.HitDetectFunction?,
	colorFilter  : ColorFilter?,
	tags         : { string }?,
	params       : { [string]: any }?,
}

export type EntityConfig = {
	part             : any?,
	origin           : CFrame,
	move             : MoveFunction?,
	onMove           : OnMoveCallback?,
	onSpawn          : OnSpawnCallback?,
	onHit            : HitCallback?,
	onMiss           : MissCallback?,
	hitDetect        : HitDetectionUtil.HitDetectFunction?,
	colorFilter      : ColorFilter?,
	attackerPlayerId : number?,
	color            : Color3?,
	params           : { [string]: any }?,
	tags             : { string }?,
	replicate        : boolean?,
	taskMaid         : any?,
	firedAt          : number?,
	delay            : number?,
}

-- ─── 글로벌 풀 ───────────────────────────────────────────────────────────────

local _handles    : { [string]: any } = {}
local _tagIndex   : { [string]: { [string]: any } } = {}
local _ownerIndex : { [number]: { [string]: any } } = {}
local _counter    : number = 0
local _heartbeat  : RBXScriptConnection? = nil

local EntityHandle_mt   = {}
EntityHandle_mt.__index = EntityHandle_mt

-- ─── 내부 유틸 ───────────────────────────────────────────────────────────────

local function makeFakePart(origin: CFrame): any
	local cf = origin
	local fp: any = {}
	fp._cf = cf
	fp.GetPivot = function(): CFrame
		return fp._cf
	end
	fp.PivotTo = function(_self: any, newCF: CFrame)
		fp._cf = newCF
	end
	fp.GetDescendants = function(): { any }
		return {}
	end
	return fp
end

local function buildTeamContext(attackerPlayerId: number?): TeamContext?
	if not attackerPlayerId then return nil end
	local attackerPlayer = Players:GetPlayerByUserId(attackerPlayerId)
	if not attackerPlayer then return nil end
	return {
		attackerChar   = attackerPlayer.Character,
		attackerPlayer = attackerPlayer,
		isEnemy        = function(a: Player, b: Player): boolean
			if a.Neutral or b.Neutral then return true end
			return a.Team == nil or a.Team ~= b.Team
		end,
	}
end

local function addToIndex(handle: any)
	local id = handle.id
	for _, tag in handle.tags do
		if not _tagIndex[tag] then _tagIndex[tag] = {} end
		_tagIndex[tag][id] = handle
	end
	if handle.ownerId then
		if not _ownerIndex[handle.ownerId] then _ownerIndex[handle.ownerId] = {} end
		_ownerIndex[handle.ownerId][id] = handle
	end
end

local function removeFromIndex(handle: any)
	local id = handle.id
	for _, tag in handle.tags do
		if _tagIndex[tag] then _tagIndex[tag][id] = nil end
	end
	if handle.ownerId and _ownerIndex[handle.ownerId] then
		_ownerIndex[handle.ownerId][id] = nil
	end
end

-- ─── 틱 ─────────────────────────────────────────────────────────────────────

local function tickHandle(handle: any, dt: number): boolean
	if not handle._alive then return false end

	if not handle._moveStopped and handle._def.move then
		handle._moveElapsed += dt
		local continues = handle._def.move(dt, handle, handle._params)
		if not continues then
			handle:Miss()
			return false
		end
	end

	if not handle._fadingOut and handle._def.hitDetect then
		local hits = HitDetectionUtil.Detect(
			handle._def.hitDetect,
			handle._moveElapsed,
			handle,
			handle._params
		)
		if #hits > 0 then
			if handle._onHit then
				for _, hitInfo in hits do
					handle._onHit(handle, hitInfo)
					if not handle._alive then break end
				end
			end
			if handle._alive then
				handle:_destroyNoMiss()
			end
			return false
		end
	end

	if handle._def.onMove and handle.part then
		handle._def.onMove(handle.part, dt, handle._params)
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
		for _, id in toRemove do
			_handles[id] = nil
		end
		if next(_handles) == nil then
			(_heartbeat :: RBXScriptConnection):Disconnect()
			_heartbeat = nil
		end
	end)
end

local function simB(handle: any)
	local now     = Workspace:GetServerTimeNow()
	local latency = math.max(0, math.min(now - handle.firedAt, 0.5))
	if latency <= 0 then return end
	local steps  = 10
	local stepDt = latency / steps
	for _ = 1, steps do
		if not handle._alive then return end
		tickHandle(handle, stepDt)
	end
end

-- ─── EntityHandle 메서드 ─────────────────────────────────────────────────────

function EntityHandle_mt:IsAlive(): boolean
	return self._alive
end

function EntityHandle_mt:Miss()
	if not self._alive then return end
	if self._onMiss then self._onMiss(self) end
	self:_destroyNoMiss()
end

function EntityHandle_mt:_destroyNoMiss()
	if not self._alive then return end
	self._alive = false
	removeFromIndex(self)
	self._maid:Destroy()
end

function EntityHandle_mt:Destroy()
	self:_destroyNoMiss()
end

-- ─── EntityController ────────────────────────────────────────────────────────

local EntityController = {}

function EntityController.new(
	def    : EntityDef,
	config : EntityConfig
): any
	_counter += 1
	local id = "ec_" .. tostring(_counter)

	-- tags 합치기
	local tags: { string } = {}
	if def.tags then for _, t in def.tags do table.insert(tags, t) end end
	if config.tags then for _, t in config.tags do table.insert(tags, t) end end

	-- params 합치기
	local params: { [string]: any }? = nil
	if def.params or config.params then
		params = {}
		if def.params   then for k, v in def.params   do (params :: any)[k] = v end end
		if config.params then for k, v in config.params do (params :: any)[k] = v end end
	end

	-- 최종 def (config 오버라이드)
	local finalDef: EntityDef = {
		model       = def.model,
		modelOffset = def.modelOffset,
		move        = config.move      or def.move,
		onMove      = config.onMove    or def.onMove,
		onSpawn     = config.onSpawn   or def.onSpawn,
		onHit       = config.onHit     or def.onHit,
		onMiss      = config.onMiss    or def.onMiss,
		hitDetect   = config.hitDetect or def.hitDetect,
		colorFilter = config.colorFilter or def.colorFilter,
		tags        = tags,
		params      = params,
	}

	-- part 결정
	local part: any = config.part
	if not part then
		part = makeFakePart(config.origin)
	end

	local handle = setmetatable({
		id              = id,
		part            = part,
		spawnCFrame     = config.origin,
		ownerId         = config.attackerPlayerId,
		defModule       = nil :: string?,
		defName         = nil :: string?,
		tags            = tags,
		firedAt         = config.firedAt or Workspace:GetServerTimeNow(),
		_alive          = true,
		_maid           = Maid.new(),
		_moveStopped    = false,
		_fadingOut      = false,
		_penetrateCount = 0,
		_moveElapsed    = 0,
		_moveOrigin     = config.origin.Position,
		_moveDir        = config.origin.LookVector,
		_sweepBase      = nil :: CFrame?,
		_onHit          = finalDef.onHit,
		_onMiss         = finalDef.onMiss,
		_teamContext    = buildTeamContext(config.attackerPlayerId),
		_def            = finalDef,
		_params         = params,
	}, EntityHandle_mt) :: any

	-- colorFilter 적용 (실제 Model일 때만)
	if finalDef.colorFilter and config.part then
		local ok, cleanup = pcall(finalDef.colorFilter, config.part, config.color)
		if ok and cleanup then
			handle._maid:GiveTask(cleanup)
		end
	end

	-- PivotTo origin (modelOffset 적용)
	if config.part then
		local pivotCF = finalDef.modelOffset
			and (config.origin * finalDef.modelOffset)
			or config.origin
		config.part:PivotTo(pivotCF)
	end

	-- onSpawn
	if finalDef.onSpawn then
		finalDef.onSpawn(handle)
	end

	-- 풀 등록
	_handles[id] = handle
	addToIndex(handle)
	handle._maid:GiveTask(function()
		_handles[id] = nil
		removeFromIndex(handle)
	end)

	-- SimB
	if config.firedAt then
		simB(handle)
	end

	if handle._alive then
		ensureHeartbeat()
	end

	return handle
end

-- ─── 글로벌 조회 API ─────────────────────────────────────────────────────────

function EntityController.GetHandleById(id: string): any?
	return _handles[id]
end

function EntityController.GetHandlesByTag(tag: string): { any }
	local result: { any } = {}
	if _tagIndex[tag] then
		for _, handle in _tagIndex[tag] do
			table.insert(result, handle)
		end
	end
	return result
end

function EntityController.GetHandlesByOwner(ownerId: number): { any }
	local result: { any } = {}
	if _ownerIndex[ownerId] then
		for _, handle in _ownerIndex[ownerId] do
			table.insert(result, handle)
		end
	end
	return result
end

return EntityController
