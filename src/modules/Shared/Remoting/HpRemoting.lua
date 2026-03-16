--!strict
--[=[
	@class HpRemoting

	HP 관련 Remote 채널.

	채널 목록:
	- HpSync: (서버 → 클라이언트) HP 상태 동기화
	          전달: current (number), max (number), delta (number)
	          delta = 0  : 상태 동기화 (스폰 / 클래스 변경 / SetMaxHp)
	          delta < 0  : 피격 (대미지)
	          delta > 0  : 회복 (힐)
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remoting = require("Remoting")

local HpRemoting
if RunService:IsServer() then
	HpRemoting = Remoting.Server.new(ReplicatedStorage, "Hp")
	HpRemoting.HpSync:DeclareEvent()
else
	HpRemoting = Remoting.Client.new(ReplicatedStorage, "Hp")
end

return HpRemoting
