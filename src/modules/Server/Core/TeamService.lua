--!strict
--[=[
	@class TeamService

	팀 배정 및 팀 판단을 담당하는 서버 서비스.

	팀 ID 규칙:
	- 팀 인스턴스 이름: "Team1", "Team2", ... (teamIndex 기반 자동 생성)
	- 팀 없음: player.Neutral = true

	흐름:
	  CreateTeams(count) → Teams 서비스에 Team 인스턴스 동적 생성
	  AssignTeam(player, teamIndex) → player.Team 설정 (자동 복제됨)
	  ClearTeams() → 모든 Team 인스턴스 제거, 플레이어 Neutral 처리

	IsEnemy 규칙:
	  source or target 팀 없음 → true
	  같은 팀               → false
	  다른 팀               → true
	  (nil / self 처리는 호출 측 담당)

	FilterTeammates / FilterEnemies:
	  InstantHit.applyMap의 hits({ Model }) 목록을 팀 기준으로 필터링합니다.
	  classifyHits 내부에서 사용합니다.

	클라이언트 동기화:
	  player.Team은 Roblox가 자동으로 클라이언트에 복제하므로
	  별도 RemoteEvent 불필요.

	색상:
	  팀 색상은 클라이언트(TeamClient)가 관리합니다.
	  서버는 색상을 다루지 않습니다.

	사용 예 (게임 모드 로직에서):
	  TeamService:CreateTeams(2)
	  TeamService:AssignTeam(playerA, 1)  -- 팀1
	  TeamService:AssignTeam(playerB, 2)  -- 팀2
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")

local Maid = require("Maid")
local ServiceBag = require("ServiceBag")

-- ─── 내부 유틸 ───────────────────────────────────────────────────────────────

local function areTeamMates(playerA: Player, playerB: Player): boolean
	if playerA.Neutral or playerB.Neutral then
		return false
	end
	return playerA.Team ~= nil and playerA.Team == playerB.Team
end

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type TeamService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_teams: { [number]: Team },
	},
	{} :: typeof({ __index = {} })
))

-- ─── 서비스 ──────────────────────────────────────────────────────────────────

local TeamService = {}
TeamService.ServiceName = "TeamService"
TeamService.__index = TeamService

function TeamService.Init(self: TeamService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._teams = {}
end

function TeamService.Start(_self: TeamService): () end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

function TeamService:CreateTeams(count: number)
	assert(count >= 1, "count must be >= 1")
	self:ClearTeams()

	for i = 1, count do
		local team = Instance.new("Team")
		team.Name = "Team" .. i
		team.AutoAssignable = false
		team.Parent = Teams
		self._teams[i] = team
	end
end

function TeamService:AssignTeam(player: Player, teamIndex: number)
	local team = self._teams[teamIndex]
	if not team then
		warn(string.format("[TeamService] teamIndex %d 없음. CreateTeams를 먼저 호출하세요.", teamIndex))
		return
	end
	player.Team = team
end

function TeamService:ClearPlayerTeam(player: Player)
	player.Team = nil
	player.Neutral = true
end

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

function TeamService:GetTeamCount(): number
	local count = 0
	for _ in self._teams do
		count += 1
	end
	return count
end

--[=[
	source와 target이 서로 적 관계인지 반환합니다.

	규칙:
	  source or target 팀 없음 → true
	  같은 팀               → false
	  다른 팀               → true

	nil / self 케이스는 호출 측에서 처리하세요.

	@param source Player
	@param target Player
	@return boolean
]=]
function TeamService:IsEnemy(source: Player, target: Player): boolean
	if source.Neutral or target.Neutral then
		return true
	end
	if areTeamMates(source, target) then
		return false
	end
	return true
end

--[=[
	victims 목록에서 source와 같은 팀인 캐릭터만 반환합니다.
	source 자신은 포함하지 않습니다.

	@param source Player
	@param victims { Model }
	@return { Model }
]=]
function TeamService:FilterTeammates(source: Player, victims: { Model }): { Model }
	local result: { Model } = {}
	for _, char in victims do
		local player = Players:GetPlayerFromCharacter(char)
		if player and player ~= source and areTeamMates(source, player) then
			table.insert(result, char)
		end
	end
	return result
end

--[=[
	victims 목록에서 source의 적 캐릭터만 반환합니다.
	IsEnemy 규칙을 따릅니다.
	source 자신은 포함하지 않습니다.

	@param source Player
	@param victims { Model }
	@return { Model }
]=]
function TeamService:FilterEnemies(source: Player, victims: { Model }): { Model }
	local result: { Model } = {}
	for _, char in victims do
		local player = Players:GetPlayerFromCharacter(char)
		if player and player ~= source and self:IsEnemy(source, player) then
			table.insert(result, char)
		end
	end
	return result
end

function TeamService.Destroy(self: TeamService)
	self:ClearTeams()
	self._maid:Destroy()
end

return TeamService
