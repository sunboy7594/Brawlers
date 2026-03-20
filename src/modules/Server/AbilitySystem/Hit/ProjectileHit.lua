--!strict
--[=[
	@class ProjectileHit

	투사체 판정 유틸리티. 서버 전용.
	InstantHit.applyMap()과 동일한 호출 패턴.

	fire():
	  origin에서 projectileDef.move()로 매 프레임 이동.
	  projectileDef.hitDetect()로 박스 판정.
	  히트 시 onHit(HitMapResult) 호출. (InstantHit.HitMapResult와 동일 타입)
	  fireMaid 파괴 시 투사체 자동 취소.

	latency 보정 (SimB):
	  latency > 0이면 fire() 호출 시 즉시 fast-forward 실행.
	  10 step으로 나눠 move → hitDetect 순서로 시뮬.
	  fast-forward 중 히트 시 즉시 onHit 호출, Heartbeat 등록 생략.

	내부 Heartbeat:
	  활성 투사체가 있을 때만 Heartbeat 연결.
	  모든 투사체 소진 시 자동 해제.

	사용 예 (서버 모듈 onFire):
	  local origin = CFrame.new(hrp.Position, hrp.Position + state.direction)
	  ProjectileHit.fire(
	      state.attacker, origin,
	      {
	          move      = AbilityEffectMover.Linear({ speed=40, maxRange=100, mode="linear" }),
	          hitDetect = AbilityEffectHitDetectionUtil.Box({ size=Vector3.new(4,4,4) }),
	          latency   = state.latency,
	      },
	      state.onHit, state.fireMaid, state.teamService, state.attackerPlayer
	  )
]=]

local require = require(script.Parent.loader).load(script)

local RunService = game:GetService("RunService")

local AbilityEffectHitDetectionUtil = require("AbilityEffectHitDetectionUtil")
local InstantHit = require("InstantHit")

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type ProjectileDef = {
	move: (dt: number, handle: any, params: { [string]: any }?) -> boolean,
	hitDetect: AbilityEffectHitDetectionUtil.HitDetectFunction,
	params: { [string]: any }?,
	latency: number,
}

type ActiveProjectile = {
	attacker: Model,
	def: ProjectileDef,
	onHit: ((InstantHit.HitMapResult) -> ())?,
	teamService: any?,
	attackerPlayer: Player?,
	elapsed: number,
	handleCF: CFrame,
	cancelled: boolean,
}

-- ─── 내부 상태 (모듈 싱글톤) ─────────────────────────────────────────────────

local _projectiles: { [string]: ActiveProjectile } = {}
local _counter: number = 0
local _heartbeat: RBXScriptConnection? = nil

-- ─── 내부 유틸 ───────────────────────────────────────────────────────────────

-- HitInfo[] → HitMapResult (InstantHit과 동일 타입으로 변환)
local function toHitMapResult(hits: { AbilityEffectHitDetectionUtil.HitInfo }): InstantHit.HitMapResult
	local vs: InstantHit.VictimSet = { enemies = {}, teammates = {}, self = nil }
	for _, hitInfo in hits do
		if hitInfo.relation == "enemy" then
			table.insert(vs.enemies, hitInfo.target)
		elseif hitInfo.relation == "team" then
			table.insert(vs.teammates, hitInfo.target)
		elseif hitInfo.relation == "self" then
			vs.self = hitInfo.target
		end
	end
	return { hit = vs }
end

-- 투사체의 현재 CFrame 기준 fake handle 생성
local function makeHandle(proj: ActiveProjectile, elapsedOverride: number?): any
	local ts = proj.teamService

	-- fakePart: GetPivot/PivotTo를 proj.handleCF에 연결하여
	-- move()가 PivotTo() 호출 시 proj.handleCF를 실시간 갱신.
	local fakePart = {
		_cf = proj.handleCF,
		GetPivot = function(self_: any): CFrame
			return self_._cf
		end,
		PivotTo = function(self_: any, cf: CFrame)
			self_._cf = cf
			proj.handleCF = cf
		end,
	}

	return {
		part = fakePart,
		_moveElapsed = elapsedOverride or proj.elapsed,
		_moveOrigin = proj.handleCF.Position,
		_moveDir = proj.handleCF.LookVector,
		_moveStopped = false,
		_fadingOut = false,
		_teamContext = {
			attackerChar = proj.attacker,
			attackerPlayer = proj.attackerPlayer,
			color = nil,
			isEnemy = function(a: Player, b: Player): boolean
				return if ts then ts:IsEnemy(a, b) else true
			end,
		},
	}
end

-- ─── Heartbeat 관리 ──────────────────────────────────────────────────────────

local function ensureHeartbeat()
	if _heartbeat then
		return
	end

	_heartbeat = RunService.Heartbeat:Connect(function(dt: number)
		local toRemove: { string } = {}

		for id, proj in _projectiles do
			if proj.cancelled then
				table.insert(toRemove, id)
				continue
			end

			proj.elapsed += dt
			local handle = makeHandle(proj)

			-- 이동
			local continues = proj.def.move(dt, handle, proj.def.params)

			-- 히트 판정
			local hits =
				AbilityEffectHitDetectionUtil.Detect(proj.def.hitDetect, handle._moveElapsed, handle, proj.def.params)

			if #hits > 0 then
				if proj.onHit then
					proj.onHit(toHitMapResult(hits))
				end
				table.insert(toRemove, id)
				continue
			end

			if not continues then
				table.insert(toRemove, id)
			end
		end

		for _, id in toRemove do
			_projectiles[id] = nil
		end

		-- 모든 투사체 소진 시 Heartbeat 해제
		if next(_projectiles) == nil then
			(_heartbeat :: RBXScriptConnection):Disconnect()
			_heartbeat = nil
		end
	end)
end

-- ─── SimB: latency fast-forward ──────────────────────────────────────────────

-- true 반환 시 fast-forward 중 이미 히트됨 → Heartbeat 등록 불필요
local function simB(proj: ActiveProjectile): boolean
	if proj.def.latency <= 0 then
		return false
	end

	local steps = 10
	local stepDt = proj.def.latency / steps

	for _ = 1, steps do
		local handle = makeHandle(proj)

		proj.def.move(stepDt, handle, proj.def.params)
		proj.elapsed += stepDt

		local hits = AbilityEffectHitDetectionUtil.Detect(proj.def.hitDetect, proj.elapsed, handle, proj.def.params)

		if #hits > 0 then
			if proj.onHit then
				proj.onHit(toHitMapResult(hits))
			end
			return true
		end
	end

	return false
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

local ProjectileHit = {}

--[=[
	투사체 판정을 시작합니다.
	InstantHit.applyMap()과 동일한 호출 패턴.

	origin은 서버가 독립 계산한 값을 전달하세요.
	(ex. CFrame.new(hrp.Position, hrp.Position + state.direction))

	onHit 콜백: InstantHit.HitMapResult
	  → { hit = VictimSet } 구조.
	  → VictimSet.enemies / .teammates / .self

	fireMaid:
	  파괴 시 투사체 즉시 취소.
	  InstantHit.applyMap의 fireMaid와 동일한 역할.

	@param attacker       Model
	@param origin         CFrame    서버 독립 계산값
	@param projectileDef  ProjectileDef
	@param onHit          ((InstantHit.HitMapResult) -> ())?
	@param fireMaid       any?
	@param teamService    any?
	@param attackerPlayer Player?
]=]
function ProjectileHit.fire(
	attacker: Model,
	origin: CFrame,
	projectileDef: ProjectileDef,
	onHit: ((InstantHit.HitMapResult) -> ())?,
	fireMaid: any?,
	teamService: any?,
	attackerPlayer: Player?
): ()
	local proj: ActiveProjectile = {
		attacker = attacker,
		def = projectileDef,
		onHit = onHit,
		teamService = teamService,
		attackerPlayer = attackerPlayer,
		elapsed = 0,
		handleCF = origin,
		cancelled = false,
	}

	-- latency fast-forward: 이미 히트됐으면 등록 생략
	if simB(proj) then
		return
	end

	-- Heartbeat 등록
	_counter += 1
	local id = tostring(_counter)
	_projectiles[id] = proj

	-- fireMaid에 취소 등록
	if fireMaid then
		fireMaid:GiveTask(function()
			proj.cancelled = true
		end)
	end

	ensureHeartbeat()
end

return ProjectileHit
