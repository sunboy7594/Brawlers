--!strict
--[=[
	@class PlayerStateRemoting

	PlayerState 관련 Remote 채널.

	채널 목록:
	- EffectApplied: (서버 → 클라이언트) effect 적용 알림
	                 전달: effectDef (EffectDef 전체), payloadId (string)
	                 클라이언트는 tags로 연출 실행, components에서 direction/duration 참조
	                 payloadId로 EffectRemoved와 매핑하여 조기 종료 처리
	- EffectRemoved: (서버 → 클라이언트) effect 조기 제거 알림
	                 전달: payloadId (string)
	                 해당 payloadId의 루프 연출을 즉시 종료
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remoting = require("Remoting")

local PlayerStateRemoting
if RunService:IsServer() then
	PlayerStateRemoting = Remoting.Server.new(ReplicatedStorage, "PlayerState")
	PlayerStateRemoting.EffectApplied:DeclareEvent()
	PlayerStateRemoting.EffectRemoved:DeclareEvent()
else
	PlayerStateRemoting = Remoting.Client.new(ReplicatedStorage, "PlayerState")
end

return PlayerStateRemoting
