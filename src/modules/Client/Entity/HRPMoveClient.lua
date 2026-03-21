--!strict
--[=[
	@class HRPMoveClient

	HRPMoveRemoting.Move 수신 → 로컬 클라이언트에서 HRP arc 이동 실행.

	보안 구조:
	  - 서버가 발급한 token이 있어야만 이동 실행
	  - token은 1회용 (수신 즉시 소비)
	  - 이동 완료(arc 종료 또는 Floor 착지) 시 LandingReport:FireServer
	  - 서버가 최종 위치 검증 후 오차 초과 시 강제 보정

	클라이언트 측 findActualLanding:
	  - 서버에서 direction/speed/distance/height만 전달
	  - 클라이언트가 현재 HRP 위치 기준으로 직접 계산
	  - 벽 두께 (순방향/역방향 Ray)
	  - 벽 높이 (수직 Ray) → 넘을 수 있는 최소 높이 보장
	  - snap 없음 (origin PivotTo 불필요)
]=]

local require = require(script.Parent.loader).load(script)

local Players  = game:GetService("Players")
local workspace = game:GetService("Workspace")

local EntityPlayer    = require("EntityPlayer")
local EntityUtils     = require("EntityUtils")
local HRPMoveRemoting = require("HRPMoveRemoting")
local Maid            = require("Maid")

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local MAX_EXTRA_DISTANCE = 5  -- 역방향 Ray 탐색 여유 거리

-- ─── 착지점 계산 (클라이언트) ────────────────────────────────────────────────
--[=[
	현재 HRP 위치 기준으로 실제 착지 거리/높이를 계산합니다.

	흐름:
	  1. 순방향 Ray: 벽 앞면 감지
	     안 맞음 → 원래 distance/height 그대로
	     맞음 →
	  2. 역방향 Ray: 벽 뒷면 위치 파악
	     얇은 벽 (wallBackDist > frontDist AND < distance)
	       → 벽 너머 착지 (거리 늘림)
	       → 수직 Ray로 벽 꼭대기 측정 → 높이 보정
	     두꺼운 벽
	       → 코앞 착지 (거리 줄임)
	       → 높이는 거리에 비례
]=]
local function findActualLanding(
	originPos : Vector3,
	dir       : Vector3,
	distance  : number,
	baseHeight: number
): (number, number)  -- (actualDistance, actualHeight)
	local heightRatio = baseHeight / math.max(distance, 0.001)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local char = Players.LocalPlayer.Character
	if char then
		rayParams.FilterDescendantsInstances = { char }
	end

	-- 1. 순방향 Ray
	local forwardRay = workspace:Raycast(originPos, dir * distance, rayParams)
	if not forwardRay then
		return distance, baseHeight
	end

	local frontDist = forwardRay.Distance

	-- 2. 역방향 Ray: 벽 뒷면 위치
	local probePos    = originPos + dir * (distance + MAX_EXTRA_DISTANCE)
	local backwardRay = workspace:Raycast(
		probePos,
		-dir * (distance + MAX_EXTRA_DISTANCE),
		rayParams
	)

	local wallBackDist: number
	if backwardRay then
		wallBackDist = (distance + MAX_EXTRA_DISTANCE) - backwardRay.Distance
	else
		wallBackDist = distance + MAX_EXTRA_DISTANCE
	end

	-- 3. 착지 거리 결정
	local jumpingOver = wallBackDist > frontDist and wallBackDist < distance
	local actualDist: number
	if jumpingOver then
		actualDist = wallBackDist + 1
	else
		actualDist = math.max(frontDist - 1.5, 1)
	end

	-- 4. 높이 결정
	local actualHeight: number
	if jumpingOver then
		-- 벽을 넘어가는 경우: 벽 꼭대기 높이 측정
		local wallHitPos  = originPos + dir * frontDist
		local probeH      = 50
		local topOrigin   = Vector3.new(wallHitPos.X, originPos.Y + probeH, wallHitPos.Z)
		local topRay      = workspace:Raycast(topOrigin, Vector3.new(0, -probeH, 0), rayParams)

		if topRay then
			local wallTopY      = topRay.Position.Y
			local clearance     = (wallTopY - originPos.Y) + 2  -- 벽 위 + 2 studs 여유
			actualHeight = math.max(actualDist * heightRatio, clearance)
		else
			actualHeight = actualDist * heightRatio
		end
	else
		-- 코앞 착지: 거리 비례 높이
		actualHeight = actualDist * heightRatio
	end

	return actualDist, actualHeight
end

-- ─── 서비스 ──────────────────────────────────────────────────────────────────

local HRPMoveClient = {}
HRPMoveClient.ServiceName = "HRPMoveClient"
HRPMoveClient.__index = HRPMoveClient

function HRPMoveClient.Init(self: any, _serviceBag: any)
	self._maid = Maid.new()
end

function HRPMoveClient.Start(self: any)
	self._maid:GiveTask(
		HRPMoveRemoting.Move:Connect(function(
			token      : string,
			defModule  : string,
			defName    : string,
			direction  : Vector3,
			speed      : number,
			distance   : number,
			height     : number,
			extraParams: { [string]: any }?
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

			-- 현재 HRP 위치 기준으로 findActualLanding 직접 계산
			-- snap 없음 (PivotTo(origin) 불필요)
			local currentPos            = hrp:GetPivot().Position
			local dir                   = direction.Unit
			local actualDist, actualH   = findActualLanding(currentPos, dir, distance, height)
			local adjustedOrigin        = CFrame.new(currentPos, currentPos + dir)

			-- params 구성 (actualDistance, actualHeight + extraParams 병합)
			local params: { [string]: any } = {
				actualDistance = actualDist,
				actualHeight   = actualH,
			}
			if extraParams then
				for k, v in extraParams do
					params[k] = v
				end
			end

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
			local function wrappedOnHit(handle: any, hitInfo: any)
				if def.onHit then def.onHit(handle, hitInfo) end
				if not handle:IsAlive() then reportLanding() end
			end

			-- arc 완료 onMiss: 보고
			local function wrappedOnMiss(handle: any)
				if def.onMiss then def.onMiss(handle) end
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
