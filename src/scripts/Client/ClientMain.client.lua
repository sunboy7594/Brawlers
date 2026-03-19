--!strict
--[[
	@class ClientMain
]]
local loader = game:GetService("ReplicatedStorage"):WaitForChild("Brawlers"):WaitForChild("loader")
local require = require(loader).bootstrapGame(loader.Parent)

local serviceBag = require("ServiceBag").new()

-- ─── Core ────────────────────────────────────────
serviceBag:GetService(require("BrawlersServiceClient"))

-- ─── 카메라 / 애니메이션 / 이동 ──────────────────
-- MouseShiftLockService는 CameraControllerClient.Init 내에서 의존하므로 먼저 등록
-- PlayerBinderClient는 AnimationControllerClient.Init에서 GetService로 참조하므로 먼저 등록
serviceBag:GetService(require("MouseShiftLockService"))
serviceBag:GetService(require("PlayerBinderClient"))
serviceBag:GetService(require("AnimationControllerClient"))
serviceBag:GetService(require("CameraControllerClient"))
serviceBag:GetService(require("BasicMovementClient"))
serviceBag:GetService(require("AnimReplicationClient"))

-- ─── Ability System ──────────────────────────────
-- AimControllerClient는 BasicAttackClient보다 먼저 등록
serviceBag:GetService(require("AimControllerClient"))
serviceBag:GetService(require("AbilityCoordinator"))

serviceBag:GetService(require("PassiveClient"))
serviceBag:GetService(require("SkillClient"))
serviceBag:GetService(require("UltimateClient"))
serviceBag:GetService(require("BasicAttackClient"))

serviceBag:GetService(require("PlayerStateClient"))

-- ─── PlayerState ─────────────────────────────────
serviceBag:GetService(require("HpClient"))
serviceBag:GetService(require("TeamClient"))

-- ─── 테스트용 (슬롯 시스템 완성 시 제거) ─────────
serviceBag:GetService(require("TestLoadoutClient"))

serviceBag:Init()
serviceBag:Start()
