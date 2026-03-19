--!strict
--[=[
	@class ProjectileHitRemoting

	투사체 판정 관련 Remote 채널. (Shared)

	채널 목록:
	- RegisterProjectile : (클라이언트 → 서버) 투사체 등록
	  전달: projectileId (string), config (ProjectileNetConfig)
	  hasSelfHit=true인 AbilityEffect 발사 시 클라이언트가 호출.
	  서버는 PendingProjectile로 등록 후 서언 시각보다 길어지면 만료.

	- ProjectileHit     : (클라이언튴 → 서버) 충돌 보고
	  전달: projectileId (string), hitPosition (Vector3)
	  클라이언트 MoveFactory에서 충돌 감지 시 호출.
	  서버는 3단계 검증 후 통과 시에만 onHit 콜백 실행.

	ProjectileNetConfig:
	  검증에 필요한 최소한의 정보만 네트워크로 전송.
	  {
	      origin    : Vector3  -- 발사 위치
	      direction : Vector3  -- 단위벡터
	      speed     : number   -- 속도 (스터드/초)
	      hitRadius : number   -- 충돌 감지 반경
	      maxRange  : number   -- 최대 사거리
	  }
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remoting = require("Remoting")

local ProjectileHitRemoting
if RunService:IsServer() then
	ProjectileHitRemoting = Remoting.Server.new(ReplicatedStorage, "ProjectileHit")
	ProjectileHitRemoting.RegisterProjectile:DeclareEvent()
	ProjectileHitRemoting.ProjectileHit:DeclareEvent()
else
	ProjectileHitRemoting = Remoting.Client.new(ReplicatedStorage, "ProjectileHit")
end

return ProjectileHitRemoting
