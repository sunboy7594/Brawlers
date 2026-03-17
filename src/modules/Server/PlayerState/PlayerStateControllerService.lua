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

	내부 구조:
	  runtime.effects: { [id]: EffectInstance } 딕셔너리
	  EffectInstance: id + effectDef + components(ComponentState) + tags(TagState) + repeatState?
	  damage 포함 모든 component를 ComponentState로 저장
	  (damage/knockback/cleanse는 즉시 처리 후 expiresAt = 생성시각으로 표시)

	클라이언트 통보:
	  effect 적용 시 EffectApplied:FireClient(target, effectDef, id)
	  repeat의 경우 tag duration을 totalDuration으로 확장한 displayDef 전송
	  effect 만료/취소 시 EffectRemoved:FireClient(target, id)
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
		local toRemove: { string } = {}

		for id, instance in runtime.effects do
			if instance.repeatState then
				local rs = instance.repeatState

				-- 취소 또는 만료
				if rs.cancelled or now >= rs.expiresAt then
					table.insert(toRemove, id)
					continue
				end

				-- 펜딩 tick 처리
				local nextFireAt = rs.startedAt + rs.fired * rs.interval
				while rs.fired < rs.count and now >= nextFireAt do
					self:_fireRepeatTick(player, runtime, instance)
					rs.fired += 1
					dirty = true
					nextFireAt = rs.startedAt + rs.fired * rs.interval
				end
			else
				-- 단발: 모든 컴포넌트/태그가 만료되면 제거
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
			self:_rebuildCache(runtime)
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

	-- 인스턴스 생성 (보호 체크 포함)
	local instance = self:_createInstance(id, effectDef, runtime, now, nil)

	-- cleanse 먼저 처리 (인스턴스 추가 전)
	for _, cs in instance.components do
		if (cs.component :: any).type == ComponentType.Cleanse then
			self:StopAll(target, false)
			break
		end
	end

	-- 인스턴스 등록
	runtime.effects[id] = instance

	-- 즉시 처리 컴포넌트 실행
	for _, cs in instance.components do
		local c = cs.component :: any
		if c.type == ComponentType.Damage then
			self:_applyDamage(target, runtime, effectDef, c)
		elseif c.type == ComponentType.Knockback then
			self:_applyKnockback(runtime, c)
		end
	end

	self:_rebuildCache(runtime)
	self:_syncMovement(target, runtime)

	-- 태그가 있을 때만 클라이언트 통보
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
	EffectApplied는 최초 1회 (tag duration = totalDuration으로 확장하여 전송).
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

	-- 첫 tick 즉시 실행
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

	self:_rebuildCache(runtime)
	self:_syncMovement(target, runtime)

	-- tag duration을 totalDuration으로 확장한 displayDef 전송
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

	self:_rebuildCache(runtime)
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
			-- 가장 늦게 만료되는 컴포넌트/태그 기준
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

		-- RepeatState 뷰 변환
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
	@param componentType PlayerStateDefs.ComponentType 값 (예: "moveLock", "slow")
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
	@param tagName PlayerStateDefs.Tag 값 (예: "vfx_burn", "anim_stun")
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
	공격 잠금 여부를 반환합니다.
]=]
function PlayerStateControllerService:IsAttackLocked(player: Player): boolean
	local runtime = self._runtimes[player.UserId]
	return if runtime then runtime.isAttackLocked else false
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
			if c.type == ComponentType.Damage or c.type == ComponentType.Knockback then
				expiresAt = now -- 즉시 처리됨, 이미 만료로 표시
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
	-- 살아있는 컴포넌트 체크
	for _, cs in instance.components do
		if cs.expiresAt == nil then
			return false
		end -- 영구
		if cs.expiresAt > now then
			return false
		end -- 아직 활성
	end
	-- 살아있는 태그 체크
	for _, ts in instance.tags do
		if ts.expiresAt > now then
			return false
		end
	end
	return true
end

-- ─── 내부: 캐시 재빌드 ───────────────────────────────────────────────────────

function PlayerStateControllerService:_rebuildCache(runtime: PlayerRuntime)
	local isMoveLocked, isAttackLocked, isIgnoreCC, isIgnoreDamage = false, false, false, false
	local slowMult, receiveMult, dealMult = 1.0, 1.0, 1.0
	local now = os.clock()

	for _, instance in runtime.effects do
		for _, cs in instance.components do
			-- 즉시 처리된 컴포넌트(expiresAt = 생성시각) 및 만료된 컴포넌트는 제외
			if cs.expiresAt ~= nil and cs.expiresAt <= now then
				continue
			end

			local c = cs.component :: any
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
	end

	runtime.isMoveLocked = isMoveLocked
	runtime.isAttackLocked = isAttackLocked
	runtime.isIgnoreCC = isIgnoreCC
	runtime.isIgnoreDamage = isIgnoreDamage
	runtime.slowMultiplier = slowMult
	runtime.receiveDamageMult = receiveMult
	runtime.dealDamageMult = dealMult
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
			ms:SetSpeedMultiplier(target, runtime.slowMultiplier)
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
	self:_checkVulnerable(target, runtime, effectDef)
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

-- ─── 내부: vulnerable 체크 ───────────────────────────────────────────────────

function PlayerStateControllerService:_checkVulnerable(
	target: Player,
	runtime: PlayerRuntime,
	incomingDef: PlayerStateDefs.EffectDef
)
	local now = os.clock()
	for _, instance in runtime.effects do
		for _, cs in instance.components do
			if cs.expiresAt ~= nil and cs.expiresAt <= now then
				continue
			end
			local c = cs.component :: any
			if c.type ~= ComponentType.Vulnerable or not c.onHit then
				continue
			end
			local onHitDef = c.onHit :: PlayerStateDefs.EffectDef
			if incomingDef.source and not onHitDef.source then
				(onHitDef :: any).source = incomingDef.source
			end
			self:Play(target, onHitDef)
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
	self:_rebuildCache(runtime)
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
