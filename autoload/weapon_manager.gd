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

## 무기별 사거리 기본값(px). 엑셀 balance 에 "<무기id>_range" 행이 있으면 그 값이 우선.
const RANGED_RANGE_BASE := 900.0
const MELEE_RANGE_BASE := 64.0

var ammo: int = 12
var upgrade_unlocked: bool = false        # 'carter' 부활 시 true (무기 강화/제작 해금)
var ranged_level: int = 0
var melee_level: int = 0
var equipped := {"ranged": "pistol", "melee": "knife"}
## 보유 무기 id 목록(제작으로 늘어남). 기본은 WeaponDB 의 craft_cost=0 무기.
var owned: Array = ["pistol", "knife"]


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


## 데미지 = 장착 무기의 기본 공격력(WeaponDB) + 슬롯 강화 레벨 보너스.
func ranged_damage() -> float:
	return _base_damage(str(equipped["ranged"]), RANGED_BASE) + ranged_level * RANGED_STEP


func melee_damage() -> float:
	return _base_damage(str(equipped["melee"]), MELEE_BASE) + melee_level * MELEE_STEP


func _base_damage(id: String, fallback: float) -> float:
	var d := WeaponDB.base_damage(id)
	return d if d > 0.0 else fallback


# ── 보유 / 제작 / 장착 ─────────────────────────────────

func is_owned(id: String) -> bool:
	return id in owned


func weapon_craft_cost(id: String) -> int:
	return WeaponDB.craft_cost(id)


## 제작 가능한(아직 미보유, craft_cost>0) 무기 id 목록.
func craftable_ids() -> Array:
	var out: Array = []
	for w in WeaponDB.weapons:
		var id := String(w.get("id", ""))
		if id != "" and int(w.get("craft_cost", 0)) > 0 and not is_owned(id):
			out.append(id)
	return out


func can_craft(id: String) -> bool:
	return upgrade_unlocked and not is_owned(id) and GameManager.tokens >= weapon_craft_cost(id)


## 토큰을 소모해 새 무기를 제작(보유 목록에 추가). 성공 시 true.
func craft_weapon(id: String) -> bool:
	if not can_craft(id):
		return false
	GameManager.tokens -= weapon_craft_cost(id)
	owned.append(id)
	weapons_changed.emit()
	return true


## 보유 무기를 해당 종류 슬롯에 장착. 성공 시 true.
func equip_weapon(id: String) -> bool:
	if not is_owned(id):
		return false
	var kind := WeaponDB.kind_of(id)
	if kind != "ranged" and kind != "melee":
		return false
	equipped[kind] = id
	weapons_changed.emit()
	return true


func current_damage(kind: String) -> float:
	return ranged_damage() if kind == "ranged" else melee_damage()


## 장착한 원거리 무기의 사거리(px). 엑셀 "<무기id>_range" 로 조정 가능.
func ranged_range() -> float:
	return Balance.get_float(str(equipped["ranged"]) + "_range", RANGED_RANGE_BASE)


## 장착한 근접 무기의 사거리(px). 엑셀 "<무기id>_range" 로 조정 가능.
func melee_range() -> float:
	return Balance.get_float(str(equipped["melee"]) + "_range", MELEE_RANGE_BASE)


## 종류별 사거리 조회(kind: "ranged" | "melee").
func range_of(kind: String) -> float:
	return ranged_range() if kind == "ranged" else melee_range()


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
		"owned": owned,
	}


func from_dict(d: Dictionary) -> void:
	ammo = int(d.get("ammo", 12))
	upgrade_unlocked = bool(d.get("upgrade_unlocked", false))
	ranged_level = int(d.get("ranged_level", 0))
	melee_level = int(d.get("melee_level", 0))
	equipped = d.get("equipped", {"ranged": "pistol", "melee": "knife"})
	# 보유 무기: 세이브값 우선, 없으면 WeaponDB 기본 보유(craft_cost=0).
	var saved_owned: Array = d.get("owned", [])
	if saved_owned.is_empty():
		var defaults := WeaponDB.default_owned()
		owned = defaults if not defaults.is_empty() else ["pistol", "knife"]
	else:
		owned = []
		for id in saved_owned:
			owned.append(String(id))
