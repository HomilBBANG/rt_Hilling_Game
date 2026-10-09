extends Panel
## 탐험 준비 화면의 인벤토리 칸. 드래그(꺼내기) + 드롭(옮기기) 지원.
## side: "carry"(가져갈 가방) | "storage"(창고). 다른 쪽에서 드롭하면 on_drop 콜백 호출.

var item_id := ""
var count := 0
var side := ""
var on_drop: Callable # func(data: Dictionary, to_side: String)


## 칸에 아이템 표시(아이콘 있으면 아이콘, 없으면 이름 + 겹친 수량).
func fill(id: String, cnt: int) -> void:
	item_id = id
	count = cnt
	var icon := ItemDB.icon_path(id)
	if icon != "":
		var tex := TextureRect.new()
		tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tex.texture = load(icon)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tex)
	else:
		var lbl := Label.new()
		lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.text = ItemDB.display_name(id)
		add_child(lbl)
	if cnt > 1:
		var c := Label.new()
		c.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		c.offset_left = -45.0
		c.offset_top = -33.0
		c.offset_right = -5.0
		c.offset_bottom = -3.0
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		c.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		c.text = "×%d" % cnt
		add_child(c)


## 아이템이 있는 칸을 드래그하면 {item_id, count, side} 를 넘긴다.
func _get_drag_data(_pos: Vector2) -> Variant:
	if item_id == "":
		return null
	var preview := Label.new()
	preview.text = "%s ×%d" % [ItemDB.display_name(item_id), count]
	preview.modulate = Color(1, 1, 1, 0.9)
	set_drag_preview(preview)
	return {"item_id": item_id, "count": count, "side": side}


## 반대편(side가 다른) 아이템만 이 칸에 드롭 가능.
func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and String(data.get("side", "")) != side


func _drop_data(_pos: Vector2, data: Variant) -> void:
	if on_drop.is_valid():
		on_drop.call(data, side)
