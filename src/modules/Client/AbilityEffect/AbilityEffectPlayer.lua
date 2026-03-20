--!strict
--[=[
	@class AbilityEffectPlayer

	AbilityEffectControllerClient를 감싸는 편의 유틸. (Client)

	담당:
	- DefModule 로드 + 이펙트 정의 파싱
	- 모델 Preload (ContentProvider)
	- AbilityEffectControllerClient.new() 호출
	- AbilityEffectReplicationRemoting 전송 (isOwner=true 시)

	Play 흐름:
	  1. DefModule require → effectDef 파싱
	  2. spawnConfig 적용한 origin 계산
	  3. AbilityEffectControllerClient.new()
	  4. isOwner=true면 EffectFired 전송
	  5. isOwner=true면 Register 전송
	  6. handle 반환

	PlayOptions:
	  {
	      origin            : CFrame | () -> CFrame,
	      color             : Color3?,
	      delay             : number?,
	      abilityEffectMaid : any?,      -- 대기 중 취소용
	      params            : { [string]: any }?,
	      isOwner           : boolean?,
	      userId            : number?,   -- isOwner=false 시 색상 계산용
	      firedAt           : number?,   -- 복제 수신 시 fast-forward용
	      teamContext       : { attackerChar, attackerPlayer, teamService }?,
	      -- DefModule 동작 덮어쓰기 (클라이언트 연이첤용만)
	      move   : MoveFunction?,
	      onMove : OnMoveCallback?,
	      onHit  : HitCallback?,
	      onMiss : MissCallback?,
	  }
]=]

local require = require(script.Parent.loader).load(script)

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AbilityEffectControllerClient = require("AbilityEffectControllerClient")
local AbilityEffectReplicationRemoting = require("AbilityEffectReplicationRemoting")
local Maid = require("Maid")
local cancellableDelay = require("cancellableDelay")

-- ─── 모델 프리로드 캐시 ─────────────────────────────────────────────────────────

local _preloaded: { [string]: boolean } = {}

local function getModelRoot(): Instance?
	return ReplicatedStorage:FindFirstChild("AbilityEffects", true)
end

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type PlayOptions = {
	origin: CFrame | (() -> CFrame),
	color: Color3?,
	delay: number?,
	abilityEffectMaid: any?,
	params: { [string]: any }?,
	isOwner: boolean?,
	userId: number?,
	firedAt: number?,
	teamContext: { attackerChar: Model?, attackerPlayer: any?, teamService: any? }?,
	move: AbilityEffectControllerClient.MoveFunction?,
	onMove: AbilityEffectControllerClient.OnMoveCallback?,
	onHit: AbilityEffectControllerClient.HitCallback?,
	onMiss: AbilityEffectControllerClient.MissCallback?,
}

-- ─── 모듈 ────────────────────────────────────────────────────────────────────

local AbilityEffectPlayer = {}

--[=[
	DefModule의 models 목록을 ContentProvider로 Preload.
	게임 시작 시 등록된 DefModule 이름 목록을 넘기세요.
]=]
function AbilityEffectPlayer.Preload(defModuleNames: { string })
	local toLoad: { Instance } = {}
	for _, name in defModuleNames do
		if _preloaded[name] then
			continue
		end
		_preloaded[name] = true
		local ok, defs = pcall(require, name)
		if not ok or type(defs) ~= "table" then
			continue
		end
		local models = (defs :: any).models
		if type(models) ~= "table" then
			continue
		end
		local root = getModelRoot()
		if not root then
			continue
		end
		for _, modelName in models do
			local m = root:FindFirstChild(modelName)
			if m then
				table.insert(toLoad, m)
			end
		end
	end
	if #toLoad > 0 then
		ContentProvider:PreloadAsync(toLoad)
	end
end

--[=[
	DefModule + effectName으로 이펙트를 재생합니다.
	delay가 있으면 abilityEffectMaid에 cancel 등록 후 대기.
	대기 중 abilityEffectMaid 파괴 시 취소.
	이미 발사된 handle의 onHit/onMiss는 abilityEffectMaid와 무관.
	@return handle? (즉시 발사 시) 또는 nil (대기 중)
]=]
function AbilityEffectPlayer.Play(
	defModuleName: string,
	effectName: string,
	options: PlayOptions
): AbilityEffectControllerClient.AbilityEffectHandle?
	local function execute(): AbilityEffectControllerClient.AbilityEffectHandle?
		-- DefModule 로드
		local ok, defs = pcall(require, defModuleName)
		if not ok or type(defs) ~= "table" then
			warn("[AbilityEffectPlayer] DefModule 로드 실패:", defModuleName)
			return nil
		end
		local baseDef: AbilityEffectControllerClient.AbilityEffectDef = (defs :: any)[effectName]
		if not baseDef then
			warn("[AbilityEffectPlayer] 이펙트 정의 없음:", effectName, "in", defModuleName)
			return nil
		end

		-- 덮어쓰기 적용 (클라이언트 연이첤 전용)
		local def: AbilityEffectControllerClient.AbilityEffectDef = {
			model = baseDef.model,
			move = options.move or baseDef.move,
			onMove = options.onMove or baseDef.onMove,
			onHit = options.onHit or baseDef.onHit,
			onMiss = options.onMiss or baseDef.onMiss,
			hitDetect = baseDef.hitDetect,
			colorFilter = baseDef.colorFilter,
			spawnConfig = baseDef.spawnConfig,
		}

		-- origin 계산
		local origin: CFrame
		if type(options.origin) == "function" then
			origin = (options.origin :: () -> CFrame)()
		else
			origin = options.origin :: CFrame
		end

		-- 색상 결정
		local color = options.color

		local isOwner = options.isOwner ~= false

		-- handle 생성
		local handle =
			AbilityEffectControllerClient.new(def, origin, color, options.params, isOwner, options.teamContext)

		-- 복제 전송 (isOwner인 경우만)
		if isOwner then
			local sentAt = Workspace:GetServerTimeNow()
			-- EffectFired: 비주얼 복제용
			AbilityEffectReplicationRemoting.EffectFired:FireServer(
				defModuleName,
				effectName,
				handle.spawnCFrame,
				sentAt
			)
			-- Register: 서버 시뮬용
			AbilityEffectReplicationRemoting.Register:FireServer(
				defModuleName,
				effectName,
				handle.spawnCFrame,
				sentAt,
				options.params
			)
		end

		return handle
	end

	-- delay 없으면 즉시 실행
	if not options.delay or options.delay <= 0 then
		return execute()
	end

	-- delay 있으면 예약
	local cancel = cancellableDelay(options.delay, function()
		execute()
	end)
	if options.abilityEffectMaid then
		options.abilityEffectMaid:GiveTask(cancel)
	end
	return nil
end

export type AbilityEffectPlayer = typeof(AbilityEffectPlayer)
return AbilityEffectPlayer
