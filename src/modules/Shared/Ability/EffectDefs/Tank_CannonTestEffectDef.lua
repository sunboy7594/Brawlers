--!strict
--[=[
	@class Tank_CannonTestEffectDef

	탱크 캐논 테스트 기본공격 이펙트 정의. (Shared)
	 Tank_CannonEffectDef로 리디렉트 — 구 버전 파일.
]=]

local require = require(script.Parent.loader).load(script)

-- Tank_CannonEffectDef로 통합되었으므로 이 파일은 해당 모듈을 반환
return require("Tank_CannonEffectDef")
