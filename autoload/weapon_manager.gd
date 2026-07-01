extends Node
## 무기/탄약 관리 (PRD 3.3).
## 기본: 총 + 칼. 강화는 '하나' 부활 시 해금되며, 토큰으로 단계 강화한다
## (하나 등장이 곧 탐사 난이도의 분기점). 탄약은 소모성, 맵 내 고정 지점 확보.

signal ammo_changed(amount: int)
signal weapons_changed

const RANGED_BASE := 25.0
const MELEE_BASE := 45.0
const RANGED_STEP := 10.0
const MELEE_STEP := 15.0
const MAX_LEVEL := 5

var ammo: int = 12
var upgrade_unlocked: bool = false        # '하나' 부활 시 true
var ranged_level: int = 0
var melee_level: int = 0
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


## '하나' 부활 시 호출 — 무기 강화 기능 해금.
func unlock_upgrades() -> void:
	if upgrade_unlocked:
		return
	upgrade_unlocked = true
	weapons_changed.emit()


func ranged_damage() -> float:
	return RANGED_BASE + ranged_level * RANGED_STEP


func melee_damage() -> float:
	return MELEE_BASE + melee_level * MELEE_STEP


func current_damage(kind: String) -> float:
	return ranged_damage() if kind == "ranged" else melee_damage()


func next_damage(kind: String) -> float:
	return current_damage(kind) + (RANGED_STEP if kind == "ranged" else MELEE_STEP)


func level_of(kind: String) -> int:
	return ranged_level if kind == "ranged" else melee_level


func upgrade_cost(kind: String) -> int:
	return 20 + level_of(kind) * 15


func is_max(kind: String) -> bool:
	return level_of(kind) >= MAX_LEVEL


func can_upgrade(kind: String) -> bool:
	return upgrade_unlocked and not is_max(kind) and GameManager.tokens >= upgrade_cost(kind)


## 토큰을 소모해 강화. 성공 시 true.
func try_upgrade(kind: String) -> bool:
	if not can_upgrade(kind):
		return false
	GameManager.tokens -= upgrade_cost(kind)
	if kind == "ranged":
		ranged_level += 1
	else:
		melee_level += 1
	weapons_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {
		"ammo": ammo,
		"upgrade_unlocked": upgrade_unlocked,
		"ranged_level": ranged_level,
		"melee_level": melee_level,
		"equipped": equipped,
	}


func from_dict(d: Dictionary) -> void:
	ammo = int(d.get("ammo", 12))
	upgrade_unlocked = bool(d.get("upgrade_unlocked", false))
	ranged_level = int(d.get("ranged_level", 0))
	melee_level = int(d.get("melee_level", 0))
	equipped = d.get("equipped", {"ranged": "pistol", "melee": "knife"})
