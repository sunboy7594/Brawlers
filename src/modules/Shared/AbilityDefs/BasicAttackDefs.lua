--!strict
--[=[
    @class BasicAttackDefs

    기본공격 전체 정의 테이블. (Shared)
    새 기본공격 추가 시 이 파일에만 항목을 추가하면 됩니다.

    관련 모듈 명명 규칙 (id 기반 자동 require):
    - 서버 모듈:    id .. "Server"   예) Tank_PunchServer
    - 클라이언트:   id .. "Client"   예) Tank_PunchClient
      (animDef는 Client 모듈 안에 포함)
]=]

export type BasicAttackDef = {
	id: string,
	rarity: string,
	class: string,
	maxAmmo: number,
	reloadTime: number, -- 탄약 1개 재생 시간 (초)
	postDelay: number, -- 발사 후 다음 조준까지 딜레이 (초)
}

local BasicAttackDefs: { [string]: BasicAttackDef } = {
	Tank_Punch = {
		id = "Tank_Punch",
		rarity = "COMMON",
		class = "TANK",
		maxAmmo = 3,
		reloadTime = 2,
		postDelay = 1,
	},
}

return BasicAttackDefs
