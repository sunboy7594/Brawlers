--!strict
--[=[
	@class BasicMovementConfig
	직업별 이동 파라미터 정의. 서버/클라이언트 공유.
	속도 값은 서버에서만 실제로 사용되며, 클라이언트는 애니메이션 정보만 참조합니다.

	직업군:
	- TANK        탱커       : 느리고 무거움
	- ASSASSIN    어쌔신     : 가장 빠름, 민첩
	- SUPPORT     서포터     : 평범, 가벼운 움직임
	- CONTROLLER  컨트롤러   : 중간, 안정적
	- DEALER      대미지딜러 : 중간보다 약간 빠름
	- MARKSMAN    저격수     : 느린 걷기, 빠른 달리기
	- ARTILLERY   투척수     : 느리고 둔함
]=]

local BasicMovementConfig = {}

export type AnimationSet = {
	Idle: string,
	Walk: string,
	Run: string,
	Breathing: string,
}

export type ClassConfig = {
	-- [Server-authoritative] 실제 WalkSpeed 적용은 서버만 수행
	walkSpeed: number,
	runSpeed: number,

	-- 관성 제어 (지수 감쇠 Lerp 계수)
	-- 값이 클수록 빠르게 목표 속도에 도달
	acceleration: number,
	deceleration: number,

	-- [Client] 애니메이션 키 이름 (BasicMovementAnimDefs의 키와 1:1 매핑)
	animations: AnimationSet,
}

-- ─────────────────────────────────────────────────────────────────────────────

BasicMovementConfig.Classes = {
	-- Fallback (클래스 미지정 시)
	Default = {
		walkSpeed = 16,
		runSpeed = 22,
		acceleration = 8,
		deceleration = 12,
		animations = {
			Idle = "Idle",
			Walk = "Walk",
			Run = "Run",
			Breathing = "Breathing",
		},
	} :: ClassConfig,

	-- 탱커: 느리고 무거운 가속/감속. 육중한 느낌.
	TANK = {
		walkSpeed = 12,
		runSpeed = 17,
		acceleration = 4,
		deceleration = 5,
		animations = {
			Idle = "Idle_Tank",
			Walk = "Walk_Tank",
			Run = "Run_Tank",
			Breathing = "Breathing_Tank",
		},
	} :: ClassConfig,

	-- 어쌔신: 가장 빠른 최고속도, 매우 빠른 가속.
	-- 감속은 조금 느려서 멈출 때 약간 미끄러지는 느낌.
	ASSASSIN = {
		walkSpeed = 17,
		runSpeed = 30,
		acceleration = 16,
		deceleration = 10,
		animations = {
			Idle = "Idle_Assassin",
			Walk = "Walk_Assassin",
			Run = "Run_Assassin",
			Breathing = "Breathing_Assassin",
		},
	} :: ClassConfig,

	-- 서포터: 평균적, 가볍고 부드러운 이동감.
	SUPPORT = {
		walkSpeed = 15,
		runSpeed = 22,
		acceleration = 10,
		deceleration = 14,
		animations = {
			Idle = "Idle_Support",
			Walk = "Walk_Support",
			Run = "Run_Support",
			Breathing = "Breathing_Support",
		},
	} :: ClassConfig,

	-- 컨트롤러: 중간 속도, 안정적이고 균형잡힌 이동.
	CONTROLLER = {
		walkSpeed = 14,
		runSpeed = 21,
		acceleration = 9,
		deceleration = 12,
		animations = {
			Idle = "Idle_Controller",
			Walk = "Walk_Controller",
			Run = "Run_Controller",
			Breathing = "Breathing_Controller",
		},
	} :: ClassConfig,

	-- 대미지 딜러: 중간보다 약간 빠르고 반응이 좋음.
	DEALER = {
		walkSpeed = 16,
		runSpeed = 24,
		acceleration = 12,
		deceleration = 13,
		animations = {
			Idle = "Idle_Dealer",
			Walk = "Walk_Dealer",
			Run = "Run_Dealer",
			Breathing = "Breathing_Dealer",
		},
	} :: ClassConfig,

	-- 저격수: 걷기는 느리지만 달리기 순간 속도는 꽤 빠름.
	-- 달리기 중에는 조준 불가 등 다른 서비스에서 제약을 걸 것.
	MARKSMAN = {
		walkSpeed = 13,
		runSpeed = 25,
		acceleration = 7,
		deceleration = 11,
		animations = {
			Idle = "Idle_Marksman",
			Walk = "Walk_Marksman",
			Run = "Run_Marksman",
			Breathing = "Breathing_Marksman",
		},
	} :: ClassConfig,

	-- 투척수: 느리고 둔함. 이동 중 포물선 계산 등 다른 서비스와 연계.
	ARTILLERY = {
		walkSpeed = 11,
		runSpeed = 16,
		acceleration = 4,
		deceleration = 6,
		animations = {
			Idle = "Idle_Artillery",
			Walk = "Walk_Artillery",
			Run = "Run_Artillery",
			Breathing = "Breathing_Artillery",
		},
	} :: ClassConfig,
}

function BasicMovementConfig.GetConfig(className: string): ClassConfig
	return BasicMovementConfig.Classes[className] or BasicMovementConfig.Classes.Default
end

return BasicMovementConfig
