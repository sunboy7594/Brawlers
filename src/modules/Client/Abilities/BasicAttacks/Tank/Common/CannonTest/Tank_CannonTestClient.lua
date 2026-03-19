--!strict
--[=[
	@class Tank_CannonTestClient

	탱크 캐논 테스트 기본공격 클라이언트 모듈.

	연이체 흐름:
	  onFire:
	    1. AbilityEffectPlayer.Play() → CannonBall 소환
	       delay 없음 → 즉시 발사, spawnCFrame 반환
	    2. params에 aimRatio 주입 (판정 크기 조정용)
	    3. 비주얼은 클라이언트가 담당, 판정은 서버(AbilityEffectSimulatorService)가 담당

	state.abilityEffectMaid:
	  delay가 있는 Play()에 넘기면 취소 시 대기 중 발사 취소됨.
	  이미 발사된 쳤논볼은 독립 수명으로 계속 진행.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local AbilityEffectPlayer = require("AbilityEffectPlayer")

-- ─── 설정 ────────────────────────────────────────────────────────────────────

local EFFECT_DEF_MODULE = "Tank_CannonEffectDef"
local EFFECT_NAME       = "CannonBall"
local ANGLE_EXPAND_TIME = 3.0  -- 조준 시간 만나에 판정 최대화

-- ─── 상태 타입 ───────────────────────────────────────────────────────────────

type BasicAttackState = {
	origin            : Vector3,
	direction         : Vector3,
	effectiveAimTime  : number,
	fireMaid          : any?,
	abilityEffectMaid : any?,
	indicator         : any,
	animator          : any?,
	teamContext       : any?,
}

-- ─── 모듈 정의 ───────────────────────────────────────────────────────────────

return {
	shapes = {},

	onAimStart = {},
	onAim = {},

	onFire = {
		function(state: BasicAttackState)
			local localPlayer = Players.LocalPlayer
			local char = localPlayer.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp then return end

			local origin = CFrame.new(hrp.Position, hrp.Position + state.direction)

			-- aimRatio: effectiveAimTime 비례로 판정 크기 제어
			local aimRatio = math.clamp(state.effectiveAimTime / ANGLE_EXPAND_TIME, 0, 1)

			-- 클라이언트 연이첤 재생
			-- isOwner=true → EffectFired + Register 서버 전송 자동
			AbilityEffectPlayer.Play(EFFECT_DEF_MODULE, EFFECT_NAME, {
				origin            = origin,
				abilityEffectMaid = state.abilityEffectMaid,
				params            = { aimRatio = aimRatio },
				teamContext       = state.teamContext,
			})
		end,
	},

	onCancel = {},
	onHitChecked = {},
}
