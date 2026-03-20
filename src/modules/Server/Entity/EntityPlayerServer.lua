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

	Preload(defModuleNames):
	  - def 모듈 쾐싱 (ContentProvider 불필요)
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EntityController = require("EntityController")
local cancellableDelay = require("cancellableDelay")

local _preloaded: { [string]: boolean } = {}

local function getModelRoot(): Instance?
	return ReplicatedStorage:FindFirstChild("Entities", true)
		or ReplicatedStorage:FindFirstChild("AbilityEffects", true)
end

export type PlayConfig = {
	part             : any?,
	origin           : CFrame,
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
	taskMaid         : any?,
	firedAt          : number?,
	delay            : number?,
}

local EntityPlayerServer = {}

function EntityPlayerServer.Play(
	defModule : string,
	defName   : string,
	config    : PlayConfig
): any?
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

	if not config.delay or config.delay <= 0 then return execute() end

	local cancel = cancellableDelay(config.delay, function() execute() end)
	if config.taskMaid then config.taskMaid:GiveTask(cancel) end
	return nil
end

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

	if not config.delay or config.delay <= 0 then return execute() end

	local cancel = cancellableDelay(config.delay, function() execute() end)
	if config.taskMaid then config.taskMaid:GiveTask(cancel) end
	return nil
end

function EntityPlayerServer.Preload(defModuleNames: { string })
	for _, modName in defModuleNames do
		if _preloaded[modName] then continue end
		_preloaded[modName] = true
		pcall(require, modName)
	end
end

return EntityPlayerServer
