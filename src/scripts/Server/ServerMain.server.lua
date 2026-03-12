--!strict
--[[
	@class ServerMain
]]
local ServerScriptService = game:GetService("ServerScriptService")

local loader = ServerScriptService.Brawlers:FindFirstChild("LoaderUtils", true).Parent
local require = require(loader).bootstrapGame(ServerScriptService.Brawlers)

local serviceBag = require("ServiceBag").new()
serviceBag:GetService(require("BrawlersService"))
serviceBag:Init()
serviceBag:Start()
