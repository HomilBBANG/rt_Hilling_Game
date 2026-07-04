extends Panel
## 탐험 준비 화면의 인벤토리 칸. 드래그(꺼내기) + 드롭(옮기기) 지원.
## side: "carry"(가져갈 가방) | "storage"(창고). 다른 쪽에서 드롭하면 on_drop 콜백 호출.

var item_id := ""
var count := 0
var side := ""
var on_drop: Callable # func(data: Dictionary, to_side: String)


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
