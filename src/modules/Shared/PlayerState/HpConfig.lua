--!strict
--[=[
	@class HpConfig

	직업별 기본 최대 HP 정의. 서버/클라이언트 공유.

	패시브·스킬로 최대 HP를 변경할 때는 HpService:SetMaxHp()를 사용할 것.
	이 값은 어디서도 직접 변경하지 않는다.
]=]

local HpConfig = {}

HpConfig.BaseMaxHp = {
	Default = 100,
	TANK = 200,
	ASSASSIN = 80,
	SUPPORT = 90,
	CONTROLLER = 100,
	DEALER = 90,
	MARKSMAN = 85,
	ARTILLERY = 95,
}

function HpConfig.GetBaseMaxHp(className: string): number
	return HpConfig.BaseMaxHp[className] or HpConfig.BaseMaxHp.Default
end

return HpConfig
