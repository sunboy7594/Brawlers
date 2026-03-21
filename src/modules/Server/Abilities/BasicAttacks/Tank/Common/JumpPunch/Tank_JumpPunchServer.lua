--!strict
--[=[
	@class Tank_JumpPunchServer

	탱크 점프 펀치 서버 모듈.

	onFire:
	  1. EntityPlayerServer.PlayHRP → 공격자 클라이언트에서 로컬 arc 점프
	     (클라이언트가 현재 위치 기준 findActualLanding 직접 계산)
	  2. LandingReport 수신 시 onLanded 콜백 → 착지점에서 ProjectileHit.verdict() 발동

	onHitChecked:
	  ① damage 35
	  ② stun 2.0s (force=true)
	  ③ EntityPlayerServer.PlayHRP → 피격자 클라이언트에서 로컬 arc 날리기
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local EntityPlayerServer = require("EntityPlayerServer")
local EntityUtils        = require("EntityUtils")
local PlayerStateUtils   = require("PlayerStateUtils")
local ProjectileHit      = require("ProjectileHit")

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local JUMP_DISTANCE = 15
local JUMP_HEIGHT   = 6
local JUMP_SPEED    = 28

local FIST_SPEED    = 35
local FIST_DISTANCE = 6
local FIST_HEIGHT   = 0.5
local FIST_BOX_SIZE = Vector3.new(4.5, 4.5, 4.5)

local DAMAGE        = 35
local STUN_DURATION = 2.0

local THROW_DISTANCE = 22
local THROW_HEIGHT   = 10
local THROW_SPEED    = 28

local MAX_EXTRA_DISTANCE = 5  -- 클라이언트와 동일 (검증 범위 계산용)

local JUMP_TOLERANCE  = 9
local THROW_TOLERANCE = 12

-- fallback 타이머: 클라이언트가 최대한 멀리 이동한 시간 + 여유
local JUMP_DURATION  = (JUMP_DISTANCE + MAX_EXTRA_DISTANCE + 1) / JUMP_SPEED + 0.5
local THROW_DURATION = (THROW_DISTANCE + MAX_EXTRA_DISTANCE + 1) / THROW_SPEED + 0.5

-- ─── 타입 ────────────────────────────────────────────────────────────────────

type BasicAttackState = {
	attacker             : Model?,
	rootPart             : BasePart?,
	origin               : Vector3,
	direction            : Vector3,
	latency              : number,
	fireMaid             : any?,
	onHitResult          : ((hitMap: any?, handle: any?, hitInfo: any?) -> ())?,
	onMissResult         : ((hitMap: any?, handle: any?) -> ())?,
	teamService          : any?,
	attackerPlayer       : Player?,
	playerStateController: any?,
	victims              : any?,
	hitMap               : any?,
	handle               : any?,
	hitInfo              : any?,
}

-- ─── 모듈 ────────────────────────────────────────────────────────────────────

return {
	onFire = {
		function(state: BasicAttackState)
			if not state.attacker then return end
			local attacker = state.attacker

			local attackerPlayer = Players:GetPlayerFromCharacter(attacker)
			if not attackerPlayer then return end

			local hrp = attacker:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp then return end

			local dir = Vector3.new(state.direction.X, 0, state.direction.Z)
			dir = if dir.Magnitude > 0.001 then dir.Unit else Vector3.new(0, 0, -1)

			local originPos      = hrp.Position
			local capturedDir    = dir
			local onHitResult    = state.onHitResult
			local onMissResult   = state.onMissResult
			local teamService    = state.teamService
			local fireMaid       = state.fireMaid

			-- 클라이언트가 현재 위치 기준으로 findActualLanding 직접 계산
			-- 서버는 direction/speed/distance/height만 전달
			-- LandingReport 수신 시 onLanded 콜백에서 fist 발사
			EntityPlayerServer.PlayHRP(
				attackerPlayer,
				"Tank_JumpPunchEntityDef",
				"PlayerJump",
				{
					direction      = dir,
					speed          = JUMP_SPEED,
					distance       = JUMP_DISTANCE,
					height         = JUMP_HEIGHT,
					originPos      = originPos,
					duration       = JUMP_DURATION,
					maxAllowedDist = JUMP_DISTANCE + MAX_EXTRA_DISTANCE + JUMP_TOLERANCE,
					tolerance      = JUMP_TOLERANCE,
					fireMaid       = fireMaid,
					params         = nil,
					onLanded       = function(actualLandingPos: Vector3)
						-- 착지 확인 후 fist 히트박스 발사
						local origin2 = CFrame.new(actualLandingPos, actualLandingPos + capturedDir)

						ProjectileHit.verdict(
							attacker,
							origin2,
							{
								move = EntityUtils.Arc({
									distance = FIST_DISTANCE,
									height   = FIST_HEIGHT,
									speed    = FIST_SPEED,
								}),
								hitDetect = EntityUtils.Box({
									size      = FIST_BOX_SIZE,
									relations = { "enemy" },
								}),
								onHitResult  = onHitResult,
								onMissResult = onMissResult,
								onHit = EntityUtils.Sequence({
									EntityUtils.LockHit(),
									EntityUtils.Despawn({ delay = 0 }),
								}),
								onMiss   = EntityUtils.Despawn({ delay = 0 }),
								params   = nil,
								latency  = 0,
							},
							nil,
							teamService,
							attackerPlayer
						)
					end,
				}
			)
		end,
	},

	onHitChecked = {
		function(snapshot: BasicAttackState, _state: BasicAttackState)
			local victims = snapshot.victims
			if not victims or #victims.enemies == 0 then return end

			local psc = snapshot.playerStateController
			if not psc then return end

			local attackerPlayer = Players:GetPlayerFromCharacter(snapshot.attacker)

			local dir     = snapshot.direction
			local flatOpp = Vector3.new(-dir.X, 0, -dir.Z)
			local throwDir: Vector3 = if flatOpp.Magnitude > 0.001
				then flatOpp.Unit
				else Vector3.new(0, 0, 1)

			for _, victimModel in victims.enemies do
				local victimPlayer = Players:GetPlayerFromCharacter(victimModel)
				if not victimPlayer then continue end

				local victimHRP = victimModel:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not victimHRP then continue end

				-- ① 데미지
				PlayerStateUtils.PlayPlayerState(psc, victimPlayer, "damage", {
					amount    = DAMAGE,
					source    = attackerPlayer,
					intensity = 0.9,
					duration  = 0.2,
				})

				-- ② 스턴
				PlayerStateUtils.PlayPlayerState(psc, victimPlayer, "stun", {
					duration  = STUN_DURATION,
					source    = attackerPlayer,
					intensity = 1.0,
					force     = true,
				})

				-- ③ 피격자 클라이언트에서 로컬 arc 날리기
				-- 클라이언트가 현재 위치 기준 findActualLanding 직접 계산
				local victimPos = victimHRP.Position
				EntityPlayerServer.PlayHRP(
					victimPlayer,
					"Tank_JumpPunchEntityDef",
					"PlayerThrow",
					{
						direction      = throwDir,
						speed          = THROW_SPEED,
						distance       = THROW_DISTANCE,
						height         = THROW_HEIGHT,
						originPos      = victimPos,
						duration       = THROW_DURATION,
						maxAllowedDist = THROW_DISTANCE + MAX_EXTRA_DISTANCE + THROW_TOLERANCE,
						tolerance      = THROW_TOLERANCE,
						params         = nil,
						onLanded       = nil,
					}
				)
			end
		end,
	},

	onMissChecked = {},
}
