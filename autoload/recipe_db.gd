extends Node
## 쿠킹 데이터 + 레시피 진행도 — data/cooking.json(엑셀 data/cooking.xlsx 에서 변환)을 읽는다.
##
## settings : 쿠킹 전역 밸런스(밤 시간, 목표 만족도, 등급 기준, 토큰, 숙련도 증가량 …)
## recipes  : 레시피별 해금 조건 + 레벨(1~3)별 재료(=투입 순서)/타이머 단계/등급별 만족도/강화 숙련도
##
## 진행도(세이브): 레시피별 현재 레벨(levels)과 누적 숙련도(mastery).
## 요리를 완성할 때마다 등급에 따라 숙련도가 쌓이고, 현재 레벨의 upgrade_mastery 를 넘으면
## 유저가 주방 준비 화면에서 수동으로 강화할 수 있다.

const DATA_PATH := "res://data/cooking.json"

var settings: Dictionary = {}
var recipes: Array = [] # 각 원소: {id, display_name, unlock, levels:[...]}
var _by_id: Dictionary = {}

var levels: Dictionary = {}  # recipe_id -> 현재 레벨(기본 1)
var mastery: Dictionary = {} # recipe_id -> 누적 숙련도


func _ready() -> void:
	reload()


func reload() -> void:
	settings.clear()
	recipes.clear()
	_by_id.clear()
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("RecipeDB: %s 없음 — 변환 스크립트를 먼저 실행하세요." % DATA_PATH)
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("RecipeDB: JSON 형식 오류(객체여야 함)")
		return
	settings = parsed.get("settings", {})
	recipes = parsed.get("recipes", [])
	for r in recipes:
		_by_id[String(r["id"])] = r


func setting(key: String, default: float) -> float:
	return float(settings.get(key, default))


func get_recipe(id: String) -> Dictionary:
	return _by_id.get(id, {})


func display_name(id: String) -> String:
	return String(get_recipe(id).get("display_name", id))


# ── 해금 ───────────────────────────────────────────────

## unlock: "default" | "item:<아이템id>"(해당 아이템을 한 번이라도 획득하면 해금)
func is_unlocked(id: String) -> bool:
	var u := String(get_recipe(id).get("unlock", "default"))
	if u == "" or u == "default":
		return true
	if u.begins_with("item:"):
		return CodexManager.is_item_obtained(u.substr(5))
	return false


## 잠긴 레시피의 해금 조건 안내 문구.
func unlock_text(id: String) -> String:
	var u := String(get_recipe(id).get("unlock", "default"))
	if u.begins_with("item:"):
		return "%s 획득 시 해금" % ItemDB.display_name(u.substr(5))
	return "해금 조건 미정"


func unlocked_ids() -> Array[String]:
	var out: Array[String] = []
	for r in recipes:
		if is_unlocked(String(r["id"])):
			out.append(String(r["id"]))
	return out


# ── 레벨 / 숙련도 ──────────────────────────────────────

func level_of(id: String) -> int:
	return int(levels.get(id, 1))


func max_level(id: String) -> int:
	return get_recipe(id).get("levels", []).size()


func mastery_of(id: String) -> int:
	return int(mastery.get(id, 0))


## 해당 레벨의 데이터(ingredients/timer_name/timer_seconds/sat/upgrade_mastery).
func level_data(id: String, lv: int = -1) -> Dictionary:
	if lv < 1:
		lv = level_of(id)
	for d in get_recipe(id).get("levels", []):
		if int(d.get("level", 0)) == lv:
			return d
	return {}


## 현재 레벨에서 다음 레벨로 가는 데 필요한 누적 숙련도. 최대 레벨이면 -1.
func mastery_required(id: String) -> int:
	if level_of(id) >= max_level(id):
		return -1
	return int(level_data(id).get("upgrade_mastery", 0))


func can_upgrade(id: String) -> bool:
	var req := mastery_required(id)
	return req >= 0 and mastery_of(id) >= req


func try_upgrade(id: String) -> bool:
	if not can_upgrade(id):
		return false
	levels[id] = level_of(id) + 1
	return true


## 요리 완성 시 등급에 따라 숙련도 증가. 증가량을 반환.
func add_mastery(id: String, grade: String) -> int:
	var gain := int(setting("mastery_" + grade.to_lower(), 1.0))
	mastery[id] = mastery_of(id) + gain
	return gain


## 조리할 요리 데이터(기본: 현재 레벨) — 밤 세션이 사용.
## {id, display_name, level, ingredients:Array, station("fryer"|"pot"|""), timer_seconds, sat:{A,B,C}}
## station 이 비어 있으면 조리대에서 바로 완성되는 요리.
func cook_data(id: String, lv: int = -1) -> Dictionary:
	if lv < 1:
		lv = level_of(id)
	var d := level_data(id, lv).duplicate(true)
	d["id"] = id
	d["display_name"] = display_name(id)
	d["level"] = lv
	if float(d.get("timer_seconds", 0.0)) <= 0.0:
		d["station"] = ""
	elif String(d.get("station", "")) == "":
		# 구버전 json(timer_name) 호환
		d["station"] = "pot" if String(d.get("timer_name", "")).contains("끓") else "fryer"
	return d


# ── 세이브 ─────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {"levels": levels.duplicate(), "mastery": mastery.duplicate()}


func from_dict(d: Dictionary) -> void:
	levels = {}
	mastery = {}
	var lv: Dictionary = d.get("levels", {})
	for k in lv.keys():
		levels[String(k)] = int(lv[k])
	var ms: Dictionary = d.get("mastery", {})
	for k in ms.keys():
		mastery[String(k)] = int(ms[k])
