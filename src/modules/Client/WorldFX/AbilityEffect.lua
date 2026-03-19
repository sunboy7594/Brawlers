--!strict
--[=[
	@class AbilityEffect

	어빌리티 이펙트 유틸 클래스. EntityAnimator와 동일한 역할.
	WorldFX 서비스를 주입받아 이펙트를 재생합니다.

	사용법:
	  local abilityEffect = AbilityEffect.new(worldFX)
	  local handle = abilityEffect:Play("Tank_PunchEffectDef", "FistPunch", origin, {
	      onHit  = function(result, handle) end,
	      onMiss = function(handle) end,
	      fireMaid = state.fireMaid,
	  })

	복제 구조 (AnimReplication과 동일한 패턴):
	  isOwner=true 시: 로컬 즉시 재생 + EffectFired → 서버 → 타 클라이언트
	  isOwner=false 시: 브로드캐스트 수신 후 로컬 재생 (서버 전송 없음)

	AbilityEffectDef 구조:
	  {
	      template    : string,
	      hasSelfHit  : boolean,
	      hitRadius   : number | (elapsed, handle) -> number,
	      move        : MoveFactory?,
	      colorFilter : ColorFilter?,
	      particles   : { string }?,
	  }

	MoveFactory:
	  (handle: AbilityEffectHandle) -> (dt: number) -> boolean
	  fast-forward: handle.firedAt (workspace:GetServerTimeNow() 기준)
	  을 이용해 시작 시 elapsed 계산 후 미리 이동 가능.

	PlayOptions:
	  {
	      onHit     : ((HitResult, AbilityEffectHandle) -> ())?,
	      onMiss    : ((AbilityEffectHandle) -> ())?,
	      fireMaid  : any?,
	      direction : Vector3?,
	      isOwner   : boolean?,
	      userId    : number?,
	      firedAt   : number?,  -- workspace:GetServerTimeNow() 기준. MoveFactory fast-forward용.
	                            -- nil이면 현재 서버 시각으로 자동 설정.
	  }
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AbilityEffectHandle = require("AbilityEffectHandle")
local Maid = require("Maid")
local WorldFXReplicationRemoting = require("WorldFXReplicationRemoting")

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type HitResult = AbilityEffectHandle.HitResult
export type ColorFilter = (model: Model, color: Color3) -> () -> ()
export type MoveFactory = (handle: AbilityEffectHandle.AbilityEffectHandle) -> (dt: number) -> boolean

export type AbilityEffectDef = {
	template    : string,
	hasSelfHit  : boolean,
	hitRadius   : (number | (elapsed: number, handle: any) -> number)?,
	move        : MoveFactory?,
	colorFilter : ColorFilter?,
	particles   : { string }?,
}

export type AbilityEffectDefs = { [string]: AbilityEffectDef }

export type PlayOptions = {
	onHit     : ((result: HitResult, handle: any) -> ())?,
	onMiss    : ((handle: any) -> ())?,
	fireMaid  : any?,
	direction : Vector3?,
	isOwner   : boolean?,
	userId    : number?,
	firedAt   : number?,
}

export type AbilityEffect = typeof(setmetatable(
	{} :: {
		_worldFX        : any,
		_maid           : any,
		_defModuleName  : string?,
	},
	{} :: typeof({ __index = {} })
))

-- ─── 클래스 ──────────────────────────────────────────────────────────────────

local AbilityEffect = {}
AbilityEffect.__index = AbilityEffect

function AbilityEffect.new(worldFX: any): AbilityEffect
	local self = setmetatable({}, AbilityEffect)
	self._worldFX = worldFX
	self._maid = Maid.new()
	return self
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

function AbilityEffect:Play(
	defModuleName : string,
	effectName    : string,
	origin        : CFrame,
	options       : PlayOptions?
): AbilityEffectHandle.AbilityEffectHandle
	options = options or {}

	-- DefModule 로드
	local ok, defs = pcall(require, defModuleName)
	if not ok or type(defs) ~= "table" then
		warn("[AbilityEffect] DefModule 로드 실패:", defModuleName)
		return AbilityEffectHandle.new(true, nil, nil, nil, 0)
	end

	local def: AbilityEffectDef = (defs :: any)[effectName]
	if not def then
		warn("[AbilityEffect] 이펙트 정의 없음:", effectName, "in", defModuleName)
		return AbilityEffectHandle.new(true, nil, nil, nil, 0)
	end

	local isOwner  = if options and options.isOwner ~= nil then options.isOwner else true
	local onHit    = options and options.onHit
	local onMiss   = options and options.onMiss
	local fireMaid = options and options.fireMaid
	local firedAt  = if options and options.firedAt
		then options.firedAt
		else Workspace:GetServerTimeNow()

	-- ─── 색상 결정 ───────────────────────────────────────────────────────────
	local teamClient = self._worldFX:GetTeamClient()
	local color: Color3
	if isOwner then
		color = teamClient:GetMyColor()
	else
		local userId = options and options.userId
		local player = if userId then Players:GetPlayerByUserId(userId) else nil
		color = if player
			then teamClient:GetRelationColor(player)
			else Color3.fromHSV(0, 1, 1)
	end

	-- ─── 모델 소환 ───────────────────────────────────────────────────────────
	local model, colorCleanup = self._worldFX:SpawnModel(def.template, origin, color, def.colorFilter)

	-- ─── 핸들 생성 ───────────────────────────────────────────────────────────
	local handle = AbilityEffectHandle.new(isOwner, model, onHit, onMiss, firedAt)

	if colorCleanup then
		handle._maid:GiveTask(colorCleanup)
	end

	-- ─── MoveFactory 루프 ────────────────────────────────────────────────────
	if def.move then
		local onUpdate = def.move(handle)
		local conn
		conn = RunService.Heartbeat:Connect(function(dt)
			if not handle:IsAlive() then
				conn:Disconnect()
				return
			end
			local shouldContinue = onUpdate(dt)
			if not shouldContinue then
				conn:Disconnect()
				if handle:IsAlive() then
					handle:Miss()
				end
			end
		end)
		handle._maid:GiveTask(conn)
	end

	-- ─── fireMaid 캔슬 연동 ──────────────────────────────────────────────────
	if fireMaid then
		fireMaid:GiveTask(function()
			handle:Destroy()
		end)
	end

	-- ─── 복제: isOwner=true 시 서버에 알림 ──────────────────────────────────
	-- 서버 → 타 클라이언트로 브로드캐스트됨
	-- isOwner=false(브로드캐스트 수신)면 전송 안 함 (무한 루프 방지)
	if isOwner then
		local direction = options and options.direction
		WorldFXReplicationRemoting.EffectFired:FireServer(
			defModuleName,
			effectName,
			origin,
			direction
		)
	end

	return handle
end

function AbilityEffect:Destroy()
	self._maid:Destroy()
end

return AbilityEffect
