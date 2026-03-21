--!strict
--[=[
	@class Tank_JumpPunchServer

	탱크 점프 펀치 서버 모듈.

	onFire:
	  1. findActualLanding으로 착지점 계산 (벽 보정)
	  2. EntityPlayerServer.PlayHRP → 공격자 클라이언트에서 로컬 arc 점프
	  3. JUMP_DELAY 후 actualLanding에서 ProjectileHit.verdict() 발동

	onHitChecked:
	  ① damage 35
	  ② stun 2.0s (force=true)
	  ③ findActualLanding으로 날리기 착지점 계산
	  ④ EntityPlayerServer.PlayHRP → 피격자 클라이언트에서 로컬 arc 날리기
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local workspace = game:GetService("Workspace")

local EntityPlayerServer = require("EntityPlayerServer")
local EntityUtils = require("EntityUtils")
local PlayerStateUtils = require("PlayerStateUtils")
local ProjectileHit = require("ProjectileHit")
local cancellableDelay = require("cancellableDelay")

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local JUMP_DISTANCE = 15
local JUMP_HEIGHT = 6
local JUMP_SPEED = 28
local JUMP_DELAY = JUMP_DISTANCE / JUMP_SPEED -- ≈ 0.54s

local FIST_SPEED = 35
local FIST_DISTANCE = 6
local FIST_HEIGHT = 0.5
local FIST_BOX_SIZE = Vector3.new(4.5, 4.5, 4.5)

local DAMAGE = 35
local STUN_DURATION = 2.0

local THROW_DISTANCE = 22
local THROW_HEIGHT = 10
local THROW_SPEED = 28

local JUMP_TOLERANCE = 9
local THROW_TOLERANCE = 12

local MAX_EXTRA_DISTANCE = 5
local HEIGHT_RATIO = JUMP_HEIGHT / JUMP_DISTANCE -- 0.4

-- ─── 착지점 계산 ─────────────────────────────────────────────────────────────
--[=[
	origin 기준 dir 방향으로 distance만큼 이동할 때 실제 착지점을 계산합니다.

	흐름:
	  1. 순방향 Ray: 벽 감지
	     안 맞음 → 그냥 expectedLanding
	     맞음    →
	  2. 역방향 Ray: probe(distance + MAX_EXTRA)에서 뒤로 쏴서 벽 뒷면 위치 파악
	     wallBackDist > distance → 벽 너머 공간 있음 → 점프 거리 늘려서 착지
	     wallBackDist <= distance → 두꺼운 벽 or 코앞 → 벽 앞 최대한 가까이 착지
]=]
local function findActualLanding(originPos: Vector3, dir: Vector3, distance: number, excludeModel: Model): Vector3
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { excludeModel }

	local forwardRay = workspace:Raycast(originPos, dir * distance, rayParams)
	if not forwardRay then
		return originPos + dir * distance
	end

	local frontDist = forwardRay.Distance
	local probePos = originPos + dir * (distance + MAX_EXTRA_DISTANCE)
	local backwardRay = workspace:Raycast(probePos, -dir * (distance + MAX_EXTRA_DISTANCE), rayParams)

	local wallBackDist: number
	if backwardRay then
		wallBackDist = (distance + MAX_EXTRA_DISTANCE) - backwardRay.Distance
	else
		-- probe가 이미 공간 안에 있음
		wallBackDist = distance + MAX_EXTRA_DISTANCE
	end

	if wallBackDist > distance then
		-- 벽 너머 공간 있음 → 점프 거리 늘려서 착지
		return originPos + dir * (wallBackDist + 1)
	else
		-- 두꺼운 벽이거나 코앞 → 벽 앞 최대한 가까이 착지 (최소 1 stud)
		return originPos + dir * math.max(frontDist - 1.5, 1)
	end
end

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

			local originPos = hrp.Position

			-- 벽 보정된 실제 착지점 계산
			local actualLanding = findActualLanding(originPos, dir, JUMP_DISTANCE, attacker)
			local actualJumpDist = (actualLanding - originPos).Magnitude
			local actualJumpHeight = actualJumpDist * HEIGHT_RATIO

			-- 공격자 클라이언트에서 로컬 arc 점프
			EntityPlayerServer.PlayHRP(attackerPlayer, "Tank_JumpPunchEntityDef", "PlayerJump", {
				origin = CFrame.new(originPos, originPos + dir),
				params = { actualDistance = actualJumpDist, actualHeight = actualJumpHeight },
				duration = actualJumpDist / JUMP_SPEED + 0.5,
				expectedLanding = actualLanding,
				tolerance = JUMP_TOLERANCE,
			})

			-- JUMP_DELAY 후 actualLanding에서 펀치 히트박스 발사
			local capturedDir = dir
			local onHitResult = state.onHitResult
			local onMissResult = state.onMissResult
			local teamService = state.teamService
			local fireMaid = state.fireMaid

			local cancelFn = cancellableDelay(JUMP_DELAY, function()
				local origin2 = CFrame.new(actualLanding, actualLanding + capturedDir)

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
					params = nil,
					latency = 0,
				}, nil, teamService, attackerPlayer)
			end)

			if fireMaid then
				fireMaid:GiveTask(cancelFn)
			end
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

				-- ③ 피격자 날리기 착지점 계산
				local victimPos = victimHRP.Position
				local actualThrowLanding = findActualLanding(victimPos, throwDir, THROW_DISTANCE, victimModel)
				local actualThrowDist = (actualThrowLanding - victimPos).Magnitude
				local actualThrowHeight = actualThrowDist * HEIGHT_RATIO

				-- ④ 피격자 클라이언트에서 로컬 arc 날리기
				EntityPlayerServer.PlayHRP(victimPlayer, "Tank_JumpPunchEntityDef", "PlayerThrow", {
					origin = CFrame.new(victimPos, victimPos + throwDir),
					params = { actualDistance = actualThrowDist, actualHeight = actualThrowHeight },
					duration = actualThrowDist / THROW_SPEED + 0.5,
					expectedLanding = actualThrowLanding,
					tolerance = THROW_TOLERANCE,
				})
			end
		end,
	},

	onMissChecked = {},
}
