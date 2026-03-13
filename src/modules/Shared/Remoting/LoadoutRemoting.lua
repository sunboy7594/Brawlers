--!strict
--[=[
	@class LoadoutRemoting

	장착 변경 요청 채널. 추후 슬롯 UI에서도 동일하게 사용합니다.
	서버/클라이언트 모두 이 모듈을 require하여 사용합니다.

	채널 목록:
	- RequestEquipBasicAttack: (클라이언트 → 서버) 기본 공격 장착 (attackId: string) → (success: boolean, result: string)
	- RequestEquipSkill:       (클라이언트 → 서버) 스킬 장착 (skillId: string) → (success: boolean, result: string)
	- RequestEquipUltimate:    (클라이언트 → 서버) 궁극기 장착 (ultimateId: string) → (success: boolean, result: string)
	- RequestEquipPassive:     (클라이언트 → 서버) 패시브 장착 (passiveId: string) → (success: boolean, result: string)
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remoting = require("Remoting")

-- 서버/클라이언트 자동 분기
local LoadoutRemoting
if RunService:IsServer() then
	LoadoutRemoting = Remoting.Server.new(ReplicatedStorage, "Loadout")
	-- 클라이언트 → 서버 방향 함수 사전 선언
	LoadoutRemoting.RequestEquipBasicAttack:DeclareMethod()
	LoadoutRemoting.RequestEquipSkill:DeclareMethod()
	LoadoutRemoting.RequestEquipUltimate:DeclareMethod()
	LoadoutRemoting.RequestEquipPassive:DeclareMethod()
else
	LoadoutRemoting = Remoting.Client.new(ReplicatedStorage, "Loadout")
end

return LoadoutRemoting
