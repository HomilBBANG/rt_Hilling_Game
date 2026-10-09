@tool
class_name CookStation
extends ColorRect
## 밤 쿠킹 조리 기구(조리대/튀김기/냄비/믹싱볼/테이블/쓰레기통).
## night_session.tscn 의 Field 아래 인스턴스로 두고, Godot 에디터 2D 화면(또는 게임 내 배치 편집)에서
## 드래그해 배치한다. 크기도 에디터에서 조절 가능(상호작용 기준 = 사각형 가장자리).
## station_id 만 고르면 이름·색은 자동으로 적용된다(에디터에서도 바로 보임).
## 기구 위 물건(재료/요리)은 show_items() 로 사각형 안에 그린다.

const INFO := {
	"counter": {"name": "조리대", "color": Color(0.55, 0.42, 0.25)},
	"fryer": {"name": "튀김기", "verb": "튀기기", "color": Color(0.78, 0.56, 0.18)},
	"pot": {"name": "냄비", "verb": "끓이기", "color": Color(0.32, 0.44, 0.62)},
	"bowl": {"name": "믹싱볼", "color": Color(0.6, 0.48, 0.66)},
	"table": {"name": "테이블", "color": Color(0.46, 0.32, 0.2)},
	"trash": {"name": "쓰레기통", "color": Color(0.3, 0.34, 0.3)},
}

@export_enum("counter", "fryer", "pot", "bowl", "table", "trash") var station_id: String = "counter":
	set(v):
		station_id = v
		_apply()

var bar: ProgressBar  # 튀김기/냄비 게이지(밤 세션이 갱신)
var status: Label     # 기구 아래 상태 문구(밤 세션이 갱신)
var _name_label: Label
var _item_nodes: Array = [] # KitchenItem


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 20)
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
	status.add_theme_font_size_override("font_size", 18)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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


## 기구 위 물건 표시. 한 줄에 3개씩, 사각형 가운데 정렬.
func show_items(items: Array, item_size := 39.0) -> void:
	while _item_nodes.size() < items.size():
		var k := KitchenItem.new()
		k.z_as_relative = false
		k.z_index = 1900 # 캐릭터(z = 발 y, 최대 ~1080)보다 위, 안내 UI(2000)보다 아래
		add_child(k, false, Node.INTERNAL_MODE_BACK)
		_item_nodes.append(k)
	while _item_nodes.size() > items.size():
		_item_nodes.pop_back().queue_free()
	var per_row := 3
	var rows := ceili(items.size() / float(per_row))
	var gap := 4.0
	for i in items.size():
		var k: KitchenItem = _item_nodes[i]
		k.size = Vector2(item_size, item_size)
		var row := i / per_row
		var in_row := mini(per_row, items.size() - row * per_row)
		var w := in_row * item_size + (in_row - 1) * gap
		var h := rows * item_size + (rows - 1) * gap
		k.position = Vector2(
			(size.x - w) * 0.5 + (i % per_row) * (item_size + gap),
			(size.y - h) * 0.5 + row * (item_size + gap))
		k.pivot_offset = k.size * 0.5
		k.set_item(items[i]) # 같은 Dictionary 가 제자리에서 바뀌므로(손질 등) 매번 다시 그림


## 손질 클릭 피드백 — 첫 물건을 톡 튀게.
func pulse() -> void:
	if _item_nodes.is_empty():
		return
	var k: KitchenItem = _item_nodes[0]
	k.scale = Vector2(1.25, 0.8)
	k.create_tween().tween_property(k, "scale", Vector2.ONE, 0.12)


func _apply() -> void:
	var info: Dictionary = INFO.get(station_id, {})
	color = info.get("color", Color.GRAY)
	if _name_label:
		_name_label.text = String(info.get("name", station_id))


## 이름은 사각형 위, 게이지·문구는 아래(크기 변경 시 재배치).
func _layout() -> void:
	if bar == null:
		return
	_name_label.position = Vector2(0.0, -28.0)
	_name_label.size = Vector2(size.x, 28.0)
	bar.position = Vector2(0.0, size.y + 6.0)
	bar.size = Vector2(size.x, 15.0)
	status.size = Vector2(size.x, 30.0)
	status.position = Vector2(0.0, size.y + 24.0)
