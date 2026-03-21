--!strict
--[=[
	@class HRPMoveClient

	HRPMoveRemoting.Move 수신 → 로컬 클라이언트에서 HRP arc 이동 실행.

	보안 구조:
	  - 서버가 발급한 token이 있어야만 이동 실행
	  - token은 1회용 (수신 즉시 소비)
	  - 이동 완료(arc 종료 또는 Floor 착지) 시 LandingReport:FireServer
	  - 서버가 최종 위치 검증 후 오차 초과 시 강제 보정

	공격자 점프와 피격자 날리기 양쪽 모두 이 서비스를 통해 처리됩니다.
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local EntityPlayer    = require("EntityPlayer")
local EntityUtils     = require("EntityUtils")
local HRPMoveRemoting = require("HRPMoveRemoting")
local Maid            = require("Maid")

local HRPMoveClient = {}
HRPMoveClient.ServiceName = "HRPMoveClient"
HRPMoveClient.__index = HRPMoveClient

function HRPMoveClient.Init(self: any, _serviceBag: any)
	self._maid = Maid.new()
end

function HRPMoveClient.Start(self: any)
	self._maid:GiveTask(
		HRPMoveRemoting.Move:Connect(function(
			token    : string,
			defModule: string,
			defName  : string,
			origin   : CFrame,
			params   : { [string]: any }?
		)
			local ok, defs = pcall(require, defModule)
			if not ok or type(defs) ~= "table" then
				warn("[HRPMoveClient] def 로드 실패:", defModule)
				return
			end
			local def = (defs :: any)[defName]
			if not def then
				warn("[HRPMoveClient] def 없음:", defName, "in", defModule)
				return
			end

			local char = Players.LocalPlayer.Character
			local hrp  = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp then return end

			-- 서버 origin의 방향만 사용, 위치는 현재 HRP 위치로 보정
			-- latency로 인해 서버가 기록한 위치와 실제 위치가 다를 수 있음
			-- → PivotTo(origin)으로 인한 미세 snap 방지
			local currentPos     = hrp:GetPivot().Position
			local serverDir      = origin.LookVector
			local adjustedOrigin = CFrame.new(currentPos, currentPos + serverDir)

			-- 착지 보고: arc 종료 또는 Floor 착지 시 1회만 실행
			local reported = false
			local function reportLanding()
				if reported then return end
				reported = true
				local c = Players.LocalPlayer.Character
				local h = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
				if h then
					HRPMoveRemoting.LandingReport:FireServer(token, h.Position)
				end
			end

			-- Floor 착지로 실제 Despawn됐을 때만 보고
			-- 벽에 스쳐도 arc가 계속되도록 IsAlive() 체크
			local function wrappedOnHit(handle: any, hitInfo: any)
				if def.onHit then
					def.onHit(handle, hitInfo)
				end
				if not handle:IsAlive() then
					reportLanding()
				end
			end

			-- arc 완료 onMiss: def.onMiss 실행 후 보고
			local function wrappedOnMiss(handle: any)
				if def.onMiss then
					def.onMiss(handle)
				end
				reportLanding()
			end

			EntityPlayer.PlayDirect({
				part      = hrp,
				origin    = adjustedOrigin,
				move      = def.move,
				onSpawn   = EntityUtils.Sequence({
					EntityUtils.AnchorPart(),
					def.onSpawn or function(_h: any) end,
				}),
				hitDetect = def.hitDetect or nil,
				onHit     = def.hitDetect and wrappedOnHit or nil,
				onMiss    = wrappedOnMiss,
				params    = params,
			})
		end)
	)
end

function HRPMoveClient.Destroy(self: any)
	self._maid:Destroy()
end

return HRPMoveClient
