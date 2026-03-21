--!strict
--[=[
	@class SkillClient

	스킬 클라이언트 서비스. (stub)

	TODO: 스킬 시스템 구현 예정
]=]

local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local SkillRemoting = require("SkillRemoting") -- luacheck: ignore

export type SkillClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
	},
	{} :: typeof({ __index = {} })
))

local SkillClient = {}
SkillClient.ServiceName = "SkillClient"
SkillClient.__index = SkillClient

function SkillClient.Init(self: SkillClient, serviceBag: ServiceBag.ServiceBag): ()
	self._serviceBag = serviceBag
	self._maid = Maid.new()
end

function SkillClient.Start(_self: SkillClient): ()
	-- TODO: 스킬 입력 감지 및 조준 로직 구현 예정
end

function SkillClient:IsFiring(): boolean
	return false
end

function SkillClient:IsToggleFiring(): boolean
	return false
end

function SkillClient:IsBlockingAim(): boolean
	return false
end

function SkillClient:GetBlockAimTypes(): { string }?
	return nil
end

function SkillClient:CancelCombatState()
	-- TODO
end

function SkillClient.Destroy(self: SkillClient)
	self._maid:Destroy()
end

return SkillClient
