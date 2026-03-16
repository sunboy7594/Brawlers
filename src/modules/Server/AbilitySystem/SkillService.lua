--!strict
--[=[
	@class SkillService

	스킬 서버 서비스. (stub)

	TODO: 스킬 시스템 구현 예정
]=]

local require = require(script.Parent.loader).load(script)

local LoadoutRemoting = require("LoadoutRemoting")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local SkillRemoting = require("SkillRemoting") -- luacheck: ignore

export type SkillService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
	},
	{} :: typeof({ __index = {} })
))

local SkillService = {}
SkillService.ServiceName = "SkillService"
SkillService.__index = SkillService

function SkillService.Init(self: SkillService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
end

function SkillService.Start(_self: SkillService): ()
	-- TODO: 스킬 Cast 수신 및 쿨다운 관리 구현 예정

	-- 미구현 동안 InvokeServer 영구 yield 방지용 fail-safe
	LoadoutRemoting.RequestEquipSkill:Bind(function(_player, _skillId)
		return false, "미구현"
	end)
end

function SkillService.Destroy(self: SkillService)
	self._maid:Destroy()
end

return SkillService
