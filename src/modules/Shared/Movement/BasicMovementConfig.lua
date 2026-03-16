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
	*현재 전부 동일하게 맞춤. 추후 조정 예정
]=]

local BasicMovementConfig = {}

export type AnimationSet = {
	Idle: string,
	Walk: string,
	Run: string,
	Breathing: string,
}

export type ClassConfig = {
	walkSpeed: number,
	runSpeed: number,
	acceleration: number,
	deceleration: number,
	animations: AnimationSet,
}

-- ─────────────────────────────────────────────────────────────────────────────

BasicMovementConfig.Classes = {
	Default = {
		walkSpeed = 12,
		runSpeed = 17,
		acceleration = 4,
		deceleration = 5,
		animations = {
			Idle = "Idle",
			Walk = "Walk",
			Run = "Run",
			Breathing = "Breathing",
		},
	} :: ClassConfig,

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

	ASSASSIN = {
		walkSpeed = 12,
		runSpeed = 17,
		acceleration = 4,
		deceleration = 5,
		animations = {
			Idle = "Idle_Assassin",
			Walk = "Walk_Assassin",
			Run = "Run_Assassin",
			Breathing = "Breathing_Assassin",
		},
	} :: ClassConfig,

	SUPPORT = {
		walkSpeed = 12,
		runSpeed = 17,
		acceleration = 4,
		deceleration = 5,
		animations = {
			Idle = "Idle_Support",
			Walk = "Walk_Support",
			Run = "Run_Support",
			Breathing = "Breathing_Support",
		},
	} :: ClassConfig,

	CONTROLLER = {
		walkSpeed = 12,
		runSpeed = 17,
		acceleration = 4,
		deceleration = 5,
		animations = {
			Idle = "Idle_Controller",
			Walk = "Walk_Controller",
			Run = "Run_Controller",
			Breathing = "Breathing_Controller",
		},
	} :: ClassConfig,

	DEALER = {
		walkSpeed = 12,
		runSpeed = 17,
		acceleration = 4,
		deceleration = 5,
		animations = {
			Idle = "Idle_Dealer",
			Walk = "Walk_Dealer",
			Run = "Run_Dealer",
			Breathing = "Breathing_Dealer",
		},
	} :: ClassConfig,

	MARKSMAN = {
		walkSpeed = 12,
		runSpeed = 17,
		acceleration = 4,
		deceleration = 5,
		animations = {
			Idle = "Idle_Marksman",
			Walk = "Walk_Marksman",
			Run = "Run_Marksman",
			Breathing = "Breathing_Marksman",
		},
	} :: ClassConfig,

	ARTILLERY = {
		walkSpeed = 12,
		runSpeed = 17,
		acceleration = 4,
		deceleration = 5,
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
