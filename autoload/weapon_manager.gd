extends Node
## 무기/탄약 관리 (PRD 3.3).
## - 기본: 총 + 칼. 업그레이드는 '하나' 부활 시 해금.
## - 탄약은 소모성, 맵 내 고정 지점에서만 확보(랜덤 아님 — 동선 학습 가능).

signal ammo_changed(amount: int)

var ammo: int = 12
var upgrade_unlocked: bool = false        # '하나' 부활 시 true (탐사 난이도 분기점)
var equipped := {"ranged": "pistol", "melee": "knife"}


func add_ammo(amount: int) -> void:
	ammo = maxi(0, ammo + amount)
	ammo_changed.emit(ammo)


func consume_ammo(amount: int) -> bool:
	if ammo < amount:
		return false
	ammo -= amount
	ammo_changed.emit(ammo)
	return true


func unlock_upgrades() -> void:
	upgrade_unlocked = true


func to_dict() -> Dictionary:
	return {"ammo": ammo, "upgrade_unlocked": upgrade_unlocked, "equipped": equipped}


func from_dict(d: Dictionary) -> void:
	ammo = int(d.get("ammo", 12))
	upgrade_unlocked = bool(d.get("upgrade_unlocked", false))
	equipped = d.get("equipped", {"ranged": "pistol", "melee": "knife"})
