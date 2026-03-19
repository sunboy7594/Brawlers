--!strict
--[=[
	@class AbilityEffectColorUtils

	모델 체색 필터 모음. (Client)

	반환 ColorFilter = (model: Model, color: Color3) -> () -> ()
	  반환값 = cleanup 함수 (Maid에 등록됨)

	종류:
	  Highlight(transparency?)  → Highlight 인스턴스로 팀 색상 오버레이
	  SelectionBox()            → 외곽선만
	  Tint()                   → 파트 색상 직접 변경
]=]

local AbilityEffectColorUtils = {}

-- ─── Highlight ────────────────────────────────────────────────────────────────────

function AbilityEffectColorUtils.Highlight(transparency: number?)
	return function(model: Model, color: Color3): () -> ()
		local h = Instance.new("Highlight")
		h.FillColor     = color
		h.OutlineColor  = color
		h.FillTransparency    = transparency or 0.5
		h.OutlineTransparency = 0
		h.Adornee = model
		h.Parent  = model
		return function()
			h:Destroy()
		end
	end
end

-- ─── SelectionBox ────────────────────────────────────────────────────────────────

function AbilityEffectColorUtils.SelectionBox(lineThickness: number?)
	return function(model: Model, color: Color3): () -> ()
		local sb = Instance.new("SelectionBox")
		sb.Color3         = color
		sb.LineThickness  = lineThickness or 0.05
		sb.SurfaceTransparency = 1
		sb.Adornee = model
		sb.Parent  = model
		return function()
			sb:Destroy()
		end
	end
end

-- ─── Tint ────────────────────────────────────────────────────────────────────────

function AbilityEffectColorUtils.Tint()
	return function(model: Model, color: Color3): () -> ()
		local originals: { [BasePart]: Color3 } = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				originals[d :: BasePart] = (d :: BasePart).Color
				;(d :: BasePart).Color = color
			end
		end
		return function()
			for part, orig in originals do
				if part.Parent then
					part.Color = orig
				end
			end
		end
	end
end

return AbilityEffectColorUtils
