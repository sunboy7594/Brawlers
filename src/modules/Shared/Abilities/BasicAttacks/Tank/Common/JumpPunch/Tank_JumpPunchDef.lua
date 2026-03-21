--!strict
local require = require(script.Parent.loader).load(script)
local AbilityTypes = require("AbilityTypes")

return {
	id        = "Tank_JumpPunch",
	rarity    = "COMMON",
	class     = "TANK",
	fireType  = "stack",
	resource = {
		resourceType = "stack",
		maxStack     = 3,
		reloadTime   = 2.5,
	},
	interval  = 2.0,
	entityDef = "Tank_JumpPunchEntityDef",
} :: AbilityTypes.AbilityDef
