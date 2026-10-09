class_name KitchenItem
extends Control
## 주방 물건(재료/요리) 하나를 그린다. 아이콘 이미지가 있으면 아이콘, 없으면
## cooking.xlsx ingredients 의 color 로 그린 임시 도형(색으로 구분).
##
## item(Dictionary) 형식 — 밤 세션 전체가 같은 형식을 쓴다.
##   재료  {type:"ing",  id, chopped:bool, chops:int, grade:"A|B|C", floor_t}
##   요리  {type:"dish", recipe:(RecipeDB.cook_data), grade, floor_t}
##   탄 요리 {type:"burnt", recipe}
##   썩은 것 {type:"rotten", name}
##
## 표시: 손질 전 재료 = 큰 원 / 손질한 재료 = 작은 조각 3개 / 요리 = 접시 위 /
##       탄 요리 = 접시 위 검은 덩어리 / 썩은 것 = 얼룩진 갈색. A가 아닌 등급은 우하단 글자.

const PLATE := Color(0.95, 0.94, 0.9)
const _GRADE_DOWN := {"A": "B", "B": "C", "C": "C"}

var item: Dictionary = {}

static var _icons := {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(42, 42)
	size = custom_minimum_size


func set_item(it: Dictionary) -> void:
	item = it
	queue_redraw()


func _draw() -> void:
	if item.is_empty():
		return
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	match String(item.get("type", "")):
		"ing":
			var id := String(item["id"])
			var col := RecipeDB.ingredient_color(id)
			var tex := _icon(id)
			if item.get("chopped", false):
				for off in [Vector2(-0.4, 0.25), Vector2(0.4, 0.25), Vector2(0.0, -0.32)]:
					_blob(c + off * r, r * 0.42, col, tex)
			else:
				_blob(c, r * 0.9, col, tex)
		"dish":
			_plate(c, r)
			draw_circle(c, r * 0.55, dish_color(item["recipe"]))
		"burnt":
			_plate(c, r)
			draw_circle(c, r * 0.55, Color(0.12, 0.1, 0.08))
		"rotten":
			draw_circle(c, r * 0.85, Color(0.42, 0.44, 0.2))
			for off in [Vector2(-0.3, -0.2), Vector2(0.28, 0.1), Vector2(-0.05, 0.38)]:
				draw_circle(c + off * r, r * 0.16, Color(0.22, 0.25, 0.08))
	var g := String(item.get("grade", ""))
	if g != "" and g != "A":
		var font := ThemeDB.fallback_font
		var at := Vector2(size.x - 13.0, size.y - 1.0)
		draw_string_outline(font, at, g, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color.BLACK)
		draw_string(font, at, g, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.75, 0.3))


func _blob(p: Vector2, rad: float, col: Color, tex: Texture2D) -> void:
	if tex:
		draw_texture_rect(tex, Rect2(p - Vector2(rad, rad), Vector2(rad, rad) * 2.0), false)
	else:
		draw_circle(p, rad, col)
		draw_arc(p, rad, 0.0, TAU, 20, col.darkened(0.45), 1.5)


func _plate(c: Vector2, r: float) -> void:
	draw_circle(c, r * 0.95, PLATE)
	draw_arc(c, r * 0.95, 0.0, TAU, 24, Color(0.55, 0.55, 0.55), 1.5)


static func _icon(id: String) -> Texture2D:
	if not _icons.has(id):
		var p := ItemDB.icon_path(id)
		_icons[id] = load(p) if p != "" else null
	return _icons[id]


# ── item 헬퍼(밤 세션 공용) ─────────────────────────────

static func make_ingredient(id: String) -> Dictionary:
	return {"type": "ing", "id": id, "chopped": false, "chops": 0, "grade": "A", "floor_t": 0.0}


## 기구에 넣을 수 있는 상태(손질 완료이거나 손질이 필요 없는 재료).
static func is_usable(it: Dictionary) -> bool:
	return it.get("type", "") == "ing" and (it.get("chopped", false) or not RecipeDB.needs_chop(String(it["id"])))


static func grade_down(g: String, steps: int = 1) -> String:
	for i in steps:
		g = _GRADE_DOWN.get(g, g)
	return g


## 요리 접시 색 = 첫 재료 색.
static func dish_color(recipe: Dictionary) -> Color:
	var ings: Array = recipe.get("ingredients", [])
	return RecipeDB.ingredient_color(String(ings[0])) if not ings.is_empty() else Color(0.8, 0.6, 0.4)


static func label_of(it: Dictionary) -> String:
	var g := String(it.get("grade", ""))
	var suffix := " (%s)" % g if g != "" else ""
	match String(it.get("type", "")):
		"ing":
			var n := ItemDB.display_name(String(it["id"]))
			if it.get("chopped", false):
				n = "손질 " + n
			return n + (suffix if g != "A" else "")
		"dish":
			return String(it["recipe"]["display_name"]) + suffix
		"burnt":
			return "탄 " + String(it["recipe"]["display_name"])
		"rotten":
			return "썩은 " + String(it.get("name", "음식"))
	return "?"
