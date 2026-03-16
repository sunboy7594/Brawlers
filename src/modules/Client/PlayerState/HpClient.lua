--!strict
--[=[
	@class HpClient

	서버로부터 HP 동기화(HpSync)를 수신하고 로컬에서 HP 상태를 관리합니다.

	테스트 단계:
	  HP 변화 시 Output으로 확인.
	  delta = 0  : 스폰 / 클래스 변경 등 상태 리셋  → "[HP] N / M  (sync)"
	  delta < 0  : 대미지                            → "[HP] N / M  (-N)"
	  delta > 0  : 회복                              → "[HP] N / M  (+N)"

	추후:
	  _hp ValueObject를 구독하여 HpBarUI에 연결할 것.
	  GetHpObject()로 ValueObject를 받아 UI 바인딩에 사용.
]=]

local require = require(script.Parent.loader).load(script)

local HpRemoting = require("HpRemoting")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local ValueObject = require("ValueObject")

-- ─── 타입 ────────────────────────────────────────────────────────────────────

export type HpState = {
	current: number,
	max: number,
}

export type HpClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_hp: any, -- ValueObject<HpState>
	},
	{} :: typeof({ __index = {} })
))

-- ─── 서비스 ──────────────────────────────────────────────────────────────────

local HpClient = {}
HpClient.ServiceName = "HpClient"
HpClient.__index = HpClient

function HpClient.Init(self: HpClient, serviceBag: ServiceBag.ServiceBag): ()
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._hp = ValueObject.new({ current = 0, max = 0 } :: HpState)
end

function HpClient.Start(self: HpClient): ()
	self._maid:GiveTask(HpRemoting.HpSync:Connect(function(current: number, max: number, delta: number)
		self._hp.Value = { current = current, max = max }

		-- 테스트용 Output 출력
		if delta == 0 then
			print(string.format("[HP] %d / %d  (sync)", current, max))
		elseif delta < 0 then
			print(string.format("[HP] %d / %d  (%.0f)", current, max, delta))
		else
			print(string.format("[HP] %d / %d  (+%.0f)", current, max, delta))
		end
	end))
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	현재 HP 상태를 담은 ValueObject를 반환합니다.
	UI 연결 시 이 오브젝트의 Changed를 구독하세요.
	@return ValueObject<HpState>
]=]
function HpClient:GetHpObject()
	return self._hp
end

function HpClient.Destroy(self: HpClient)
	self._hp:Destroy()
	self._maid:Destroy()
end

return HpClient
