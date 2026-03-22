--!strict
--[=[
	@class Tank_JumpPunchEntityDef

	탱크 점프 펀치 엔티티 정의. (Shared)

	"PunchFist":
	  착지 직후 전방으로 짧은 arc를 그리며 날아가는 히트박스 엔티티.

	"PlayerJump":
	  공격자 HRP arc 점프용. HRPMoveClient가 수신 후 로컬에서 PlayDirect로 실행.

	"PlayerThrow":
	  피격자 HRP arc 날리기용. HRPMoveClient가 수신 후 로컬에서 실행.
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

local THROW_DISTANCE = 22
local THROW_HEIGHT = 10
local THROW_SPEED = 28

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

	-- ─── PlayerJump: 공격자 HRP 로컬 arc 점프 ───────────────────────────────
	PlayerJump = {
		-- model = nil → HRPMoveClient가 HRP 자체를 part로 전달
		move = EntityUtils.Arc({
			distance = JUMP_DISTANCE,
			height = JUMP_HEIGHT,
			speed = JUMP_SPEED,
			rotate = false,
		}),
		onSpawn = EntityUtils.AnchorPart(),
	},

	-- ─── PlayerThrow: 피격자 HRP 로컬 arc 날리기 ────────────────────────────
	PlayerThrow = {
		-- model = nil → HRPMoveClient가 HRP 자체를 part로 전달
		move = EntityUtils.Arc({
			distance = THROW_DISTANCE,
			height = THROW_HEIGHT,
			speed = THROW_SPEED,
			rotate = false,
		}),
		onSpawn = EntityUtils.AnchorPart(),
	},
}
