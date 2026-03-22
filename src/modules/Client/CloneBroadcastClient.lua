--!strict
--[=[
	@class CloneBroadcastClient

	HRP 위치 브로드캐스트 클라이언트 서비스.

	담당:
	  1. 내 위치를 매 RenderStepped 서버에 전송 (PositionUpload, buffer 24 bytes)
	  2. 다른 플레이어 캐릭터 추가 시 클론 생성 + 원본 투명화
	  3. PositionBroadcast 수신 → 각 클론 Lerp PivotTo
	  4. lerp alpha 동적 조절 API (공격 모듈에서 호출)

	클론 구조:
	  원본 캐릭터를 Clone() → Humanoid, Script 계열 제거 → workspace에 Parent
	  원본 캐릭터: 모든 BasePart LocalTransparencyModifier = 1 (본인 눈에만 투명)
	  클론: Anchored=true, 60Hz Lerp PivotTo로 위치 추적

	lerp alpha:
	  기본값 LERP_ALPHA_DEFAULT (0.35)
	  SetLerpAlpha(value)로 재정의 가능
	  ResetLerpAlpha()로 기본값 복원

	AnimReplicationClient 연동:
	  클론 생성 완료 시 CloneReady 신호 발사
	  → AnimReplicationClient가 이 신호를 받아 state.joints를 클론 Motor6D로 교체
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CloneBroadcastRemoting = require("CloneBroadcastRemoting")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local Signal = require("Signal")

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local LERP_ALPHA_DEFAULT = 0.35

-- ─── 타입 ────────────────────────────────────────────────────────────────────

type CloneEntry = {
	clone: Model,
	cloneHRP: BasePart,
	targetCF: CFrame,
	maid: any,
}

export type CloneBroadcastClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_clones: { [number]: CloneEntry },
		_lerpAlpha: number,
		CloneReady: any, -- Signal<userId: number, clone: Model>
	},
	{} :: typeof({ __index = {} })
))

local CloneBroadcastClient = {}
CloneBroadcastClient.ServiceName = "CloneBroadcastClient"
CloneBroadcastClient.__index = CloneBroadcastClient

-- ─── 초기화 ──────────────────────────────────────────────────────────────────

function CloneBroadcastClient.Init(self: CloneBroadcastClient, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._clones = {}
	self._lerpAlpha = LERP_ALPHA_DEFAULT
	self.CloneReady = Signal.new()
	self._maid:GiveTask(self.CloneReady)
end

function CloneBroadcastClient.Start(self: CloneBroadcastClient)
	local localPlayer = Players.LocalPlayer

	-- 다른 플레이어 클론 관리
	for _, player in Players:GetPlayers() do
		if player ~= localPlayer then
			self:_onPlayerAdded(player)
		end
	end
	self._maid:GiveTask(Players.PlayerAdded:Connect(function(player)
		if player ~= localPlayer then
			self:_onPlayerAdded(player)
		end
	end))
	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player)
		self:_removeClone(player.UserId)
	end))

	-- 내 위치 전송 + 클론 Lerp 업데이트
	self._maid:GiveTask(RunService.RenderStepped:Connect(function()
		self:_uploadMyPosition()
		self:_updateClones()
	end))

	-- 서버 브로드캐스트 수신
	self._maid:GiveTask(CloneBroadcastRemoting.PositionBroadcast.OnClientEvent:Connect(function(buf)
		self:_onBroadcast(buf)
	end))
end

-- ─── lerp API ────────────────────────────────────────────────────────────────

--[=[
	lerp alpha를 임시로 변경합니다.
	공격 모듈 onFire에서 낮추고, fireMaid 정리 시 ResetLerpAlpha로 복원합니다.
]=]
function CloneBroadcastClient:SetLerpAlpha(alpha: number)
	self._lerpAlpha = math.clamp(alpha, 0.01, 1)
end

function CloneBroadcastClient:ResetLerpAlpha()
	self._lerpAlpha = LERP_ALPHA_DEFAULT
end

-- ─── 내 위치 전송 ─────────────────────────────────────────────────────────────

function CloneBroadcastClient:_uploadMyPosition()
	local char = Players.LocalPlayer.Character
	if not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	local buf = CloneBroadcastRemoting.encodeMyCFrame(hrp.CFrame)
	CloneBroadcastRemoting.PositionUpload:FireServer(buf)
end

-- ─── 브로드캐스트 수신 ───────────────────────────────────────────────────────

function CloneBroadcastClient:_onBroadcast(buf: any)
	if typeof(buf) ~= "buffer" then
		return
	end

	local entries = CloneBroadcastRemoting.decodeBatch(buf)
	local localUserId = Players.LocalPlayer.UserId

	for _, entry in entries do
		if entry.userId == localUserId then
			continue
		end
		local cloneEntry = self._clones[entry.userId]
		if cloneEntry then
			cloneEntry.targetCF = entry.cframe
		end
	end
end

-- ─── 클론 Lerp 업데이트 ──────────────────────────────────────────────────────

function CloneBroadcastClient:_updateClones()
	local alpha = self._lerpAlpha
	for _, entry in self._clones do
		local currentCF = entry.cloneHRP:GetPivot()
		local newCF = currentCF:Lerp(entry.targetCF, alpha)
		entry.clone:PivotTo(newCF)
	end
end

-- ─── 클론 생성 ───────────────────────────────────────────────────────────────

function CloneBroadcastClient:_onPlayerAdded(player: Player)
	local pMaid = Maid.new()
	self._maid:GiveTask(pMaid)

	local function onCharacterAdded(char: Model)
		-- 이전 클론 정리
		self:_removeClone(player.UserId)

		-- 원본 투명화
		local charMaid = Maid.new()
		pMaid:GiveTask(charMaid)

		charMaid:GiveTask(char.DescendantAdded:Connect(function(desc)
			if desc:IsA("BasePart") then
				(desc :: BasePart).LocalTransparencyModifier = 1
			end
		end))
		for _, desc in char:GetDescendants() do
			if desc:IsA("BasePart") then
				(desc :: BasePart).LocalTransparencyModifier = 1
			end
		end
		charMaid:GiveTask(function()
			-- 캐릭터 제거 시 LocalTransparencyModifier 복원 (다음 스폰 대비)
			for _, desc in char:GetDescendants() do
				if desc:IsA("BasePart") and (desc :: BasePart).Parent then
					(desc :: BasePart).LocalTransparencyModifier = 0
				end
			end
		end)

		-- 클론 생성
		local clone = self:_buildClone(char)
		if not clone then
			return
		end

		local cloneHRP = clone:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not cloneHRP then
			clone:Destroy()
			return
		end

		clone.Parent = workspace

		local entry: CloneEntry = {
			clone = clone,
			cloneHRP = cloneHRP,
			targetCF = char:GetPivot(),
			maid = charMaid,
		}
		self._clones[player.UserId] = entry

		-- AnimReplicationClient에 클론 준비 알림
		self.CloneReady:Fire(player.UserId, clone)

		charMaid:GiveTask(function()
			self:_removeClone(player.UserId)
		end)
	end

	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
	pMaid:GiveTask(player.CharacterAdded:Connect(onCharacterAdded))
end

--[=[
	원본 캐릭터에서 시각 전용 클론을 생성합니다.
	제거 대상: Humanoid, Script, LocalScript, ModuleScript, BodyMover 계열
	모든 BasePart: Anchored=true, CanCollide=false, CastShadow=false
]=]
function CloneBroadcastClient:_buildClone(char: Model): Model?
	-- Archivable 임시 허용
	local prevArchivable = char.Archivable
	char.Archivable = true
	local clone = char:Clone() :: Model
	char.Archivable = prevArchivable

	if not clone then
		return nil
	end

	-- 불필요 인스턴스 제거
	for _, desc in clone:GetDescendants() do
		local className = desc.ClassName
		if
			className == "Humanoid"
			or className == "HumanoidDescription"
			or className == "Script"
			or className == "LocalScript"
			or className == "ModuleScript"
			or className == "Animator"
			or desc:IsA("BodyMover")
			or desc:IsA("Constraint")
			or desc:IsA("WeldConstraint")
		then
			desc:Destroy()
		end
	end

	-- BasePart 설정
	for _, desc in clone:GetDescendants() do
		if desc:IsA("BasePart") then
			local bp = desc :: BasePart
			bp.Anchored = true
			bp.CanCollide = false
			bp.CastShadow = false
		end
	end

	-- 이름 구분
	clone.Name = char.Name .. "_Clone"

	return clone
end

-- ─── 클론 제거 ───────────────────────────────────────────────────────────────

function CloneBroadcastClient:_removeClone(userId: number)
	local entry = self._clones[userId]
	if not entry then
		return
	end
	if entry.clone and entry.clone.Parent then
		entry.clone:Destroy()
	end
	self._clones[userId] = nil
end

-- ─── 정리 ────────────────────────────────────────────────────────────────────

function CloneBroadcastClient.Destroy(self: CloneBroadcastClient)
	for userId in self._clones do
		self:_removeClone(userId)
	end
	self._maid:Destroy()
end

return CloneBroadcastClient
