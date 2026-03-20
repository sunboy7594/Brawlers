--!strict
--[=[
	@class AbilityEffectSimulatorService
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AbilityEffectHitDetectionUtil = require("AbilityEffectHitDetectionUtil")
local AbilityEffectReplicationRemoting = require("AbilityEffectReplicationRemoting")
local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local TeamService = require("TeamService")

local RATE_LIMIT_INTERVAL = 0.05
local MAX_ORIGIN_DISTANCE = 200
local MAX_LATENCY = 0.5

local AbilityEffectSimulatorService = {}
AbilityEffectSimulatorService.ServiceName = "AbilityEffectSimulatorService"
AbilityEffectSimulatorService.__index = AbilityEffectSimulatorService

type PendingSim = {
	player: Player,
	def: any,
	origin: CFrame,
	params: { [string]: any }?,
	latency: number,
	elapsed: number,
	onHit: ((hitInfos: { AbilityEffectHitDetectionUtil.HitInfo }) -> ())?,
}

function AbilityEffectSimulatorService.Init(self: any, serviceBag: any)
	self._maid = Maid.new()
	self._teamService = serviceBag:GetService(TeamService)
	self._sims = {} :: { [string]: PendingSim }
	self._lastRegTime = {} :: { [number]: number }
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
		for id, sim in self._sims do
			if sim.player == p then
				self._sims[id] = nil
			end
		end
	end))

	self._maid:GiveTask(
		AbilityEffectReplicationRemoting.Register:Connect(
			function(player, defModuleName, effectName, origin, sentAt, params)
				self:_onRegister(player, defModuleName, effectName, origin, sentAt, params)
			end
		)
	)

	self._maid:GiveTask(RunService.Heartbeat:Connect(function(dt: number)
		self:_tick(dt)
	end))
end

-- ─── onHit 콜백 등록 ─────────────────────────────────────────────────────────

function AbilityEffectSimulatorService:SetPendingOnHit(
	userId: number,
	cb: (hitInfos: { AbilityEffectHitDetectionUtil.HitInfo }) -> ()
)
	self._pendingOnHit[userId] = cb
end

function AbilityEffectSimulatorService:TakePendingOnHit(
	userId: number
): ((hitInfos: { AbilityEffectHitDetectionUtil.HitInfo }) -> ())?
	local cb = self._pendingOnHit[userId]
	self._pendingOnHit[userId] = nil
	return cb
end

-- ─── fake handle 생성 헬퍼 ───────────────────────────────────────────────────

function AbilityEffectSimulatorService:_makeHandle(sim: PendingSim, elapsedOverride: number?): any
	local ts = self._teamService
	return {
		part = nil,
		_moveElapsed = elapsedOverride or sim.elapsed,
		_moveOrigin = sim.origin.Position,
		_moveDir = sim.origin.LookVector,
		_moveStopped = false,
		_fadingOut = false,
		_teamContext = {
			attackerChar = sim.player.Character,
			attackerPlayer = sim.player,
			color = nil,
			isEnemy = function(a: Player, b: Player): boolean
				return ts:IsEnemy(a, b)
			end,
		},
	}
end

-- ─── Register 처리 ───────────────────────────────────────────────────────────

function AbilityEffectSimulatorService:_onRegister(player, defModuleName, effectName, origin, sentAt, params)
	if type(defModuleName) ~= "string" or #defModuleName == 0 then
		return
	end
	if type(effectName) ~= "string" or #effectName == 0 then
		return
	end
	if typeof(origin) ~= "CFrame" then
		return
	end
	if type(sentAt) ~= "number" then
		return
	end
	if params ~= nil and type(params) ~= "table" then
		return
	end

	local now = Workspace:GetServerTimeNow()
	local last = self._lastRegTime[player.UserId] or 0
	if now - last < RATE_LIMIT_INTERVAL then
		return
	end
	self._lastRegTime[player.UserId] = now

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		local dist = ((origin :: CFrame).Position - hrp.Position).Magnitude
		if dist > MAX_ORIGIN_DISTANCE then
			return
		end
	end
	if not char then
		return
	end

	local ok, defs = pcall(require, defModuleName :: string)
	if not ok or type(defs) ~= "table" then
		return
	end
	local def = (defs :: any)[effectName :: string]
	if not def then
		return
	end

	local onHit = self:TakePendingOnHit(player.UserId)
	local latency = math.clamp(now - (sentAt :: number), 0, MAX_LATENCY)
	local projectileId = tostring(player.UserId) .. "_" .. string.format("%.6f", now)

	local sim: PendingSim = {
		player = player,
		def = def,
		origin = origin :: CFrame,
		params = params :: { [string]: any }?,
		latency = latency,
		elapsed = 0,
		onHit = onHit,
	}

	if def.hitDetect and def.move then
		self:_simB(sim)
	end

	self._sims[projectileId] = sim
end

-- ─── SimB ────────────────────────────────────────────────────────────────────

function AbilityEffectSimulatorService:_simB(sim: PendingSim)
	if sim.latency <= 0 then
		return
	end

	local steps = 10
	local stepDt = sim.latency / steps

	for i = 1, steps do
		local t = stepDt * i
		local handle = self:_makeHandle(sim, t)
		local hits = AbilityEffectHitDetectionUtil.Detect(sim.def.hitDetect, t, handle, sim.params)
		if #hits > 0 then
			for id, s in self._sims do
				if s == sim then
					self._sims[id] = nil
					break
				end
			end
			if sim.onHit then
				sim.onHit(hits)
			end
			return
		end
	end
end

-- ─── Heartbeat tick (SimA) ───────────────────────────────────────────────────

function AbilityEffectSimulatorService:_tick(dt: number)
	local toRemove: { string } = {}

	for id, sim in self._sims do
		sim.elapsed += dt

		local char = sim.player.Character
		if not char then
			table.insert(toRemove, id)
			continue
		end

		local handle = self:_makeHandle(sim, sim.elapsed + sim.latency)

		local continues = true
		if sim.def.move then
			continues = sim.def.move(dt, handle, sim.params)
		end

		if sim.def.hitDetect then
			local hits =
				AbilityEffectHitDetectionUtil.Detect(sim.def.hitDetect, handle._moveElapsed, handle, sim.params)
			if #hits > 0 then
				if sim.onHit then
					sim.onHit(hits)
				end
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
