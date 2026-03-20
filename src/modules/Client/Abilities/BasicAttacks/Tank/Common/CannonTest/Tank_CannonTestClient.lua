--!strict
--[=[
	@class Tank_CannonTestClient
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local AbilityEffectPlayer = require("AbilityEffectPlayer")

local EFFECT_DEF_MODULE = "Tank_CannonTestEffectDef"
local EFFECT_NAME = "CannonBall"
local ANGLE_EXPAND_TIME = 3.0

type TeamContext = {
	attackerChar: Model?,
	attackerPlayer: Player?,
	color: Color3?,
	isEnemy: (a: Player, b: Player) -> boolean,
}

type BasicAttackState = {
	origin: Vector3,
	direction: Vector3,
	effectiveAimTime: number,
	fireMaid: any?,
	abilityEffectMaid: any?,
	indicator: any,
	animator: any?,
	teamContext: TeamContext?,
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

			AbilityEffectPlayer.Play(EFFECT_DEF_MODULE, EFFECT_NAME, {
				origin = origin,
				color = state.teamContext and state.teamContext.color,
				abilityEffectMaid = state.abilityEffectMaid,
				params = { aimRatio = aimRatio },
				teamContext = state.teamContext,
			})
		end,
	},

	onCancel = {},
	onHitChecked = {},
}
