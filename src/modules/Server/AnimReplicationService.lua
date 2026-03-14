--!strict
--[=[
	@class AnimReplicationService

	절차적 애니메이션 서버 복제 서비스.

	동작:
	- 클라이언트로부터 AnimChanged 수신
	  → animDefModuleName으로 AnimDef require
	  → factory(joint, defaultC0, serverAC) 실행 → onUpdate 클로저 생성
	  → Heartbeat마다 onUpdate(joint, dt) 실행 → joint.C0 변경 → 자동 복제
	- AnimStopped 수신 → 해당 애니메이션 클로저 제거

	serverAC:
	- spring(joint, targetC0, speed, damper, dt) : Nevermore Spring 보간
	- GetMoveDir()                                : humanoid.MoveDirection 로컬 좌표 변환
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

type JointEntry = {
	onUpdate: (joint: Motor6D, dt: number) -> (),
	posSpring: any, -- Spring<Vector3>
	rotSpring: any, -- Spring<Vector3>
}

-- animDefModuleName_animName → { [jointName]: JointEntry }
type AnimEntry = {
	joints: { [string]: JointEntry },
	layer: number,
}

type PlayerAnimState = {
	-- animKey → AnimEntry  (animKey = animDefModuleName .. "_" .. animName)
	anims: { [string]: AnimEntry },
	-- joint 레퍼런스 캐시 (jointName → Motor6D)
	joints: { [string]: Motor6D },
	-- defaultC0 캐시 (전송받은 값)
	defaultC0s: { [string]: CFrame },
	-- humanoid / rootPart (MoveDir 계산용)
	humanoid: Humanoid?,
	rootPart: BasePart?,
	-- 플레이어별 Maid
	maid: any,
}

export type AnimReplicationService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_playerStates: { [number]: PlayerAnimState },
	},
	{} :: typeof({ __index = {} })
))

local AnimReplicationService = {}
AnimReplicationService.ServiceName = "AnimReplicationService"
AnimReplicationService.__index = AnimReplicationService

-- ─── 초기화 ──────────────────────────────────────────────────────────────────

function AnimReplicationService.Init(self: AnimReplicationService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._playerStates = {}

	self._maid:GiveTask(
		AnimReplicationRemoting.AnimChanged:Connect(
			function(
				player: Player,
				animDefModuleName: unknown,
				animName: unknown,
				animType: unknown,
				layer: unknown,
				defaultC0Map: unknown
			)
				self:_onAnimChanged(player, animDefModuleName, animName, animType, layer, defaultC0Map)
			end
		)
	)

	self._maid:GiveTask(
		AnimReplicationRemoting.AnimStopped:Connect(
			function(player: Player, animDefModuleName: unknown, animName: unknown)
				self:_onAnimStopped(player, animDefModuleName, animName)
			end
		)
	)
end

function AnimReplicationService.Start(self: AnimReplicationService): ()
	for _, player in Players:GetPlayers() do
		self:_onPlayerAdded(player)
	end
	self._maid:GiveTask(Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end))
	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end))
	self._maid:GiveTask(RunService.Heartbeat:Connect(function(dt)
		self:_update(dt)
	end))
end

-- ─── 플레이어 라이프사이클 ────────────────────────────────────────────────────

function AnimReplicationService:_onPlayerAdded(player: Player)
	local pMaid = Maid.new()

	local state: PlayerAnimState = {
		anims = {},
		joints = {},
		defaultC0s = {},
		humanoid = nil,
		rootPart = nil,
		maid = pMaid,
	}
	self._playerStates[player.UserId] = state

	local function onCharacterAdded(char: Model)
		-- 기존 애니메이션 전부 클리어
		state.anims = {}
		state.joints = {}
		state.defaultC0s = {}

		state.humanoid = char:WaitForChild("Humanoid") :: Humanoid
		state.rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart

		-- joint 캐시 구성
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

	self._playerStates[player.UserId] = state
end

function AnimReplicationService:_onPlayerRemoving(player: Player)
	local state = self._playerStates[player.UserId]
	if state then
		state.maid:Destroy()
	end
	self._playerStates[player.UserId] = nil
end

-- ─── 수신 처리 ───────────────────────────────────────────────────────────────

function AnimReplicationService:_onAnimChanged(
	player: Player,
	animDefModuleName: unknown,
	animName: unknown,
	animType: unknown,
	layer: unknown,
	defaultC0Map: unknown
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

	local state = self._playerStates[player.UserId]
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
	local ok, animDefs = pcall(require, animDefModuleName)
	if not ok or type(animDefs) ~= "table" then
		warn("[AnimReplicationService] AnimDef 로드 실패:", animDefModuleName)
		return
	end

	local def = animDefs[animName :: string]
	if not def then
		return
	end

	local serverAC = self:_makeServerAC(state)
	local animKey = animDefModuleName .. "_" .. animName

	if animType == "anim" then
		if type(layer) ~= "number" then
			return
		end

		-- 같은 layer의 기존 anim 교체
		for existingKey, existing in state.anims do
			if existing.layer == layer then
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

			local rx0, ry0, rz0 = defaultC0:ToEulerAnglesXYZ()
			local posSpring = Spring.new(joint.C0.Position)
			posSpring.Speed = 20
			posSpring.Damper = 1
			local rotSpring = Spring.new(Vector3.new(rx0, ry0, rz0))
			rotSpring.Speed = 20
			rotSpring.Damper = 1

			serverAC._springs[joint] = { pos = posSpring, rot = rotSpring }
			serverAC._defaultC0s[joint] = defaultC0

			local onUpdate = factory(joint, defaultC0, serverAC)
			jointEntries[jointName] = {
				onUpdate = onUpdate,
				posSpring = posSpring,
				rotSpring = rotSpring,
			}
		end

		state.anims[animKey] = { joints = jointEntries, layer = layer :: number }
	elseif animType == "modify" then
		-- modifier: onUpdate로 매 프레임 current CFrame에 적용
		local jointEntries: { [string]: JointEntry } = {}
		for jointName, factory in def.joints do
			local joint = state.joints[jointName]
			if not joint then
				continue
			end

			local defaultC0 = state.defaultC0s[jointName] or joint.C0

			local rx0, ry0, rz0 = defaultC0:ToEulerAnglesXYZ()
			local posSpring = Spring.new(joint.C0.Position)
			posSpring.Speed = 20
			posSpring.Damper = 1
			local rotSpring = Spring.new(Vector3.new(rx0, ry0, rz0))
			rotSpring.Speed = 20
			rotSpring.Damper = 1

			serverAC._springs[joint] = { pos = posSpring, rot = rotSpring }
			serverAC._defaultC0s[joint] = defaultC0

			local modCallback = factory(joint, defaultC0, serverAC)

			-- modifier는 매 프레임 current C0에 적용
			local function onUpdate(j: Motor6D, _dt: number)
				j.C0 = modCallback(j.C0, _dt)
			end

			jointEntries[jointName] = {
				onUpdate = onUpdate,
				posSpring = posSpring,
				rotSpring = rotSpring,
			}
		end

		-- modifier는 layer 없이 별도 키로 저장 (layer = -1 관례)
		state.anims[animKey] = { joints = jointEntries, layer = -1 }
	end
end

function AnimReplicationService:_onAnimStopped(player: Player, animDefModuleName: unknown, animName: unknown)
	if type(animDefModuleName) ~= "string" then
		return
	end
	if type(animName) ~= "string" then
		return
	end

	local state = self._playerStates[player.UserId]
	if not state then
		return
	end

	local animKey = animDefModuleName .. "_" .. animName
	state.anims[animKey] = nil
end

-- ─── Heartbeat 업데이트 ───────────────────────────────────────────────────────

function AnimReplicationService:_update(dt: number)
	for _, state in self._playerStates do
		for _, animEntry in state.anims do
			for jointName, jointEntry in animEntry.joints do
				local joint = state.joints[jointName]
				if not joint then
					continue
				end
				jointEntry.onUpdate(joint, dt)
			end
		end
	end
end

-- ─── serverAC 생성 ────────────────────────────────────────────────────────────

function AnimReplicationService:_makeServerAC(state: PlayerAnimState): any
	local serverAC = {
		_springs = {} :: { [Motor6D]: { pos: any, rot: any } },
		_defaultC0s = {} :: { [Motor6D]: CFrame },
	}

	--[=[
		AnimDef factory 안에서 ac:spring() 대신 호출.
		Nevermore Spring으로 보간 후 joint.C0 변경.
	]=]
	function serverAC:spring(joint: Motor6D, targetC0: CFrame, speed: number, damper: number, _dt: number)
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

	--[=[
		이동 방향을 캐릭터 로컬 좌표로 변환하여 반환.
	]=]
	function serverAC:GetMoveDir(): Vector3
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

	--[=[
		전송받은 defaultC0Map 또는 현재 joint.C0 반환.
	]=]
	function serverAC:GetDefaultC0(joint: Motor6D): CFrame
		return self._defaultC0s[joint] or joint.C0
	end

	return serverAC
end

function AnimReplicationService.Destroy(self: AnimReplicationService)
	self._maid:Destroy()
end

return AnimReplicationService
