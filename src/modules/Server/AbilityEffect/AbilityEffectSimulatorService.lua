--!strict
--[=[
	@class AbilityEffectSimulatorService

	클라이언트가 Register를 보냈을 때 서버가 독립적으로 투사체를 시뮬하여 판정하는 서비스. (Server)

	흐름:
	  Register 수신
	    → latency = GetServerTimeNow() - sentAt 계산
	    → SimB (Spherecast): origin → origin + dir * latency * speed 구간 스직 스요
	       히트 감지 시 SimA 취소 + 즉시 판정
	    → SimA (Heartbeat 루프): 보정된 위치부터 시뮬
	       hitDetect 판정 → onHit callback 실행 → BasicAttackService로 데미지 전달

	  InstantHit(지연 0 아닐)도 포함:
	    delay가 있는 판정은 sentAt 기준으로 latency를 차감합니다.

	로딩 부하:
	  서버 Heartbeat에서 투사체가 활성인 동안 매 틱 실행.
	  maxRange/speed 반영한 수명 제한으로 자동 만료.
]=]

local require = require(script.Parent.loader).load(script)

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

local AbilityEffectHitDetectionUtil    = require("AbilityEffectHitDetectionUtil")
local AbilityEffectReplicationRemoting = require("AbilityEffectReplicationRemoting")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local TeamService = require("TeamService")

local RATE_LIMIT_INTERVAL  = 0.05
local MAX_ORIGIN_DISTANCE  = 200
local MAX_LATENCY          = 0.5   -- 이 이상이면 latency 보정 안 함

local AbilityEffectSimulatorService = {}
AbilityEffectSimulatorService.ServiceName = "AbilityEffectSimulatorService"
AbilityEffectSimulatorService.__index = AbilityEffectSimulatorService

type PendingSim = {
	player      : Player,
	def         : any,
	origin      : CFrame,
	params      : { [string]: any }?,
	latency     : number,
	elapsed     : number,
	onHit       : ((hitInfos: { AbilityEffectHitDetectionUtil.HitInfo }) -> ())?,
}

function AbilityEffectSimulatorService.Init(self: any, serviceBag: any)
	self._maid        = Maid.new()
	self._teamService = serviceBag:GetService(TeamService)
	self._sims        = {} :: { [string]: PendingSim }   -- projectileId -> PendingSim
	self._lastRegTime = {} :: { [number]: number }
	-- onHit 콜백 등록테이블: userId -> callback
	self._pendingOnHit = {} :: { [number]: (hitInfos: { AbilityEffectHitDetectionUtil.HitInfo }) -> () }
end

function AbilityEffectSimulatorService.Start(self: any)
	for _, player in Players:GetPlayers() do
		self._lastRegTime[player.UserId] = 0
	end
	self._maid:GiveTask(Players.PlayerAdded:Connect(function(p)
		self._lastRegTime[p.UserId] = 0
	end))
	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(p)
		self._lastRegTime[p.UserId] = nil
		self._pendingOnHit[p.UserId] = nil
		-- 해당 플레이어의 시뮬 제거
		for id, sim in self._sims do
			if sim.player == p then
				self._sims[id] = nil
			end
		end
	end))

	-- Register 수신
	self._maid:GiveTask(
		AbilityEffectReplicationRemoting.Register:Connect(function(
			player        : Player,
			defModuleName : unknown,
			effectName    : unknown,
			origin        : unknown,
			sentAt        : unknown,
			params        : unknown
		)
			self:_onRegister(player, defModuleName, effectName, origin, sentAt, params)
		end)
	)

	-- Heartbeat: 활성 시뮬 진행
	self._maid:GiveTask(RunService.Heartbeat:Connect(function(dt: number)
		self:_tick(dt)
	end))
end

-- ─── onHit 콜백 등록 (BasicAttackService가 호출) ─────────────────────────────

function AbilityEffectSimulatorService:SetPendingOnHit(
	userId : number,
	cb     : (hitInfos: { AbilityEffectHitDetectionUtil.HitInfo }) -> ()
)
	self._pendingOnHit[userId] = cb
end

function AbilityEffectSimulatorService:TakePendingOnHit(
	userId : number
): ((hitInfos: { AbilityEffectHitDetectionUtil.HitInfo }) -> ())?
	local cb = self._pendingOnHit[userId]
	self._pendingOnHit[userId] = nil
	return cb
end

-- ─── Register 처리 ──────────────────────────────────────────────────────────────────────

function AbilityEffectSimulatorService:_onRegister(
	player        : Player,
	defModuleName : unknown,
	effectName    : unknown,
	origin        : unknown,
	sentAt        : unknown,
	params        : unknown
)
	if type(defModuleName) ~= "string" or #defModuleName == 0 then return end
	if type(effectName) ~= "string"    or #effectName == 0    then return end
	if typeof(origin) ~= "CFrame"  then return end
	if type(sentAt)   ~= "number"  then return end
	if params ~= nil and type(params) ~= "table" then return end

	-- rate limit
	local now = Workspace:GetServerTimeNow()
	local last = self._lastRegTime[player.UserId] or 0
	if now - last < RATE_LIMIT_INTERVAL then return end
	self._lastRegTime[player.UserId] = now

	-- origin 거리 검증
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		local dist = ((origin :: CFrame).Position - hrp.Position).Magnitude
		if dist > MAX_ORIGIN_DISTANCE then return end
	end
	if not char then return end

	-- DefModule 로드
	local ok, defs = pcall(require, defModuleName :: string)
	if not ok or type(defs) ~= "table" then return end
	local def = (defs :: any)[effectName :: string]
	if not def then return end

	-- onHit 콜백 픽업
	local onHit = self:TakePendingOnHit(player.UserId)

	local latency = math.clamp(now - (sentAt :: number), 0, MAX_LATENCY)

	-- 프로제트일 ID 생성
	local projectileId = tostring(player.UserId) .. "_" .. string.format("%.6f", now)

	local sim: PendingSim = {
		player  = player,
		def     = def,
		origin  = origin :: CFrame,
		params  = params :: { [string]: any }?,
		latency = latency,
		elapsed = 0,
		onHit   = onHit,
	}

	-- SimB: latency 구간 스직 코스트
	-- hitDetect가 있으면 수행
	if def.hitDetect and def.move then
		self:_simB(sim)
	end

	self._sims[projectileId] = sim
end

-- ─── SimB: latency 구간 한 번만 판정 ─────────────────────────────────────────

function AbilityEffectSimulatorService:_simB(sim: PendingSim)
	if sim.latency <= 0 then return end

	-- move가 Linear일 경우 Spherecast로 빠르게 스요
	-- (그 외 move는 현재 Heartbeat tick 단위로 처리)
	local def = sim.def
	local origin = sim.origin

	-- 모의 handle 객체 (직접 HitDetect 호출용)
	local handle = {
		part         = nil,
		_moveElapsed = 0,
		_moveOrigin  = origin.Position,
		_moveDir     = origin.LookVector,
		_moveStopped = false,
		_fadingOut   = false,
	}

	-- latency 구간 스커닝 (10틱 스탭)
	local steps = 10
	local stepDt = sim.latency / steps
	for i = 1, steps do
		local t = stepDt * i
		-- hitDetect 직접 실행
		local char = sim.player.Character
		local attackerPlayer = sim.player
		local hits = AbilityEffectHitDetectionUtil.Detect(
			def.hitDetect,
			t,
			handle,
			sim.params,
			char,
			self._teamService,
			attackerPlayer
		)
		if #hits > 0 then
			-- SimB 히트: 연관된 sim를 제거 (SimA 취소)
			for id, s in self._sims do
				if s == sim then
					self._sims[id] = nil
					break
				end
			end
			if sim.onHit then sim.onHit(hits) end
			return
		end
	end
end

-- ─── Heartbeat tick (SimA) ─────────────────────────────────────────────────────

function AbilityEffectSimulatorService:_tick(dt: number)
	local toRemove: { string } = {}

	for id, sim in self._sims do
		sim.elapsed += dt

		local def = sim.def
		local char = sim.player.Character
		if not char then
			table.insert(toRemove, id)
			continue
		end

		-- 모의 handle
		local handle = {
			part         = nil,
			_moveElapsed = sim.elapsed + sim.latency,   -- latency만큼 앞서
			_moveOrigin  = sim.origin.Position,
			_moveDir     = sim.origin.LookVector,
			_moveStopped = false,
			_fadingOut   = false,
		}

		-- move 실행 (순수 위치 계산, 모델 없음)
		local continues = true
		if def.move then
			continues = def.move(dt, handle, sim.params)
		end

		-- hitDetect
		if def.hitDetect then
			local hits = AbilityEffectHitDetectionUtil.Detect(
				def.hitDetect,
				handle._moveElapsed,
				handle,
				sim.params,
				char,
				self._teamService,
				sim.player
			)
			if #hits > 0 then
				if sim.onHit then sim.onHit(hits) end
				table.insert(toRemove, id)
				continue
			end
		end

		if not continues then
			table.insert(toRemove, id)
		end
	end

	for _, id in toRemove do
		self._sims[id] = nil
	end
end

function AbilityEffectSimulatorService.Destroy(self: any)
	self._maid:Destroy()
end

return AbilityEffectSimulatorService
