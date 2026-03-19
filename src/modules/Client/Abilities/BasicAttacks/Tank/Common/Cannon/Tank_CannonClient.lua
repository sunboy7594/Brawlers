--!strict
--[=[
	@class Tank_CannonClient

	탱크 캐논 기본공격 클라이언트 모듈.

	투사체 흐름:
	- onFire:
	    1. projectileId 생성
	    2. AbilityEffect:Play() → 모델 소환 (state.abilityEffect 주입 시)
	    3. RegisterProjectile 서버 전송
	    4. Heartbeat 루프: 매 프레임 모델 이동 + 충돌 감지
	    5. 충돌 시: handle:Hit() + ProjectileHit:FireServer
	       만료 시: handle:Miss()
	- fireMaid 캔슬 연동

	state.abilityEffect 주입:
	  BasicAttackClient에서 AbilityEffect.new(worldFX)를 만들어
	  state.abilityEffect에 넣으면 자동으로 활성화됩니다.
	  (TODO: BasicAttackClient 수정 필요)
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ProjectileHitRemoting = require("ProjectileHitRemoting")

-- ─── 투사체 설정 ──────────────────────────────────────────────────────────────

local PROJECTILE_SPEED = 40 -- 스터드/초
local HIT_RADIUS = 2.5 -- 충돌 감지 반경 (스터드)
local MAX_RANGE = 100 -- 최대 사거리 (스터드)
local EFFECT_DEF_MODULE = "Tank_CannonEffectDef"
local EFFECT_NAME = "CannonBall"

-- ─── 상태 타입 ────────────────────────────────────────────────────────────────

type BasicAttackState = {
	origin: Vector3,
	direction: Vector3,
	fireMaid: any?,
	indicator: any,
	animator: any?,
	abilityEffect: any?, -- AbilityEffect 인스턴스 (BasicAttackClient에서 주입 예정)
}

-- ─── 모듈 정의 ────────────────────────────────────────────────────────────────

return {
	shapes = {},

	onAimStart = {},
	onAim = {},

	onFire = {
		function(state: BasicAttackState)
			local localPlayer = Players.LocalPlayer
			local localChar = localPlayer.Character

			-- ─── 고유 투사체 ID 생성 ───────────────────────────────────────────
			local projectileId = tostring(localPlayer.UserId) .. "_" .. string.format("%.6f", os.clock())

			local origin = state.origin
			local direction = state.direction

			-- ─── AbilityEffect 소환 ────────────────────────────────────────────
			-- state.abilityEffect가 주입되어 있으면 3D 모델 소환
			-- 없으면 비주얼 없이 판정만 동작
			local handle: any? = nil
			if state.abilityEffect then
				handle =
					state.abilityEffect:Play(EFFECT_DEF_MODULE, EFFECT_NAME, CFrame.new(origin, origin + direction), {
						fireMaid = state.fireMaid,
						direction = direction,
					})
			end

			-- ─── 서버에 투사체 등록 ────────────────────────────────────────────
			-- (서버 Tank_CannonServer.onFire가 이미 setPendingOnHit을 호출한 상태)
			ProjectileHitRemoting.RegisterProjectile:FireServer(projectileId, {
				origin = origin,
				direction = direction,
				speed = PROJECTILE_SPEED,
				hitRadius = HIT_RADIUS,
				maxRange = MAX_RANGE,
			})

			-- ─── 충돌 감지용 OverlapParams ────────────────────────────────────
			local overlapParams = OverlapParams.new()
			overlapParams.FilterType = Enum.RaycastFilterType.Exclude
			if localChar then
				overlapParams.FilterDescendantsInstances = { localChar }
			end

			-- ─── 투사체 시뮬레이션 루프 ──────────────────────────────────────
			local elapsed = 0
			local done = false

			local conn: RBXScriptConnection
			conn = RunService.Heartbeat:Connect(function(dt: number)
				if done then
					conn:Disconnect()
					return
				end

				elapsed += dt
				local dist = PROJECTILE_SPEED * elapsed

				-- 사거리 초과 → 미스
				if dist >= MAX_RANGE then
					done = true
					conn:Disconnect()
					if handle and handle:IsAlive() then
						handle:Miss()
					end
					return
				end

				local currentPos = origin + direction * dist

				-- ─── 모델 위치 갱신 ──────────────────────────────────────────
				if handle and handle.part and handle:IsAlive() then
					handle.part:PivotTo(CFrame.new(currentPos, currentPos + direction))
				end

				-- ─── 충돌 감지 ───────────────────────────────────────────────
				local parts = workspace:GetPartBoundsInRadius(currentPos, HIT_RADIUS, overlapParams)
				for _, part in parts do
					local char = part:FindFirstAncestorOfClass("Model")
					if not char then
						continue
					end
					local humanoid = char:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Health > 0 then
						done = true
						conn:Disconnect()

						-- handle에 히트 알림 (onHit 콜백 실행)
						if handle and handle:IsAlive() then
							handle:Hit({
								target = char,
								relation = "enemy", -- 클라이언트는 대략 enemy로 처리
							})
						end

						-- 서버에 히트 보고 (서버가 실제 팀 판별 + 데미지 처리)
						ProjectileHitRemoting.ProjectileHit:FireServer(projectileId, currentPos)
						return
					end
				end
			end)

			-- ─── fireMaid 캔슬 연동 ───────────────────────────────────────────
			-- CancelCombatState() → fireMaid:Destroy() → 루프 자동 중단
			if state.fireMaid then
				state.fireMaid:GiveTask(function()
					done = true
					conn:Disconnect()
					-- handle은 fireMaid에 이미 등록되어 자동 Destroy됨
				end)
			end
		end,
	},

	onCancel = {},
	onHitChecked = {},
}
