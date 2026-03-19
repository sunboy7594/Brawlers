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

	AbilityEffectDef 구조:
	  {
	      template    : string,         -- ReplicatedStorage.AbilityEffects 내 이름
	      hasSelfHit  : boolean,        -- true면 MoveFactory 내부에서 직접 충돌 감지
	      hitRadius   : number          -- hasSelfHit=true 시 충돌 감지 반경
	                  | (elapsed: number, handle: any) -> number,
	      move        : MoveFactory?,   -- (handle) -> (dt) -> boolean
	      colorFilter : ColorFilter?,   -- (model, color) -> cleanup
	      particles   : { string }?,    -- 추후 파티클 확장용
	  }

	MoveFactory:
	  (handle: AbilityEffectHandle) -> (dt: number) -> boolean
	  반환 함수가 false를 반환하거나 handle이 Destroy되면 루프 종료.
	  hasSelfHit=true면 내부에서 직접 충돌 감지 후 handle:Hit() 호출 가능.
	  hasSelfHit=false면 순수 이동만 담당 (판정은 onHitChecked에서 handle:Hit() 호출).

	PlayOptions:
	  {
	      onHit     : ((HitResult, AbilityEffectHandle) -> ())?,
	      onMiss    : ((AbilityEffectHandle) -> ())?,
	      fireMaid  : any?,     -- 등록 시 캔슬 가능하게 (CancelCombatState 연동)
	      direction : Vector3?, -- nil이면 origin.LookVector
	      isOwner   : boolean?, -- nil이면 true (로컬 플레이어)
	      userId    : number?,  -- 브로드캐스트 수신 시 원래 공격자 userId (색상 계산용)
	  }
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AbilityEffectHandle = require("AbilityEffectHandle")
local Maid = require("Maid")

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
}

export type AbilityEffect = typeof(setmetatable(
	{} :: {
		_worldFX : any,
		_maid    : any,
	},
	{} :: typeof({ __index = {} })
))

-- ─── 클래스 ──────────────────────────────────────────────────────────────────

local AbilityEffect = {}
AbilityEffect.__index = AbilityEffect

--[=[
	AbilityEffect 유틸 인스턴스를 생성합니다.
	@param worldFX WorldFX 서비스 인스턴스
]=]
function AbilityEffect.new(worldFX: any): AbilityEffect
	local self = setmetatable({}, AbilityEffect)
	self._worldFX = worldFX
	self._maid = Maid.new()
	return self
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	이펙트를 재생합니다.

	@param defModuleName string   -- require 가능한 모듈 이름 (AbilityEffectDefs 반환)
	@param effectName    string   -- 딕셔너리 키
	@param origin        CFrame  -- 발사 위치/방향
	@param options       PlayOptions?
	@return AbilityEffectHandle
]=]
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
		return AbilityEffectHandle.new(true, nil, nil, nil)
	end

	local def: AbilityEffectDef = (defs :: any)[effectName]
	if not def then
		warn("[AbilityEffect] 이펙트 정의 없음:", effectName, "in", defModuleName)
		return AbilityEffectHandle.new(true, nil, nil, nil)
	end

	local isOwner = if options and options.isOwner ~= nil then options.isOwner else true
	local onHit   = options and options.onHit
	local onMiss  = options and options.onMiss
	local fireMaid = options and options.fireMaid

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
			else Color3.fromHSV(0, 1, 1)  -- fallback: 빨간색
	end

	-- ─── 모델 소환 ───────────────────────────────────────────────────────────
	local model, colorCleanup = self._worldFX:SpawnModel(def.template, origin, color, def.colorFilter)

	-- ─── 핸들 생성 ───────────────────────────────────────────────────────────
	local handle = AbilityEffectHandle.new(isOwner, model, onHit, onMiss)

	-- 색상 cleanup 등록
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
	-- CancelCombatState() → fireMaid:Destroy() → handle:Destroy() 자동 실행
	if fireMaid then
		fireMaid:GiveTask(function()
			handle:Destroy()
		end)
	end

	return handle
end

function AbilityEffect:Destroy()
	self._maid:Destroy()
end

return AbilityEffect
