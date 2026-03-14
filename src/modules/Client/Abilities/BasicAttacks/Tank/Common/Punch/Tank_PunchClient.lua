--!strict
--[=[
    @class Tank_PunchClient

    탱크 주먹 공격 클라이언트 모듈.
]=]

local require = require(script.Parent.loader).load(script)

local ConeIndicator = require("ConeIndicator")

return {
	indicator = ConeIndicator.new({ range = 8, angle = 90 }),
	onAim = nil,

	onHitConfirmed = function(_victims: { Model })
		-- TODO: 히트 이펙트 및 사운드 재생
	end,
}
