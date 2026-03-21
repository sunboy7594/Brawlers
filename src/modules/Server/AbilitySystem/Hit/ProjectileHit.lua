--!strict
--[=[
	@class ProjectileHit

	투사체 판정 유틸리티. 서버 전용.
	EntityController를 래핑합니다.

	ProjectileDef 필드:
	  move         : 이동 함수 (EntityUtils.Linear 등)
	  hitDetect    : 판정 함수
	  onHitResult  : ((hitMap?, handle?, hitInfo?) -> ())?  → state.onHitResult (onHitChecked 트리거)
	  onMissResult : ((hitMap?, handle?) -> ())?            → state.onMissResult (onMissChecked 트리거)
	  onHit        : ((handle, hitInfo) -> ())?             → handle 정리 콜백 (EntityUtils.Despawn 등)
	  onMiss       : ((handle) -> ())?                      → handle 정리 콜백
	  latency      : 레이턴시 보정값
	  delay        : 발사 지연

	delay + latency 보정:
	  effectiveDelay = max(0, delay - latency)  → cancellableDelay로 발사 지연
	  forwardTime    = max(0, latency - delay)  → firedAt = now - forwardTime으로 EntityController simB 활용

	teamContext:
	  attacker(Model) + attackerPlayer + teamService로 직접 빌드해 EntityController에 주입.
	  teamService가 nil이면 Roblox 기본 팀 시스템으로 폴백.
]=]

local require = require(script.Parent.loader).load(script)

local Workspace = game:GetService("Workspace")

local EntityController = require("EntityController")
local HitDetectionUtil = require("HitDetectionUtil")
local InstantHit       = require("InstantHit")
local cancellableDelay = require("cancellableDelay")

export type ProjectileDef = {
	move         : EntityController.MoveFunction,
	hitDetect    : HitDetectionUtil.HitDetectFunction,
	-- state.onHitResult 파이프라인 콜백 (onHitChecked / onMissChecked 트리거)
	onHitResult  : ((hitMap: InstantHit.HitMapResult?, handle: any?, hitInfo: HitDetectionUtil.HitInfo?) -> ())?,
	onMissResult : ((hitMap: InstantHit.HitMapResult?, handle: any?) -> ())?,
	-- handle 정리 콜백 (EntityUtils.Despawn 등)
	onHit        : ((handle: any, hitInfo: HitDetectionUtil.HitInfo) -> ())?,
	onMiss       : ((handle: any) -> ())?,
	params       : { [string]: any }?,
	latency      : number,
	delay        : number?,
}

local ProjectileHit = {}

--[=[
	투사체 판정을 시작합니다.

	@param attacker       Model
	@param origin         CFrame    서버 독립 계산값
	@param def            ProjectileDef
	@param fireMaid       any?      effectiveDelay 취소용
	@param teamService    any?
	@param attackerPlayer Player?
	@return EntityController handle (즉시 발사 시) | nil (delay 중)
]=]
function ProjectileHit.verdict(
	attacker       : Model,
	origin         : CFrame,
	def            : ProjectileDef,
	fireMaid       : any?,
	teamService    : any?,
	attackerPlayer : Player?
): any?
	local latency = def.latency
	local delay   = def.delay or 0

	local effectiveDelay = math.max(0, delay - latency)
	local forwardTime    = math.max(0, latency - delay)

	local function launch(): any?
		-- teamContext 직접 빌드 (서버 teamService 사용, 없으면 Roblox 팀 폴백)
		local teamContext: EntityController.TeamContext = {
			attackerChar   = attacker,
			attackerPlayer = attackerPlayer,
			isEnemy        = function(a: Player, b: Player): boolean
				if teamService then
					return teamService:IsEnemy(a, b)
				end
				if a.Neutral or b.Neutral then return true end
				return a.Team == nil or a.Team ~= b.Team
			end,
		}

		local handle = EntityController.new({}, {
			origin           = origin,
			move             = def.move,
			hitDetect        = def.hitDetect,
			params           = def.params,
			teamContext      = teamContext,
			attackerPlayerId = attackerPlayer and attackerPlayer.UserId,
			-- forwardTime만큼 과거 시점으로 firedAt 설정 → EntityController simB가 알아서 fast-forward
			firedAt          = Workspace:GetServerTimeNow() - forwardTime,
			onHit            = function(h: any, hitInfo: HitDetectionUtil.HitInfo)
				-- 파이프라인 콜백 먼저 (onHitChecked 트리거)
				if def.onHitResult then
					def.onHitResult(nil, h, hitInfo)
				end
				-- 그 다음 handle 정리 (Despawn 등)
				if def.onHit then
					def.onHit(h, hitInfo)
				end
			end,
			onMiss           = function(h: any)
				-- 파이프라인 콜백 먼저 (onMissChecked 트리거)
				if def.onMissResult then
					def.onMissResult(nil, h)
				end
				-- 그 다음 handle 정리
				if def.onMiss then
					def.onMiss(h)
				end
			end,
		})

		return handle
	end

	if effectiveDelay > 0 then
		local cancel = cancellableDelay(effectiveDelay, function() launch() end)
		if fireMaid then fireMaid:GiveTask(cancel) end
		return nil
	end

	return launch()
end

return ProjectileHit
