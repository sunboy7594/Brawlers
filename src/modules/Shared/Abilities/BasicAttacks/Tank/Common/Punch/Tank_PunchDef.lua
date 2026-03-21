--!strict
local require = require(script.Parent.loader).load(script)

local AbilityTypes = require("AbilityTypes")

return {
	id = "Tank_Punch",
	rarity = "COMMON",
	class = "TANK",
	fireType = "stack",
	resource = {
		resourceType = "stack",
		maxStack = 3,
		reloadTime = 2,
	},
	interval = 1,
} :: AbilityTypes.AbilityDef
