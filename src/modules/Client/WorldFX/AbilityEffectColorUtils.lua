--!strict
--[=[
	@class AbilityEffectColorUtils

	AbilityEffect 색상 필터 프리셋 모음.

	colorFilter 타입:
	  (model: Model, color: Color3) -> (() -> ())
	  반환값은 cleanup 함수 (이펙트 종료 시 Maid가 호출).

	사용법:
	  -- AbilityEffectDef에서:
	  colorFilter = AbilityEffectColorUtils.Highlight(0.6)
	  colorFilter = AbilityEffectColorUtils.SelectionBox()

	실험 방법:
	  두 프리셋을 def에 교체하며 테스트 후 원하는 걸 선택하세요.
]=]

local AbilityEffectColorUtils = {}

--[=[
	Highlight 인스턴스를 모델에 붙여 색상 오버레이를 적용합니다.
	원본 모델 디자인이 비치면서 색상이 씌워지는 필터 효과.

	@param fillTransparency number?  0~1 (기본 0.6, 낮을수록 진한 오버레이)
	@return ColorFilter
]=]
function AbilityEffectColorUtils.Highlight(fillTransparency: number?)
	local transparency = fillTransparency or 0.6
	return function(model: Model, color: Color3): () -> ()
		local highlight = Instance.new("Highlight")
		highlight.FillColor = color
		highlight.OutlineColor = color
		highlight.FillTransparency = transparency
		highlight.OutlineTransparency = 0.3
		highlight.Adornee = model
		highlight.Parent = model
		return function()
			if highlight and highlight.Parent then
				highlight:Destroy()
			end
		end
	end
end

--[=[
	SelectionBox를 모델에 붙여 외곽선 색상을 적용합니다.
	내부는 원본 유지, 외곽선만 색상 적용.

	@return ColorFilter
]=]
function AbilityEffectColorUtils.SelectionBox()
	return function(model: Model, color: Color3): () -> ()
		local box = Instance.new("SelectionBox")
		box.Color3 = color
		box.LineThickness = 0.05
		box.SurfaceTransparency = 1
		box.Adornee = model
		box.Parent = model
		return function()
			if box and box.Parent then
				box:Destroy()
			end
		end
	end
end

return AbilityEffectColorUtils
