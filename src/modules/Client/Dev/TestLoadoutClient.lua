--!strict
--[=[
	@class TestLoadoutClient

	테스트용 임시 장착 클라이언트 서비스.
	캐릭터 스폰 시 자동으로 TANK 클래스와 Punch 공격을 장착합니다.

	추후 슬롯 시스템 완성 시 이 파일만 제거하면 됩니다.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local BasicAttackClient = require("BasicAttackClient")
local ClassRemoting = require("ClassRemoting")
local LoadoutRemoting = require("LoadoutRemoting")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")

export type TestLoadoutClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_basicAttackClient: BasicAttackClient.BasicAttackClient,
	},
	{} :: typeof({ __index = {} })
))

local TestLoadoutClient = {}
TestLoadoutClient.ServiceName = "TestLoadoutClient"
TestLoadoutClient.__index = TestLoadoutClient

-- ─── 초기화 ──────────────────────────────────────────────────────────────────

function TestLoadoutClient.Init(self: TestLoadoutClient, serviceBag: ServiceBag.ServiceBag): ()
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._basicAttackClient = serviceBag:GetService(BasicAttackClient)
end

function TestLoadoutClient.Start(self: TestLoadoutClient): ()
	local player = Players.LocalPlayer

	local function onCharacterAdded(_char: Model)
		-- 서버 초기화 대기 후 클래스/장착 요청
		task.wait()

		-- 1. 클래스 변경 요청
		ClassRemoting.RequestClassChange:InvokeServer("TANK")

		-- 2. 기본 공격 장착 요청
		local success: unknown, _result: unknown =
			LoadoutRemoting.RequestEquipBasicAttack:InvokeServer("Tank_CannonTest")

		-- 3. 성공 시 클라이언트 상태 갱신
		if success == true then
			self._basicAttackClient:SetEquippedAttack("Tank_CannonTest")
		end
	end

	-- 현재 캐릭터가 이미 있으면 즉시 처리
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end

	self._maid:GiveTask(player.CharacterAdded:Connect(onCharacterAdded))
end

function TestLoadoutClient.Destroy(self: TestLoadoutClient)
	self._maid:Destroy()
end

return TestLoadoutClient
