--!strict
--[=[
	@class EntityPlayerServer

	EntityController를 감싸는 서버 편의 유틸.
	(서버 전용 - 클라이언트 EntityPlayer와 이름 충돌 방지를 위해 분리)

	Play(defModule, defName, config):
	  - def 파일 로드
	  - def.model로 ReplicatedStorage에서 Clone
	  - EntityController.new() 생성

	PlayDirect(config):
	  - def 없이 직접 실행

	PlayHRP(player, defModule, defName, config):
	  - 클라이언트에서 HRP를 직접 이동 (끊김 방지)
	  - 토큰 발급 → FireClient(direction, speed, distance, height)
	  - 클라이언트가 현재 위치 기준으로 findActualLanding 직접 계산
	  - 착지 후 LandingReport 수신 → 거리 검증 → onLanded 콜백 실행
	  - BindLandingReport()를 서버 시작 시 한 번 호출해야 함

	BindLandingReport():
	  - LandingReport 이벤트 바인딩 (서버 시작 시 1회 호출)

	Preload(defModuleNames):
	  - def 모듈 캐싱
]=]

local require = require(script.Parent.loader).load(script)

local HttpService       = game:GetService("HttpService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EntityController = require("EntityController")
local HRPMoveRemoting  = require("HRPMoveRemoting")
local cancellableDelay = require("cancellableDelay")

local _preloaded: { [string]: boolean } = {}

-- ─── 토큰 저장소 ─────────────────────────────────────────────────────────────
local _pendingMoves: {
	[number]: {
		[string]: {
			originPos      : Vector3,
			maxAllowedDist : number,
			expiry         : number,
			tolerance      : number,
			onLanded       : ((actualPos: Vector3) -> ())?,
		}
	}
} = {}

local function getModelRoot(): Instance?
	return ReplicatedStorage:FindFirstChild("Entities")
end

export type PlayConfig = {
	part: any?,
	origin: CFrame,
	move: any?,
	onMove: any?,
	onSpawn: any?,
	onHit: any?,
	onMiss: any?,
	hitDetect: any?,
	colorFilter: any?,
	attackerPlayerId: number?,
	color: Color3?,
	params: { [string]: any }?,
	tags: { string }?,
	taskMaid: any?,
	firedAt: number?,
	delay: number?,
}

export type PlayHRPConfig = {
	-- 이동 파라미터 (클라이언트가 findActualLanding에 사용)
	direction      : Vector3,  -- 정규화된 수평 방향
	speed          : number,
	distance       : number,   -- 기본 거리 (클라이언트가 벽 보정)
	height         : number,   -- 기본 높이 (클라이언트가 벽 높이 보정)
	-- 서버 검증용
	originPos      : Vector3,  -- 서버 기준 발사 위치 (검증 기준점)
	duration       : number,   -- fallback 타이머
	maxAllowedDist : number,   -- 최대 허용 이동 거리
	tolerance      : number?,  -- 추가 허용 오차
	-- 착지 확인 후 콜백 (선택적, fist 발사 등)
	onLanded       : ((actualPos: Vector3) -> ())?,
	-- fireMaid 소멸 시 토큰 자동 소멸 (전투 취소 시 onLanded 방지)
	fireMaid       : any?,
	params         : { [string]: any }?,
}

local EntityPlayerServer = {}

-- ─── PlayHRP ─────────────────────────────────────────────────────────────────
function EntityPlayerServer.PlayHRP(
	player    : Player,
	defModule : string,
	defName   : string,
	config    : PlayHRPConfig
): ()
	local token     = HttpService:GenerateGUID(false)
	local userId    = player.UserId
	local tolerance = config.tolerance or 9

	if not _pendingMoves[userId] then
		_pendingMoves[userId] = {}
	end
	_pendingMoves[userId][token] = {
		originPos      = config.originPos,
		maxAllowedDist = config.maxAllowedDist,
		expiry         = os.clock() + config.duration + 1.5,
		tolerance      = tolerance,
		onLanded       = config.onLanded,
	}

	-- fireMaid 소멸 시 토큰 소멸 (전투 취소 시 onLanded 방지)
	if config.fireMaid then
		config.fireMaid:GiveTask(function()
			local pending = _pendingMoves[userId]
			if pending then
				pending[token] = nil
			end
		end)
	end

	-- 클라이언트에 이동 권한 부여
	-- origin 대신 direction/speed/distance/height 전달
	-- 클라이언트가 현재 위치 기준으로 findActualLanding 직접 계산
	HRPMoveRemoting.Move:FireClient(
		player,
		token,
		defModule,
		defName,
		config.direction,
		config.speed,
		config.distance,
		config.height,
		config.params
	)

	-- fallback: LandingReport가 안 오면 duration 후 서버가 직접 처리
	task.delay(config.duration + 0.6, function()
		local pending = _pendingMoves[userId]
		if not pending or not pending[token] then return end

		local p = pending[token]
		pending[token] = nil

		-- 현재 위치 확인
		local char = player.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then
			if p.onLanded then p.onLanded(p.originPos) end
			return
		end

		local actualPos = hrp.Position
		local diff = Vector3.new(
			actualPos.X - p.originPos.X,
			0,
			actualPos.Z - p.originPos.Z
		).Magnitude

		if diff > p.maxAllowedDist then
			-- exploit: 최대 허용 거리로 클램핑
			local toActual = Vector3.new(actualPos.X - p.originPos.X, 0, actualPos.Z - p.originPos.Z)
			if toActual.Magnitude > 0.001 then
				local clampedPos = p.originPos + toActual.Unit * p.maxAllowedDist
				hrp:PivotTo(CFrame.new(clampedPos.X, hrp.Position.Y, clampedPos.Z))
				actualPos = hrp.Position
			end
		end

		-- fallback onLanded 호출 (fist 등 후처리)
		if p.onLanded then
			p.onLanded(actualPos)
		end
	end)
end

-- ─── BindLandingReport ───────────────────────────────────────────────────────
local _bound = false
function EntityPlayerServer.BindLandingReport(): ()
	if _bound then return end
	_bound = true

	HRPMoveRemoting.LandingReport:Connect(function(
		player   : Player,
		token    : string,
		actualPos: Vector3
	)
		local userId = player.UserId
		local pending = _pendingMoves[userId]
		if not pending then return end

		local p = pending[token]
		if not p then return end

		-- 토큰 즉시 소멸 (재사용 방지)
		pending[token] = nil

		-- 만료 확인
		if os.clock() > p.expiry then return end

		-- 이동 거리 검증
		local diff = Vector3.new(
			actualPos.X - p.originPos.X,
			0,
			actualPos.Z - p.originPos.Z
		).Magnitude

		if diff > p.maxAllowedDist then
			-- exploit: 최대 허용 거리로 클램핑
			local char = player.Character
			local hrp  = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				local toActual = Vector3.new(actualPos.X - p.originPos.X, 0, actualPos.Z - p.originPos.Z)
				if toActual.Magnitude > 0.001 then
					local clampedPos = p.originPos + toActual.Unit * p.maxAllowedDist
					hrp:PivotTo(CFrame.new(clampedPos.X, hrp.Position.Y, clampedPos.Z))
					actualPos = hrp.Position
				end
			end
		end

		-- 착지 확인 후 콜백 (fist 발사 등)
		if p.onLanded then
			p.onLanded(actualPos)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		_pendingMoves[player.UserId] = nil
	end)
end

-- ─── Play ────────────────────────────────────────────────────────────────────
function EntityPlayerServer.Play(defModule: string, defName: string, config: PlayConfig): any?
	local function execute(): any?
		local ok, defs = pcall(require, defModule)
		if not ok or type(defs) ~= "table" then
			warn("[EntityPlayerServer] def 로드 실패:", defModule, defs)
			return nil
		end
		local def: EntityController.EntityDef = (defs :: any)[defName]
		if not def then
			warn("[EntityPlayerServer] def 없음:", defName, "in", defModule)
			return nil
		end

		local part = config.part
		local ownPart = false
		if not part and def.model then
			local root = getModelRoot()
			local template = root and root:FindFirstChild(def.model, true)
			if template and template:IsA("Model") then
				part = (template :: Model):Clone()
				part.Parent = workspace
				ownPart = true
			end
		end

		local handle = EntityController.new(def, {
			part             = part,
			origin           = config.origin,
			move             = config.move,
			onMove           = config.onMove,
			onSpawn          = config.onSpawn,
			onHit            = config.onHit,
			onMiss           = config.onMiss,
			hitDetect        = config.hitDetect,
			colorFilter      = config.colorFilter,
			attackerPlayerId = config.attackerPlayerId,
			color            = config.color,
			params           = config.params,
			tags             = config.tags,
			firedAt          = config.firedAt,
		})

		handle.defModule = defModule
		handle.defName   = defName

		if ownPart and part then
			handle._maid:GiveTask(part)
		end

		return handle
	end

	if not config.delay or config.delay <= 0 then
		return execute()
	end

	local cancel = cancellableDelay(config.delay, function() execute() end)
	if config.taskMaid then
		config.taskMaid:GiveTask(cancel)
	end
	return nil
end

-- ─── PlayDirect ──────────────────────────────────────────────────────────────
function EntityPlayerServer.PlayDirect(config: PlayConfig): any?
	local function execute(): any?
		local emptyDef: EntityController.EntityDef = {}
		local handle = EntityController.new(emptyDef, {
			part             = config.part,
			origin           = config.origin,
			move             = config.move,
			onMove           = config.onMove,
			onSpawn          = config.onSpawn,
			onHit            = config.onHit,
			onMiss           = config.onMiss,
			hitDetect        = config.hitDetect,
			colorFilter      = config.colorFilter,
			attackerPlayerId = config.attackerPlayerId,
			params           = config.params,
			tags             = config.tags,
			firedAt          = config.firedAt,
		})
		return handle
	end

	if not config.delay or config.delay <= 0 then
		return execute()
	end

	local cancel = cancellableDelay(config.delay, function() execute() end)
	if config.taskMaid then
		config.taskMaid:GiveTask(cancel)
	end
	return nil
end

-- ─── Preload ─────────────────────────────────────────────────────────────────
function EntityPlayerServer.Preload(defModuleNames: { string })
	for _, modName in defModuleNames do
		if _preloaded[modName] then continue end
		_preloaded[modName] = true
		pcall(require, modName)
	end
end

return EntityPlayerServer
