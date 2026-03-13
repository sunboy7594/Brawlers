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

-- 어빌리티 시스템
-- AimController는 BasicAttackClient보다 먼저 등록해야 Init에서 GetService 가능
serviceBag:GetService(require("AimController"))
serviceBag:GetService(require("BasicAttackClient"))
serviceBag:GetService(require("SkillClient"))
serviceBag:GetService(require("UltimateClient"))
-- 테스트용 장착 클라이언트 (슬롯 시스템 완성 시 제거)
serviceBag:GetService(require("TestLoadoutClient"))

serviceBag:Init()
serviceBag:Start()
