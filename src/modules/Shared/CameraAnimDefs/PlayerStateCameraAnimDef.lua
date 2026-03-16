--!strict
--[=[
	@class PlayerStateCameraAnimDef

	tag name → 카메라 CameraAnimDef 키 매핑.
	PlayerStateClient가 cam_* tag를 받아 여기서 조회 후 CameraAnimator에 재생합니다.

	intensity (0~1):
	  CameraAnimator에 그대로 전달하여 흔들림 크기/속도 스케일링에 활용.

	knockbackRef:
	  true이면 클라이언트가 knockback component의 direction을
	  카메라 연출 방향으로 참조함.
]=]

local PlayerStateDefs = require("PlayerStateDefs")
local Tag = PlayerStateDefs.Tag

type CameraMapping = {
	cameraAnimKey: string,
	knockbackRef:  boolean?,
}

local PlayerStateCameraAnimDef: { [string]: CameraMapping } = {

	[Tag.CamShake] = {
		cameraAnimKey = "HitShake",
	},

	[Tag.CamRecoil] = {
		cameraAnimKey = "HitRecoil",
	},

	[Tag.CamKnockback] = {
		cameraAnimKey = "HitRecoil",
		knockbackRef  = true,
	},

	[Tag.CamMotionSickness] = {
		cameraAnimKey = "MotionSickness",
	},
}

return PlayerStateCameraAnimDef
