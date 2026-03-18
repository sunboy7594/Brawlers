--!strict
--[=[
	@class AbilityCoordinator

	ability 간 동시성 규칙을 집행하는 클라이언트 서비스.

	규칙:
	- 조준(Aim): AimController가 하나만 유지하므로 자동 처리
	- 발사(Fire): 원칙적으로 하나만
	  → 새 fire 발동 시 기존 firing 중인 ability를 cancel
	  예외: toggle firing은 다른 ability fire에 의해 cancel되지 않음

	- CancelAll: 공격불가 상태 등 전체 캔슬 시 호출
	  → 모든 registered client의 CancelCombatState() 실행
	  → toggle firing 포함 예외 없음

	등록:
	  AbilityCoordinator는 서비스백에서 BasicAttackClient, SkillClient, UltimateClient를
	  참조하지 않습니다. 대신 각 Client가 Start() 시점에 Register()를 호출합니다.
	  (circular dependency 방지)
]=]

local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local ServiceBag = require("ServiceBag")

-- ─── 타입 ────────────────────────────────────────────────────────────────────

type AbilityClient = {
	AbilityType: string,
	IsFiring: (self: any) -> boolean,
	IsToggleFiring: (self: any) -> boolean,
	CancelCombatState: (self: any) -> (),
}

export type AbilityCoordinator = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_clients: { AbilityClient },
	},
	{} :: typeof({ __index = {} })
))

local AbilityCoordinator = {}
AbilityCoordinator.ServiceName = "AbilityCoordinator"
AbilityCoordinator.__index = AbilityCoordinator

-- ─── 초기화 ──────────────────────────────────────────────────────────────────

function AbilityCoordinator.Init(self: AbilityCoordinator, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._clients = {}
end

function AbilityCoordinator.Start(_self: AbilityCoordinator): ()
	-- 각 Client가 Start() 시점에 Register() 호출
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	ability client를 등록합니다.
	각 ability Client의 Start()에서 호출합니다.
]=]
function AbilityCoordinator:Register(client: AbilityClient)
	table.insert(self._clients, client)
end

--[=[
	fire가 발동되었음을 알립니다.
	toggle 이외의 firing 중인 ability를 cancel합니다.

	@param firingClient 방금 fire를 실행한 client (자기 자신 제외)
]=]
function AbilityCoordinator:OnFireExecuted(firingClient: AbilityClient)
	for _, client in self._clients do
		if client == firingClient then
			continue
		end
		-- toggle firing은 다른 ability fire에 의해 cancel되지 않음
		if client:IsFiring() and not client:IsToggleFiring() then
			client:CancelCombatState()
		end
	end
end

--[=[
	공격불가 등 외부 이벤트로 모든 ability를 cancel합니다.
	toggle firing 포함 예외 없음.
]=]
function AbilityCoordinator:CancelAll()
	for _, client in self._clients do
		client:CancelCombatState()
	end
end

function AbilityCoordinator:CancelByType(abilityType: string)
	for _, client in self._clients do
		if abilityType == "*" or client.AbilityType == abilityType then
			client:CancelCombatState()
		end
	end
end

function AbilityCoordinator.Destroy(self: AbilityCoordinator)
	self._maid:Destroy()
end

return AbilityCoordinator
