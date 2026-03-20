--!strict
--[=[
	@class TeamClient
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")

local Maid = require("Maid")
local ServiceBag = require("ServiceBag")

local COLOR_SELF = Color3.fromHSV(210 / 360, 0.8, 1)
local COLOR_ENEMY_SINGLE = Color3.fromHSV(0, 1, 1)
local COLOR_LOBBY_ENEMY = Color3.fromHSV(0, 1, 1)

local ENEMY_HUE_MIN = 0
local ENEMY_HUE_MAX = 60

local function parseTeamIndex(team: Team): number?
	return tonumber(team.Name:match("^Team(%d+)$"))
end

local function areTeamMates(playerA: Player, playerB: Player): boolean
	if playerA.Neutral or playerB.Neutral then
		return false
	end
	return playerA.Team ~= nil and playerA.Team == playerB.Team
end

export type ColorMode = "InLobby" | "InGame"

export type TeamClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_mode: ColorMode,
		_locked: boolean,
		_enemyColorTable: { [number]: Color3 },
	},
	{} :: typeof({ __index = {} })
))

local TeamClient = {}
TeamClient.ServiceName = "TeamClient"
TeamClient.__index = TeamClient

function TeamClient.Init(self: TeamClient, serviceBag: ServiceBag.ServiceBag): ()
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._mode = "InLobby"
	self._locked = false
	self._enemyColorTable = {}
end

function TeamClient.Start(self: TeamClient): ()
	local localPlayer = Players.LocalPlayer

	self._maid:GiveTask(localPlayer:GetPropertyChangedSignal("Team"):Connect(function()
		if not self._locked then
			self:_rebuildColorTable()
		end
	end))
	self._maid:GiveTask(Teams.ChildAdded:Connect(function()
		if not self._locked then
			self:_rebuildColorTable()
		end
	end))
	self._maid:GiveTask(Teams.ChildRemoved:Connect(function()
		if not self._locked then
			self:_rebuildColorTable()
		end
	end))

	self:_rebuildColorTable()
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

function TeamClient:SetMode(mode: ColorMode)
	self._mode = mode
	local wasLocked = self._locked
	self._locked = false
	self:_rebuildColorTable()
	self._locked = wasLocked
end

function TeamClient:LockColors()
	self._locked = true
end

function TeamClient:UnlockColors()
	self._locked = false
	self:_rebuildColorTable()
end

function TeamClient:GetMyColor(): Color3
	return COLOR_SELF
end

function TeamClient:GetRelationColor(player: Player): Color3
	local localPlayer = Players.LocalPlayer

	if player == localPlayer or areTeamMates(localPlayer, player) then
		return COLOR_SELF
	end

	if self._mode == "InLobby" then
		return COLOR_LOBBY_ENEMY
	end

	if player.Team then
		local idx = parseTeamIndex(player.Team)
		if idx and self._enemyColorTable[idx] then
			return self._enemyColorTable[idx]
		end
	end

	return COLOR_ENEMY_SINGLE
end

--[=[
	playerB가 있으면 두 플레이어 간 직접 판정.
	playerB가 없으면 로컬 플레이어 기준 판정.
	@param playerA Player
	@param playerB Player?
	@return boolean
]=]
function TeamClient:IsEnemy(playerA: Player, playerB: Player?): boolean
	if playerB then
		-- 두 플레이어 간 직접 판정
		if playerA == playerB then
			return false
		end
		if playerA.Neutral or playerB.Neutral then
			return true
		end
		return not areTeamMates(playerA, playerB)
	else
		-- 로컬 플레이어 기준
		local localPlayer = Players.LocalPlayer
		if playerA == localPlayer then
			return false
		end
		if localPlayer.Neutral or playerA.Neutral then
			return true
		end
		return not areTeamMates(localPlayer, playerA)
	end
end

function TeamClient:GetMyTeam(): Team?
	local localPlayer = Players.LocalPlayer
	if localPlayer.Neutral then
		return nil
	end
	return localPlayer.Team
end

-- ─── 내부 ────────────────────────────────────────────────────────────────────

function TeamClient:_rebuildColorTable()
	local newTable: { [number]: Color3 } = {}

	if self._mode == "InGame" then
		local localPlayer = Players.LocalPlayer
		local myTeam = if localPlayer.Neutral then nil else localPlayer.Team

		local enemyIndices: { number } = {}
		for _, team in Teams:GetTeams() do
			if team == myTeam then
				continue
			end
			local idx = parseTeamIndex(team)
			if idx then
				table.insert(enemyIndices, idx)
			end
		end

		table.sort(enemyIndices)

		local total = #enemyIndices
		for reIndex, teamIndex in enemyIndices do
			local hue = if total == 1
				then ENEMY_HUE_MIN
				else ENEMY_HUE_MIN + (reIndex - 1) / (total - 1) * (ENEMY_HUE_MAX - ENEMY_HUE_MIN)
			newTable[teamIndex] = Color3.fromHSV(hue / 360, 1, 1)
		end
	end

	self._enemyColorTable = newTable
end

function TeamClient.Destroy(self: TeamClient)
	self._maid:Destroy()
end

return TeamClient
