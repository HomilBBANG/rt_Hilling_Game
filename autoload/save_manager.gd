extends Node
## 세이브/로드 매니저 (PRD 3.7). JSON 기반, 사람이 읽기 쉬운 구조.
## 저장은 GameManager 가 페이즈 시작 시점에만 호출한다(미드세션 세이브 없음).

const SAVE_PATH := "user://savegame.json"


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game(data: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: 세이브 파일 열기 실패 — %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


func load_game() -> Dictionary:
	if not has_save():
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveManager: 세이브 파싱 실패")
		return {}
	return parsed


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)
