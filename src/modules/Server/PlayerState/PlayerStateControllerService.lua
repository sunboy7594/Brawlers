--!strict
--[=[
	@class PlayerStateControllerService

	플레이어 상태 효과(Effect)를 통합 관리하는 서버 서비스.

	담당:
	- Play             : 단발 effect 적용
	- PlayRepeat       : 동일 effect를 일정 간격으로 반복 적용
	- Stop             : instanceId로 특정 effect 제거
	- StopAll          : 전체 또는 force=false 한정 effect 제거
	- GetActiveEffects : 대상의 현재 effect 목록 열람
	- HasEffect        : 대상에 특정 componentType 존재 여부 확인

	보호 처리:
	- 대상에 ignoreCC 활성     → force=false effect의 cc계열 component 무시
	- 대상에 ignoreDamage 활성 → force=false effect의 damage component 무시
	- effect.force=true        → 위 두 경우 모두 뚫고 강제 적용
	cc계열: slow, moveLock, attackLock, knockback, cameraLock

	클라이언트 통보:
	- effect 적용 시 EffectApplied:FireClient(target, effectDef, payloadId)
	- effect 조기 제거 시 EffectRemoved:FireClient(target, payloadId)
	- 클라이언트는 payloadId로 루프 연출 조기 종료 매핑
]=]

local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BasicMovementService = require("BasicMovementService")
local HpService = require("HpService")
local Maid = require("Maid")
local PlayerStateDefs = require("PlayerStateDefs")
local PlayerStateRemoting = require("PlayerStateRemoting")
local ServiceBag = require("ServiceBag")

local CC_TYPES = PlayerStateDefs.CC_TYPES
local ComponentType = PlayerStateDefs.ComponentType

-- ─── 내부 타입 ───────────────────────────────────────────────────────────────

type EffectInstance = {
	instanceId: string,
	effectDef: PlayerStateDefs.EffectDef,
	component: PlayerStateDefs.Component,
	payloadId: string,
	expiresAt: number?,
}

type PlayerRuntime = {
	effects: { EffectInstance },
	isMoveLocked: boolean,
	isAttackLocked: boolean,
	isIgnoreCC: boolean,
	isIgnoreDamage: boolean,
	slowMultiplier: number,
	receiveDamageMult: number,
	dealDamageMult: number,
	humanoid: Humanoid?,
	rootPart: BasePart?,
}

export type PlayerStateControllerService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_movementService: any,
		_hpService: any,
		_runtimes: { [number]: PlayerRuntime },
		_playerMaids: { [number]: any },
		_idCounter: number,
	},
	{} :: typeof({ __index = {} })
))

-- ─── 서비스 ──────────────────────────────────────────────────────────────────

local PlayerStateControllerService = {}
PlayerStateControllerService.ServiceName = "PlayerStateControllerService"
PlayerStateControllerService.__index = PlayerStateControllerService

function PlayerStateControllerService.Init(self: PlayerStateControllerService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._movementService = serviceBag:GetService(BasicMovementService)
	self._hpService = serviceBag:GetService(HpService)
	self._runtimes = {}
	self._playerMaids = {}
	self._idCounter = 0
end

function PlayerStateControllerService.Start(self: PlayerStateControllerService): ()
	for _, player in Players:GetPlayers() do
		self:_onPlayerAdded(player)
	end
	self._maid:GiveTask(Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end))
	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end))
	self._maid:GiveTask(RunService.Heartbeat:Connect(function(dt)
		self:_onHeartbeat(dt)
	end))
end

-- ─── 플레이어 라이프사이클 ────────────────────────────────────────────────────

function PlayerStateControllerService:_onPlayerAdded(player: Player)
	local pMaid = Maid.new()
	self._playerMaids[player.UserId] = pMaid

	local runtime: PlayerRuntime = {
		effects = {},
		isMoveLocked = false,
		isAttackLocked = false,
		isIgnoreCC = false,
		isIgnoreDamage = false,
		slowMultiplier = 1.0,
		receiveDamageMult = 1.0,
		dealDamageMult = 1.0,
		humanoid = nil,
		rootPart = nil,
	}
	self._runtimes[player.UserId] = runtime

	local function onCharacterAdded(char: Model)
		local humanoid = char:WaitForChild("Humanoid") :: Humanoid
		local rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart
		runtime.humanoid = humanoid
		runtime.rootPart = rootPart
		self:_clearAllEffects(player, runtime)
		pMaid:GiveTask(humanoid.Died:Connect(function()
			self:_clearAllEffects(player, runtime)
			runtime.humanoid = nil
			runtime.rootPart = nil
		end))
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end
	pMaid:GiveTask(player.CharacterAdded:Connect(onCharacterAdded))
end

function PlayerStateControllerService:_onPlayerRemoving(player: Player)
	local runtime = self._runtimes[player.UserId]
	if runtime then
		self:_clearAllEffects(player, runtime)
	end
	self._runtimes[player.UserId] = nil
	local pMaid = self._playerMaids[player.UserId]
	if pMaid then
		pMaid:Destroy()
		self._playerMaids[player.UserId] = nil
	end
end

-- ─── Heartbeat ───────────────────────────────────────────────────────────────

function PlayerStateControllerService:_onHeartbeat(_dt: number)
	local now = os.clock()
	for userId, runtime in self._runtimes do
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			continue
		end
		local dirty = false
		local expiredPayloads: { [string]: boolean } = {}
		local i = 1
		while i <= #runtime.effects do
			local inst = runtime.effects[i]
			if inst.expiresAt and now >= inst.expiresAt then
				expiredPayloads[inst.payloadId] = true
				table.remove(runtime.effects, i)
				dirty = true
			else
				i += 1
			end
		end
		for pid in expiredPayloads do
			local hasMore = false
			for _, inst in runtime.effects do
				if inst.payloadId == pid then
					hasMore = true
					break
				end
			end
			if not hasMore then
				PlayerStateRemoting.EffectRemoved:FireClient(player, pid)
			end
		end
		if dirty then
			self:_rebuildCache(runtime)
			self:_syncMovement(player, runtime)
		end
	end
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	단발 effect를 즉시 적용합니다.
	@return string payloadId (Stop 호출 시 사용)
]=]
function PlayerStateControllerService:Play(target: Player, effectDef: PlayerStateDefs.EffectDef): string
	local runtime = self._runtimes[target.UserId]
	if not runtime then
		return ""
	end
	local payloadId = self:_generateId()
	self:_applyEffectDef(target, runtime, effectDef, payloadId)
	return payloadId
end

--[=[
	동일 effect를 일정 간격으로 count회 반복 적용합니다.
	interval = totalDuration / count 자동 계산.
	@return () -> ()  취소 함수
]=]
function PlayerStateControllerService:PlayRepeat(
	target: Player,
	effectDef: PlayerStateDefs.EffectDef,
	totalDuration: number,
	count: number
): () -> ()
	local interval = totalDuration / count
	local fired = 0
	local cancelled = false

	local function tick()
		if cancelled then
			return
		end
		local runtime = self._runtimes[target.UserId]
		if not runtime then
			return
		end
		local payloadId = self:_generateId()
		self:_applyEffectDef(target, runtime, effectDef, payloadId)
		fired += 1
		if fired < count then
			task.delay(interval, tick)
		end
	end

	task.delay(0, tick)

	return function()
		cancelled = true
	end
end

--[=[
	instanceId로 특정 effect를 제거합니다.
]=]
function PlayerStateControllerService:Stop(target: Player, instanceId: string)
	local runtime = self._runtimes[target.UserId]
	if not runtime then
		return
	end
	local payloadId: string? = nil
	for _, inst in runtime.effects do
		if inst.instanceId == instanceId then
			payloadId = inst.payloadId
			break
		end
	end
	self:_removeEffectInstance(runtime, instanceId)
	if payloadId then
		local hasMore = false
		for _, inst in runtime.effects do
			if inst.payloadId == payloadId then
				hasMore = true
				break
			end
		end
		if not hasMore then
			PlayerStateRemoting.EffectRemoved:FireClient(target, payloadId)
		end
	end
	self:_rebuildCache(runtime)
	self:_syncMovement(target, runtime)
end

--[=[
	대상의 effect를 제거합니다.
	includeForced = nil 또는 true  → force=true 포함 전부 제거
	includeForced = false          → force=false인 것만 제거 (cleanse 동작)
]=]
function PlayerStateControllerService:StopAll(target: Player, includeForced: boolean?)
	local runtime = self._runtimes[target.UserId]
	if not runtime then
		return
	end

	local removedPayloads: { [string]: boolean } = {}
	local toRemove: { EffectInstance } = {}

	for _, inst in runtime.effects do
		if includeForced == false then
			if not inst.effectDef.force then
				table.insert(toRemove, inst)
				removedPayloads[inst.payloadId] = true
			end
		else
			table.insert(toRemove, inst)
			removedPayloads[inst.payloadId] = true
		end
	end

	for _, inst in toRemove do
		self:_removeEffectInstance(runtime, inst.instanceId)
	end
	for pid in removedPayloads do
		PlayerStateRemoting.EffectRemoved:FireClient(target, pid)
	end
	self:_rebuildCache(runtime)
	self:_syncMovement(target, runtime)
end

--[=[
	대상에게 현재 적용 중인 모든 effect 목록을 반환합니다.
	@return { PlayerStateDefs.ActiveEffectView }
]=]
function PlayerStateControllerService:GetActiveEffects(target: Player): { PlayerStateDefs.ActiveEffectView }
	local runtime = self._runtimes[target.UserId]
	if not runtime then
		return {}
	end

	local now = os.clock()
	local result: { PlayerStateDefs.ActiveEffectView } = {}
	for _, inst in runtime.effects do
		local c = inst.component :: any
		table.insert(result, {
			instanceId = inst.instanceId,
			componentType = c.type,
			expiresAt = inst.expiresAt,
			remaining = if inst.expiresAt then math.max(0, inst.expiresAt - now) else nil,
			effectDef = inst.effectDef,
		})
	end
	return result
end

--[=[
	대상에게 특정 componentType의 effect가 존재하는지 확인합니다.
	@param componentType PlayerStateDefs.ComponentType 값 (예: "moveLock", "slow")
]=]
function PlayerStateControllerService:HasEffect(target: Player, componentType: string): boolean
	local runtime = self._runtimes[target.UserId]
	if not runtime then
		return false
	end
	for _, inst in runtime.effects do
		local c = inst.component :: any
		if c.type == componentType then
			return true
		end
	end
	return false
end

--[=[
	대미지 수신 배율을 반환합니다. (기본 1.0)
]=]
function PlayerStateControllerService:GetReceiveDamageMult(target: Player): number
	local runtime = self._runtimes[target.UserId]
	return if runtime then runtime.receiveDamageMult else 1.0
end

--[=[
	대미지 딜 배율을 반환합니다. (기본 1.0)
]=]
function PlayerStateControllerService:GetDealDamageMult(player: Player): number
	local runtime = self._runtimes[player.UserId]
	return if runtime then runtime.dealDamageMult else 1.0
end

--[=[
	공격 잠금 여부를 반환합니다.
]=]
function PlayerStateControllerService:IsAttackLocked(player: Player): boolean
	local runtime = self._runtimes[player.UserId]
	return if runtime then runtime.isAttackLocked else false
end

-- ─── 내부: Effect 적용 ────────────────────────────────────────────────────────

function PlayerStateControllerService:_applyEffectDef(
	target: Player,
	runtime: PlayerRuntime,
	effectDef: PlayerStateDefs.EffectDef,
	payloadId: string
)
	local components = effectDef.components
	local force = effectDef.force == true
	if components then
		for _, comp in components do
			local c = comp :: any
			if not force then
				if runtime.isIgnoreDamage and c.type == ComponentType.Damage then
					continue
				end
				if runtime.isIgnoreCC and CC_TYPES[c.type] then
					continue
				end
			end
			if c.type == ComponentType.Cleanse then
				self:StopAll(target, false)
			elseif c.type == ComponentType.Knockback then
				self:_applyKnockback(runtime, c)
			elseif c.type == ComponentType.Damage then
				self:_applyDamage(target, runtime, effectDef, c)
			else
				self:_registerInstance(runtime, effectDef, comp, payloadId)
			end
		end
	end
	self:_rebuildCache(runtime)
	self:_syncMovement(target, runtime)
	PlayerStateRemoting.EffectApplied:FireClient(target, effectDef, payloadId)
end

function PlayerStateControllerService:_generateId(): string
	self._idCounter += 1
	return "ps_" .. tostring(self._idCounter)
end

function PlayerStateControllerService:_registerInstance(
	runtime: PlayerRuntime,
	effectDef: PlayerStateDefs.EffectDef,
	comp: PlayerStateDefs.Component,
	payloadId: string
): string
	local c = comp :: any
	local instanceId = self:_generateId()
	local inst: EffectInstance = {
		instanceId = instanceId,
		effectDef = effectDef,
		component = comp,
		payloadId = payloadId,
		expiresAt = if c.duration then os.clock() + c.duration else nil,
	}
	table.insert(runtime.effects, inst)
	return instanceId
end

--[=[
	대미지 component 처리.
	multiplier 계산을 여기서 완료한 뒤 최종 값을 HpService에 위임.
	effectDef.source를 함께 전달하여 HpService에서 팀 체크 수행.
]=]
function PlayerStateControllerService:_applyDamage(
	target: Player,
	runtime: PlayerRuntime,
	effectDef: PlayerStateDefs.EffectDef,
	comp: any
)
	local amount = comp.amount * runtime.receiveDamageMult
	if effectDef.source then
		local sourceRuntime = self._runtimes[effectDef.source.UserId]
		if sourceRuntime then
			amount *= sourceRuntime.dealDamageMult
		end
	end

	if amount <= 0 then
		return
	end

	self._hpService:ApplyDamage(target, amount, effectDef.source)
	self:_checkVulnerable(target, runtime, effectDef)
end

function PlayerStateControllerService:_applyKnockback(runtime: PlayerRuntime, comp: any)
	local rootPart = runtime.rootPart
	if not rootPart then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = rootPart
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = attachment
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.VectorVelocity = (comp.direction :: Vector3).Unit * (comp.force :: number)
	lv.MaxForce = math.huge
	lv.Parent = rootPart
	task.delay(0.08, function()
		lv:Destroy()
		attachment:Destroy()
	end)
end

function PlayerStateControllerService:_checkVulnerable(
	target: Player,
	runtime: PlayerRuntime,
	incomingDef: PlayerStateDefs.EffectDef
)
	for _, inst in runtime.effects do
		local c = inst.component :: any
		if c.type ~= ComponentType.Vulnerable or not c.onHit then
			continue
		end
		local onHitDef = c.onHit :: PlayerStateDefs.EffectDef
		if incomingDef.source and not onHitDef.source then
			(onHitDef :: any).source = incomingDef.source
		end
		self:_applyEffectDef(target, runtime, onHitDef, self:_generateId())
	end
end

function PlayerStateControllerService:_rebuildCache(runtime: PlayerRuntime)
	local isMoveLocked, isAttackLocked, isIgnoreCC, isIgnoreDamage = false, false, false, false
	local slowMult, receiveMult, dealMult = 1.0, 1.0, 1.0
	for _, inst in runtime.effects do
		local c = inst.component :: any
		if c.type == ComponentType.MoveLock then
			isMoveLocked = true
		elseif c.type == ComponentType.AttackLock then
			isAttackLocked = true
		elseif c.type == ComponentType.IgnoreCC then
			isIgnoreCC = true
		elseif c.type == ComponentType.IgnoreDamage then
			isIgnoreDamage = true
		elseif c.type == ComponentType.Slow then
			slowMult *= c.multiplier
		elseif c.type == ComponentType.ReceiveDamageMult then
			receiveMult *= c.multiplier
		elseif c.type == ComponentType.DealDamageMult then
			dealMult *= c.multiplier
		end
	end
	runtime.isMoveLocked = isMoveLocked
	runtime.isAttackLocked = isAttackLocked
	runtime.isIgnoreCC = isIgnoreCC
	runtime.isIgnoreDamage = isIgnoreDamage
	runtime.slowMultiplier = slowMult
	runtime.receiveDamageMult = receiveMult
	runtime.dealDamageMult = dealMult
end

function PlayerStateControllerService:_syncMovement(target: Player, runtime: PlayerRuntime)
	local ms = self._movementService
	if not ms then
		return
	end
	if runtime.isMoveLocked then
		ms:SetMovementLocked(target, true)
	else
		ms:SetMovementLocked(target, false)
		if ms.SetSpeedMultiplier then
			ms:SetSpeedMultiplier(target, runtime.slowMultiplier)
		end
	end
end

function PlayerStateControllerService:_removeEffectInstance(runtime: PlayerRuntime, instanceId: string)
	for i, inst in runtime.effects do
		if inst.instanceId == instanceId then
			table.remove(runtime.effects, i)
			return
		end
	end
end

function PlayerStateControllerService:_clearAllEffects(target: Player, runtime: PlayerRuntime)
	local sentPayloads: { [string]: boolean } = {}
	for _, inst in runtime.effects do
		if not sentPayloads[inst.payloadId] then
			sentPayloads[inst.payloadId] = true
			PlayerStateRemoting.EffectRemoved:FireClient(target, inst.payloadId)
		end
	end
	table.clear(runtime.effects)
	self:_rebuildCache(runtime)
	self:_syncMovement(target, runtime)
end

function PlayerStateControllerService.Destroy(self: PlayerStateControllerService)
	self._maid:Destroy()
end

return PlayerStateControllerService
