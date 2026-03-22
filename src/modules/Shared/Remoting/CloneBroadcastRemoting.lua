--!strict
--[=[
	@class CloneBroadcastRemoting

	HRP 위치 브로드캐스트용 Raw UnreliableRemoteEvent 채널.
	Remoting 래퍼 미사용 — UnreliableRemoteEvent + buffer 직접 처리.

	채널:
	  PositionUpload   (UnreliableRemoteEvent) : 클라이언트 → 서버
	    payload: buffer [ px(f32) py(f32) pz(f32) rx(f32) ry(f32) rz(f32) ] = 24 bytes

	  PositionBroadcast (UnreliableRemoteEvent) : 서버 → 클라이언트
	    payload: buffer [ count(u8) | (userId(u32) px py pz rx ry rz)(×N) ] = 1 + 28N bytes
	    서버가 매 프레임 모든 플레이어를 하나의 buffer에 묶어 전송 (batch)

	buffer 인코딩 유틸:
	  CloneBroadcastRemoting.encodeMyCFrame(cf)        → buffer (24 bytes)
	  CloneBroadcastRemoting.decodeMyCFrame(buf)        → CFrame
	  CloneBroadcastRemoting.encodeBatch(entries)       → buffer (1 + 28N bytes)
	  CloneBroadcastRemoting.decodeBatch(buf)           → { { userId, cframe } }
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "CloneBroadcast"
local UPLOAD_NAME = "PositionUpload"
local BROADCAST_NAME = "PositionBroadcast"

-- ─── RemoteEvent 생성 / 조회 ─────────────────────────────────────────────────

local folder: Folder
local uploadEvent: UnreliableRemoteEvent
local broadcastEvent: UnreliableRemoteEvent

if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = ReplicatedStorage

	uploadEvent = Instance.new("UnreliableRemoteEvent")
	uploadEvent.Name = UPLOAD_NAME
	uploadEvent.Parent = folder

	broadcastEvent = Instance.new("UnreliableRemoteEvent")
	broadcastEvent.Name = BROADCAST_NAME
	broadcastEvent.Parent = folder
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	uploadEvent = folder:WaitForChild(UPLOAD_NAME) :: UnreliableRemoteEvent
	broadcastEvent = folder:WaitForChild(BROADCAST_NAME) :: UnreliableRemoteEvent
end

-- ─── buffer 인코딩 유틸 ───────────────────────────────────────────────────────

local CloneBroadcastRemoting = {}

CloneBroadcastRemoting.PositionUpload = uploadEvent
CloneBroadcastRemoting.PositionBroadcast = broadcastEvent

--[=[
	내 CFrame → 24 bytes buffer (클라이언트 → 서버)
	[ px(f32) py(f32) pz(f32) rx(f32) ry(f32) rz(f32) ]
]=]
function CloneBroadcastRemoting.encodeMyCFrame(cf: CFrame): buffer
	local buf = buffer.create(24)
	local p = cf.Position
	local rx, ry, rz = cf:ToEulerAnglesYXZ()
	buffer.writef32(buf, 0, p.X)
	buffer.writef32(buf, 4, p.Y)
	buffer.writef32(buf, 8, p.Z)
	buffer.writef32(buf, 12, rx)
	buffer.writef32(buf, 16, ry)
	buffer.writef32(buf, 20, rz)
	return buf
end

--[=[
	24 bytes buffer → CFrame (서버 수신 후 검증용 / 디버그용)
]=]
function CloneBroadcastRemoting.decodeMyCFrame(buf: buffer): CFrame
	local px = buffer.readf32(buf, 0)
	local py = buffer.readf32(buf, 4)
	local pz = buffer.readf32(buf, 8)
	local rx = buffer.readf32(buf, 12)
	local ry = buffer.readf32(buf, 16)
	local rz = buffer.readf32(buf, 20)
	return CFrame.new(px, py, pz) * CFrame.fromEulerAnglesYXZ(rx, ry, rz)
end

--[=[
	배치 인코딩 (서버 → 클라이언트)
	entries: { { userId: number, cframe: CFrame } }
	→ buffer [ count(u8) | userId(u32) px py pz rx ry rz ] × N
	   = 1 + 28N bytes
]=]
function CloneBroadcastRemoting.encodeBatch(entries: { { userId: number, cframe: CFrame } }): buffer
	local count = #entries
	local buf = buffer.create(1 + count * 28)
	buffer.writeu8(buf, 0, count)
	for i, entry in entries do
		local base = 1 + (i - 1) * 28
		local p = entry.cframe.Position
		local rx, ry, rz = entry.cframe:ToEulerAnglesYXZ()
		buffer.writeu32(buf, base, entry.userId)
		buffer.writef32(buf, base + 4, p.X)
		buffer.writef32(buf, base + 8, p.Y)
		buffer.writef32(buf, base + 12, p.Z)
		buffer.writef32(buf, base + 16, rx)
		buffer.writef32(buf, base + 20, ry)
		buffer.writef32(buf, base + 24, rz)
	end
	return buf
end

--[=[
	배치 디코딩 (클라이언트 수신)
	→ { { userId: number, cframe: CFrame } }
]=]
function CloneBroadcastRemoting.decodeBatch(buf: buffer): { { userId: number, cframe: CFrame } }
	local count = buffer.readu8(buf, 0)
	local result: { { userId: number, cframe: CFrame } } = table.create(count)
	for i = 1, count do
		local base = 1 + (i - 1) * 28
		local userId = buffer.readu32(buf, base)
		local px = buffer.readf32(buf, base + 4)
		local py = buffer.readf32(buf, base + 8)
		local pz = buffer.readf32(buf, base + 12)
		local rx = buffer.readf32(buf, base + 16)
		local ry = buffer.readf32(buf, base + 20)
		local rz = buffer.readf32(buf, base + 24)
		result[i] = {
			userId = userId,
			cframe = CFrame.new(px, py, pz) * CFrame.fromEulerAnglesYXZ(rx, ry, rz),
		}
	end
	return result
end

return CloneBroadcastRemoting
