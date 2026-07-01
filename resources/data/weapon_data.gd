class_name WeaponData
extends Resource
## 무기 정의 (PRD 3.3). 총(원거리) + 칼(근접) 조합.

enum Kind { RANGED, MELEE }

@export var id: String
@export var display_name: String
@export var kind: Kind = Kind.RANGED
@export var damage: float = 1.0
@export var uses_ammo: bool = true
## '하나' 해금 후 적용 가능한 강화 단계 수(업그레이드 트리 깊이 — PRD 미해결 질문).
@export var max_upgrade_level: int = 0
