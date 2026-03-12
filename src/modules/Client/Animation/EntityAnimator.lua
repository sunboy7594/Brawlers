--!strict
--[=[
	@class EntityAnimator

	범용 애니메이터. 관절 목록과 AnimDefs를 주입받아 PlayAnimation을 제공합니다.
	BaseObject를 상속하여 self._maid를 자동으로 제공받습니다.

	AnimDef.type:
	  "anim"   → layer 기반 재생. 같은 layer의 기존 anim을 교체.
	  "modify" → 이름 기반 modifier 등록. 여러 개 동시 등록 가능.

	AnimFactory 호출 시 AnimationControllerClient에서 defaultC0를 조회하여
	함께 넘겨줍니다. factory는 이 값을 base로 사용해야 하며,
	절대로 joint.C0를 capture 시점에 base로 써서는 안 됩니다.
]=]

local require = require(script.Parent.loader).load(script)

local BaseObject = require("BaseObject")

-- ─── 타입 ────────────────────────────────────────────────────────────────────

--[=[
	anim factory: (joint, defaultC0, ac) → onUpdate 클로저
]=]
export type AnimFactory = (joint: Motor6D, defaultC0: CFrame, animController: any) -> (joint: Motor6D, dt: number) -> ()

--[=[
	modify factory: (joint, defaultC0, ac) → modifier 클로저
	current는 애니메이션 레이어가 적용된 joint.C0 값입니다.
]=]
export type ModifyFactory = (
	joint: Motor6D,
	defaultC0: CFrame,
	animController: any
) -> (current: CFrame, dt: number) -> CFrame

export type AnimDef =
	{
		type: "anim",
		layer: number,
		joints: { [string]: AnimFactory },
	}
	| {
		type: "modify",
		joints: { [string]: ModifyFactory },
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
	StopAll: (self: any, owner: string, joints: { Motor6D }) -> (),
	SetModifier: (self: any, owner: string, joint: Motor6D, callback: (CFrame, number) -> CFrame) -> (),
	RemoveModifier: (self: any, owner: string, joint: Motor6D) -> (),
}

export type EntityAnimator = typeof(setmetatable(
	{} :: {
		_maid: any, -- BaseObject에서 자동 제공
		_owner: string,
		_joints: { [string]: Motor6D },
		_animDefs: AnimDefs,
		_animController: AnimationControllerClient,
		_activeAnims: { [string]: ActiveAnim },
		_activeModifiers: { [string]: ActiveModifier },
	},
	{} :: typeof({ __index = BaseObject })
))

-- ─── 클래스 선언 (BaseObject 상속) ───────────────────────────────────────────

local EntityAnimator = setmetatable({}, BaseObject)
EntityAnimator.__index = EntityAnimator

-- ─── 생성자 ──────────────────────────────────────────────────────────────────

function EntityAnimator.new(
	owner: string,
	joints: { [string]: Motor6D },
	animDefs: AnimDefs,
	animController: AnimationControllerClient
): EntityAnimator
	local self = (setmetatable(BaseObject.new(), EntityAnimator) :: any) :: EntityAnimator

	self._owner = owner
	self._joints = joints
	self._animDefs = animDefs
	self._animController = animController
	self._activeAnims = {}
	self._activeModifiers = {}

	-- 모든 관절 등록 (defaultC0 저장)
	for _, joint in joints do
		animController:RegisterJoint(joint)
	end

	return self
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

function EntityAnimator:PlayAnimation(name: string, duration: number?, onFinish: (() -> ())?)
	local def = self._animDefs[name]
	if not def then
		warn(string.format("[EntityAnimator] '%s' 에 애니메이션 정의 '%s' 없음", self._owner, name))
		return
	end

	if def.type == "anim" then
		-- 이미 재생 중이면 무시
		if self._activeAnims[name] then
			return
		end

		-- 같은 layer의 기존 anim 교체
		for activeName, active in self._activeAnims do
			if active.layer == def.layer then
				self:_stopAnim(activeName)
				break
			end
		end

		-- 새 anim 등록
		local joints: { Motor6D } = {}
		for jointName, factory in def.joints do
			local joint = self._joints[jointName]
			if not joint then
				continue
			end
			local defaultC0 = self._animController:GetDefaultC0(joint)
			local onUpdate = factory(joint, defaultC0, self._animController)
			self._animController:Play(self._owner, def.layer, joint, onUpdate, duration, onFinish)
			table.insert(joints, joint)
		end

		self._activeAnims[name] = { layer = def.layer, joints = joints }
	elseif def.type == "modify" then
		-- 이미 등록된 modifier면 무시
		if self._activeModifiers[name] then
			return
		end

		-- modifier 등록
		local modKey = self._owner .. "_" .. name
		local joints: { Motor6D } = {}
		for jointName, factory in def.joints do
			local joint = self._joints[jointName]
			if not joint then
				continue
			end
			local defaultC0 = self._animController:GetDefaultC0(joint)
			local callback = factory(joint, defaultC0, self._animController)
			self._animController:SetModifier(modKey, joint, callback)
			table.insert(joints, joint)
		end

		self._activeModifiers[name] = { joints = joints }
	end
end

--[=[
	애니메이션/modifier를 정지합니다.

	@param name
	  nil        → 전부 제거 (anim + modifier)
	  "anim"     → 모든 anim 제거
	  "modify"   → 모든 modifier 제거
	  그 외 문자열 → 해당 이름의 anim 또는 modifier 제거. 없으면 무시.
]=]
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

--[=[
	모든 anim을 제거합니다. modifier는 유지됩니다.
]=]
function EntityAnimator:StopAllAnims()
	local names: { string } = {}
	for name in self._activeAnims do
		table.insert(names, name)
	end
	for _, name in names do
		self:_stopAnim(name)
	end
end

--[=[
	모든 modifier를 제거합니다. anim은 유지됩니다.
]=]
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
end

return EntityAnimator
