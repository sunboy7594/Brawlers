--!strict
--[=[
	@class ClassService

	플레이어 직업 클래스를 중앙에서 관리하는 서버 서비스.

	담당:
	- RequestClassChange 수신 → 검증 → 클래스 적용
	- ClassRemoting.ClassChanged:FireClient → 클라이언트 통보
	- ClassChanged Signal 발행 → 서버 내 구독자 통보 (BasicMovementService, HpService 등)
	- GetClass(player) → 현재 클래스명 반환
	- SetClass(player, className) → 외부 강제 변경 (패시브 등)

	클래스 변경 시 부수 처리:
	- BasicAttackService:CancelCombatState → 예약 발사 / onHit 클로저 초기화

	분리 이유:
	BasicMovementService는 WalkSpeed 관리만 담당.
	클래스 상태 소유 및 변경 처리는 이 서비스가 전담하여
	HpService, 패시브 등 모든 클래스 구독자가 한 곳만 바라보게 함.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local BasicAttackService = require("BasicAttackService")
local BasicMovementConfig = require("BasicMovementConfig")
local ClassRemoting = require("ClassRemoting")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local Signal = require("Signal")

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type ClassService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_attackService: any,
		_playerClasses: { [number]: string },
		ClassChanged: any, -- Signal<Player, string>
	},
	{} :: typeof({ __index = {} })
))

-- ─── 서비스 ──────────────────────────────────────────────────────────────────

local ClassService = {}
ClassService.ServiceName = "ClassService"
ClassService.__index = ClassService

function ClassService.Init(self: ClassService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._attackService = serviceBag:GetService(BasicAttackService)
	self._playerClasses = {}
	self.ClassChanged = Signal.new()

	-- 클라이언트 → 서버: 클래스 변경 요청
	self._maid:GiveTask(ClassRemoting.RequestClassChange:Bind(function(player: Player, className: unknown)
		if type(className) ~= "string" then
			return false, "Invalid class name"
		end
		if not BasicMovementConfig.Classes[className] then
			return false, "Unknown class: " .. className
		end
		self:_applyClass(player, className)
		return true, className
	end))
end

function ClassService.Start(self: ClassService): ()
	for _, player in Players:GetPlayers() do
		self:_onPlayerAdded(player)
	end
	self._maid:GiveTask(Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end))
	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player)
		self._playerClasses[player.UserId] = nil
	end))
end

-- ─── 내부 ────────────────────────────────────────────────────────────────────

function ClassService:_onPlayerAdded(player: Player)
	-- 첫 접속: Default 배정 (재접속이면 이미 값이 없으므로 항상 Default)
	if not self._playerClasses[player.UserId] then
		self._playerClasses[player.UserId] = "Default"
	end
end

function ClassService:_applyClass(player: Player, className: string)
	self._playerClasses[player.UserId] = className

	-- 전투 상태 초기화 (예약 발사, onHit 클로저 등)
	self._attackService:CancelCombatState(player)

	-- 클라이언트에 확정 알림 (애니메이션 전환 등)
	ClassRemoting.ClassChanged:FireClient(player, className)

	-- 서버 내 구독자 통보 (BasicMovementService, HpService 등)
	self.ClassChanged:Fire(player, className)
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	플레이어의 현재 클래스명을 반환합니다.
	@return string -- 클래스명, 데이터 없으면 "Default"
]=]
function ClassService:GetClass(player: Player): string
	return self._playerClasses[player.UserId] or "Default"
end

--[=[
	외부(패시브, 게임 로직 등)에서 클래스를 강제 적용합니다.
	클라이언트 통보 및 서버 Signal 발행까지 포함됩니다.
	@param player Player
	@param className string
]=]
function ClassService:SetClass(player: Player, className: string)
	assert(BasicMovementConfig.Classes[className], "Unknown class: " .. className)
	self:_applyClass(player, className)
end

function ClassService.Destroy(self: ClassService)
	self.ClassChanged:Destroy()
	self._maid:Destroy()
end

return ClassService
