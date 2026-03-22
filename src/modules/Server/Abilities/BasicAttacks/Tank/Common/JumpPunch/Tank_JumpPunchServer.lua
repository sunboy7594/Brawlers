--!strict
--[=[
	@class Tank_JumpPunchServer

	탱크 점프 펀치 서버 모듈.

	onFire:
	  HRPMoveRemoting.PlayMove로 공격자 클라이언트에게 PlayerJump 신호 전송.
	  클라이언트가 로컬에서 HRP를 PivotTo로 직접 이동 → 끊김 없음.
	  서버는 arc 시간(JUMP_DISTANCE/JUMP_SPEED)만큼 delay 후 착지 위치에서 fist 발사.

	onHitChecked:
	  ① damage 35
	  ② stun 2.0s
	  ③ HRPMoveRemoting.PlayMove로 피격자 클라이언트에게 PlayerThrow 신호 전송.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local EntityUtils = require("EntityUtils")
local HRPMoveRemoting = require("HRPMoveRemoting")
local PlayerStateUtils = require("PlayerStateUtils")
local ProjectileHit = require("ProjectileHit")

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local JUMP_DISTANCE = 15
local JUMP_HEIGHT = 6
local JUMP_SPEED = 28

local FIST_SPEED = 35
local FIST_DISTANCE = 6
local FIST_HEIGHT = 0.5
local FIST_BOX_SIZE = Vector3.new(4.5, 4.5, 4.5)

local DAMAGE = 35
local STUN_DURATION = 2.0

local THROW_DISTANCE = 22
local THROW_HEIGHT = 10
local THROW_SPEED = 28

local JUMP_DURATION = JUMP_DISTANCE / JUMP_SPEED -- ≈ 0.54s

-- ─── 타입 ────────────────────────────────────────────────────────────────────

type BasicAttackState = {
	attacker: Model?,
	rootPart: BasePart?,
	origin: Vector3,
	direction: Vector3,
	latency: number,
	fireMaid: any?,
	onHitResult: ((hitMap: any?, handle: any?, hitInfo: any?) -> ())?,
	onMissResult: ((hitMap: any?, handle: any?) -> ())?,
	teamService: any?,
	attackerPlayer: Player?,
	playerStateController: any?,
	victims: any?,
	hitMap: any?,
	handle: any?,
	hitInfo: any?,
}

-- ─── 모듈 ────────────────────────────────────────────────────────────────────

return {
	onFire = {
		function(state: BasicAttackState)
			if not state.attacker then
				return
			end

			local attackerPlayer = state.attackerPlayer or Players:GetPlayerFromCharacter(state.attacker)
			if not attackerPlayer then
				return
			end

			local hrp = state.rootPart
			if not hrp then
				return
			end

			local dir = Vector3.new(state.direction.X, 0, state.direction.Z)
			dir = if dir.Magnitude > 0.001 then dir.Unit else Vector3.new(0, 0, -1)

			local originCF = CFrame.new(hrp.Position, hrp.Position + dir)

			-- 클라이언트에서 로컬 HRP 이동
			HRPMoveRemoting.PlayMove:FireClient(attackerPlayer, "Tank_JumpPunchEntityDef", "PlayerJump", originCF)

			-- 착지 위치: 수학적으로 계산 (arc 수평 이동량)
			local landingPos = hrp.Position + dir * JUMP_DISTANCE

			local capturedDir = dir
			local onHitResult = state.onHitResult
			local onMissResult = state.onMissResult
			local teamService = state.teamService
			local fireMaid = state.fireMaid
			local attacker = state.attacker

			-- arc 완료 후 fist 발사
			local cancelled = false
			if fireMaid then
				fireMaid:GiveTask(function()
					cancelled = true
				end)
			end

			task.delay(JUMP_DURATION, function()
				if cancelled then
					return
				end
				if not attacker or not attacker.Parent then
					return
				end

				local origin2 = CFrame.new(landingPos, landingPos + capturedDir)

				ProjectileHit.verdict(attacker, origin2, {
					move = EntityUtils.Arc({
						distance = FIST_DISTANCE,
						height = FIST_HEIGHT,
						speed = FIST_SPEED,
					}),
					hitDetect = EntityUtils.Box({
						size = FIST_BOX_SIZE,
						relations = { "enemy" },
					}),
					onHitResult = onHitResult,
					onMissResult = onMissResult,
					onHit = EntityUtils.Sequence({
						EntityUtils.LockHit(),
						EntityUtils.Despawn({ delay = 0 }),
					}),
					onMiss = EntityUtils.Despawn({ delay = 0 }),
					latency = 0,
				}, fireMaid, teamService, attackerPlayer)
			end)
		end,
	},

	onHitChecked = {
		function(snapshot: BasicAttackState, _state: BasicAttackState)
			local victims = snapshot.victims
			if not victims or #victims.enemies == 0 then
				return
			end

			local psc = snapshot.playerStateController
			if not psc then
				return
			end

			local attackerPlayer = Players:GetPlayerFromCharacter(snapshot.attacker)

			local dir = snapshot.direction
			local flatOpp = Vector3.new(-dir.X, 0, -dir.Z)
			local throwDir: Vector3 = if flatOpp.Magnitude > 0.001 then flatOpp.Unit else Vector3.new(0, 0, 1)

			for _, victimModel in victims.enemies do
				local victimPlayer = Players:GetPlayerFromCharacter(victimModel)
				if not victimPlayer then
					continue
				end

				local victimHRP = victimModel:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not victimHRP then
					continue
				end

				-- ① 데미지
				PlayerStateUtils.PlayPlayerState(psc, victimPlayer, "damage", {
					amount = DAMAGE,
					source = attackerPlayer,
					intensity = 0.9,
					duration = 0.2,
				})

				-- ② 스턴
				PlayerStateUtils.PlayPlayerState(psc, victimPlayer, "stun", {
					duration = STUN_DURATION,
					source = attackerPlayer,
					intensity = 1.0,
					force = true,
				})

				-- ③ 피격자 클라이언트에서 로컬 HRP 날리기
				local throwOrigin = CFrame.new(victimHRP.Position, victimHRP.Position + throwDir)
				HRPMoveRemoting.PlayMove:FireClient(victimPlayer, "Tank_JumpPunchEntityDef", "PlayerThrow", throwOrigin)
			end
		end,
	},

	onMissChecked = {},
}
