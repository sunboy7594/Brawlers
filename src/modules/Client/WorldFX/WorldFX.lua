--!strict
--[=[
	@class WorldFX

	월드 공간 연출 허브 서비스 (클라이언트).
	3D 모델 소환, 파티클 연출, 색상 필터 적용을 담당합니다.

	AbilityEffect 유틸이 이 서비스를 통해 모델을 소환합니다.

	에셋 규칙:
	  ReplicatedStorage.AbilityEffects.<templateName> : Model
	  파티클은 추후 확장.

	공개 API:
	  SpawnModel(templateName, origin, color, colorFilter?) → (Model?, cleanup?)
	  GetTeamClient() → TeamClient
	  GetFXFolder()   → Folder?
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local TeamClient = require("TeamClient")

-- ─── 상수 ────────────────────────────────────────────────────────────────────

local ASSETS_FOLDER = "AbilityEffects"  -- ReplicatedStorage 내 템플릿 폴더
local FX_FOLDER_NAME = "WorldFX"        -- workspace 내 이펙트 폴더

-- ─── 타입 ────────────────────────────────────────────────────────────────────

--[=[
	색상 필터 함수 타입.
	@type ColorFilter (model: Model, color: Color3) -> (() -> ())
	반환값은 cleanup 함수. AbilityEffectHandle의 Maid에 등록됩니다.
]=]
export type ColorFilter = (model: Model, color: Color3) -> () -> ()

export type WorldFX = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: any,
		_teamClient: any,
		_fxFolder: Folder?,
	},
	{} :: typeof({ __index = {} })
))

-- ─── 서비스 ──────────────────────────────────────────────────────────────────

local WorldFX = {}
WorldFX.ServiceName = "WorldFX"
WorldFX.__index = WorldFX

function WorldFX.Init(self: WorldFX, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._teamClient = serviceBag:GetService(TeamClient)
	self._fxFolder = nil
end

function WorldFX.Start(self: WorldFX)
	local folder = Instance.new("Folder")
	folder.Name = FX_FOLDER_NAME
	folder.Parent = workspace
	self._fxFolder = folder
	self._maid:GiveTask(folder)
end

-- ─── 공개 API ────────────────────────────────────────────────────────────────

--[=[
	ReplicatedStorage.AbilityEffects에서 템플릿을 클론하여 월드에 배치합니다.
	colorFilter가 있으면 적용 후 cleanup 함수를 반환합니다.

	@param templateName  string
	@param origin        CFrame
	@param color         Color3
	@param colorFilter   ColorFilter?
	@return Model?, (() -> ())?
]=]
function WorldFX:SpawnModel(
	templateName: string,
	origin: CFrame,
	color: Color3,
	colorFilter: ColorFilter?
): (Model?, (() -> ())?)
	local assets = ReplicatedStorage:FindFirstChild(ASSETS_FOLDER)
	if not assets then
		warn("[WorldFX] ReplicatedStorage." .. ASSETS_FOLDER .. " 폴더 없음")
		return nil, nil
	end

	local template = assets:FindFirstChild(templateName)
	if not template then
		warn("[WorldFX] 템플릿 없음:", templateName)
		return nil, nil
	end

	local model = (template :: Model):Clone()
	model:PivotTo(origin)

	-- 비주얼 전용: 충돌/그림자 해제
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			(desc :: BasePart).CanCollide = false
			(desc :: BasePart).CastShadow = false
			(desc :: BasePart).Anchored = true
		end
	end

	model.Parent = self._fxFolder

	-- 색상 필터 적용
	local cleanup: (() -> ())? = nil
	if colorFilter then
		cleanup = colorFilter(model, color)
	end

	return model, cleanup
end

--[=[
	TeamClient 인스턴스를 반환합니다.
	AbilityEffect가 색상 계산 시 사용합니다.
	@return TeamClient
]=]
function WorldFX:GetTeamClient(): any
	return self._teamClient
end

--[=[
	WorldFX 이펙트 폴더를 반환합니다.
	@return Folder?
]=]
function WorldFX:GetFXFolder(): Folder?
	return self._fxFolder
end

function WorldFX.Destroy(self: WorldFX)
	self._maid:Destroy()
end

return WorldFX
