--!strict
--[[
	@class ServerMain
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- ─── Assets/Events 폴더 + RemoteEvent 생성 (loader 부트스트랩 이전) ───────────
local assets = Instance.new("Folder")
assets.Name = "Assets"
assets.Parent = ReplicatedStorage

local events = Instance.new("Folder")
events.Name = "Events"
events.Parent = assets

local EVENT_NAMES = {
	"MovementStateEvent",
	"ClassUpdateEvent",
}
for _, name in EVENT_NAMES do
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = events
end

-- ─── Loader 부트스트랩 ────────────────────────────────────────────────────────
local loader = ServerScriptService.Brawlers:FindFirstChild("LoaderUtils", true).Parent
local require = require(loader).bootstrapGame(ServerScriptService.Brawlers)

local serviceBag = require("ServiceBag").new()
serviceBag:GetService(require("BrawlersService"))
serviceBag:Init()
serviceBag:Start()

-- ─── 캐릭터에 "Player" 태그 부착 (HumanoidBinderClient 트리거용) ───────────────
local function tagCharacter(character: Model)
	CollectionService:AddTag(character, "Player")
end

Players.PlayerAdded:Connect(function(player)
	if player.Character then
		tagCharacter(player.Character)
	end
	player.CharacterAdded:Connect(tagCharacter)
end)

for _, player in Players:GetPlayers() do
	if player.Character then
		tagCharacter(player.Character)
	end
	player.CharacterAdded:Connect(tagCharacter)
end
