--!strict
--[=[
	@class KeybindConfig
	게임 전체 키바인드 설정. 이 파일만 수정하면 모든 입력이 바뀝니다.

	적용 대상:
	- SkillInputClient        : BasicAttack / Skill / Ultimate
	- BasicMovementClient     : Run (달리기)
	- CameraControllerClient  : ShiftLock (카메라 잠금)
]=]

local KeybindConfig = {}

KeybindConfig.Binds = {
	-- ─── 전투 ────────────────────────────────────────────────────────────────
	BasicAttack = Enum.UserInputType.MouseButton1,
	Skill       = Enum.KeyCode.Space,
	Ultimate    = Enum.KeyCode.R,

	-- ─── 이동 ────────────────────────────────────────────────────────────────
	Run = Enum.KeyCode.LeftShift,

	-- ─── 카메라 ──────────────────────────────────────────────────────────────
	ShiftLock = Enum.KeyCode.LeftControl,
}

return KeybindConfig
