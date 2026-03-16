--!strict
--[=[
	@class BasicMovementCameraAnimDef

	이동 관련 카메라 애니메이션 정의.
]=]

type CameraController = any

type CameraAnimDef = {
	layer: "effect" | "offset" | "override",
	factory: (cc: CameraController) -> any,
}

local BasicMovementCameraAnimDef: { [string]: CameraAnimDef } = {}

-- ============================================================
-- [offset] 달리기 FOV 확장
-- ============================================================
BasicMovementCameraAnimDef["RunFOV"] = {
	layer = "offset",
	factory = function(_cc)
		return {
			offset = Vector3.new(0, 0, 0),
			fov = 75,
			stiffness = 200,
			damping = 10,
		}
	end,
}

return BasicMovementCameraAnimDef
