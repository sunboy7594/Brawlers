--!strict
--[=[
	@class DevCommandClientService

	개발용 클라이언트 전용 Cmdr 커맨드 등록 서비스.
	ClientMain에서 GetService로 등록할 것.

	커맨드 목록:
	  set-attack <attackId>    기본공격 변경 (LoadoutRemoting 경유)
	  set-skill <skillId>      스킬 변경 (미구현 stub)
	  set-ultimate <ultimateId> 궁극기 변경 (미구현 stub)
]=]

local require = require(script.Parent.loader).load(script)

local BasicAttackClient = require("BasicAttackClient")
local CmdrServiceClient = require("CmdrServiceClient")
local LoadoutRemoting = require("LoadoutRemoting")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type DevCommandClientService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_cmdrClient: any,
		_basicAttackClient: BasicAttackClient.BasicAttackClient,
	},
	{} :: typeof({ __index = {} })
))

-- ─── 서비스 ──────────────────────────────────────────────────────────────────

local DevCommandClientService = {}
DevCommandClientService.ServiceName = "DevCommandClientService"
DevCommandClientService.__index = DevCommandClientService

function DevCommandClientService.Init(self: DevCommandClientService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._cmdrClient = serviceBag:GetService(CmdrServiceClient)
	self._basicAttackClient = serviceBag:GetService(BasicAttackClient)
end

function DevCommandClientService.Start(self: DevCommandClientService): ()
	self:_registerCommands()
end

-- ─── 커맨드 등록 ──────────────────────────────────────────────────────────────

function DevCommandClientService:_registerCommands()
	local cmdr = self._cmdrClient
	local basicAttackClient = self._basicAttackClient

	-- ── set-attack ────────────────────────────────────────────────────────────
	cmdr:RegisterCommand({
		Name = "set-attack",
		Aliases = { "sa" },
		Description = "[Dev] 기본공격을 변경합니다. 예) sa Tank_Punch",
		Args = {
			{
				Type = "string",
				Name = "attackId",
				Description = "BasicAttackDefs의 키 (예: Tank_Punch, Tank_CannonTest)",
			},
		},
	}, function(_context, attackId: string)
		local success, result = LoadoutRemoting.RequestEquipBasicAttack:InvokeServer(attackId)
		if success then
			basicAttackClient:SetEquippedAttack(attackId)
			return string.format("[Dev] 기본공격 → '%s'", attackId)
		end
		return "실패: " .. tostring(result)
	end)

	-- ── set-skill ─────────────────────────────────────────────────────────────
	cmdr:RegisterCommand({
		Name = "set-skill",
		Aliases = { "ss" },
		Description = "[Dev] 스킬을 변경합니다. (미구현)",
		Args = {
			{
				Type = "string",
				Name = "skillId",
				Description = "SkillDefs의 키",
			},
		},
	}, function(_context, skillId: string)
		-- TODO: SkillService 구현 후 LoadoutRemoting.RequestEquipSkill 연결
		return string.format("[Dev] set-skill '%s' → 스킬 시스템 미구현.", skillId)
	end)

	-- ── set-ultimate ──────────────────────────────────────────────────────────
	cmdr:RegisterCommand({
		Name = "set-ultimate",
		Aliases = { "su" },
		Description = "[Dev] 궁극기를 변경합니다. (미구현)",
		Args = {
			{
				Type = "string",
				Name = "ultimateId",
				Description = "UltimateDefs의 키",
			},
		},
	}, function(_context, ultimateId: string)
		-- TODO: UltimateService 구현 후 LoadoutRemoting.RequestEquipUltimate 연결
		return string.format("[Dev] set-ultimate '%s' → 궁극기 시스템 미구현.", ultimateId)
	end)
end

-- ─── 정리 ────────────────────────────────────────────────────────────────────

function DevCommandClientService.Destroy(self: DevCommandClientService): ()
	self._maid:Destroy()
end

return DevCommandClientService
