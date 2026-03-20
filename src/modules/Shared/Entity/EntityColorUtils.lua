--!strict
--[=[
	@class EntityColorUtils

	모델 체색 필터 모음. (Shared)

	ColorFilter 타입: (model: any, color: Color3?) -> () -> ()
	  반환값 = cleanup 함수 (Maid에 등록됨)
	  color = nil이면 채색 안 함
	  colorFilter 자체가 nil이면 EntityController가 호출 안 함

	종류:
	  Highlight(config?) → Highlight 인스턴스로 팀 색상 오버레이
	    depthMode: "Occluded" (기본) / "AlwaysOnTop" (벽 뒤에서도 보임)
	  SelectionBox(config?) → 외곽선 (바운딩 박스 기준 직육면체)
	  Tint()              → 파트 색상 직접 변경

	추후 추가 여지:
	  ColorShift(config) → 시간에 따라 색상 변화 (Heartbeat 기반)
]=]

local EntityColorUtils = {}

-- ─── Highlight ───────────────────────────────────────────────────────────────

export type HighlightConfig = {
	fillTransparency    : number?,
	outlineTransparency : number?,
	depthMode           : ("AlwaysOnTop" | "Occluded")?,
	fillColor           : Color3?,
	outlineColor        : Color3?,
}

function EntityColorUtils.Highlight(config: HighlightConfig?)
	local cfg = config or {}
	return function(model: any, color: Color3?): () -> ()
		if typeof(model) ~= "Instance" then return function() end end
		local fillColor    = (cfg :: any).fillColor    or color
		local outlineColor = (cfg :: any).outlineColor or color
		if not fillColor and not outlineColor then return function() end end

		local h = Instance.new("Highlight")
		h.FillColor           = fillColor    or Color3.new(1, 1, 1)
		h.OutlineColor        = outlineColor or Color3.new(1, 1, 1)
		h.FillTransparency    = (cfg :: any).fillTransparency    or 0.5
		h.OutlineTransparency = (cfg :: any).outlineTransparency or 0
		h.DepthMode           = if ((cfg :: any).depthMode or "Occluded") == "AlwaysOnTop"
			then Enum.HighlightDepthMode.AlwaysOnTop
			else Enum.HighlightDepthMode.Occluded
		h.Adornee = model :: Instance
		h.Parent  = model :: Instance
		return function() h:Destroy() end
	end
end

-- ─── SelectionBox ────────────────────────────────────────────────────────────

export type SelectionBoxConfig = {
	lineThickness       : number?,
	surfaceTransparency : number?,
}

function EntityColorUtils.SelectionBox(config: SelectionBoxConfig?)
	local cfg = config or {}
	return function(model: any, color: Color3?): () -> ()
		if typeof(model) ~= "Instance" then return function() end end
		if not color then return function() end end

		local sb = Instance.new("SelectionBox")
		sb.Color3              = color
		sb.LineThickness       = (cfg :: any).lineThickness       or 0.05
		sb.SurfaceTransparency = (cfg :: any).surfaceTransparency or 1
		sb.SurfaceColor3       = color
		sb.Adornee = model :: Instance
		sb.Parent  = model :: Instance
		return function() sb:Destroy() end
	end
end

-- ─── Tint ────────────────────────────────────────────────────────────────────

function EntityColorUtils.Tint()
	return function(model: any, color: Color3?): () -> ()
		if typeof(model) ~= "Instance" then return function() end end
		if not color then return function() end end

		local originals: { [BasePart]: Color3 } = {}
		for _, d in (model :: Instance):GetDescendants() do
			if d:IsA("BasePart") then
				originals[d :: BasePart] = (d :: BasePart).Color
				;(d :: BasePart).Color = color
			end
		end
		return function()
			for part, orig in originals do
				if part.Parent then part.Color = orig end
			end
		end
	end
end

return EntityColorUtils
