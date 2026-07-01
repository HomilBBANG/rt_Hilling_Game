extends Node
## NPC 해금 표 로더 — data/npc_unlocks.json 을 읽는다(엑셀에서 변환된 파일).
## 항목: { threshold:int, npc_id, display_name, role, unlocks, note }. 임계값 오름차순.
##
## 워크플로:
##   1) data/npc_unlocks.xlsx 를 엑셀로 편집(임계값·NPC 설정)
##   2) `python tools/convert_npc_unlocks.py` 실행 → npc_unlocks.json 갱신
##   3) 게임 실행 시 이 로더가 자동으로 읽음

const DATA_PATH := "res://data/npc_unlocks.json"

var entries: Array = []


func _ready() -> void:
	reload()


func reload() -> void:
	entries.clear()
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("NpcUnlockDB: %s 없음 — 변환 스크립트를 먼저 실행하세요." % DATA_PATH)
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_ARRAY:
		push_error("NpcUnlockDB: JSON 형식 오류(배열이어야 함)")
		return
	for row in parsed:
		if typeof(row) == TYPE_DICTIONARY:
			entries.append(row)
	entries.sort_custom(func(a, b): return float(a.get("threshold", 0)) < float(b.get("threshold", 0)))


## UI용 표시 이름 조회. 없으면 npc_id 반환.
func display_name_of(npc_id: String) -> String:
	for e in entries:
		if String(e.get("npc_id", "")) == npc_id:
			return String(e.get("display_name", npc_id))
	return npc_id
