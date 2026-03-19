--!strict
--[[
	@class ServerMain
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local loader = ServerScriptService.Brawlers:FindFirstChild("LoaderUtils", true).Parent
local require = require(loader).bootstrapGame(ServerScriptService.Brawlers)

local serviceBag = require("ServiceBag").new()

-- ─── Core ────────────────────────────────────────────────
serviceBag:GetService(require("BrawlersService"))
serviceBag:GetService(require("TagService"))
serviceBag:GetService(require("BasicAttackService"))
serviceBag:GetService(require("ClassService"))
serviceBag:GetService(require("TeamService"))
serviceBag:GetService(require("HpService"))

-- ─── Movement ───────────────────────────────────────────
serviceBag:GetService(require("BasicMovementService"))

-- ─── Ability System ──────────────────────────────────────
serviceBag:GetService(require("PassiveService"))
serviceBag:GetService(require("SkillService"))
serviceBag:GetService(require("UltimateService"))
serviceBag:GetService(require("AnimReplicationService"))
serviceBag:GetService(require("PlayerStateControllerService"))

-- ─── AbilityEffect ───────────────────────────────────────────
-- AbilityEffectReplicationService: EffectFired → 타 클라이언트 포워딩
-- AbilityEffectSimulatorService: Register → 서버 시뮬 + 판정
serviceBag:GetService(require("AbilityEffectReplicationService"))
serviceBag:GetService(require("AbilityEffectSimulatorService"))

serviceBag:Init()
serviceBag:Start()
