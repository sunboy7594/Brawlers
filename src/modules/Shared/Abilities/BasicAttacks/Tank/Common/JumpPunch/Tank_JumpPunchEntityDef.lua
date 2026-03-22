--!strict
--[=[
	@class Tank_JumpPunchEntityDef

	탱크 점프 펀치 엔티티 정의. (Shared)

	"PunchFist":
	  착지 직후 전방으로 짧은 arc를 그리며 날아가는 히트박스 엔티티.
	  서버(ProjectileHit)와 클라이언트(EntityPlayer) 양쪽에서 사용.

	"PlayerJump":
	  공격자 HRP arc 점프용 def. model = nil (HRP 자체를 part로 사용).
	  HRPMoveClient가 수신 후 로컬에서 EntityPlayer.PlayDirect로 실행.

	"PlayerThrow":
	  피격자 HRP arc 날리기용 def. model = nil.
	  HRPMoveClient가 수신 후 로컬에서 실행.
]=]

local require = require(script.Parent.loader).load(script)

local EntityColorUtils = require("EntityColorUtils")
local EntityUtils = require("EntityUtils")

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local FIST_SPEED = 35
local FIST_DISTANCE = 4
local FIST_HEIGHT = 0.8

local JUMP_DISTANCE = 15
local JUMP_HEIGHT = 6
local JUMP_SPEED = 28
local JUMP_DURATION = JUMP_DISTANCE / JUMP_SPEED -- ≈ 0.54s

local THROW_DISTANCE = 22
local THROW_HEIGHT = 10
local THROW_SPEED = 28
local THROW_DURATION = THROW_DISTANCE / THROW_SPEED -- ≈ 0.79s

local HEIGHT_RATIO = JUMP_HEIGHT / JUMP_DISTANCE -- 0.4 (거리 대비 높이 비율)

-- ─── 착지 onHit ──────────────────────────────────────────────────────────────
-- HitRole == "Floor"인 obstacle에 닿았을 때만 Despawn.
-- Wall/Shield 등 다른 obstacle은 무시하여 통과.
-- (Floor hitDetect는 HRPMoveClient에서 주입)
local _despawn = EntityUtils.Despawn({ delay = 0 })
local function onFloorHit(handle: any, hitInfo: any)
	local target = hitInfo and hitInfo.target
	if not target then
		return
	end
	if (target :: any):GetAttribute("HitRole") == "Floor" then
		_despawn(handle, hitInfo)
	end
end

-- ─── 엔티티 정의 테이블 ──────────────────────────────────────────────────────

return {
	-- ─── PunchFist: 착지 후 전방 짧은 arc 히트박스 ───────────────────────────
	PunchFist = {
		model = "Tank_JumpPunchFist",
		tags = { "jump_punch_fist" },

		move = EntityUtils.Arc({
			distance = FIST_DISTANCE,
			height = FIST_HEIGHT,
			speed = FIST_SPEED,
			-- rotate 기본 true → 접선 방향 회전
		}),

		onSpawn = EntityUtils.Animate(EntityUtils.FadeTo({
			from = 1,
			to = 0,
			duration = 0.06,
			speed = 40,
		})),

		hitDetect = EntityUtils.Box({
			size = Vector3.new(3.2, 3.2, 3.2),
			relations = { "enemy" },
		}),

		onHit = EntityUtils.Sequence({
			EntityUtils.LockHit(),
			EntityUtils.Despawn({ delay = 0 }),
		}),

		onMiss = EntityUtils.Sequence({
			EntityUtils.Animate(EntityUtils.FadeTo({
				from = 0,
				to = 1,
				duration = 0.06,
				speed = 30,
			})),
			EntityUtils.Despawn({ delay = 0.06 }),
		}),

		colorFilter = EntityColorUtils.Highlight({
			fillTransparency = 0.2,
			outlineTransparency = 0,
			depthMode = "AlwaysOnTop",
		}),
	},
}
