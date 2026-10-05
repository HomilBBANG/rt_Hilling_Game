extends Node
## 무기 카탈로그 로더 — data/weapons.json(엑셀에서 변환)을 읽는다.
## 각 무기: {id, display_name, kind(ranged|melee), base_damage, craft_cost, uses_ammo}.
## craft_cost=0 인 무기는 기본 보유(WeaponManager 참고).

const DATA_PATH := "res://data/weapons.json"

var weapons: Array = [] # 각 원소는 Dictionary
var _by_id: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	weapons.clear()
	_by_id.clear()
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("WeaponDB: %s 없음 — 변환 스크립트를 먼저 실행하세요." % DATA_PATH)
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_ARRAY:
		push_error("WeaponDB: JSON 형식 오류(배열이어야 함)")
		return
	weapons = parsed
	for w in weapons:
		if typeof(w) == TYPE_DICTIONARY and w.has("id"):
			_by_id[String(w["id"])] = w


func get_weapon(id: String) -> Dictionary:
	return _by_id.get(id, {})


func display_name(id: String) -> String:
	return String(get_weapon(id).get("display_name", id))


func kind_of(id: String) -> String:
	return String(get_weapon(id).get("kind", ""))


func base_damage(id: String) -> float:
	return float(get_weapon(id).get("base_damage", 0.0))


func craft_cost(id: String) -> int:
	return int(get_weapon(id).get("craft_cost", 0))


func uses_ammo(id: String) -> bool:
	return bool(get_weapon(id).get("uses_ammo", false))


## 총구 X 위치(Aim 로컬, 무기별 총열 길이). 없으면 기본 19.
func muzzle_x(id: String) -> float:
	return float(get_weapon(id).get("muzzle_x", 19.0))


## 무기 스프라이트 텍스처 경로(sprite 열, assets/characters/<sprite>.png). 없으면 "".
func sprite_path(id: String) -> String:
	var sp := String(get_weapon(id).get("sprite", ""))
	if sp == "":
		return ""
	var p := "res://assets/characters/%s.png" % sp
	return p if ResourceLoader.exists(p) else ""


## craft_cost=0 인 기본 보유 무기 id 목록.
func default_owned() -> Array:
	var out: Array = []
	for w in weapons:
		if int(w.get("craft_cost", 0)) == 0:
			out.append(String(w["id"]))
	return out


## 특정 종류(ranged|melee)의 무기 id 목록(표시 순서).
func ids_of_kind(kind: String) -> Array:
	var out: Array = []
	for w in weapons:
		if String(w.get("kind", "")) == kind:
			out.append(String(w["id"]))
	return out
