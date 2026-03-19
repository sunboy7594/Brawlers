--!strict
--[=[
	@class Tank_CannonClient

	탱크 캐논 기본공격 클라이언트 모듈.

	투사체 시스템 테스트:
	- onFire: projectileId 생성 → RegisterProjectile 서버 전송 → Heartbeat 충돌 감지 루프
	- 충돌 감지 시: ProjectileHit 서버 전송
	- fireMaid 캔슬 연동 (고정 루프 자동 실행)

	비주얼 (3D 모델):
	  TODO: AbilityEffect를 스테이트에 주입하여 파트 소환 추가 예정.
	  현재는 충돌 감지 로직만 있음.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ProjectileHitRemoting = require("ProjectileHitRemoting")

-- ─── 투사체 설정 ───────────────────────────────────────────────────────────────

local PROJECTILE_SPEED = 40   -- 스터드/초
local HIT_RADIUS       = 2.5  -- 충돌 감지 반경 (스터드)
local MAX_RANGE        = 100  -- 최대 사거리 (스터드)

-- ─── 상태 타입 ───────────────────────────────────────────────────────────────

type BasicAttackState = {
	origin    : Vector3,
	direction : Vector3,
	fireMaid  : any?,
	indicator : any,
	animator  : any?,
}

-- ─── 모듈 정의 ───────────────────────────────────────────────────────────────

return {
	shapes = {},

	onAimStart = {},
	onAim = {},

	onFire = {
		function(state: BasicAttackState)
			local localPlayer = Players.LocalPlayer
			local localChar = localPlayer.Character

			-- 고유 투사체 ID 생성 (UserId + 시각)
			local projectileId = tostring(localPlayer.UserId)
				.. "_"
				.. string.format("%.6f", os.clock())

			-- 서버에 투사체 등록
			-- (서버 onFire는 이미 setPendingOnHit을 호출한 상태)
			ProjectileHitRemoting.RegisterProjectile:FireServer(projectileId, {
				origin    = state.origin,
				direction = state.direction,
				speed     = PROJECTILE_SPEED,
				hitRadius = HIT_RADIUS,
				maxRange  = MAX_RANGE,
			})

			-- 충돌 감지용 OverlapParams (자신 캐릭터 제외)
			local overlapParams = OverlapParams.new()
			overlapParams.FilterType = Enum.RaycastFilterType.Exclude
			if localChar then
				overlapParams.FilterDescendantsInstances = { localChar }
			end

			-- 투사체 시뮬레이션 루프
			local elapsed = 0
			local done = false
			local origin = state.origin
			local direction = state.direction

			local conn: RBXScriptConnection
			conn = RunService.Heartbeat:Connect(function(dt: number)
				if done then
					conn:Disconnect()
					return
				end

				elapsed += dt
				local dist = PROJECTILE_SPEED * elapsed

				-- 사거리 초과
				if dist >= MAX_RANGE then
					done = true
					conn:Disconnect()
					return
				end

				local currentPos = origin + direction * dist

				-- 충돌 감지
				local parts = workspace:GetPartBoundsInRadius(currentPos, HIT_RADIUS, overlapParams)
				for _, part in parts do
					local char = part:FindFirstAncestorOfClass("Model")
					if not char then continue end
					local humanoid = char:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Health > 0 then
						done = true
						conn:Disconnect()
						-- 서버에 히트 보고
						ProjectileHitRemoting.ProjectileHit:FireServer(projectileId, currentPos)
						return
					end
				end
			end)

			-- fireMaid 캔슬 연동
			if state.fireMaid then
				state.fireMaid:GiveTask(function()
					done = true
					conn:Disconnect()
				end)
			end
		end,
	},

	onCancel = {},
	onHitChecked = {},
}
