--!strict
--[=[
	@class AbilityEffectPlayer

	AbilityEffectControllerClient를 감싼는 편의 유틸. (Client)

	변경:
	  Register:FireServer() 제거.
	  서버 투사체 판정은 서버 모듈 onFire에서 ProjectileHit.fire()로 직접 처리.
	  EffectFired는 타 클라이언트 연출 복제 전용으로만 사용.
]=]

local require = require(script.Parent.loader).load(script)

local ContentProvider   = game:GetService("ContentProvider")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local AbilityEffectControllerClient    = require("AbilityEffectControllerClient")
local AbilityEffectReplicationRemoting = require("AbilityEffectReplicationRemoting")
local Maid             = require("Maid")
local cancellableDelay = require("cancellableDelay")

local _preloaded: { [string]: boolean } = {}

local function getModelRoot(): Instance?
	return ReplicatedStorage:FindFirstChild("AbilityEffects", true)
end

export type PlayOptions = {
	origin            : CFrame | (() -> CFrame),
	color             : Color3?,
	delay             : number?,
	abilityEffectMaid : any?,
	params            : { [string]: any }?,
	isOwner           : boolean?,
	userId            : number?,
	firedAt           : number?,
	teamContext       : { attackerChar: Model?, attackerPlayer: any?, teamService: any? }?,
	move              : AbilityEffectControllerClient.MoveFunction?,
	onMove            : AbilityEffectControllerClient.OnMoveCallback?,
	onHit             : AbilityEffectControllerClient.HitCallback?,
	onMiss            : AbilityEffectControllerClient.MissCallback?,
}

local AbilityEffectPlayer = {}

function AbilityEffectPlayer.Preload(defModuleNames: { string })
	local root = getModelRoot()
	if not root then return end
	for _, modName in defModuleNames do
		if _preloaded[modName] then continue end
		_preloaded[modName] = true
		local ok, defs = pcall(require, modName)
		if not ok or type(defs) ~= "table" then continue end
		local assets: { Instance } = {}
		for _, def in defs :: any do
			if type(def) ~= "table" then continue end
			if def.model then
				local template = root:FindFirstChild(def.model)
				if template then table.insert(assets, template) end
			end
		end
		if #assets > 0 then ContentProvider:PreloadAsync(assets) end
	end
end

function AbilityEffectPlayer.Play(
	defModuleName : string,
	effectName    : string,
	options       : PlayOptions
): AbilityEffectControllerClient.AbilityEffectHandle?
	local function execute(): AbilityEffectControllerClient.AbilityEffectHandle?
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

		local def: AbilityEffectControllerClient.AbilityEffectDef = {
			model       = baseDef.model,
			move        = options.move   or baseDef.move,
			onMove      = options.onMove or baseDef.onMove,
			onHit       = options.onHit  or baseDef.onHit,
			onMiss      = options.onMiss or baseDef.onMiss,
			hitDetect   = baseDef.hitDetect,
			colorFilter = baseDef.colorFilter,
			spawnConfig = baseDef.spawnConfig,
		}

		local origin: CFrame
		if type(options.origin) == "function" then
			origin = (options.origin :: () -> CFrame)()
		else
			origin = options.origin :: CFrame
		end

		local isOwner = options.isOwner ~= false
		local handle = AbilityEffectControllerClient.new(
			def, origin, options.color, options.params, isOwner, options.teamContext
		)

		if isOwner then
			AbilityEffectReplicationRemoting.EffectFired:FireServer(
				defModuleName, effectName, handle.spawnCFrame, Workspace:GetServerTimeNow()
			)
		end

		return handle
	end

	if not options.delay or options.delay <= 0 then return execute() end

	local cancel = cancellableDelay(options.delay, function() execute() end)
	if options.abilityEffectMaid then options.abilityEffectMaid:GiveTask(cancel) end
	return nil
end

export type AbilityEffectPlayer = typeof(AbilityEffectPlayer)
return AbilityEffectPlayer
