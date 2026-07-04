extends Node
## 몬스터 종류/능력치 로더 — data/monsters.json(엑셀에서 변환)을 읽는다.
## 행 순서 = 몬스터 종류 순서(스폰 시 순환). 첫 종류가 '가장 첫번째 일반 몬스터'.
##
## 워크플로:
##   1) data/monsters.xlsx 편집(id, max_hp, contact_damage, speed, ... , sprite)
##   2) `python tools/convert_monsters.py` 실행 → monsters.json 갱신
##   3) 게임 실행 시 이 로더가 자동으로 읽음

const DATA_PATH := "res://data/monsters.json"

var types: Array = [] # 각 원소는 Dictionary(몬스터 필드)


func _ready() -> void:
	reload()


func reload() -> void:
	types.clear()
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("MonsterDB: %s 없음 — 변환 스크립트를 먼저 실행하세요." % DATA_PATH)
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_ARRAY:
		types = parsed
	else:
		push_error("MonsterDB: JSON 형식 오류(배열이어야 함)")


func count() -> int:
	return types.size()


## i 번째 몬스터 종류(범위를 넘으면 순환). 데이터가 없으면 빈 사전.
func get_type(i: int) -> Dictionary:
	if types.is_empty():
		return {}
	return types[i % types.size()]


## id 로 몬스터 종류 조회(보스 등). 없으면 빈 사전.
func get_by_id(id: String) -> Dictionary:
	for t in types:
		if String(t.get("id", "")) == id:
			return t
	return {}


## 보스를 제외한 일반 몬스터 종류 목록(일반 스폰 풀).
func regular_types() -> Array:
	var out: Array = []
	for t in types:
		if not bool(t.get("is_boss", false)):
			out.append(t)
	return out


## i 번째 일반 몬스터 종류(순환). 없으면 빈 사전.
func get_regular(i: int) -> Dictionary:
	var reg := regular_types()
	if reg.is_empty():
		return {}
	return reg[i % reg.size()]
