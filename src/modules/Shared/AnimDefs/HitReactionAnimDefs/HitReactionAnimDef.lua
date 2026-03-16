--!strict
--[=[
	@class HitReactionAnimDef

	피격 시 캐릭터 몸 애니메이션 정의.
	HitReactionClient의 EntityAnimator에 주입됩니다.

	AnimDef.type:
	  "anim"   → layer 기반 재생
	  "modify" → modifier 등록

	애니메이션 목록:
	- HitStagger  : 일반 피격 시 몸통 뒤로 살짝 젖혀짐
	- HitKnockback: 강한 넉백 피격 시 상체 크게 젖혀짐
]=]

local Layer = {
	BASE = 0,
	ACTION = 1,
	OVERRIDE = 2,
}

type OnUpdate = (joint: Motor6D, dt: number) -> ()
type AnimFactory = (joint: Motor6D, defaultC0: CFrame, ac: any) -> OnUpdate

type AnimDef =
	{ type: "anim", layer: number, duration: number, force: boolean?, joints: { [string]: AnimFactory } }
	| { type: "modify", joints: { [string]: (joint: Motor6D, defaultC0: CFrame, ac: any) -> (CFrame, number) -> CFrame } }

local HitReactionAnimDef: { [string]: AnimDef } = {}

-- ============================================================
-- HitStagger: 일반 피격
-- 상체가 뒤로 살짝 젖혀졌다가 돌아옴
-- ============================================================
HitReactionAnimDef["HitStagger"] = {
	type = "anim",
	layer = Layer.ACTION,
	duration = 0.3,
	force = true,
	joints = {
		Waist = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			local t = 0
			local duration = 0.25
			return function(joint: Motor6D, dt: number)
				t += dt
				local progress = math.min(t / duration, 1)
				-- 0→1→0 형태: 젖혀졌다 복귀
				local angle = math.sin(progress * math.pi) * math.rad(-12)
				local target = defaultC0 * CFrame.Angles(angle, 0, 0)
				ac:spring(joint, target, 25, 1.0, dt)
			end
		end,
		Neck = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			local t = 0
			local duration = 0.25
			return function(joint: Motor6D, dt: number)
				t += dt
				local progress = math.min(t / duration, 1)
				local angle = math.sin(progress * math.pi) * math.rad(-8)
				local target = defaultC0 * CFrame.Angles(angle, 0, 0)
				ac:spring(joint, target, 20, 1.0, dt)
			end
		end,
	},
}

-- ============================================================
-- HitKnockback: 강한 피격 (넉백)
-- 상체가 크게 젖혀지고 팔이 벌어짐
-- ============================================================
HitReactionAnimDef["HitKnockback"] = {
	type = "anim",
	layer = Layer.ACTION,
	duration = 0.4,
	force = true,
	joints = {
		Waist = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			local t = 0
			local duration = 0.4
			return function(joint: Motor6D, dt: number)
				t += dt
				local progress = math.min(t / duration, 1)
				local angle = math.sin(progress * math.pi) * math.rad(-22)
				local target = defaultC0 * CFrame.Angles(angle, 0, 0)
				ac:spring(joint, target, 20, 1.0, dt)
			end
		end,
		Neck = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			local t = 0
			local duration = 0.4
			return function(joint: Motor6D, dt: number)
				t += dt
				local progress = math.min(t / duration, 1)
				local angle = math.sin(progress * math.pi) * math.rad(-15)
				local target = defaultC0 * CFrame.Angles(angle, 0, 0)
				ac:spring(joint, target, 18, 1.0, dt)
			end
		end,
		RightShoulder = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			local t = 0
			local duration = 0.4
			return function(joint: Motor6D, dt: number)
				t += dt
				local progress = math.min(t / duration, 1)
				local angle = math.sin(progress * math.pi) * math.rad(30)
				local target = defaultC0 * CFrame.Angles(0, 0, angle)
				ac:spring(joint, target, 18, 1.0, dt)
			end
		end,
		LeftShoulder = function(_joint: Motor6D, defaultC0: CFrame, ac: any): OnUpdate
			local t = 0
			local duration = 0.4
			return function(joint: Motor6D, dt: number)
				t += dt
				local progress = math.min(t / duration, 1)
				local angle = math.sin(progress * math.pi) * math.rad(-30)
				local target = defaultC0 * CFrame.Angles(0, 0, angle)
				ac:spring(joint, target, 18, 1.0, dt)
			end
		end,
	},
}

return HitReactionAnimDef
