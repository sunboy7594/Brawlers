--!strict
--[[
	@class BrawlersTranslator
]]

local require = require(script.Parent.loader).load(script)

return require("JSONTranslator").new("BrawlersTranslator", "en", {
	gameName = "Brawlers",
})
