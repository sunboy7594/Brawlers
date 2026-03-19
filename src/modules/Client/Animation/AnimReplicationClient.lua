--!strict
--[=[
	@class AnimReplicationClient

	다른 플레이어의 절차적 애니메이션을 로컬에서 실행하는 클라이언트 서비스.

	동작:
	- AnimBroadcast 수신 → animDefModuleName으로 AnimDef require
	  → factory(joint, defaultC0, localAC, params) 실행 → Heartbeat마다 onUpdate(joint, dt)
	- AnimStopBroadcast 수신 → 해당 애니메이션 제거
	  (animDefModuleName/animName이 nil이면 해당 플레이어 전체 정지 — 퇴장 처리)
	- 레이트 조인: 서버가 CharacterAdded 시 기존 상태 전송 → 동일하게 처리
	- 자기 자신(LocalPlayer)의 이벤트는 userId 비교로 무시

	localAC (AnimationControllerClient 대체):
	- spring(joint, targetC0, speed, damper, dt) : Nevermore Spring 보간 후 joint.C0 적용
	- GetMoveDir()                                : 해당 플레이어 MoveDirection 로컬 좌표 변환
	- GetDefaultC0(joint)                         : 전송받은 defaultC0Map에서 반환
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AnimReplicationRemoting = require("AnimReplicationRemoting")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local Spring = require("Spring")

-- ─── 타입 ────────────────────────────────────────────────────────────────────

type AnimParams = {
	intensity: number?,
	direction: Vector3?,
}

type JointEntry = {
	onUpdate: (joint: Motor6D, dt: number) -> (),
}

type AnimEntry = {
	joints: { [string]: JointEntry },
	layer: number,
	duration: number,
	elapsed: number,
}

type RemotePlayerState = {
	anims: { [string]: AnimEntry },
	joints: { [string]: Motor6D },
	defaultC0s: { [string]: CFrame },
	jointSprings: { [Motor6D]: { pos: any, rot: any } },
	humanoid: Humanoid?,
	rootPart: BasePart?,
	localAC: any,
	maid: any,
}

export type AnimReplicationClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_remoteStates: { [number]: RemotePlayerState },
	},
	{} :: typeof({ __index = {} })
))

local AnimReplicationClient = {}
AnimReplicationClient.ServiceName = "AnimReplicationClient"
AnimReplicationClient.__index = AnimReplicationClient

-- ─── 초기화 ──────────────────────────────────────────────────────────────────

function AnimReplicationClient.Init(self: AnimReplicationClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._remoteStates = {}
end

function AnimReplicationClient.Start(self: AnimReplicationClient): ()
	for _, player in Players:GetPlayers() do
		if player ~= Players.LocalPlayer then
			self:_onPlayerAdded(player)
		end
	end
	self._maid:GiveTask(Players.PlayerAdded:Connect(function(player)
		if player ~= Players.LocalPlayer then
			self:_onPlayerAdded(player)
		end
	end))
	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end))
	self._maid:GiveTask(
		AnimReplicationRemoting.AnimBroadcast:Connect(
			function(userId, animDefModuleName, animName, animType, layer, duration, defaultC0Map, animParams)
				if userId == Players.LocalPlayer.UserId then
					return
				end
				self:_onAnimBroadcast(
					userId,
					animDefModuleName,
					animName,
					animType,
					layer,
					duration,
					defaultC0Map,
					animParams
				)
			end
		)
	)
	self._maid:GiveTask(
		AnimReplicationRemoting.AnimStopBroadcast:Connect(function(userId, animDefModuleName, animName)
			if userId == Players.LocalPlayer.UserId then
				return
			end
			self:_onAnimStopBroadcast(userId, animDefModuleName, animName)
		end)
	)
	self._maid:GiveTask(RunService.Heartbeat:Connect(function(dt)
		self:_update(dt)
	end))
end

-- ─── 플레이어 관리 ────────────────────────────────────────────────────────────

function AnimReplicationClient:_onPlayerAdded(player: Player)
	local pMaid = Maid.new()
	self._maid:GiveTask(pMaid)

	local state: RemotePlayerState = {
		anims = {},
		joints = {},
		defaultC0s = {},
		jointSprings = {},
		humanoid = nil,
		rootPart = nil,
		localAC = nil,
		maid = pMaid,
	}
	state.localAC = self:_makeLocalAC(state)
	self._remoteStates[player.UserId] = state

	local function onCharacterAdded(char: Model)
		state.anims = {}
		state.joints = {}
		state.defaultC0s = {}
		state.jointSprings = {}
		state.humanoid = char:WaitForChild("Humanoid") :: Humanoid
		state.rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart
		for _, desc in char:GetDescendants() do
			if desc:IsA("Motor6D") then
				state.joints[desc.Name] = desc
			end
		end
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end
	pMaid:GiveTask(player.CharacterAdded:Connect(onCharacterAdded))
end

function AnimReplicationClient:_onPlayerRemoving(player: Player)
	local state = self._remoteStates[player.UserId]
	if state then
		state.maid:Destroy()
	end
	self._remoteStates[player.UserId] = nil
end

-- ─── 브로드캐스트 수신 ────────────────────────────────────────────────────────

function AnimReplicationClient:_onAnimBroadcast(
	userId: number,
	animDefModuleName: unknown,
	animName: unknown,
	animType: unknown,
	layer: unknown,
	duration: unknown,
	defaultC0Map: unknown,
	animParams: unknown
)
	if type(animDefModuleName) ~= "string" then
		return
	end
	if type(animName) ~= "string" then
		return
	end
	if type(animType) ~= "string" then
		return
	end
	if type(defaultC0Map) ~= "table" then
		return
	end

	local state = self._remoteStates[userId]
	if not state then
		return
	end

	-- defaultC0Map 병합
	for jointName, c0 in defaultC0Map :: { [string]: unknown } do
		if type(jointName) == "string" and typeof(c0) == "CFrame" then
			state.defaultC0s[jointName] = c0 :: CFrame
		end
	end

	-- AnimDef 로드
	local ok, animDefs = pcall(require, animDefModuleName :: string)
	if not ok or type(animDefs) ~= "table" then
		warn("[AnimReplicationClient] AnimDef 로드 실패:", animDefModuleName)
		return
	end

	local def = animDefs[animName :: string]
	if not def then
		return
	end

	local localAC = state.localAC
	local animKey = animDefModuleName .. "_" .. animName
	local animDuration = type(duration) == "number" and duration or math.huge

	if animType == "anim" then
		if type(layer) ~= "number" then
			return
		end

		-- 같은 layer 기존 항목 교체
		for existingKey, existing in state.anims do
			if existing.layer == (layer :: number) then
				state.anims[existingKey] = nil
				break
			end
		end

		local jointEntries: { [string]: JointEntry } = {}
		for jointName, factory in def.joints do
			local joint = state.joints[jointName]
			if not joint then
				continue
			end
			local defaultC0 = state.defaultC0s[jointName] or joint.C0
			self:_ensureJointSprings(state, joint, defaultC0)
			localAC._springs[joint] = state.jointSprings[joint]
			localAC._defaultC0s[joint] = defaultC0
			local onUpdate = factory(joint, defaultC0, localAC, animParams)
			jointEntries[jointName] = { onUpdate = onUpdate }
		end

		state.anims[animKey] = {
			joints = jointEntries,
			layer = layer :: number,
			duration = animDuration,
			elapsed = 0,
		}

	elseif animType == "modify" then
		local jointEntries: { [string]: JointEntry } = {}
		for jointName, factory in def.joints do
			local joint = state.joints[jointName]
			if not joint then
				continue
			end
			local defaultC0 = state.defaultC0s[jointName] or joint.C0
			self:_ensureJointSprings(state, joint, defaultC0)
			localAC._springs[joint] = state.jointSprings[joint]
			localAC._defaultC0s[joint] = defaultC0
			local modCallback = factory(joint, defaultC0, localAC, animParams)
			local function onUpdate(j: Motor6D, _dt: number)
				j.C0 = modCallback(j.C0, _dt)
			end
			jointEntries[jointName] = { onUpdate = onUpdate }
		end

		state.anims[animKey] = {
			joints = jointEntries,
			layer = -1,
			duration = math.huge,
			elapsed = 0,
		}
	end
end

function AnimReplicationClient:_onAnimStopBroadcast(
	userId: number,
	animDefModuleName: unknown,
	animName: unknown
)
	local state = self._remoteStates[userId]
	if not state then
		return
	end

	-- nil이면 플레이어 퇴장 → 전부 정지
	if animDefModuleName == nil then
		state.anims = {}
		return
	end

	if type(animDefModuleName) ~= "string" then
		return
	end
	if type(animName) ~= "string" then
		return
	end
	state.anims[animDefModuleName .. "_" .. animName] = nil
end

-- ─── Heartbeat 업데이트 ───────────────────────────────────────────────────────

function AnimReplicationClient:_update(dt: number)
	for _, state in self._remoteStates do
		local activeJoints: { [Motor6D]: boolean } = {}
		local toRemove: { string } = {}

		for animKey, animEntry in state.anims do
			animEntry.elapsed += dt
			if animEntry.elapsed >= animEntry.duration then
				table.insert(toRemove, animKey)
				continue
			end
			for jointName, jointEntry in animEntry.joints do
				local joint = state.joints[jointName]
				if not joint then
					continue
				end
				activeJoints[joint] = true
				jointEntry.onUpdate(joint, dt)
			end
		end

		for _, animKey in toRemove do
			state.anims[animKey] = nil
		end

		-- 비활성 관절 → defaultC0로 spring 복귀
		for jointName, joint in state.joints do
			if activeJoints[joint] then
				continue
			end
			local springs = state.jointSprings[joint]
			if not springs then
				continue
			end
			local defaultC0 = state.defaultC0s[jointName] or joint.C0

			springs.pos.Speed = 20
			springs.pos.Damper = 0.8
			springs.rot.Speed = 20
			springs.rot.Damper = 0.8

			local tx, ty, tz = defaultC0:ToEulerAnglesXYZ()
			springs.pos.Target = defaultC0.Position
			springs.rot.Target = Vector3.new(tx, ty, tz)

			local p = springs.pos.Position
			local r = springs.rot.Position
			joint.C0 = CFrame.new(p) * CFrame.fromEulerAnglesXYZ(r.X, r.Y, r.Z)
		end
	end
end

-- ─── 헬퍼 ────────────────────────────────────────────────────────────────────

function AnimReplicationClient:_ensureJointSprings(
	state: RemotePlayerState,
	joint: Motor6D,
	defaultC0: CFrame
)
	if state.jointSprings[joint] then
		return
	end
	local rx0, ry0, rz0 = defaultC0:ToEulerAnglesXYZ()
	local posSpring = Spring.new(joint.C0.Position)
	posSpring.Speed = 20
	posSpring.Damper = 1
	local rotSpring = Spring.new(Vector3.new(rx0, ry0, rz0))
	rotSpring.Speed = 20
	rotSpring.Damper = 1
	state.jointSprings[joint] = { pos = posSpring, rot = rotSpring }
end

-- localAC: factory에 주입하는 컨트롤러 (serverAC와 동일한 인터페이스)
function AnimReplicationClient:_makeLocalAC(state: RemotePlayerState): any
	local localAC = {
		_springs = {} :: { [Motor6D]: { pos: any, rot: any } },
		_defaultC0s = {} :: { [Motor6D]: CFrame },
	}

	function localAC:spring(joint: Motor6D, targetC0: CFrame, speed: number, damper: number, _dt: number)
		local springs = self._springs[joint]
		if not springs then
			return
		end
		springs.pos.Speed = speed
		springs.pos.Damper = damper
		springs.rot.Speed = speed
		springs.rot.Damper = damper
		local tx, ty, tz = targetC0:ToEulerAnglesXYZ()
		springs.pos.Target = targetC0.Position
		springs.rot.Target = Vector3.new(tx, ty, tz)
		local p = springs.pos.Position
		local r = springs.rot.Position
		joint.C0 = CFrame.new(p) * CFrame.fromEulerAnglesXYZ(r.X, r.Y, r.Z)
	end

	function localAC:GetMoveDir(): Vector3
		local humanoid = state.humanoid
		local rootPart = state.rootPart
		if not humanoid or not rootPart then
			return Vector3.zero
		end
		local worldDir = humanoid.MoveDirection
		if worldDir.Magnitude < 0.01 then
			return Vector3.zero
		end
		return rootPart.CFrame:VectorToObjectSpace(worldDir)
	end

	function localAC:GetDefaultC0(joint: Motor6D): CFrame
		return self._defaultC0s[joint] or joint.C0
	end

	return localAC
end

function AnimReplicationClient.Destroy(self: AnimReplicationClient)
	self._maid:Destroy()
end

return AnimReplicationClient
