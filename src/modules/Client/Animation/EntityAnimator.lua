--!strict
--[=[
	@class EntityAnimator

	범용 애니메이터. 관절 목록과 AnimDefs를 주입받아 PlayAnimation을 제공합니다.
	BaseObject를 상속하여 self._maid를 자동으로 제공받습니다.

	AnimDef.type:
	  "anim"   → layer 기반 재생. 같은 layer의 기존 anim을 교체.
	  "modify" → 이름 기반 modifier 등록. 여러 개 동시 등록 가능.

	params:
	  { intensity: number?, direction: Vector3? }
	  factory 호출 시 전달. intensity는 애니메이션 강도, direction은 방향 기반 연출용.
	  서버 복제 시에도 params가 함께 전송되어 다른 클라이언트에도 동일하게 적용됩니다.
	  BasicMovementAnimDef처럼 CycleRef 참조 공유가 필요한 경우 params 없이 nil 전달.

	복제 구조:
	  PlayAnimation/StopAnimation 시 AnimReplicationRemoting으로 서버에 알림.
	  서버(AnimReplicationService)는 다른 클라이언트에 설계도(AnimDef + params)를 포워딩.
	  클라이언트(AnimReplicationClient)가 로컬에서 동일한 factory를 실행하여 joint.C0 변경.
	  카메라 애니메이션(CameraAnimator)은 복제 불필요이므로 전송하지 않음.
	  replicates = false 옵션으로 복제 제외 가능.
]=]

local require = require(script.Parent.loader).load(script)

local RunService = game:GetService("RunService")

local AnimReplicationRemoting = require("AnimReplicationRemoting")
local BaseObject = require("BaseObject")

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type AnimParams = {
	intensity: number?,
	direction: Vector3?,
}

export type AnimFactory = (
	joint: Motor6D,
	defaultC0: CFrame,
	animController: any,
	params: AnimParams?
) -> (joint: Motor6D, dt: number) -> ()

export type ModifyFactory = (
	joint: Motor6D,
	defaultC0: CFrame,
	animController: any,
	params: AnimParams?
) -> (current: CFrame, dt: number) -> CFrame

export type AnimDef =
	{
		type: "anim",
		layer: number,
		joints: { [string]: AnimFactory },
		replicates: boolean?,
	}
	| {
		type: "modify",
		joints: { [string]: ModifyFactory },
		replicates: boolean?,
	}

export type AnimDefs = { [string]: AnimDef }

type ActiveAnim = {
	layer: number,
	joints: { Motor6D },
}

type ActiveModifier = {
	joints: { Motor6D },
}

type AnimationControllerClient = {
	RegisterJoint: (self: any, joint: Motor6D) -> (),
	GetDefaultC0: (self: any, joint: Motor6D) -> CFrame,
	Play: (
		self: any,
		owner: string,
		layer: number,
		joint: Motor6D,
		onUpdate: (Motor6D, number) -> (),
		duration: number?,
		onFinish: (() -> ())?
	) -> (),
	Stop: (self: any, owner: string, joint: Motor6D) -> (),
	StopAll: (self: any, owner: string, joints: { Motor6D }) -> (),
	SetModifier: (self: any, owner: string, joint: Motor6D, callback: (CFrame, number) -> CFrame) -> (),
	RemoveModifier: (self: any, owner: string, joint: Motor6D) -> (),
}

export type EntityAnimator = typeof(setmetatable(
	{} :: {
		_maid: any,
		_owner: string,
		_animDefModuleName: string,
		_joints: { [string]: Motor6D },
		_animDefs: AnimDefs,
		_animController: AnimationControllerClient,
		_activeAnims: { [string]: ActiveAnim },
		_activeModifiers: { [string]: ActiveModifier },
	},
	{} :: typeof({ __index = BaseObject })
))

-- ─── 클래스 ──────────────────────────────────────────────────────────────────

local EntityAnimator = setmetatable({}, BaseObject)
EntityAnimator.__index = EntityAnimator

-- ─── 생성자 ──────────────────────────────────────────────────────────────────

function EntityAnimator.new(
	owner: string,
	animDefModuleName: string,
	joints: { [string]: Motor6D },
	animDefs: AnimDefs,
	animController: AnimationControllerClient
): EntityAnimator
	local self = (setmetatable(BaseObject.new(), EntityAnimator) :: any) :: EntityAnimator

	self._owner = owner
	self._animDefModuleName = animDefModuleName
	self._joints = joints
	self._animDefs = animDefs
	self._animController = animController
	self._activeAnims = {}
	self._activeModifiers = {}

	for _, joint in joints do
		animController:RegisterJoint(joint)
	end

	return self
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	@param params AnimParams?  { intensity, direction } — factory에 전달.
	                           BasicMovementAnimDef처럼 참조 공유가 필요하면 nil 전달.
]=]
function EntityAnimator:PlayAnimation(
	name: string,
	duration: number?,
	onFinish: (() -> ())?,
	force: boolean?,
	params: AnimParams?
)
	local def = self._animDefs[name]
	if not def then
		warn(string.format("[EntityAnimator] '%s' 에 애니메이션 정의 '%s' 없음", self._owner, name))
		return
	end

	if def.type == "anim" then
		if self._activeAnims[name] then
			if not force then
				return
			end
			self:_stopAnim(name)
		end

		for activeName, active in self._activeAnims do
			if active.layer == def.layer then
				self:_stopAnim(activeName)
				break
			end
		end

		local joints: { Motor6D } = {}
		local defaultC0Map: { [string]: CFrame } = {}

		for jointName, factory in def.joints do
			local joint = self._joints[jointName]
			if not joint then
				continue
			end

			local defaultC0 = self._animController:GetDefaultC0(joint)
			local onUpdate = factory(joint, defaultC0, self._animController, params)
			self._animController:Play(self._owner, def.layer, joint, onUpdate, duration, onFinish)
			table.insert(joints, joint)
			defaultC0Map[jointName] = defaultC0
		end

		self._activeAnims[name] = { layer = def.layer, joints = joints }

		if RunService:IsClient() and def.replicates ~= false then
			AnimReplicationRemoting.AnimChanged:FireServer(
				self._animDefModuleName,
				name,
				"anim",
				def.layer,
				duration or math.huge,
				defaultC0Map,
				params
			)
		end
	elseif def.type == "modify" then
		if self._activeModifiers[name] then
			return
		end

		local modKey = self._owner .. "_" .. name
		local joints: { Motor6D } = {}
		local defaultC0Map: { [string]: CFrame } = {}

		for jointName, factory in def.joints do
			local joint = self._joints[jointName]
			if not joint then
				continue
			end

			local defaultC0 = self._animController:GetDefaultC0(joint)
			local callback = factory(joint, defaultC0, self._animController, params)
			self._animController:SetModifier(modKey, joint, callback)
			table.insert(joints, joint)
			defaultC0Map[jointName] = defaultC0
		end

		self._activeModifiers[name] = { joints = joints }

		if RunService:IsClient() and def.replicates ~= false then
			AnimReplicationRemoting.AnimChanged:FireServer(
				self._animDefModuleName,
				name,
				"modify",
				nil,
				math.huge,
				defaultC0Map,
				params
			)
		end
	end
end

function EntityAnimator:StopAnimation(name: string?)
	if name == nil then
		self:StopAllAnims()
		self:StopAllModifiers()
	elseif name == "anim" then
		self:StopAllAnims()
	elseif name == "modify" then
		self:StopAllModifiers()
	else
		local def = self._animDefs[name]
		if not def then
			return
		end
		if def.type == "anim" then
			self:_stopAnim(name)
		else
			self:_stopModifier(name)
		end
	end
end

function EntityAnimator:StopAllAnims()
	local names: { string } = {}
	for name in self._activeAnims do
		table.insert(names, name)
	end
	for _, name in names do
		self:_stopAnim(name)
	end
end

function EntityAnimator:StopAllModifiers()
	local names: { string } = {}
	for name in self._activeModifiers do
		table.insert(names, name)
	end
	for _, name in names do
		self:_stopModifier(name)
	end
end

function EntityAnimator:UpdateJoints(joints: { [string]: Motor6D })
	self:StopAnimation()
	self._joints = joints
	for _, joint in joints do
		self._animController:RegisterJoint(joint)
	end
end

function EntityAnimator:Destroy()
	self:StopAnimation()
	BaseObject.Destroy(self)
end

-- ─── 내부 ────────────────────────────────────────────────────────────────────

function EntityAnimator:_stopAnim(name: string)
	local active = self._activeAnims[name]
	if not active then
		return
	end

	self._animController:StopAll(self._owner, active.joints)
	self._activeAnims[name] = nil

	local def = self._animDefs[name]
	if RunService:IsClient() and def and def.replicates ~= false then
		AnimReplicationRemoting.AnimStopped:FireServer(self._animDefModuleName, name)
	end
end

function EntityAnimator:_stopModifier(name: string)
	local active = self._activeModifiers[name]
	if not active then
		return
	end

	local modKey = self._owner .. "_" .. name
	for _, joint in active.joints do
		self._animController:RemoveModifier(modKey, joint)
	end
	self._activeModifiers[name] = nil

	local def = self._animDefs[name]
	if RunService:IsClient() and def and def.replicates ~= false then
		AnimReplicationRemoting.AnimStopped:FireServer(self._animDefModuleName, name)
	end
end

return EntityAnimator
