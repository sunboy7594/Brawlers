--!strict
--[=[
	@class Tank_JumpPunchServer

	탱크 점프 펜치 서버 모듈.

	onFire:
	  TODO: 서버 직접 HRP 이동 (PivotTo + velocity 보간) 구현 예정
	  구현 전까지 이동 없이 트주에서 주먹으로 판정만 실행

	onHitChecked:
	  ① damage 35
	  ② stun 2.0s (force=true)
	  TODO: 직접 HRP 이동으로 피격자 날리기 구현 예정
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local EntityUtils      = require("EntityUtils")
local PlayerStateUtils = require("PlayerStateUtils")
local ProjectileHit    = require("ProjectileHit")

-- ─── 상수 ──────────────────────────────────────────────────────────────────

local FIST_SPEED    = 35
local FIST_DISTANCE = 6
local FIST_HEIGHT   = 0.5
local FIST_BOX_SIZE = Vector3.new(4.5, 4.5, 4.5)

local DAMAGE        = 35
local STUN_DURATION = 2.0

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

			local onHitResult  = state.onHitResult
			local onMissResult = state.onMissResult
			local teamService  = state.teamService

			-- TODO: 서버 직접 HRP arc 이동 구현 예정 (PivotTo + velocity 보간)
			-- 임시: 현재 위치에서 직접 fist 발사
			local origin = CFrame.new(hrp.Position, hrp.Position + dir)
			ProjectileHit.verdict(
				attacker,
				origin,
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
					latency  = state.latency,
				},
				state.fireMaid,
				teamService,
				attackerPlayer
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

			for _, victimModel in victims.enemies do
				local victimPlayer = Players:GetPlayerFromCharacter(victimModel)
				if not victimPlayer then continue end

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

				-- TODO: 서버 직접 HRP arc 이동으로 피격자 날리기 구현 예정
			end
		end,
	},

	onMissChecked = {},
}
