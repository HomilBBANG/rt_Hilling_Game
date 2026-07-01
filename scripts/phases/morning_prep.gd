extends Control
## 아침 준비 페이즈 (PRD 2). 인벤토리 점검 · 지역 선택 · 장비 착용.
## TODO: 지역 선택 UI(RegionData 목록), 장비 착용, 인벤토리 표시.

func _ready() -> void:
	$Center/VBox/Title.text = "아침 준비 — Day %d" % GameManager.day
	$Center/VBox/ActionButton.pressed.connect(GameManager.advance)
