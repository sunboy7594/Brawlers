--!strict
--[=[
	@class TeamClient

	팀 정보를 로컬에서 관리하는 클라이언트 서비스.

	동기화 방식:
	  player.Team은 Roblox가 서버→클라이언트로 자동 복제하므로
	  별도 RemoteEvent 없이 player.Team 프로퍼티를 직접 읽음.

	테스트 단계:
	  팀 변경 감지 시 Output 출력.

	추후:
	  IsEnemy(player) 결과를 기반으로
	  - 내 팀  → 파란색
	  - 적 팀  → 빨간색
	  으로 캐릭터 색상/네임태그 적용 예정.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local Maid = require("Maid")
local ServiceBag = require("ServiceBag")

-- ─── 내부 유틸 ───────────────────────────────────────────────────────────────

local function getTeam(player: Player): Team?
	if player.Neutral then
		return nil
	end
	return player.Team
end

local function areTeamMates(playerA: Player, playerB: Player): boolean
	if playerA.Neutral or playerB.Neutral then
		return false
	end
	return playerA.Team ~= nil and playerA.Team == playerB.Team
end

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type TeamClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
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
end

function TeamClient.Start(self: TeamClient): ()
	local localPlayer = Players.LocalPlayer

	-- 테스트용: 팀 변경 시 Output 출력
	self._maid:GiveTask(localPlayer:GetPropertyChangedSignal("Team"):Connect(function()
		local team = getTeam(localPlayer)
		if team then
			print(string.format("[Team] %s 배정됨", team.Name))
		else
			print("[Team] 팀 없음 (FFA)")
		end
	end))
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	대상 플레이어가 나의 적인지 반환합니다.

	- 자기 자신           → false
	- 내가 팀 없음 (FFA) → true (모두 적)
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
	FFA 상태면 nil.
	@return Team?
]=]
function TeamClient:GetMyTeam(): Team?
	return getTeam(Players.LocalPlayer)
end

function TeamClient.Destroy(self: TeamClient)
	self._maid:Destroy()
end

return TeamClient
