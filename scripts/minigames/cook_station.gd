@tool
class_name CookStation
extends ColorRect
## 밤 쿠킹 조리 기구(조리대/튀김기/냄비/테이블/쓰레기통).
## night_session.tscn 의 Field 아래 인스턴스로 두고, Godot 에디터 2D 화면에서 드래그해 배치한다.
## 크기도 에디터에서 조절 가능(상호작용 기준점 = 사각형 중심).
## station_id 만 고르면 이름·색은 자동으로 적용된다(에디터에서도 바로 보임).

const INFO := {
	"counter": {"name": "조리대", "color": Color(0.55, 0.42, 0.25)},
	"fryer": {"name": "튀김기", "verb": "튀기기", "color": Color(0.78, 0.56, 0.18)},
	"pot": {"name": "냄비", "verb": "끓이기", "color": Color(0.32, 0.44, 0.62)},
	"table": {"name": "테이블", "color": Color(0.46, 0.32, 0.2)},
	"trash": {"name": "쓰레기통", "color": Color(0.3, 0.34, 0.3)},
}

@export_enum("counter", "fryer", "pot", "table", "trash") var station_id: String = "counter":
	set(v):
		station_id = v
		_apply()

var bar: ProgressBar  # 튀김기/냄비 게이지(밤 세션이 갱신)
var status: Label     # 기구 아래 상태 문구(밤 세션이 갱신)
var _name_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_name_label.add_theme_constant_override("outline_size", 4)
	add_child(_name_label, false, Node.INTERNAL_MODE_FRONT)

	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.visible = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.z_index = 2000 # 기구 z(발 높이 정렬) 위로 — 앞에 선 캐릭터에 가리지 않게
	add_child(bar, false, Node.INTERNAL_MODE_FRONT)

	status = Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 13)
	status.add_theme_color_override("font_outline_color", Color.BLACK)
	status.add_theme_constant_override("outline_size", 4)
	status.z_index = 2000
	add_child(status, false, Node.INTERNAL_MODE_FRONT)

	resized.connect(_layout)
	_apply()
	_layout()


## 상호작용 기준점(필드 좌표).
func center() -> Vector2:
	return position + size * 0.5


func display_name() -> String:
	return String(INFO.get(station_id, {}).get("name", station_id))


func _apply() -> void:
	var info: Dictionary = INFO.get(station_id, {})
	color = info.get("color", Color.GRAY)
	if _name_label:
		_name_label.text = String(info.get("name", station_id))


## 게이지·문구를 사각형 아래에 붙인다(크기 변경 시 재배치).
func _layout() -> void:
	if bar == null:
		return
	bar.position = Vector2(0.0, size.y + 4.0)
	bar.size = Vector2(size.x, 10.0)
	status.size = Vector2(200.0, 20.0)
	status.position = Vector2((size.x - 200.0) * 0.5, size.y + 16.0)
