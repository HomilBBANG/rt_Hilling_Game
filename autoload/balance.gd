extends Node
## 게임 밸런스 수치 로더 — data/balance.json(엑셀에서 변환)을 읽는다.
## 키-값 구조라 새 수치는 엑셀에 행만 추가하면 된다.
##
## 워크플로:
##   1) data/balance.xlsx 를 엑셀로 편집(key, value, note)
##   2) `python tools/convert_balance.py` 실행 → balance.json 갱신
##   3) 게임 실행 시 이 로더가 자동으로 읽음
##
## 사용: Balance.get_float("player_speed", 280.0) / Balance.get_int("scavenge_seconds", 150)

const DATA_PATH := "res://data/balance.json"

var _values: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	_values.clear()
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("Balance: %s 없음 — 변환 스크립트를 먼저 실행하세요." % DATA_PATH)
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_DICTIONARY:
		_values = parsed
	else:
		push_error("Balance: JSON 형식 오류(객체여야 함)")


func has(key: String) -> bool:
	return _values.has(key)


func get_float(key: String, def: float) -> float:
	return float(_values.get(key, def))


## 그날 밤 목표 만족도(balance.xlsx day_targets 시트).
## 적힌 날 중 day 이하인 가장 큰 날의 값 — 마지막 날 이후는 마지막 값 유지. 시트가 없으면 def.
func day_target(day: int, def: float) -> float:
	var t: Dictionary = _values.get("day_targets", {})
	var best_day := 0
	var best := def
	for k in t.keys():
		var d := int(k)
		if d <= day and d > best_day:
			best_day = d
			best = float(t[k])
	return best


func get_int(key: String, def: int) -> int:
	return int(_values.get(key, def))
