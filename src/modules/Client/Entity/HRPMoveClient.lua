--!strict
--[=[
	@class HRPMoveClient

	서버로부터 HRPMove 신호를 수신해 로컬에서 EntityPlayer.PlayDirect를 실행합니다.

	- PlayMove 수신: entityDefModule + defName으로 def 로드 → 로컬 HRP에 PlayDirect
	  클라이언트가 자기 HRP의 네트워크 소유권을 계속 유지하므로 PivotTo가 즉시 반영됨.
	- StopMove 수신: 현재 진행 중인 HRP 이동 Maid 정리 → 자동 복원(AnchorPart cleanup)
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local EntityPlayer = require("EntityPlayer")
local HRPMoveRemoting = require("HRPMoveRemoting")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")

export type HRPMoveClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_moveMaid: any,
	},
	{} :: typeof({ __index = {} })
))

local HRPMoveClient = {}
HRPMoveClient.ServiceName = "HRPMoveClient"
HRPMoveClient.__index = HRPMoveClient

function HRPMoveClient.Init(self: HRPMoveClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._moveMaid = Maid.new()
end

function HRPMoveClient.Start(self: HRPMoveClient): ()
	self._maid:GiveTask(
		HRPMoveRemoting.PlayMove:Connect(function(entityDefModule: string, defName: string, originCF: CFrame)
			self:_play(entityDefModule, defName, originCF)
		end)
	)

	self._maid:GiveTask(HRPMoveRemoting.StopMove:Connect(function()
		self:_stop()
	end))
end

function HRPMoveClient:_play(entityDefModule: string, defName: string, originCF: CFrame)
	-- 기존 이동 중단
	self:_stop()

	local player = Players.LocalPlayer
	local character = player.Character
	if not character then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	local ok, defs = pcall(require, entityDefModule)
	if not ok or type(defs) ~= "table" then
		warn("[HRPMoveClient] def 로드 실패:", entityDefModule, defs)
		return
	end
	local def = (defs :: any)[defName]
	if not def then
		warn("[HRPMoveClient] def 없음:", defName, "in", entityDefModule)
		return
	end

	local moveMaid = Maid.new()
	self._moveMaid:GiveTask(moveMaid)

	EntityPlayer.PlayDirect({
		part = hrp,
		origin = originCF,
		move = def.move,
		onSpawn = def.onSpawn,
		onMiss = def.onMiss,
		taskMaid = moveMaid,
	})
end

function HRPMoveClient:_stop()
	self._moveMaid:DoCleaning()
end

function HRPMoveClient.Destroy(self: HRPMoveClient)
	self._maid:Destroy()
	self._moveMaid:Destroy()
end

return HRPMoveClient
