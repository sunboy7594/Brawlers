--!strict
--[=[
	@class PlayerStateControllerService

	플레이어 상태 효과(Effect)를 통합 관리하는 서버 서비스.

	담당:
	- Play             : 단발 effect 적용
	- PlayRepeat       : effect를 일정 간격으로 반복 적용 (instance 1개 생성)
	- StopAll          : 전체 또는 force=false 한정 effect 제거
	- GetActiveEffects : 대상의 현재 effect 목록 열람 (instance 단위)
	- GetActiveTags    : 현재 활성 tag 목록 열람
	- HasEffect        : 대상에 특정 componentType 존재 여부 확인
	- HasTag           : 대상에 특정 tag 존재 여부 확인
	- IsAbilityLocked  : 특정 어빌리티 타입 잠금 여부 확인

	내부 구조:
	  runtime.effects: { [id]: EffectInstance } 딕셔너리
	  EffectInstance: id + effectDef + components(ComponentState) + tags(TagState) + repeatState?
	  damage 포함 모든 component를 ComponentState로 저장
	  (damage/knockback/cleanse/resourceDelta는 즉시 처리 후 expiresAt = 생성시각으로 표시)

	클라이언트 통보:
	  effect 적용 시 EffectApplied:FireClient(target, effectDef, id)
	  repeat의 경우 tag duration을 totalDuration으로 확장한 displayDef 전송
	  effect 만료/취소 시 EffectRemoved:FireClient(target, id)

	공개 Signal:
	  ResourceDeltaApplied  : (target: Player, amount: number)
	    → resourceDelta component 즉시 처리 시 발동. BasicAttackService가 구독.
	  EffectiveMultipliersChanged : (target: Player)
	    → reloadRateMult/regenRateMult 변경 시 발동. BasicAttackService가 ResourceSync 재발송.
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
local Signal = require("Signal")

local CC_TYPES = PlayerStateDefs.CC_TYPES
local ComponentType = PlayerStateDefs.ComponentType

-- ─── 내부 타입 ───────────────────────────────────────────────────────────────

type ComponentState = PlayerStateDefs.ComponentState
type TagState = PlayerStateDefs.TagState

type RepeatStateInternal = {
	totalDuration: number,
	count: number,
	interval: number,
	fired: number,
	startedAt: number,
	expiresAt: number,
	cancelled: boolean,
}

type EffectInstance = {
	id: string,
	effectDef: PlayerStateDefs.EffectDef,
	components: { ComponentState },
	tags: { TagState },
	startedAt: number,
	sentApplied: boolean,
	repeatState: RepeatStateInternal?,
}

type PlayerRuntime = {
	effects: { [string]: EffectInstance },
	isMoveLocked: boolean,
	-- lockedAbilityTypes: nil=잠금없음, { ["*"]=true }=전부잠금, { ["BasicAttack"]=true, ... }=선택잠금
	lockedAbilityTypes: { [string]: boolean }?,
	isIgnoreCC: boolean,
	isIgnoreDamage: boolean,
	walkSpeedMult: number,
	receiveDamageMult: number,
	dealDamageMult: number,
	reloadRateMult: number,
	regenRateMult: number,
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
		ResourceDeltaApplied: any,
		EffectiveMultipliersChanged: any,
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
	self.ResourceDeltaApplied = self._maid:GiveTask(Signal.new())
	self.EffectiveMultipliersChanged = self._maid:GiveTask(Signal.new())
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
		lockedAbilityTypes = nil,
		isIgnoreCC = false,
		isIgnoreDamage = false,
		walkSpeedMult = 1.0,
		receiveDamageMult = 1.0,
		dealDamageMult = 1.0,
		reloadRateMult = 1.0,
		regenRateMult = 1.0,
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

		for _, part in char:GetDescendants() do
			if part:IsA("BasePart") then
				part.CollisionGroup = "Characters"
			end
		end
		pMaid:GiveTask(char.DescendantAdded:Connect(function(desc)
			if desc:IsA("BasePart") then
				desc.CollisionGroup = "Characters"
			end
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
		local toRemove: { string } = {}

		for id, instance in runtime.effects do
			if instance.repeatState then
				local rs = instance.repeatState

				if rs.cancelled or now >= rs.expiresAt then
					table.insert(toRemove, id)
					continue
				end

				local nextFireAt = rs.startedAt + rs.fired * rs.interval
				while rs.fired < rs.count and now >= nextFireAt do
					self:_fireRepeatTick(player, runtime, instance)
					rs.fired += 1
					dirty = true
					nextFireAt = rs.startedAt + rs.fired * rs.interval
				end
			else
				if self:_isInstanceExpired(instance, now) then
					table.insert(toRemove, id)
				end
			end
		end

		for _, id in toRemove do
			local instance = runtime.effects[id]
			if instance and instance.sentApplied then
				PlayerStateRemoting.EffectRemoved:FireClient(player, id)
			end
			runtime.effects[id] = nil
			dirty = true
		end

		if dirty then
			self:_rebuildCache(runtime, player)
			self:_syncMovement(player, runtime)
		end
	end
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	단발 effect를 즉시 적용합니다.
	@return string id
]=]
function PlayerStateControllerService:Play(target: Player, effectDef: PlayerStateDefs.EffectDef): string
	local runtime = self._runtimes[target.UserId]
	if not runtime then
		return ""
	end

	local id = self:_generateId()
	local now = os.clock()

	local instance = self:_createInstance(id, effectDef, runtime, now, nil)

	-- cleanse 먼저 처리 (인스턴스 추가 전)
	for _, cs in instance.components do
		if (cs.component :: any).type == ComponentType.Cleanse then
			self:StopAll(target, false)
			break
		end
	end

	runtime.effects[id] = instance

	-- 즉시 처리 컴포넌트 실행
	for _, cs in instance.components do
		local c = cs.component :: any
		if c.type == ComponentType.Damage then
			self:_applyDamage(target, runtime, effectDef, c)
		elseif c.type == ComponentType.Knockback then
			self:_applyKnockback(runtime, c)
		elseif c.type == ComponentType.ResourceDelta then
			self.ResourceDeltaApplied:Fire(target, c.amount)
		end
	end

	self:_rebuildCache(runtime, target)
	self:_syncMovement(target, runtime)

	if effectDef.tags and #effectDef.tags > 0 then
		PlayerStateRemoting.EffectApplied:FireClient(target, effectDef, id)
		instance.sentApplied = true
	end

	return id
end

--[=[
	effect를 일정 간격으로 count회 반복 적용합니다.
	interval = totalDuration / count 자동 계산.
	instance 1개 생성. Heartbeat에서 tick 관리.
	@return () -> ()  취소 함수
]=]
function PlayerStateControllerService:PlayRepeat(
	target: Player,
	effectDef: PlayerStateDefs.EffectDef,
	totalDuration: number,
	count: number
): () -> ()
	local runtime = self._runtimes[target.UserId]
	if not runtime then
		return function() end
	end

	local id = self:_generateId()
	local now = os.clock()
	local interval = totalDuration / count

	local repeatState: RepeatStateInternal = {
		totalDuration = totalDuration,
		count = count,
		interval = interval,
		fired = 0,
		startedAt = now,
		expiresAt = now + totalDuration,
		cancelled = false,
	}

	local instance = self:_createInstance(id, effectDef, runtime, now, repeatState)

	for _, cs in instance.components do
		local c = cs.component :: any
		if c.type == ComponentType.Cleanse then
			self:StopAll(target, false)
			break
		end
	end

	runtime.effects[id] = instance
	self:_fireRepeatTick(target, runtime, instance)
	repeatState.fired = 1

	self:_rebuildCache(runtime, target)
	self:_syncMovement(target, runtime)

	if effectDef.tags and #effectDef.tags > 0 then
		local displayDef = self:_makeRepeatDisplayDef(effectDef, totalDuration)
		PlayerStateRemoting.EffectApplied:FireClient(target, displayDef, id)
		instance.sentApplied = true
	end

	return function()
		local inst = self._runtimes[target.UserId] and self._runtimes[target.UserId].effects[id]
		if inst and inst.repeatState then
			inst.repeatState.cancelled = true
		end
	end
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

	local toRemove: { string } = {}

	for id, instance in runtime.effects do
		if includeForced == false then
			if not instance.effectDef.force then
				table.insert(toRemove, id)
			end
		else
			table.insert(toRemove, id)
		end
	end

	for _, id in toRemove do
		local instance = runtime.effects[id]
		if instance then
			if instance.repeatState then
				instance.repeatState.cancelled = true
			end
			if instance.sentApplied then
				PlayerStateRemoting.EffectRemoved:FireClient(target, id)
			end
		end
		runtime.effects[id] = nil
	end

	self:_rebuildCache(runtime, target)
	self:_syncMovement(target, runtime)
end

--[=[
	대상에게 현재 적용 중인 모든 effect 목록을 instance 단위로 반환합니다.
	@return { PlayerStateDefs.ActiveEffectView }
]=]
function PlayerStateControllerService:GetActiveEffects(target: Player): { PlayerStateDefs.ActiveEffectView }
	local runtime = self._runtimes[target.UserId]
	if not runtime then
		return {}
	end

	local now = os.clock()
	local result: { PlayerStateDefs.ActiveEffectView } = {}

	for id, instance in runtime.effects do
		local remaining: number? = nil

		if instance.repeatState then
			remaining = math.max(0, instance.repeatState.expiresAt - now)
		else
			local maxExpiry: number = 0
			local hasPermanent = false

			for _, cs in instance.components do
				if cs.expiresAt == nil then
					hasPermanent = true
					break
				end
				if cs.expiresAt > maxExpiry then
					maxExpiry = cs.expiresAt
				end
			end

			if not hasPermanent then
				for _, ts in instance.tags do
					if ts.expiresAt > maxExpiry then
						maxExpiry = ts.expiresAt
					end
				end
				remaining = math.max(0, maxExpiry - now)
			end
		end

		local repeatStateView: PlayerStateDefs.RepeatState? = nil
		if instance.repeatState then
			local rs = instance.repeatState
			repeatStateView = {
				totalDuration = rs.totalDuration,
				count = rs.count,
				interval = rs.interval,
				fired = rs.fired,
				startedAt = rs.startedAt,
				expiresAt = rs.expiresAt,
			}
		end

		table.insert(result, {
			id = id,
			effectDef = instance.effectDef,
			components = instance.components,
			tags = instance.tags,
			startedAt = instance.startedAt,
			remaining = remaining,
			repeatState = repeatStateView,
		})
	end

	return result
end

--[=[
	대상에게 현재 활성 tag 목록을 반환합니다.
	@return { PlayerStateDefs.ActiveTagView }
]=]
function PlayerStateControllerService:GetActiveTags(target: Player): { PlayerStateDefs.ActiveTagView }
	local runtime = self._runtimes[target.UserId]
	if not runtime then
		return {}
	end

	local now = os.clock()
	local result: { PlayerStateDefs.ActiveTagView } = {}
	local seen: { [string]: boolean } = {}

	for _, instance in runtime.effects do
		for _, ts in instance.tags do
			if ts.expiresAt > now and not seen[ts.tag.name] then
				seen[ts.tag.name] = true
				table.insert(result, {
					name = ts.tag.name,
					expiresAt = ts.expiresAt,
					remaining = math.max(0, ts.expiresAt - now),
				})
			end
		end
	end

	return result
end

--[=[
	대상에게 특정 componentType의 effect가 존재하는지 확인합니다.
]=]
function PlayerStateControllerService:HasEffect(target: Player, componentType: string): boolean
	local runtime = self._runtimes[target.UserId]
	if not runtime then
		return false
	end

	local now = os.clock()
	for _, instance in runtime.effects do
		for _, cs in instance.components do
			if cs.expiresAt ~= nil and cs.expiresAt <= now then
				continue
			end
			local c = cs.component :: any
			if c.type == componentType then
				return true
			end
		end
	end
	return false
end

--[=[
	대상에게 특정 tag가 존재하는지 확인합니다.
]=]
function PlayerStateControllerService:HasTag(target: Player, tagName: string): boolean
	local runtime = self._runtimes[target.UserId]
	if not runtime then
		return false
	end

	local now = os.clock()
	for _, instance in runtime.effects do
		for _, ts in instance.tags do
			if ts.expiresAt > now and ts.tag.name == tagName then
				return true
			end
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
	장전 속도 배율을 반환합니다. (기본 1.0)
	BasicAttackService가 읽어 유효 reloadTime을 계산합니다.
]=]
function PlayerStateControllerService:GetReloadRateMult(player: Player): number
	local runtime = self._runtimes[player.UserId]
	return if runtime then runtime.reloadRateMult else 1.0
end

--[=[
	재생 속도 배율을 반환합니다. (기본 1.0)
	BasicAttackService가 읽어 유효 regenRate를 계산합니다.
]=]
function PlayerStateControllerService:GetRegenRateMult(player: Player): number
	local runtime = self._runtimes[player.UserId]
	return if runtime then runtime.regenRateMult else 1.0
end

--[=[
	특정 어빌리티 타입이 잠겨있는지 확인합니다.

	@param player Player
	@param abilityType string  "BasicAttack" | "Skill" | "Ultimate"
	@return boolean
]=]
function PlayerStateControllerService:IsAbilityLocked(player: Player, abilityType: string): boolean
	local runtime = self._runtimes[player.UserId]
	if not runtime then
		return false
	end
	local locked = runtime.lockedAbilityTypes
	if locked == nil then
		return false
	end
	if locked["*"] then
		return true
	end
	return locked[abilityType] == true
end

-- ─── 내부: 인스턴스 생성 ──────────────────────────────────────────────────────

function PlayerStateControllerService:_createInstance(
	id: string,
	effectDef: PlayerStateDefs.EffectDef,
	runtime: PlayerRuntime,
	now: number,
	repeatState: RepeatStateInternal?
): EffectInstance
	local components: { ComponentState } = {}
	local tags: { TagState } = {}
	local force = effectDef.force == true

	if effectDef.components then
		for _, comp in effectDef.components do
			local c = comp :: any

			-- cleanse는 보호 체크 없이 항상 포함 (instant)
			if c.type == ComponentType.Cleanse then
				table.insert(components, { component = comp, expiresAt = now })
				continue
			end

			-- 보호 체크
			if not force then
				if runtime.isIgnoreDamage and c.type == ComponentType.Damage then
					continue
				end
				if runtime.isIgnoreCC and CC_TYPES[c.type] then
					continue
				end
			end

			local expiresAt: number?

			-- 즉시 처리 컴포넌트
			if
				c.type == ComponentType.Damage
				or c.type == ComponentType.Knockback
				or c.type == ComponentType.ResourceDelta
			then
				expiresAt = now
			elseif c.duration then
				expiresAt = now + c.duration
			else
				expiresAt = nil -- 영구
			end

			table.insert(components, { component = comp, expiresAt = expiresAt })
		end
	end

	if effectDef.tags then
		for _, tag in effectDef.tags do
			table.insert(tags, {
				tag = tag,
				expiresAt = now + tag.duration,
			})
		end
	end

	return {
		id = id,
		effectDef = effectDef,
		components = components,
		tags = tags,
		startedAt = now,
		sentApplied = false,
		repeatState = repeatState,
	}
end

-- ─── 내부: 반복 tick 실행 ────────────────────────────────────────────────────

function PlayerStateControllerService:_fireRepeatTick(target: Player, runtime: PlayerRuntime, instance: EffectInstance)
	local effectDef = instance.effectDef
	local force = effectDef.force == true

	if not effectDef.components then
		return
	end

	for _, comp in effectDef.components do
		local c = comp :: any

		if not force then
			if runtime.isIgnoreDamage and c.type == ComponentType.Damage then
				continue
			end
			if runtime.isIgnoreCC and CC_TYPES[c.type] then
				continue
			end
		end

		if c.type == ComponentType.Damage then
			self:_applyDamage(target, runtime, effectDef, c)
		elseif c.type == ComponentType.Knockback then
			self:_applyKnockback(runtime, c)
		elseif c.type == ComponentType.ResourceDelta then
			self.ResourceDeltaApplied:Fire(target, c.amount)
		end
	end
end

-- ─── 내부: displayDef 생성 (repeat용 tag duration 확장) ────────────────────────

function PlayerStateControllerService:_makeRepeatDisplayDef(
	effectDef: PlayerStateDefs.EffectDef,
	totalDuration: number
): PlayerStateDefs.EffectDef
	local newTags: { PlayerStateDefs.TagEntry }? = nil
	if effectDef.tags then
		newTags = {}
		for _, tag in effectDef.tags do
			table.insert(newTags :: { PlayerStateDefs.TagEntry }, {
				name = tag.name,
				duration = totalDuration,
				intensity = tag.intensity,
			})
		end
	end
	return {
		force = effectDef.force,
		source = effectDef.source,
		tags = newTags,
		components = effectDef.components,
	}
end

-- ─── 내부: 만료 체크 ─────────────────────────────────────────────────────────

function PlayerStateControllerService:_isInstanceExpired(instance: EffectInstance, now: number): boolean
	for _, cs in instance.components do
		if cs.expiresAt == nil then
			return false
		end
		if cs.expiresAt > now then
			return false
		end
	end
	for _, ts in instance.tags do
		if ts.expiresAt > now then
			return false
		end
	end
	return true
end

-- ─── 내부: 캐시 재빌드 ───────────────────────────────────────────────────────

--[=[
	@param runtime PlayerRuntime
	@param player Player?  nil이면 EffectiveMultipliersChanged 미발동
]=]
function PlayerStateControllerService:_rebuildCache(runtime: PlayerRuntime, player: Player?)
	local isMoveLocked = false
	local lockedAbilityTypes: { [string]: boolean }? = nil
	local isIgnoreCC, isIgnoreDamage = false, false
	local speedMult, receiveMult, dealMult = 1.0, 1.0, 1.0
	local reloadMult, regenMult = 1.0, 1.0
	local now = os.clock()

	for _, instance in runtime.effects do
		for _, cs in instance.components do
			if cs.expiresAt ~= nil and cs.expiresAt <= now then
				continue
			end

			local c = cs.component :: any
			if c.type == ComponentType.MoveLock then
				isMoveLocked = true
			elseif c.type == ComponentType.AbilityLock then
				if not lockedAbilityTypes then
					lockedAbilityTypes = {}
				end
				if c.abilityTypes == nil then
					-- nil → 전부 잠금
					lockedAbilityTypes["*"] = true
				else
					for _, aType in c.abilityTypes do
						lockedAbilityTypes[aType] = true
					end
				end
			elseif c.type == ComponentType.IgnoreCC then
				isIgnoreCC = true
			elseif c.type == ComponentType.IgnoreDamage then
				isIgnoreDamage = true
			elseif c.type == ComponentType.WalkSpeedMult then
				speedMult = math.min(speedMult, c.multiplier)
			elseif c.type == ComponentType.ReceiveDamageMult then
				receiveMult *= c.multiplier
			elseif c.type == ComponentType.DealDamageMult then
				dealMult *= c.multiplier
			elseif c.type == ComponentType.ReloadRateMult then
				reloadMult *= c.multiplier
			elseif c.type == ComponentType.RegenRateMult then
				regenMult *= c.multiplier
			end
		end
	end

	local prevReloadMult = runtime.reloadRateMult
	local prevRegenMult = runtime.regenRateMult

	runtime.isMoveLocked = isMoveLocked
	runtime.lockedAbilityTypes = lockedAbilityTypes
	runtime.isIgnoreCC = isIgnoreCC
	runtime.isIgnoreDamage = isIgnoreDamage
	runtime.walkSpeedMult = speedMult
	runtime.receiveDamageMult = receiveMult
	runtime.dealDamageMult = dealMult
	runtime.reloadRateMult = reloadMult
	runtime.regenRateMult = regenMult

	-- 배율 변경 시 BasicAttackService에 알림
	if player then
		local reloadChanged = math.abs(prevReloadMult - reloadMult) > 0.001
		local regenChanged = math.abs(prevRegenMult - regenMult) > 0.001
		if reloadChanged or regenChanged then
			self.EffectiveMultipliersChanged:Fire(player)
		end
	end
end

-- ─── 내부: 이동 동기화 ───────────────────────────────────────────────────────

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
			ms:SetSpeedMultiplier(target, runtime.walkSpeedMult)
		end
	end
end

-- ─── 내부: 대미지 처리 ───────────────────────────────────────────────────────

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
	self:_checkOnHitReact(target, runtime, effectDef)
end

-- ─── 내부: 넉백 처리 ─────────────────────────────────────────────────────────

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

-- ─── 내부: onHitReact 체크 ───────────────────────────────────────────────────

--[=[
	대상이 공격을 받았을 때 onHitReact component의 콜백을 호출합니다.
	incomingEffectDef.source로 공격자를 확인할 수 있습니다.
]=]
function PlayerStateControllerService:_checkOnHitReact(
	target: Player,
	runtime: PlayerRuntime,
	incomingEffectDef: PlayerStateDefs.EffectDef
)
	local now = os.clock()
	for _, instance in runtime.effects do
		for _, cs in instance.components do
			if cs.expiresAt ~= nil and cs.expiresAt <= now then
				continue
			end
			local c = cs.component :: any
			if c.type ~= ComponentType.OnHitReact or not c.onHit then
				continue
			end
			-- 콜백 호출. incomingEffectDef 전체 전달.
			local ok, err = pcall(c.onHit, incomingEffectDef)
			if not ok then
				warn(string.format("[PSC] onHitReact 콜백 오류 (target=%s): %s", target.Name, tostring(err)))
			end
		end
	end
end

-- ─── 내부: 전체 초기화 ───────────────────────────────────────────────────────

function PlayerStateControllerService:_clearAllEffects(target: Player, runtime: PlayerRuntime)
	for id, instance in runtime.effects do
		if instance.repeatState then
			instance.repeatState.cancelled = true
		end
		if instance.sentApplied then
			PlayerStateRemoting.EffectRemoved:FireClient(target, id)
		end
	end
	table.clear(runtime.effects)
	self:_rebuildCache(runtime, target)
	self:_syncMovement(target, runtime)
end

-- ─── 내부: ID 생성 ───────────────────────────────────────────────────────────

function PlayerStateControllerService:_generateId(): string
	self._idCounter += 1
	return "ps_" .. tostring(self._idCounter)
end

function PlayerStateControllerService.Destroy(self: PlayerStateControllerService)
	self._maid:Destroy()
end

return PlayerStateControllerService
