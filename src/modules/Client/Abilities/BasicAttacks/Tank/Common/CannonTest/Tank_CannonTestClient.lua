--!strict
--[=[
	@class Tank_CannonTestClient
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local EntityPlayer = require("EntityPlayer")

local ENTITY_DEF_MODULE = "Tank_CannonTestEntityDef"
local ENTITY_NAME = "CannonBall"
local ANGLE_EXPAND_TIME = 3.0

type BasicAttackState = {
	origin: Vector3,
	direction: Vector3,
	effectiveAimTime: number,
	taskMaid: any?,
	indicator: any,
	animator: any?,
	attackerPlayerId: number?,
	teamContext: { color: Color3?, [string]: any }?,
}

return {
	shapes = {},

	onAimStart = {},
	onAim = {},

	onFire = {
		function(state: BasicAttackState)
			local localPlayer = Players.LocalPlayer
			local char = localPlayer.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp then
				return
			end

			local origin = CFrame.new(hrp.Position, hrp.Position + state.direction)
			local aimRatio = math.clamp(state.effectiveAimTime / ANGLE_EXPAND_TIME, 0, 1)

			EntityPlayer.Play(ENTITY_DEF_MODULE, ENTITY_NAME, {
				origin = origin,
				color = state.teamContext and state.teamContext.color,
				attackerPlayerId = state.attackerPlayerId or localPlayer.UserId,
				params = { aimRatio = aimRatio },
				taskMaid = state.taskMaid,
				replicate = true,
			})
		end,
	},

	onCancel = {},
	onHitChecked = {},
}
