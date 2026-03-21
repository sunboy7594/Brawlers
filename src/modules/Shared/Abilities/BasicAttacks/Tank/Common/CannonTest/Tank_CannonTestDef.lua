--!strict
local require = require(script.Parent.loader).load(script)

local AbilityTypes = require("AbilityTypes")

return {
	id = "Tank_CannonTest",
	rarity = "COMMON",
	class = "TANK",
	fireType = "stack",
	resource = {
		resourceType = "stack",
		maxStack = 3,
		reloadTime = 2,
	},
	interval = 0.3,
	effectDef = "Tank_CannonTestEntityDef",
} :: AbilityTypes.AbilityDef
