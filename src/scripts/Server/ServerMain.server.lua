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

-- ─── Core ────────────────────────────────────────
-- ClassService는 BasicAttackService를 GetService하므로 먼저 등록
-- TeamService는 HpService보다 먼저 등록 (HpService.Init에서 GetService)
-- HpService는 ClassService, TeamService를 GetService하므로 그 다음에 등록
-- PlayerStateService는 HpService를 GetService하므로 HpService 다음에 등록
serviceBag:GetService(require("BrawlersService"))
serviceBag:GetService(require("TagService"))
serviceBag:GetService(require("BasicAttackService"))
serviceBag:GetService(require("ClassService"))
serviceBag:GetService(require("TeamService"))
serviceBag:GetService(require("HpService"))

-- ─── Movement ────────────────────────────────────
-- BasicMovementService는 ClassService를 GetService
serviceBag:GetService(require("BasicMovementService"))

-- ─── Ability System ──────────────────────────────
serviceBag:GetService(require("PassiveService"))
serviceBag:GetService(require("SkillService"))
serviceBag:GetService(require("UltimateService"))
serviceBag:GetService(require("AnimReplicationService"))
serviceBag:GetService(require("PlayerStateService"))

serviceBag:Init()
serviceBag:Start()
