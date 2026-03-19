--!strict
--[=[
	@class TeamClient

	팀 정보 및 색상을 로컬에서 관리하는 클라이언트 서비스.

	동기화 방식:
	  player.Team은 Roblox가 서버→클라이언트로 자동 복제하므로
	  별도 RemoteEvent 없이 player.Team 프로퍼티를 직접 읽음.

	색상 모드:
	  InLobby : 자신/자신팀 → 파란색, 나머지 → 빨간색
	  InGame  : 자신/자신팀 → 파란색
	           적팀 목록을 팀 번호(Team1, Team2...) 오름차순 정렬 후 재색인
	           재색인 1 → 빨간색 (HSV 0°), 증가할수록 노란색(HSV 60°) 방향 보간

	고정 모드:
	  LockColors()   → 현재 색상 테이블 스냅샷 고정 (이후 팀 변경 무시)
	  UnlockColors() → 동적 재계산 복귀

	공개 API:
	  SetMode(mode)            : "InLobby" | "InGame" 모드 설정 + 색상 테이블 재계산
	  LockColors()             : 색상 테이블 고정
	  UnlockColors()           : 동적 재계산 복귀
	  GetRelationColor(player) : 해당 플레이어의 관계 기반 색상 반환
	  GetMyColor()             : 자신(파란색) 고정 반환
	  IsEnemy(player)          : 적 여부 반환
	  GetMyTeam()              : 로컬 플레이어 팀 반환
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")

local Maid = require("Maid")
local ServiceBag = require("ServiceBag")

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local COLOR_SELF = Color3.fromHSV(210/360, 0.8, 1)   -- 파란색
local COLOR_ENEMY_SINGLE = Color3.fromHSV(0, 1, 1)    -- 빨간색 (적 1팀)
local COLOR_LOBBY_ENEMY = Color3.fromHSV(0, 1, 1)     -- InLobby 적: 빨간색

local ENEMY_HUE_MIN = 0        -- 빨간색 (HSV 도)
local ENEMY_HUE_MAX = 60       -- 노란색 (HSV 도)

-- ─── 내부 유틸 ───────────────────────────────────────────────────────────────

-- "Team12" → 12, 파싱 실패 시 nil
local function parseTeamIndex(team: Team): number?
	local n = tonumber(team.Name:match("^Team(%d+)$"))
	return n
end

local function areTeamMates(playerA: Player, playerB: Player): boolean
	if playerA.Neutral or playerB.Neutral then
		return false
	end
	return playerA.Team ~= nil and playerA.Team == playerB.Team
end

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type ColorMode = "InLobby" | "InGame"

export type TeamClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_mode: ColorMode,
		_locked: boolean,
		-- teamIndex → Color3 (적팀 색상 캐시)
		_enemyColorTable: { [number]: Color3 },
	},
	{} :: typeof({ __index = {} })
))

-- ─── 서비스 ──────────────────────────────────────────────────────────────────

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

	-- 팀 변경 감지 → 동적 모드일 때 색상 테이블 재계산
	self._maid:GiveTask(localPlayer:GetPropertyChangedSignal("Team"):Connect(function()
		if not self._locked then
			self:_rebuildColorTable()
		end
	 end))

	-- Teams 서비스 변경 감지 (팀 추가/제거)
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

--[=[
	색상 모드를 설정하고 색상 테이블을 재계산합니다.
	LockColors 상태에서도 모드 변경 + 재계산은 허용합니다.
	@param mode "InLobby" | "InGame"
]=]
function TeamClient:SetMode(mode: ColorMode)
	self._mode = mode
	-- 모드 변경은 Lock 여부와 무관하게 재계산
	local wasLocked = self._locked
	self._locked = false
	self:_rebuildColorTable()
	self._locked = wasLocked
end

--[=[
	현재 색상 테이블을 고정합니다.
	이후 팀 구성이 변경되어도 색상 테이블이 재계산되지 않습니다.
	InGame 시작 시 호출하세요.
]=]
function TeamClient:LockColors()
	self._locked = true
end

--[=[
	색상 테이블 고정을 해제하고 동적 재계산으로 복귀합니다.
]=]
function TeamClient:UnlockColors()
	self._locked = false
	self:_rebuildColorTable()
end

--[=[
	자신(파란색)을 항상 반환합니다.
	@return Color3
]=]
function TeamClient:GetMyColor(): Color3
	return COLOR_SELF
end

--[=[
	해당 플레이어의 관계 기반 색상을 반환합니다.
	- 자기 자신 또는 아군 → 파란색
	- 그 외               → 모드에 따라 계산
	@param player Player
	@return Color3
]=]
function TeamClient:GetRelationColor(player: Player): Color3
	local localPlayer = Players.LocalPlayer

	-- 자기 자신 또는 아군
	if player == localPlayer or areTeamMates(localPlayer, player) then
		return COLOR_SELF
	end

	-- InLobby: 무조건 빨간색
	if self._mode == "InLobby" then
		return COLOR_LOBBY_ENEMY
	end

	-- InGame: 팀 index 기반 보간 색상
	if player.Team then
		local idx = parseTeamIndex(player.Team)
		if idx and self._enemyColorTable[idx] then
			return self._enemyColorTable[idx]
		end
	end

	-- 팀 없음 또는 파싱 실패 → 빨간색 fallback
	return COLOR_ENEMY_SINGLE
end

--[=[
	대상 플레이어가 나의 적인지 반환합니다.
	- 자기 자신           → false
	- 내가 팀 없음        → true
	- 상대가 팀 없음      → true
	- 같은 팀             → false
	- 다른 팀             → true
	@param player Player
	@return boolean
]=]
function TeamClient:IsEnemy(player: Player): boolean
	local localPlayer = Players.LocalPlayer
	if player == localPlayer then
		return false
	end
	if localPlayer.Neutral or player.Neutral then
		return true
	end
	return not areTeamMates(localPlayer, player)
end

--[=[
	로컬 플레이어의 현재 팀을 반환합니다.
	팀 없으면 nil.
	@return Team?
]=]
function TeamClient:GetMyTeam(): Team?
	local localPlayer = Players.LocalPlayer
	if localPlayer.Neutral then
		return nil
	end
	return localPlayer.Team
end

-- ─── 내부: 색상 테이블 재계산 ────────────────────────────────────────────────

--[=[
	InGame 모드용 적팀 색상 테이블 재계산.

	1. 전체 팀 목록에서 내 팀 제외 → 적팀 목록
	2. 팀 index 오름차순 정렬
	3. 재색인 1..N → HSV 보간 (0° ~ 60°)
	   N == 1 → 빨간색 고정
	   N > 1  → (reIndex-1)/(N-1) * 60° 보간
]=]
function TeamClient:_rebuildColorTable()
	local newTable: { [number]: Color3 } = {}

	if self._mode == "InGame" then
		local localPlayer = Players.LocalPlayer
		local myTeam = if localPlayer.Neutral then nil else localPlayer.Team

		-- 적팀 index 수집
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

		-- 오름차순 정렬
		table.sort(enemyIndices)

		local total = #enemyIndices
		for reIndex, teamIndex in enemyIndices do
			local hue: number
			if total == 1 then
				hue = ENEMY_HUE_MIN
			else
				hue = ENEMY_HUE_MIN + (reIndex - 1) / (total - 1) * (ENEMY_HUE_MAX - ENEMY_HUE_MIN)
			end
			newTable[teamIndex] = Color3.fromHSV(hue / 360, 1, 1)
		end
	end

	self._enemyColorTable = newTable
end

function TeamClient.Destroy(self: TeamClient)
	self._maid:Destroy()
end

return TeamClient
