--!strict
--[=[
    @class BasicAttackDefs

    기본공격 전체 정의 테이블. (Shared)
    새 기본공격 추가 시 이 파일에만 항목을 추가하면 됩니다.

    관련 모듈 명명 규칙 (id 기반 자동 require):
    - 서버 모듈:    id .. "Server"     예) Tank_PunchServer
    - 클라이언트:   id .. "Client"     예) Tank_PunchClient
    - 애니메이션:  id .. "AnimDef"    예) Tank_PunchAnimDef
	- 엔티티 정의: entityDef 필드에 직접 지정된 모듈명 (예: Tank_CannonTestEntityDef)
]=]

local require = require(script.Parent.loader).load(script)

local AbilityTypes = require("AbilityTypes")

export type BasicAttackDef = AbilityTypes.AbilityDef

-- 변경 후: 각 Def를 require해서 합산
local BasicAttackDefs: { [string]: BasicAttackDef } = {
	Tank_Punch = require("Tank_PunchDef"),
	Tank_CannonTest = require("Tank_CannonTestDef"),
	Tank_RapidFirePunch = require("Tank_RapidFirePunchDef"), -- ← 추가
}

return BasicAttackDefs
