--!strict
--[=[
	@class CameraAnimator

	CameraControllerClient의 레이어 구조에 맞게 카메라 애니메이션을 이름으로 정의·저장·실행합니다.
	BaseObject를 상속하여 self._maid를 자동으로 제공받습니다.

	레이어:
	  "effect"   → SetEffectModifier / RemoveEffectModifier (여러 개 동시 등록 가능)
	  "offset"   → SetOffsetModifier / RemoveOffsetModifier (여러 개 동시 등록 가능)
	  "override" → SetOverride / ClearOverride              (하나만 유지, 새 등록 시 기존 교체)

	params: { intensity: number?, direction: Vector3? }
	  PlayAnimation 호출 시 factory에 전달. intensity로 흔들림 강도 등 스케일링.
	  direction은 방향 기반 카메라 연출(cam_knockback 등)에 사용.
]=]

local require = require(script.Parent.loader).load(script)

local BaseObject = require("BaseObject")

-- ─── 타입 ────────────────────────────────────────────────────────────────────

type CameraController = {
	SetEffectModifier: (self: any, name: string, modifier: (CFrame, number) -> CFrame) -> (),
	RemoveEffectModifier: (self: any, name: string) -> (),
	SetOffsetModifier: (
		self: any,
		name: string,
		modifier: { offset: Vector3, fov: number?, stiffness: number, damping: number }
	) -> (),
	RemoveOffsetModifier: (self: any, name: string) -> (),
	SetOverride: (self: any, onUpdate: (Camera, number) -> ()) -> (),
	ClearOverride: (self: any) -> (),
}

export type CameraAnimLayer = "effect" | "offset" | "override"

export type CameraAnimParams = {
	intensity: number?,
	direction: Vector3?,
}

export type CameraAnimFactory = (controller: CameraController, params: CameraAnimParams?) -> any

export type CameraAnimDef = {
	layer: CameraAnimLayer,
	factory: CameraAnimFactory,
}

export type CameraAnimDefs = { [string]: CameraAnimDef }

type ActiveAnim = {
	layer: CameraAnimLayer,
	durationThread: thread?,
}

export type CameraAnimator = typeof(setmetatable(
	{} :: {
		_maid: any,
		_owner: string,
		_animDefs: CameraAnimDefs,
		_controller: CameraController,
		_activeAnims: { [string]: ActiveAnim },
		_currentOverride: string?,
	},
	{} :: typeof({ __index = BaseObject })
))

-- ─── 클래스 선언 (BaseObject 상속) ───────────────────────────────────────────

local CameraAnimator = setmetatable({}, BaseObject)
CameraAnimator.__index = CameraAnimator

-- ─── 생성자 ──────────────────────────────────────────────────────────────────

function CameraAnimator.new(owner: string, animDefs: CameraAnimDefs, cameraController: CameraController): CameraAnimator
	local self = (setmetatable(BaseObject.new(), CameraAnimator) :: any) :: CameraAnimator
	self._owner = owner
	self._animDefs = animDefs
	self._controller = cameraController
	self._activeAnims = {}
	self._currentOverride = nil
	return self
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	카메라 애니메이션을 재생합니다.

	- effect / offset: 이름 기반 등록. 여러 개 동시 가능.
	- override: 하나만 유지. 새 등록 시 기존 override 자동 교체.

	force=true이면 이미 재생 중인 경우 기존 것을 정지하고 처음부터 재시작합니다.
	force=false(기본): 이미 재생 중이면 무시합니다.

	@param params CameraAnimParams?  { intensity, direction } — factory에 전달.
]=]
function CameraAnimator:PlayAnimation(
	name: string,
	duration: number?,
	onFinish: (() -> ())?,
	force: boolean?,
	params: CameraAnimParams?
)
	local def = self._animDefs[name]
	if not def then
		warn(string.format("[CameraAnimator] '%s' 에 카메라 애니메이션 정의 '%s' 없음", self._owner, name))
		return
	end

	if self._activeAnims[name] then
		if not force then
			return
		end
		self:_stopByName(name)
	end

	if def.layer == "override" and self._currentOverride then
		self:_stopByName(self._currentOverride)
	end

	local modKey = self._owner .. "_" .. name
	local result = def.factory(self._controller, params)

	if def.layer == "effect" then
		self._controller:SetEffectModifier(modKey, result)
	elseif def.layer == "offset" then
		self._controller:SetOffsetModifier(modKey, result)
	elseif def.layer == "override" then
		self._controller:SetOverride(result)
		self._currentOverride = name
	end

	local durationThread: thread? = nil
	if duration then
		durationThread = task.delay(duration, function()
			local active = self._activeAnims[name]
			if not active or active.durationThread ~= durationThread then
				return
			end
			active.durationThread = nil
			self:_stopByName(name)
			if onFinish then
				onFinish()
			end
		end)
	end

	self._activeAnims[name] = {
		layer = def.layer,
		durationThread = durationThread,
	}
end

--[=[
	카메라 애니메이션을 정지합니다.

	@param name
	  nil      → 전부 정지
	  문자열   → 해당 이름만 정지. 없으면 무시.
]=]
function CameraAnimator:Stop(name: string?)
	if name == nil then
		local names: { string } = {}
		for n in self._activeAnims do
			table.insert(names, n)
		end
		for _, n in names do
			self:_stopByName(n)
		end
	else
		self:_stopByName(name)
	end
end

function CameraAnimator:StopAllEffects()
	local names: { string } = {}
	for n, active in self._activeAnims do
		if active.layer == "effect" then
			table.insert(names, n)
		end
	end
	for _, n in names do
		self:_stopByName(n)
	end
end

function CameraAnimator:StopAllOffsets()
	local names: { string } = {}
	for n, active in self._activeAnims do
		if active.layer == "offset" then
			table.insert(names, n)
		end
	end
	for _, n in names do
		self:_stopByName(n)
	end
end

function CameraAnimator:StopAllOverrides()
	if self._currentOverride then
		self:_stopByName(self._currentOverride)
	end
end

-- ─── 내부 ────────────────────────────────────────────────────────────────────

function CameraAnimator:_stopByName(name: string)
	local active = self._activeAnims[name]
	if not active then
		return
	end

	if active.durationThread then
		task.cancel(active.durationThread)
	end

	local modKey = self._owner .. "_" .. name

	if active.layer == "effect" then
		self._controller:RemoveEffectModifier(modKey)
	elseif active.layer == "offset" then
		self._controller:RemoveOffsetModifier(modKey)
	elseif active.layer == "override" then
		self._controller:ClearOverride()
		self._currentOverride = nil
	end

	self._activeAnims[name] = nil
end

-- ─── 정리 ────────────────────────────────────────────────────────────────────

function CameraAnimator:Destroy()
	self:Stop()
	BaseObject.Destroy(self)
end

return CameraAnimator
