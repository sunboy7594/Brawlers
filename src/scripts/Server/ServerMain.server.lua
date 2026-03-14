--!strict
--[[
	@class ServerMain
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- ─── Loader 부트스트랩 ────────────────────────────────────────────────────────
-- MovementRemoting / ClassRemoting이 Init() 시점에 자동으로 RemoteEvent를 생성하므로
-- 수동 RemoteEvent 생성 코드 불필요
local loader = ServerScriptService.Brawlers:FindFirstChild("LoaderUtils", true).Parent
local require = require(loader).bootstrapGame(ServerScriptService.Brawlers)

local serviceBag = require("ServiceBag").new()
serviceBag:GetService(require("BrawlersService"))
serviceBag:GetService(require("TagService"))
serviceBag:GetService(require("BasicMovementService"))
-- 어빌리티 서비스 (LoadoutRemoting을 Init에서 선언하므로 MovementService 이후에 등록)
serviceBag:GetService(require("BasicAttackService"))
serviceBag:GetService(require("PassiveService"))
serviceBag:GetService(require("SkillService"))
serviceBag:GetService(require("UltimateService"))

serviceBag:Init()
serviceBag:Start()
