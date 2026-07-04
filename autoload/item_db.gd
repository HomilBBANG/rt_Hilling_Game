extends Node
## 아이템 목록 로더 — data/items.json(엑셀에서 변환)을 읽는다.
## 각 아이템: {id, display_name, category, max_stack}.
## 인벤토리 표시 이름 + 한 칸 겹치기(스택) 최대 개수를 여기서 제공.

const DATA_PATH := "res://data/items.json"
const DEFAULT_MAX_STACK := 99 # 목록에 없는 아이템의 기본 최대 스택

var items: Array = []
var _by_id: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	items.clear()
	_by_id.clear()
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("ItemDB: %s 없음 — 변환 스크립트를 먼저 실행하세요." % DATA_PATH)
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_ARRAY:
		push_error("ItemDB: JSON 형식 오류(배열이어야 함)")
		return
	items = parsed
	for it in items:
		if typeof(it) == TYPE_DICTIONARY and it.has("id"):
			_by_id[String(it["id"])] = it


func get_item(id: String) -> Dictionary:
	return _by_id.get(id, {})


func display_name(id: String) -> String:
	return String(get_item(id).get("display_name", id))


func max_stack(id: String) -> int:
	return int(get_item(id).get("max_stack", DEFAULT_MAX_STACK))


func category(id: String) -> String:
	return String(get_item(id).get("category", ""))


func weight(id: String) -> float:
	return float(get_item(id).get("weight", 1.0)) # 목록에 없으면 기본 1


func is_consumable(id: String) -> bool:
	return bool(get_item(id).get("consumable", false))


func heal_amount(id: String) -> int:
	return int(get_item(id).get("heal", 0))
