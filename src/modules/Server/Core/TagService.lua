--!strict
--[=[
    @class TagService
    Humanoid, BasePart 등 조건에 맞는 인스턴스에 자동으로 CollectionService 태그를 부여합니다.
]=]

local require = require(script.Parent.loader).load(script)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Maid = require("Maid")
local ServiceBag = require("ServiceBag")

local TagService = {}
TagService.ServiceName = "TagService"

-- 태그 규칙 정의
-- condition: 인스턴스를 받아 태그를 붙일지 여부 반환 (Model 단위)
-- tag: 붙일 태그 이름
type TagRule = {
	tag: string,
	condition: (instance: Instance) -> boolean,
}

local TAG_RULES: { TagRule } = {
	{
		-- 플레이어 캐릭터: Players 서비스에 등록된 캐릭터 Model
		-- Humanoid 유무와 무관하게 플레이어가 조종하는 Model이면 태그 부여
		tag = "Player",
		condition = function(instance)
			if not instance:IsA("Model") then
				return false
			end
			return Players:GetPlayerFromCharacter(instance) ~= nil
		end,
	},
	{
		-- NPC 캐릭터: Humanoid는 있지만 플레이어 캐릭터가 아닌 것
		tag = "Character",
		condition = function(instance)
			if not instance:IsA("Humanoid") then
				return false
			end
			local model = instance.Parent
			if not (model ~= nil and model:IsA("Model")) then
				return false
			end
			return Players:GetPlayerFromCharacter(model) == nil
		end,
	},
	{
		tag = "Interactable",
		condition = function(instance)
			return instance:IsA("BasePart") and instance:GetAttribute("Interactable") == true
		end,
	},
	{
		tag = "Hazard",
		condition = function(instance)
			return instance:IsA("BasePart") and instance:GetAttribute("Hazard") == true
		end,
	},
	-- 새 태그 추가할 때 여기에만 추가하면 됨
}

export type TagService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
	},
	{} :: typeof({ __index = TagService })
))

function TagService.Init(self: TagService, serviceBag: ServiceBag.ServiceBag)
	self._serviceBag = serviceBag
	self._maid = Maid.new()
end

function TagService.Start(self: TagService)
	local function checkAndTag(instance: Instance)
		for _, rule in TAG_RULES do
			if rule.condition(instance) then
				if not CollectionService:HasTag(instance, rule.tag) then
					CollectionService:AddTag(instance, rule.tag)
				end
			end
		end
	end

	-- 기존 인스턴스 스캔
	-- "Player" 규칙은 이제 Model 단위이므로 workspace 하위 Model을 직접 확인
	for _, instance in workspace:GetDescendants() do
		checkAndTag(instance)
	end

	-- 새로 추가되는 인스턴스 감시
	self._maid:GiveTask(workspace.DescendantAdded:Connect(checkAndTag))
end

function TagService.Destroy(self: TagService)
	self._maid:Destroy()
end

return TagService
