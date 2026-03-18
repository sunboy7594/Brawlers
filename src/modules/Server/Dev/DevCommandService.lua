--!strict
--[=[
	@class DevCommandService

	개발용 Cmdr 커맨드 등록 서비스.
	BrawlersService.Init에서 GetService로 등록할 것.

	커맨드 목록:
	  set-class <className>            클래스 변경
	  set-team <teamIndex>             팀 배정 (팀이 없으면 자동 생성)
	  ffa                              FFA(팀 없음) 상태
	  create-teams <count>             N개 팀 생성
	  apply-effect <name> [dur] [f]    이펙트 적용 (PlayerStateUtils 빌더명)
	  cleanse                          클렌즈 (모든 CC 제거)
	  clear-effects                    모든 이펙트 강제 제거
	  list-effects                     활성 이펙트 목록 출력
	  kill-me                          즉사
	  heal-me                          HP 완전 회복
	  hp-info                          현재 HP 출력
	  resource-log on|off              Heartbeat마다 리소스 현황 출력 토글
]=]

local require = require(script.Parent.loader).load(script)

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local BasicAttackService = require("BasicAttackService")
local ClassService = require("ClassService")
local CmdrService = require("CmdrService")
local HpService = require("HpService")
local Maid = require("Maid")
local PlayerStateControllerService = require("PlayerStateControllerService")
local PlayerStateUtils = require("PlayerStateUtils")
local ServiceBag = require("ServiceBag")
local TeamService = require("TeamService")

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type DevCommandService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_cmdrService: any,
		_classService: any,
		_teamService: any,
		_hpService: any,
		_psc: any,
		_basicAttackService: any,
		_resourceLogMaid: Maid.Maid,
	},
	{} :: typeof({ __index = {} })
))

-- ─── 서비스 ──────────────────────────────────────────────────────────────────

local DevCommandService = {}
DevCommandService.ServiceName = "DevCommandService"
DevCommandService.__index = DevCommandService

function DevCommandService.Init(self: DevCommandService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()

	self._cmdrService = serviceBag:GetService(CmdrService)
	self._classService = serviceBag:GetService(ClassService)
	self._teamService = serviceBag:GetService(TeamService)
	self._hpService = serviceBag:GetService(HpService)
	self._psc = serviceBag:GetService(PlayerStateControllerService)
	self._basicAttackService = serviceBag:GetService(BasicAttackService)

	self._resourceLogMaid = Maid.new()
	self._maid:GiveTask(self._resourceLogMaid)
end

function DevCommandService.Start(self: DevCommandService): ()
	self:_registerCommands()
end

-- ─── 내부 유틸 ────────────────────────────────────────────────────────────────

-- Cmdr context에서 실행자 Player를 꺼냅니다.
local function getPlayer(context: any): Player?
	return context.Executor
end

-- ─── 커맨드 등록 ──────────────────────────────────────────────────────────────

function DevCommandService:_registerCommands()
	local cmdr = self._cmdrService

	-- ── 1. set-class ──────────────────────────────────────────────────────────
	cmdr:RegisterCommand({
		Name = "set-class",
		Aliases = { "sc" },
		Description = "[Dev] 자신의 클래스를 변경합니다.",
		Args = {
			{
				Type = "string",
				Name = "className",
				Description = "클래스 이름 (예: Tank, Default)",
			},
		},
	}, function(context, className: string)
		local player = getPlayer(context)
		if not player then
			return "플레이어를 찾을 수 없습니다."
		end
		local ok, err = pcall(function()
			self._classService:SetClass(player, className)
		end)
		if not ok then
			return "클래스 변경 실패: " .. tostring(err)
		end
		return string.format("[Dev] 클래스 → '%s'", className)
	end)

	-- ── 2. set-team ───────────────────────────────────────────────────────────
	cmdr:RegisterCommand({
		Name = "set-team",
		Aliases = { "st" },
		Description = "[Dev] 지정 팀 번호에 배정합니다. 팀이 부족하면 자동 생성.",
		Args = {
			{
				Type = "integer",
				Name = "teamIndex",
				Description = "팀 번호 (1부터)",
			},
		},
	}, function(context, teamIndex: number)
		local player = getPlayer(context)
		if not player then
			return "플레이어를 찾을 수 없습니다."
		end
		-- 팀이 부족하면 자동 생성
		if self._teamService:GetTeamCount() < teamIndex then
			self._teamService:CreateTeams(teamIndex)
		end
		local ok, err = pcall(function()
			self._teamService:AssignTeam(player, teamIndex)
		end)
		if not ok then
			return "팀 배정 실패: " .. tostring(err)
		end
		return string.format("[Dev] Team%d 배정 완료.", teamIndex)
	end)

	-- ── 3. ffa ────────────────────────────────────────────────────────────────
	cmdr:RegisterCommand({
		Name = "ffa",
		Aliases = {},
		Description = "[Dev] FFA(팀 없음) 상태로 변경합니다.",
		Args = {},
	}, function(context)
		local player = getPlayer(context)
		if not player then
			return "플레이어를 찾을 수 없습니다."
		end
		self._teamService:ClearPlayerTeam(player)
		return "[Dev] FFA 상태로 변경됐습니다."
	end)

	-- ── 4. create-teams ───────────────────────────────────────────────────────
	cmdr:RegisterCommand({
		Name = "create-teams",
		Aliases = { "ct" },
		Description = "[Dev] N개의 팀을 생성합니다. 기존 팀은 제거됩니다.",
		Args = {
			{
				Type = "integer",
				Name = "count",
				Description = "팀 수",
			},
		},
	}, function(_context, count: number)
		local ok, err = pcall(function()
			self._teamService:CreateTeams(count)
		end)
		if not ok then
			return "팀 생성 실패: " .. tostring(err)
		end
		return string.format("[Dev] %d개 팀을 생성했습니다.", count)
	end)

	-- ── 5. apply-effect (PlayPlayerState) ────────────────────────────────────
	-- params JSON 예시: {"duration":5,"force":true,"intensity":0.9}
	-- 지원 키: duration, force, intensity, multiplier, amount, knockbackForce
	cmdr:RegisterCommand({
		Name = "apply-effect",
		Aliases = { "ae" },
		Description = '[Dev] PlayPlayerState. 예) ae stun {"duration":3,"force":true}',
		Args = {
			{
				Type = "string",
				Name = "effectName",
				Description = "빌더명 (stun/slow/burn/poison/freeze/knockback/hyperArmor/ignoreDamage/cleanse/vulnerable/damage/airborne)",
			},
			{
				Type = "string",
				Name = "paramsJson",
				Description = 'params JSON (선택). 예: {"duration":5,"force":true,"intensity":0.9}',
				Optional = true,
			},
		},
	}, function(context, effectName: string, paramsJson: string?)
		local player = getPlayer(context)
		if not player then
			return "플레이어를 찾을 수 없습니다."
		end

		local params = {}
		if paramsJson and paramsJson ~= "" then
			local ok, decoded = pcall(HttpService.JSONDecode, HttpService, paramsJson)
			if not ok then
				return "JSON 파싱 실패: " .. tostring(decoded)
			end
			params = decoded
		end

		local ok, err = pcall(function()
			PlayerStateUtils.PlayPlayerState(self._psc, player, effectName, params)
		end)
		if not ok then
			return "이펙트 적용 실패: " .. tostring(err)
		end
		return string.format("[Dev] PlayPlayerState '%s' 완료. params: %s", effectName, paramsJson or "{}")
	end)

	-- ── 5b. apply-effect-repeat (PlayPlayerStateRepeat) ──────────────────────
	-- params JSON 예시: {"amount":10,"totalDuration":8,"count":4}
	cmdr:RegisterCommand({
		Name = "apply-effect-repeat",
		Aliases = { "aer" },
		Description = '[Dev] PlayPlayerStateRepeat. 예) aer burn {"amount":5,"totalDuration":10,"count":6}',
		Args = {
			{
				Type = "string",
				Name = "effectName",
				Description = "빌더명 (burn/poison/damage 등 도트 계열)",
			},
			{
				Type = "string",
				Name = "paramsJson",
				Description = "params JSON (선택). totalDuration/count/amount 등",
				Optional = true,
			},
		},
	}, function(context, effectName: string, paramsJson: string?)
		local player = getPlayer(context)
		if not player then
			return "플레이어를 찾을 수 없습니다."
		end

		local params = {}
		if paramsJson and paramsJson ~= "" then
			local ok, decoded = pcall(HttpService.JSONDecode, HttpService, paramsJson)
			if not ok then
				return "JSON 파싱 실패: " .. tostring(decoded)
			end
			params = decoded
		end

		local ok, err = pcall(function()
			PlayerStateUtils.PlayPlayerStateRepeat(self._psc, player, effectName, params)
		end)
		if not ok then
			return "반복 이펙트 적용 실패: " .. tostring(err)
		end
		return string.format("[Dev] PlayPlayerStateRepeat '%s' 완료. params: %s", effectName, paramsJson or "{}")
	end)

	-- ── 6. cleanse ────────────────────────────────────────────────────────────
	cmdr:RegisterCommand({
		Name = "cleanse",
		Aliases = { "cl" },
		Description = "[Dev] 자신의 모든 CC를 클렌즈합니다 (force).",
		Args = {},
	}, function(context)
		local player = getPlayer(context)
		if not player then
			return "플레이어를 찾을 수 없습니다."
		end
		PlayerStateUtils.PlayPlayerState(self._psc, player, "cleanse", { force = true })
		return "[Dev] 클렌즈 완료."
	end)

	-- ── 7. clear-effects ──────────────────────────────────────────────────────
	cmdr:RegisterCommand({
		Name = "clear-effects",
		Aliases = { "cle" },
		Description = "[Dev] 자신의 모든 이펙트를 강제 제거합니다.",
		Args = {},
	}, function(context)
		local player = getPlayer(context)
		if not player then
			return "플레이어를 찾을 수 없습니다."
		end
		self._psc:StopAll(player, true)
		return "[Dev] 모든 이펙트 제거 완료."
	end)

	-- ── 8. list-effects (GetAppliedBuilders) ──────────────────────────────────
	-- 기존과 동일하나 명확히 GetAppliedBuilders 호출임을 명시
	cmdr:RegisterCommand({
		Name = "list-effects",
		Aliases = { "le" },
		Description = "[Dev] GetAppliedBuilders — 현재 적용된 이펙트 목록 출력.",
		Args = {},
	}, function(context)
		local player = getPlayer(context)
		if not player then
			return "플레이어를 찾을 수 없습니다."
		end

		local effects = PlayerStateUtils.GetAppliedBuilders(self._psc, player)
		if #effects == 0 then
			return "[Dev] 적용된 이펙트 없음."
		end

		local lines: { string } = {}
		for _, e in effects do
			local rem = if e.remaining then string.format("%.1fs", e.remaining) else "∞"
			table.insert(lines, string.format("  [%s] %s  남은: %s", e.id, e.builderName, rem))
		end
		return "[Dev] GetAppliedBuilders:\n" .. table.concat(lines, "\n")
	end)

	-- ── 9. kill-me ────────────────────────────────────────────────────────────
	cmdr:RegisterCommand({
		Name = "kill-me",
		Aliases = { "km" },
		Description = "[Dev] 즉시 사망합니다.",
		Args = {},
	}, function(context)
		local player = getPlayer(context)
		if not player then
			return "플레이어를 찾을 수 없습니다."
		end
		self._hpService:ApplyDamage(player, 999999)
		return "[Dev] 즉사 처리됐습니다."
	end)

	-- ── 10. heal-me ───────────────────────────────────────────────────────────
	cmdr:RegisterCommand({
		Name = "heal-me",
		Aliases = { "hm" },
		Description = "[Dev] HP를 최대로 회복합니다.",
		Args = {},
	}, function(context)
		local player = getPlayer(context)
		if not player then
			return "플레이어를 찾을 수 없습니다."
		end
		self._hpService:ApplyHeal(player, 999999)
		return "[Dev] HP 완전 회복."
	end)

	-- ── 11. hp-info ───────────────────────────────────────────────────────────
	cmdr:RegisterCommand({
		Name = "hp-info",
		Aliases = { "hp" },
		Description = "[Dev] 현재 HP를 출력합니다.",
		Args = {},
	}, function(context)
		local player = getPlayer(context)
		if not player then
			return "플레이어를 찾을 수 없습니다."
		end
		local current, max = self._hpService:GetHp(player)
		local pct = if max > 0 then math.floor(current / max * 100) else 0
		return string.format("[Dev] HP: %d / %d (%d%%)", current, max, pct)
	end)

	-- ── 12. resource-log ──────────────────────────────────────────────────────
	cmdr:RegisterCommand({
		Name = "resource-log",
		Aliases = { "rl" },
		Description = "[Dev] Heartbeat마다 리소스 현황을 Output에 출력합니다. on/off 토글.",
		Args = {
			{
				Type = "string",
				Name = "toggle",
				Description = "on 또는 off",
			},
		},
	}, function(context, toggle: string)
		local player = getPlayer(context)
		if not player then
			return "플레이어를 찾을 수 없습니다."
		end

		local lower = string.lower(toggle)

		if lower == "on" then
			-- 이미 켜져 있으면 기존 것 먼저 정리
			self._resourceLogMaid:DoCleaning()

			self._resourceLogMaid:GiveTask(RunService.Heartbeat:Connect(function()
				-- HP
				local current, max = self._hpService:GetHp(player)
				-- 클래스
				local className = self._classService:GetClass(player)
				-- 기본공격 리소스
				local state = (self._basicAttackService :: any)._playerStates[player.UserId]
				local resourceStr = "(없음)"
				if state then
					if state.resourceType == "stack" then
						resourceStr = string.format(
							"Stack %d/%d (reload %.2fs)",
							state.currentStack,
							state.maxStack,
							state.reloadTime
						)
					elseif state.resourceType == "gauge" then
						resourceStr = string.format("Gauge %.1f/%.1f", state.currentGauge, state.maxGauge)
					end
				end
				-- 활성 이펙트
				local effects = PlayerStateUtils.GetAppliedBuilders(self._psc, player)
				local effectNames: { string } = {}
				for _, e in effects do
					table.insert(effectNames, e.builderName)
				end
				local effectStr = if #effectNames > 0 then table.concat(effectNames, ", ") else "없음"

				print(
					string.format(
						"[DevLog] HP:%d/%d | Class:%s | %s | Effects:[%s]",
						current,
						max,
						className,
						resourceStr,
						effectStr
					)
				)
			end))

			return "[Dev] resource-log ON. 중지: resource-log off"
		elseif lower == "off" then
			self._resourceLogMaid:DoCleaning()
			return "[Dev] resource-log OFF."
		else
			return "사용법: resource-log on | off"
		end
	end)
	-- ── 13. set-attack ────────────────────────────────────────────────────────
	cmdr:RegisterCommand({
		Name = "set-attack",
		Aliases = { "sa" },
		Description = "[Dev] 기본공격 강제 변경. 예) sa Tank_Punch",
		Args = {
			{
				Type = "string",
				Name = "attackId",
				Description = "BasicAttackDefs의 키 (예: Tank_Punch, Tank_CannonTest)",
			},
		},
	}, function(context, attackId: string)
		local player = getPlayer(context)
		if not player then
			return "플레이어를 찾을 수 없습니다."
		end
		local ok, err = self._basicAttackService:ForceEquip(player, attackId)
		if not ok then
			return "기본공격 변경 실패: " .. tostring(err)
		end
		return string.format("[Dev] 기본공격 → '%s'", attackId)
	end)

	-- ── 14. set-skill ─────────────────────────────────────────────────────────
	cmdr:RegisterCommand({
		Name = "set-skill",
		Aliases = { "ss" },
		Description = "[Dev] 스킬 강제 변경. (미구현)",
		Args = {
			{ Type = "string", Name = "skillId", Description = "SkillDefs의 키" },
		},
	}, function(_context, skillId: string)
		return string.format("[Dev] set-skill '%s' → 스킬 시스템 미구현.", skillId)
	end)

	-- ── 15. set-ultimate ──────────────────────────────────────────────────────
	cmdr:RegisterCommand({
		Name = "set-ultimate",
		Aliases = { "su" },
		Description = "[Dev] 궁극기 강제 변경. (미구현)",
		Args = {
			{ Type = "string", Name = "ultimateId", Description = "UltimateDefs의 키" },
		},
	}, function(_context, ultimateId: string)
		return string.format("[Dev] set-ultimate '%s' → 궁극기 시스템 미구현.", ultimateId)
	end)
end

-- ─── 정리 ────────────────────────────────────────────────────────────────────

function DevCommandService.Destroy(self: DevCommandService): ()
	self._maid:Destroy()
end

return DevCommandService
