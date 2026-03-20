--!strict
--[=[
	@class EntityPlayer (Client)

	EntityController를 감싸는 클라이언트 편의 유틸.

	Play(defModule, defName, config):
	  - def 파일 로드
	  - def.model로 ReplicatedStorage에서 Clone
	  - EntityController.new() 생성
	  - replicate=true면 EntityFired:FireServer

	PlayDirect(config):
	  - def 없이 직접 실행
	  - 로컈만, 복제 불가

	Preload(defModuleNames):
	  - ContentProvider:PreloadAsync + def 모듈 쾐싱
]=]

local require = require(script.Parent.loader).load(script)

local ContentProvider   = game:GetService("ContentProvider")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EntityController          = require("EntityController")
local EntityReplicationRemoting = require("EntityReplicationRemoting")
local cancellableDelay          = require("cancellableDelay")

local _preloaded: { [string]: boolean } = {}

local function getModelRoot(): Instance?
	return ReplicatedStorage:FindFirstChild("Entities", true)
		or ReplicatedStorage:FindFirstChild("AbilityEffects", true)
end

export type PlayConfig = {
	part             : any?,
	origin           : CFrame | (() -> CFrame),
	move             : any?,
	onMove           : any?,
	onSpawn          : any?,
	onHit            : any?,
	onMiss           : any?,
	hitDetect        : any?,
	colorFilter      : any?,
	attackerPlayerId : number?,
	color            : Color3?,
	params           : { [string]: any }?,
	tags             : { string }?,
	replicate        : boolean?,
	taskMaid         : any?,
	firedAt          : number?,
	delay            : number?,
}

local EntityPlayer = {}

function EntityPlayer.Play(
	defModule : string,
	defName   : string,
	config    : PlayConfig
): any?
	local function execute(): any?
		local ok, defs = pcall(require, defModule)
		if not ok or type(defs) ~= "table" then
			warn("[EntityPlayer] def 로드 실패:", defModule, defs)
			return nil
		end
		local def: EntityController.EntityDef = (defs :: any)[defName]
		if not def then
			warn("[EntityPlayer] def 없음:", defName, "in", defModule)
			return nil
		end

		local origin: CFrame
		if type(config.origin) == "function" then
			origin = (config.origin :: () -> CFrame)()
		else
			origin = config.origin :: CFrame
		end

		-- 모델 Clone
		local part = config.part
		local ownPart = false
		if not part and def.model then
			local root     = getModelRoot()
			local template = root and root:FindFirstChild(def.model, true)
			if template and template:IsA("Model") then
				part = (template :: Model):Clone()
				part.Parent = workspace
				ownPart = true
			end
		end

		local handle = EntityController.new(def, {
			part             = part,
			origin           = origin,
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
			replicate        = config.replicate,
			taskMaid         = config.taskMaid,
			firedAt          = config.firedAt,
		})

		handle.defModule = defModule
		handle.defName   = defName

		-- 직접 Clone한 모델은 handle maid에 등록
		if ownPart and part then
			handle._maid:GiveTask(part)
		end

		-- 복제
		if config.replicate == true then
			EntityReplicationRemoting.EntityFired:FireServer(
				defModule,
				defName,
				handle.spawnCFrame,
				Workspace:GetServerTimeNow(),
				config.params,
				handle.tags
			)
		end

		return handle
	end

	if not config.delay or config.delay <= 0 then return execute() end

	local cancel = cancellableDelay(config.delay, function() execute() end)
	if config.taskMaid then config.taskMaid:GiveTask(cancel) end
	return nil
end

function EntityPlayer.PlayDirect(config: PlayConfig): any?
	local function execute(): any?
		local origin: CFrame
		if type(config.origin) == "function" then
			origin = (config.origin :: () -> CFrame)()
		else
			origin = config.origin :: CFrame
		end

		local emptyDef: EntityController.EntityDef = {}
		local handle = EntityController.new(emptyDef, {
			part             = config.part,
			origin           = origin,
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

		-- 직접 넘기지 않은 part는 어차피 외부에서 생성한 것, maid 등록 불필요

		return handle
	end

	if not config.delay or config.delay <= 0 then return execute() end

	local cancel = cancellableDelay(config.delay, function() execute() end)
	if config.taskMaid then config.taskMaid:GiveTask(cancel) end
	return nil
end

function EntityPlayer.Preload(defModuleNames: { string })
	local root = getModelRoot()
	for _, modName in defModuleNames do
		if _preloaded[modName] then continue end
		_preloaded[modName] = true
		local ok, defs = pcall(require, modName)
		if not ok or type(defs) ~= "table" then continue end
		if not root then continue end
		local assets: { Instance } = {}
		for _, def in defs :: any do
			if type(def) ~= "table" then continue end
			local d = def :: any
			if d.model then
				local template = root:FindFirstChild(d.model, true)
				if template then table.insert(assets, template) end
			end
		end
		if #assets > 0 then ContentProvider:PreloadAsync(assets) end
	end
end

return EntityPlayer
