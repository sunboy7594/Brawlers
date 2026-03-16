--!strict
--[=[
	@class TeamService

	팀 배정 및 팀 판단을 담당하는 서버 서비스.

	팀 ID 규칙:
	- 팀 인스턴스 이름: "Team1", "Team2", ... (teamIndex 기반 자동 생성)
	- 팀 없음 (FFA): player.Neutral = true

	흐름:
	  CreateTeams(count) → Teams 서비스에 Team 인스턴스 동적 생성
	  AssignTeam(player, teamIndex) → player.Team 설정 (자동 복제됨)
	  ClearTeams() → 모든 Team 인스턴스 제거, 플레이어 Neutral 처리

	CanDamage 규칙:
	  source == nil          → true  (환경 대미지)
	  source == target       → true  (자해 허용)
	  source or target 팀 없음 → true  (FFA는 모두 공격 가능)
	  같은 팀               → false (팀킬 방지)
	  다른 팀               → true

	클라이언트 동기화:
	  player.Team은 Roblox가 자동으로 클라이언트에 복제하므로
	  별도 RemoteEvent 불필요.

	사용 예 (게임 모드 로직에서):
	  TeamService:CreateTeams(2)
	  TeamService:AssignTeam(playerA, 1)  -- 레드팀
	  TeamService:AssignTeam(playerB, 2)  -- 블루팀
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")

local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local TeamUtils = require("TeamUtils")

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type TeamService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_teams: { [number]: Team }, -- teamIndex → Team 인스턴스
	},
	{} :: typeof({ __index = {} })
))

-- ─── 서비스 ──────────────────────────────────────────────────────────────────

local TeamService = {}
TeamService.ServiceName = "TeamService"
TeamService.__index = TeamService

-- 팀별 기본 색상 (TeamColor는 필수값이므로 순서대로 배정)
local TEAM_COLORS: { BrickColor } = {
	BrickColor.new("Bright red"),
	BrickColor.new("Bright blue"),
	BrickColor.new("Bright green"),
	BrickColor.new("Bright yellow"),
	BrickColor.new("Hot pink"),
	BrickColor.new("Cyan"),
	BrickColor.new("Lime green"),
	BrickColor.new("Orange"),
}

function TeamService.Init(self: TeamService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._teams = {}
end

function TeamService.Start(_self: TeamService): ()
	-- 현재는 외부(게임 모드 로직)에서 CreateTeams/AssignTeam을 호출하는 구조.
	-- 추후 게임 모드 서비스가 Start에서 팀 초기화를 요청할 예정.
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	N개의 팀을 생성합니다. 기존 팀이 있으면 먼저 제거 후 재생성합니다.
	@param count number  생성할 팀 수 (1 이상)
]=]
function TeamService:CreateTeams(count: number)
	assert(count >= 1, "count must be >= 1")
	self:ClearTeams()

	for i = 1, count do
		local team = Instance.new("Team")
		team.Name = "Team" .. i
		team.TeamColor = TEAM_COLORS[((i - 1) % #TEAM_COLORS) + 1]
		team.AutoAssignable = false
		team.Parent = Teams
		self._teams[i] = team
	end
end

--[=[
	플레이어를 특정 팀에 배정합니다.
	player.Team이 설정되면 Roblox가 자동으로 클라이언트에 복제합니다.
	@param player Player
	@param teamIndex number  1부터 시작
]=]
function TeamService:AssignTeam(player: Player, teamIndex: number)
	local team = self._teams[teamIndex]
	if not team then
		warn(string.format("[TeamService] teamIndex %d 없음. CreateTeams를 먼저 호출하세요.", teamIndex))
		return
	end
	player.Team = team
end

--[=[
	플레이어를 팀 없음(FFA) 상태로 만듭니다.
	@param player Player
]=]
function TeamService:ClearPlayerTeam(player: Player)
	player.Team = nil
	player.Neutral = true
end

--[=[
	생성된 모든 팀을 제거하고 모든 플레이어를 Neutral 상태로 만듭니다.
]=]
function TeamService:ClearTeams()
	for _, team in self._teams do
		team:Destroy()
	end
	table.clear(self._teams)

	for _, player in Players:GetPlayers() do
		player.Team = nil
		player.Neutral = true
	end
end

--[=[
	플레이어의 현재 팀 인덱스를 반환합니다.
	팀이 없으면 nil 반환 (FFA 상태).
	@return number?
]=]
function TeamService:GetTeamIndex(player: Player): number?
	if player.Neutral or not player.Team then
		return nil
	end
	for index, team in self._teams do
		if team == player.Team then
			return index
		end
	end
	return nil
end

--[=[
	현재 생성된 팀 수를 반환합니다.
]=]
function TeamService:GetTeamCount(): number
	local count = 0
	for _ in self._teams do
		count += 1
	end
	return count
end

--[=[
	source가 target에게 대미지를 줄 수 있는지 판단합니다.

	규칙:
	  source == nil          → true  (환경 대미지)
	  source == target       → true  (자해 허용)
	  둘 중 하나라도 팀 없음  → true  (FFA)
	  같은 팀               → false (팀킬 방지)
	  다른 팀               → true

	@param source Player?  공격자 (nil이면 환경/자해 대미지)
	@param target Player   피격자
	@return boolean
]=]
function TeamService:CanDamage(source: Player?, target: Player): boolean
	-- 환경 대미지 또는 자해
	if source == nil or source == target then
		return true
	end

	-- 팀 없음(FFA): 양쪽 다 공격 가능
	if source.Neutral or target.Neutral then
		return true
	end

	-- 같은 팀이면 대미지 차단
	if TeamUtils.areTeamMates(source, target) then
		return false
	end

	return true
end

function TeamService.Destroy(self: TeamService)
	self:ClearTeams()
	self._maid:Destroy()
end

return TeamService
