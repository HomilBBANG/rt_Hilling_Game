extends Control
## 로비(메인 메뉴). 새 게임 / 불러오기 / 진행도 초기화(테스트용).
## 버튼이 GameManager.boot_mode 를 지정하고 게임 씬(main.tscn)으로 전환하면,
## main.gd 가 그 모드대로 새 게임 또는 이어하기를 시작한다.

const GAME_SCENE := "res://scenes/main.tscn"

@onready var _new_btn: Button = $Center/VBox/NewButton
@onready var _load_btn: Button = $Center/VBox/LoadButton
@onready var _reset_btn: Button = $Center/VBox/ResetButton
@onready var _info: Label = $Center/VBox/Info


func _ready() -> void:
	_new_btn.pressed.connect(_on_new)
	_load_btn.pressed.connect(_on_load)
	_reset_btn.pressed.connect(_on_reset)
	_refresh()


func _on_new() -> void:
	GameManager.boot_mode = "new"
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_load() -> void:
	if not SaveManager.has_save():
		return
	GameManager.boot_mode = "load"
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_reset() -> void:
	SaveManager.delete_save()
	_info.text = "진행도를 초기화했습니다."
	_refresh(false)


## 세이브 유무에 따라 버튼/안내를 갱신. update_info=false 면 초기화 안내문을 유지.
func _refresh(update_info := true) -> void:
	var has := SaveManager.has_save()
	_load_btn.disabled = not has
	if not update_info:
		return
	if has:
		var d := SaveManager.load_game()
		_info.text = "세이브: Day %d · %s" % [int(d.get("day", 1)), _phase_name(String(d.get("phase", "")))]
	else:
		_info.text = "세이브 없음"


func _phase_name(phase: String) -> String:
	match phase:
		"morning":
			return "아침(캠프)"
		"night":
			return "밤(요리)"
	return "-"
