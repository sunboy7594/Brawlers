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
serviceBag:GetService(require("BrawlersService"))
serviceBag:GetService(require("TagService"))
serviceBag:GetService(require("BasicMovementService"))
serviceBag:GetService(require("BasicAttackService"))
serviceBag:GetService(require("PassiveService"))
serviceBag:GetService(require("SkillService"))
serviceBag:GetService(require("UltimateService"))
serviceBag:GetService(require("AnimReplicationService"))

serviceBag:Init()
serviceBag:Start()
