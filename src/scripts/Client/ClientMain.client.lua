--!strict
--[[
	@class ClientMain
]]
local loader = game:GetService("ReplicatedStorage"):WaitForChild("Brawlers"):WaitForChild("loader")
local require = require(loader).bootstrapGame(loader.Parent)

local serviceBag = require("ServiceBag").new()

-- 기존 서비스
serviceBag:GetService(require("BrawlersServiceClient"))

-- 카메라/애니메이션/이동 시스템
-- MouseShiftLockService는 CameraControllerClient.Init 내에서 의존하므로 먼저 등록
serviceBag:GetService(require("MouseShiftLockService"))
serviceBag:GetService(require("AnimationControllerClient"))
serviceBag:GetService(require("CameraControllerClient"))
serviceBag:GetService(require("BasicMovementClient"))
serviceBag:GetService(require("HumanoidBinderClient"))

serviceBag:Init()
serviceBag:Start()
