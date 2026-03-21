--!strict
--[=[
	@class Tank_JumpPunchServer

	탱크 점프 펀치 서버 모듈.

	onFire:
	  1. EntityPlayerServer.PlayHRP → 공격자 클라이언트에서 로컬 arc 점프
	     (토큰 발급 → FireClient → 착지 위치 검증)
	  2. JUMP_DELAY 후 착지 위치에서 ProjectileHit.verdict() 발동

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
local cancellableDelay   = require("cancellableDelay")

-- ─── 상수 (Tank_JumpPunchEntityDef와 동일하게 유지) ─────────────────────────

local JUMP_DISTANCE = 15
local JUMP_HEIGHT   = 6
local JUMP_SPEED    = 28
local JUMP_DELAY    = JUMP_DISTANCE / JUMP_SPEED   -- ≈ 0.54s

local FIST_SPEED    = 35
local FIST_DISTANCE = 4
local FIST_HEIGHT   = 0.8
local FIST_BOX_SIZE = Vector3.new(3.2, 3.2, 3.2)

local DAMAGE        = 35
local STUN_DURATION = 2.0

local THROW_DISTANCE = 22
local THROW_HEIGHT   = 10
local THROW_SPEED    = 28

-- 허용 오차: latency(최대 200ms) * 이동속도(28) + 여유(3) ≈ 9 스터드
local JUMP_TOLERANCE  = 9
local THROW_TOLERANCE = 12

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

			local originPos = hrp.Position

			-- Y 고정 게임: 수평만 계산
			local expectedLanding = Vector3.new(
				originPos.X + dir.X * JUMP_DISTANCE,
				originPos.Y,
				originPos.Z + dir.Z * JUMP_DISTANCE
			)

			-- 공격자 클라이언트에서 로컬 arc 점프 실행
			EntityPlayerServer.PlayHRP(
				attackerPlayer,
				"Tank_JumpPunchEntityDef",
				"PlayerJump",
				{
					origin          = CFrame.new(originPos, originPos + dir),
					params          = nil,
					duration        = JUMP_DELAY + 0.2,
					expectedLanding = expectedLanding,
					tolerance       = JUMP_TOLERANCE,
				}
			)

			-- JUMP_DELAY 후 착지 위치에서 펀치 히트박스 발사
			local capturedDir    = state.direction
			local onHitResult    = state.onHitResult
			local onMissResult   = state.onMissResult
			local teamService    = state.teamService
			local fireMaid       = state.fireMaid

			local cancelFn = cancellableDelay(JUMP_DELAY, function()
				local hrp2 = attacker:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not hrp2 then return end

				local origin2 = CFrame.new(hrp2.Position, hrp2.Position + capturedDir)

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
			end)

			if fireMaid then
				fireMaid:GiveTask(cancelFn)
			end
		end,
	},

	onHitChecked = {
		function(snapshot: BasicAttackState, _state: BasicAttackState)
			local victims = snapshot.victims
			if not victims or #victims.enemies == 0 then return end

			local psc = snapshot.playerStateController
			if not psc then return end

			local attackerPlayer = Players:GetPlayerFromCharacter(snapshot.attacker)

			-- 날리기 방향: 펀치 진행 방향 수평 반대
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
				local victimPos = victimHRP.Position
				local expectedThrowEnd = Vector3.new(
					victimPos.X + throwDir.X * THROW_DISTANCE,
					victimPos.Y,
					victimPos.Z + throwDir.Z * THROW_DISTANCE
				)

				EntityPlayerServer.PlayHRP(
					victimPlayer,
					"Tank_JumpPunchEntityDef",
					"PlayerThrow",
					{
						origin          = CFrame.new(victimPos, victimPos + throwDir),
						params          = nil,
						duration        = THROW_DISTANCE / THROW_SPEED + 0.3,
						expectedLanding = expectedThrowEnd,
						tolerance       = THROW_TOLERANCE,
					}
				)
			end
		end,
	},

	onMissChecked = {},
}
