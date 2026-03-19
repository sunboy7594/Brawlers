--!strict
--[=[
	@class AbilityEffectHandle

	AbilityEffect:Play()가 반환하는 핸들 클래스.
	이펙트 생명주기, 히트/미스 콜백, 상태를 관리합니다.

	필드:
	  isOwner          : boolean      -- 로컬 플레이어가 발사한 이펙트인지
	  part             : Model?        -- 소환된 3D 모델 (없으면 nil)
	  firedAt          : number        -- os.clock() 기준 발사 시각 (fast-forward 계산용)
	  state            : EffectState   -- 공유 상태 테이블
	    .hitTargets    : { Model }     -- 맞춘 캐릭터 목록 (중복 없음, 벽 제외)

	공개 API:
	  :Hit(result)     -- onHit 콜백 실행, hitTargets에 추가
	  :Miss()          -- onMiss 콜백 실행 후 Destroy
	  :IsAlive()       -- 살아있는지 여부
	  :Destroy()       -- 즉시 정리 (part 제거, fireMaid 캔슬 연동)
]=]

local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")

-- ─── 타입 ────────────────────────────────────────────────────────────────────

--[=[
	충돌 결과 타입.
	target   : 맞은 캐릭터 Model 또는 벽 BasePart
	relation : 공격자와의 관계
]=]
export type HitResult = {
	target   : Instance,
	relation : "enemy" | "teammate" | "self" | "wall",
}

type EffectState = {
	hitTargets : { Model },
}

export type AbilityEffectHandle = typeof(setmetatable(
	{} :: {
		isOwner  : boolean,
		part     : Model?,
		firedAt  : number,
		state    : EffectState,
		_alive   : boolean,
		_maid    : any,
		_onHit   : ((result: HitResult, handle: any) -> ())?,
		_onMiss  : ((handle: any) -> ())?,
	},
	{} :: typeof({ __index = {} })
))

-- ─── 클래스 ──────────────────────────────────────────────────────────────────

local AbilityEffectHandle = {}
AbilityEffectHandle.__index = AbilityEffectHandle

function AbilityEffectHandle.new(
	isOwner  : boolean,
	part     : Model?,
	onHit    : ((result: HitResult, handle: any) -> ())?,
	onMiss   : ((handle: any) -> ())?
): AbilityEffectHandle
	local self = setmetatable({}, AbilityEffectHandle)
	self.isOwner = isOwner
	self.part    = part
	self.firedAt = os.clock()
	self.state   = {
		hitTargets = {} :: { Model },
	}
	self._alive  = true
	self._maid   = Maid.new()
	self._onHit  = onHit
	self._onMiss = onMiss

	-- part가 있으면 Destroy 시 자동 제거
	if part then
		self._maid:GiveTask(part)
	end

	return self
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	충돌 처리. onHit 콜백 실행 + hitTargets 추가.
	relation == "wall"이면 hitTargets에 추가하지 않음.
	@param result HitResult
]=]
function AbilityEffectHandle:Hit(result: HitResult)
	if not self._alive then
		return
	end

	-- 캐릭터 히트만 hitTargets 추적 (벽 제외)
	if result.relation ~= "wall" then
		local target = result.target
		if typeof(target) == "Instance" and target:IsA("Model") then
			table.insert(self.state.hitTargets, target :: Model)
		end
	end

	if self._onHit then
		self._onHit(result, self)
	end
end

--[=[
	미스 처리. onMiss 콜백 실행 후 Destroy.
]=]
function AbilityEffectHandle:Miss()
	if not self._alive then
		return
	end
	if self._onMiss then
		self._onMiss(self)
	end
	self:Destroy()
end

--[=[
	@return boolean 이펙트가 아직 살아있는지
]=]
function AbilityEffectHandle:IsAlive(): boolean
	return self._alive
end

--[=[
	즉시 정리. part 제거, MoveFactory 루프 종료, fireMaid 연동 cleanup 실행.
]=]
function AbilityEffectHandle:Destroy()
	if not self._alive then
		return
	end
	self._alive = false
	self._maid:Destroy()
end

return AbilityEffectHandle
