--!strict
--[=[
	@class Tank_JumpPunchServer

	탱크 점프 펀치 서버 모듈.

	onFire:
	  EntityPlayerServer.PlayDirect로 공격자 HRP를 서버에서 직접 arc 이동.
	  EntityUtils.Arc가 HRP 감지 → SetNetworkOwner(nil) + PlatformStand + 벽 보정 + PivotTo + velocity 보간.
	  arc 완료(onMiss) 시 착지점에서 ProjectileHit.verdict() 발동.

	onHitChecked:
	  ① damage 35
	  ② stun 2.0s (force=true)
	  ③ EntityPlayerServer.PlayDirect로 피격자 HRP를 서버에서 직접 arc 날리기.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local EntityPlayerServer = require("EntityPlayerServer")
local EntityUtils = require("EntityUtils")
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
			local attacker = state.attacker

			local attackerPlayer = Players:GetPlayerFromCharacter(attacker)
			if not attackerPlayer then
				return
			end

			local hrp = attacker:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp then
				return
			end

			local dir = Vector3.new(state.direction.X, 0, state.direction.Z)
			dir = if dir.Magnitude > 0.001 then dir.Unit else Vector3.new(0, 0, -1)

			local capturedDir = dir
			local onHitResult = state.onHitResult
			local onMissResult = state.onMissResult
			local teamService = state.teamService
			local fireMaid = state.fireMaid

			-- 서버에서 HRP를 직접 arc 이동
			-- EntityUtils.Arc가 HRP 감지 → SetNetworkOwner(nil) + 벽 보정 + PivotTo + velocity 보간
			EntityPlayerServer.PlayDirect({
				part = hrp,
				origin = CFrame.new(hrp.Position, hrp.Position + dir),
				move = EntityUtils.Arc({
					distance = JUMP_DISTANCE,
					height = JUMP_HEIGHT,
					speed = JUMP_SPEED,
					rotate = false,
				}),
				onSpawn = EntityUtils.AnchorPart(), -- 서버에서는 스킵, 클라이언트 연출용
				onMiss = function(handle)
					-- arc 완료 = 착지. 현재 HRP 위치에서 fist 발사
					local landingPos = hrp.Position
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
				end,
				taskMaid = fireMaid,
			})
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

				-- ③ 피격자 HRP 서버 직접 arc 날리기
				EntityPlayerServer.PlayDirect({
					part = victimHRP,
					origin = CFrame.new(victimHRP.Position, victimHRP.Position + throwDir),
					move = EntityUtils.Arc({
						distance = THROW_DISTANCE,
						height = THROW_HEIGHT,
						speed = THROW_SPEED,
						rotate = false,
					}),
					onSpawn = EntityUtils.AnchorPart(), -- 서버에서는 스킵
				})
			end
		end,
	},

	onMissChecked = {},
}
