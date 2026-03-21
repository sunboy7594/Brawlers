--!strict
--[=[
	@class EntityPlayerServer

	EntityController를 감싸는 서버 편의 유틸.
	(서버 전용 - 클라이언트 EntityPlayer와 이름 충돌 방지를 위해 분리)

	Play(defModule, defName, config):
	  - def 파일 로드
	  - def.model로 ReplicatedStorage에서 Clone
	  - EntityController.new() 생성
	  - 서버에서 생성된 모델은 Roblox가 자동 복제
	  - 복제 트리거 불필요

	PlayDirect(config):
	  - def 없이 직접 실행

	PlayHRP(player, defModule, defName, config):
	  - part가 HRP인 경우 클라이언트에서 로컬 실행 (끊김 방지)
	  - 토큰 발급 → FireClient → 서버 착지 위치 검증
	  - BindLandingReport()를 서버 시작 시 한 번 호출해야 함

	BindLandingReport():
	  - LandingReport 이벤트 바인딩 (서버 시작 시 1회 호출)

	Preload(defModuleNames):
	  - def 모듈 캐싱 (ContentProvider 불필요)
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
-- [userId][token] = { expectedLanding, expiry, tolerance }
local _pendingMoves: {
	[number]: {
		[string]: {
			expectedLanding: Vector3,
			expiry: number,
			tolerance: number,
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
	origin: CFrame,
	params: { [string]: any }?,
	-- arc 총 소요 시간 (검증 타이머 기준)
	duration: number,
	-- 서버가 계산한 예상 착지 위치 (수평)
	expectedLanding: Vector3,
	-- 허용 오차 (스터드), 기본 9
	tolerance: number?,
}

local EntityPlayerServer = {}

-- ─── 내부: 착지 위치 검증 ─────────────────────────────────────────────────────
local function validateLanding(player: Player, expectedLanding: Vector3, tolerance: number)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end

	local actual = hrp.Position
	local diff = Vector3.new(
		actual.X - expectedLanding.X,
		0,
		actual.Z - expectedLanding.Z
	).Magnitude

	if diff > tolerance then
		-- 예상 착지 위치로 강제 보정 (Y는 실제값 유지)
		hrp:PivotTo(CFrame.new(expectedLanding.X, actual.Y, expectedLanding.Z))
	end
end

-- ─── PlayHRP ─────────────────────────────────────────────────────────────────
--[=[
	서버 권한 부여 후 클라이언트에서 HRP를 직접 이동.

	흐름:
	  1. 토큰 생성 및 저장
	  2. FireClient(player) → 클라이언트가 로컬 arc 실행
	  3. duration + buffer 후 착지 위치 검증
	     클라이언트가 먼저 LandingReport를 보내면 즉시 검증 후 토큰 소멸
]=]
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
		expectedLanding = config.expectedLanding,
		expiry          = os.clock() + config.duration + 1.5,
		tolerance       = tolerance,
	}

	-- 클라이언트에 이동 권한 부여
	HRPMoveRemoting.Move:FireClient(
		player,
		token,
		defModule,
		defName,
		config.origin,
		config.params
	)

	-- fallback: 클라이언트가 LandingReport를 안 보낼 경우 서버가 직접 검증
	task.delay(config.duration + 0.6, function()
		local pending = _pendingMoves[userId]
		if not pending or not pending[token] then return end
		pending[token] = nil
		validateLanding(player, config.expectedLanding, tolerance)
	end)
end

-- ─── BindLandingReport ───────────────────────────────────────────────────────
--[=[
	LandingReport 이벤트를 바인딩합니다.
	서버 서비스 Start() 시 1회 호출해야 합니다.
	(예: BasicAttackService.Start 또는 별도 HRPMoveService.Start)
]=]
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
		if not p then return end  -- 없거나 이미 소멸된 토큰 → 무시

		-- 토큰 즉시 소멸 (재사용 방지)
		pending[token] = nil

		-- 만료 확인
		if os.clock() > p.expiry then
			validateLanding(player, p.expectedLanding, p.tolerance)
			return
		end

		-- 착지 위치 검증
		local diff = Vector3.new(
			actualPos.X - p.expectedLanding.X,
			0,
			actualPos.Z - p.expectedLanding.Z
		).Magnitude

		if diff > p.tolerance then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				local el = p.expectedLanding
				hrp:PivotTo(CFrame.new(el.X, hrp.Position.Y, el.Z))
			end
		end
	end)

	-- 플레이어 퇴장 시 토큰 정리
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
