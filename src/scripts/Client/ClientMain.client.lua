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
serviceBag:GetService(require("MouseShiftLockService"))
serviceBag:GetService(require("PlayerBinderClient"))
serviceBag:GetService(require("AnimationControllerClient"))
serviceBag:GetService(require("CameraControllerClient"))
serviceBag:GetService(require("BasicMovementClient"))
serviceBag:GetService(require("AnimReplicationClient"))

-- ─── WorldFX ─────────────────────────────────────
-- WorldFX는 TeamClient보다 먼저 등록 (GetService로 TeamClient를 Init에서 참조)
-- WorldFXReplicationClient는 WorldFX 다음에 등록
serviceBag:GetService(require("TeamClient"))
serviceBag:GetService(require("WorldFX"))
serviceBag:GetService(require("WorldFXReplicationClient"))

-- ─── Ability System ──────────────────────────────
serviceBag:GetService(require("AimControllerClient"))
serviceBag:GetService(require("AbilityCoordinator"))

serviceBag:GetService(require("PassiveClient"))
serviceBag:GetService(require("SkillClient"))
serviceBag:GetService(require("UltimateClient"))
serviceBag:GetService(require("BasicAttackClient"))

serviceBag:GetService(require("PlayerStateClient"))

-- ─── PlayerState ─────────────────────────────────
serviceBag:GetService(require("HpClient"))

-- ─── 테스트용 (슬롯 시스템 완성 시 제거) ─────────
serviceBag:GetService(require("TestLoadoutClient"))

serviceBag:Init()
serviceBag:Start()
