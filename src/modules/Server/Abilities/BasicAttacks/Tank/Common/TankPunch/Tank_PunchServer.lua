--!strict
--[=[
    @class Tank_PunchServer

    탱크 주먹 공격 서버 모듈.
]=]

local require = require(script.Parent.loader).load(script)

local InstantHit = require("InstantHit")

return {
	onFire = function(attacker: Model, origin: Vector3, direction: Vector3, _aimTime: number): { Model }
		local result = InstantHit.apply(attacker, origin, direction, {
			shape = "cone",
			range = 8,
			angle = 90,
			damage = 40,
			knockback = 15,
		})
		return result :: { Model }
	end,
}
