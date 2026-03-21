--!strict
--[=[
	@class Tank_RapidFirePunchClient

	탱크 연속 펀치 클라이언트 모듈.

	hold 동작 흐름:
	  [마우스 다운]
	    onAimStart → line 인디케이터 show
	    _startFireLoop 진입

	  [fire 루프 매 틱]
	    onAim     → origin / direction 갱신
	    onFire    → Punch1/2 교대 애니메이션
	              → EntityPlayer.Play(PunchBolt, replicate=true)

	  [마우스 업 / 게이지 소진]
	    onCancel  → 인디케이터 hide, 진행 중 애니메이션 정리

	인디케이터:
	  shape = "line"  range=12  width=1.8
	  hold 중 계속 origin/direction 업데이트되어 조준선처럼 표시됨.

	엔티티:
	  Tank_RapidFirePunchEntityDef / PunchBolt
	  replicate=true → 타 클라이언트에도 복제 재생.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local EntityPlayer = require("EntityPlayer")

-- ─── 상수 ───────────────────────────────────────────────────────────────────

local ENTITY_DEF_MODULE = "Tank_RapidFirePunchEntityDef"
local ENTITY_NAME       = "PunchBolt"

local LINE_RANGE = 12
local LINE_WIDTH = 1.8

local COMBO_ANIMS   = { "Punch1", "Punch2" }

-- ─── 타입 ───────────────────────────────────────────────────────────────────

type BasicAttackState = {
	origin          : Vector3,
	direction       : Vector3,
	effectiveAimTime: number,
	fireComboCount  : number,
	isFiring        : boolean,
	indicator       : any,
	animator        : any?,
	fireMaid        : any?,
	teamContext     : { color: Color3?, [string]: any }?,
}

-- ─── 모듈 ───────────────────────────────────────────────────────────────────

return {
	-- DynamicIndicator 에 등록할 shape 목록
	shapes = {
		aimLine = "line",
	},

	-- ─── onAimStart ─────────────────────────────────────────────────────────
	-- hold: 마우스 다운 시 _tryStartAim → 여기 호출
	onAimStart = {
		function(state: BasicAttackState)
			-- line 인디케이터 초기 설정 및 show
			state.indicator:update("aimLine", {
				origin    = state.origin,
				direction = state.direction,
				range     = LINE_RANGE,
				width     = LINE_WIDTH,
			})
			state.indicator:show("aimLine")
		end,
	},

	-- ─── onAim ──────────────────────────────────────────────────────────────
	-- 매 프레임 AimController 가 호출. origin/direction 업데이트.
	onAim = {
		function(state: BasicAttackState)
			state.indicator:update("aimLine", {
				origin    = state.origin,
				direction = state.direction,
			})
		end,
	},

	-- ─── onFire ─────────────────────────────────────────────────────────────
	-- fire 루프 매 틱 (interval마다) 호출
	onFire = {
		function(state: BasicAttackState)
			-- ① 펀치 애니메이션 (Punch1 / Punch2 교대)
			state.fireComboCount = (state.fireComboCount % #COMBO_ANIMS) + 1
			local animName = COMBO_ANIMS[state.fireComboCount]

			if state.animator then
				-- force=true: 이전 펀치가 채 끝나기 전에 덮어써서 빠른 연타감 표현
				state.animator:PlayAnimation(animName, 0.06, nil, true)

				-- fireMaid 에 정리 함수 등록
				if state.fireMaid then
					state.fireMaid:GiveTask(function()
						state.animator:StopAnimation(animName)
					end)
				end
			end

			-- ② 연출용 엔티티 직선 소환
			local localPlayer = Players.LocalPlayer
			local char = localPlayer.Character
			local hrp  = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp then return end

			-- HRP 위치에서 조준 방향으로 origin CFrame 계산
			local origin = CFrame.new(hrp.Position, hrp.Position + state.direction)

			EntityPlayer.Play(ENTITY_DEF_MODULE, ENTITY_NAME, {
				origin           = origin,
				color            = state.teamContext and state.teamContext.color,
				attackerPlayerId = localPlayer.UserId,
				taskMaid         = state.fireMaid,
				replicate        = true,
			})
		end,
	},

	-- ─── onCancel ───────────────────────────────────────────────────────────
	-- hold 종료(마우스 업, 게이지 소진, 스킬 교체 등) 시 호출
	onCancel = {
		function(state: BasicAttackState)
			state.indicator:hide("aimLine")
		end,
	},

	-- ─── onHitChecked ───────────────────────────────────────────────────────
	-- 서버에서 hit 확정 후 알림 (현재 클라이언트 측 추가 연출 없음)
	onHitChecked = {},
}