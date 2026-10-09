class_name RecipeCards
extends RefCounted
## 레시피 카드 격자 + 상세 패널 공용 빌더 — 캠프 '레시피 북'과 밤 '주방 준비'가 같은 모습으로 쓴다.
##   카드: 완성 요리 그림 + 이름 + 숙련도 게이지. 미해금 = 회색 + 🔒, god 선호 음식 = 분홍 테두리 + ♥ 선호.
##   상세: 요리·이름·레벨, 필요한 재료(아이콘·수량·손질, 선택 시 보유 수), 조리 기구·시간, 만족도, 숙련도.

const _KI := preload("res://scripts/minigames/kitchen_item.gd")
const LOCKED_TINT := Color(0.45, 0.45, 0.45)
const PREF_COLOR := Color(1.0, 0.5, 0.7)   # 선호 음식 테두리
const CARD_SIZE := Vector2(180, 200)


## 보유한 레시피 먼저, 그다음 미해금(엑셀 순서 유지).
static func order() -> Array[String]:
	var owned: Array[String] = []
	var locked: Array[String] = []
	for r in RecipeDB.recipes:
		var id := String(r["id"])
		if RecipeDB.is_unlocked(id):
			owned.append(id)
		else:
			locked.append(id)
	return owned + locked


## 카드 1장. on_press 는 카드 클릭(선택) 시 호출(인자 없음 — 호출 측에서 bind).
static func card(id: String, selected: bool, on_press: Callable) -> Button:
	var owned := RecipeDB.is_unlocked(id)
	var pref := BelamiManager.is_preferred(id)
	var d := RecipeDB.cook_data(id)
	var c := Button.new()
	c.focus_mode = Control.FOCUS_NONE
	c.custom_minimum_size = CARD_SIZE
	c.toggle_mode = true
	c.button_pressed = selected
	c.pressed.connect(on_press)
	_style_card(c, pref)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10
	box.offset_right = -10
	box.offset_top = 12
	box.offset_bottom = -10
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(box)
	var dish := dish_visual(d, 84.0)
	dish.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(dish)
	var name_lb := Label.new()
	name_lb.text = ("🔒 " if not owned else "") + String(d["display_name"])
	name_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lb.add_theme_font_size_override("font_size", 20)
	name_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_lb)
	box.add_child(mastery_bar(id, 12.0))
	if pref:
		var tag := Label.new()
		tag.text = "♥ 선호"
		tag.add_theme_font_size_override("font_size", 16)
		tag.add_theme_color_override("font_color", PREF_COLOR)
		tag.add_theme_color_override("font_outline_color", Color.BLACK)
		tag.add_theme_constant_override("outline_size", 4)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		tag.offset_left = -78
		tag.offset_top = 6
		tag.offset_right = -8
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		c.add_child(tag)
	if not owned:
		c.modulate = LOCKED_TINT
	return c


## 카드 배경·테두리(보통/마우스 올림/선택). 선호 음식은 모든 상태에서 분홍 테두리.
static func _style_card(c: Button, pref: bool) -> void:
	var states := {
		"normal": [Color(0.12, 0.12, 0.14), Color(0.26, 0.26, 0.3), 2],
		"hover": [Color(0.17, 0.17, 0.2), Color(0.4, 0.4, 0.45), 2],
		"pressed": [Color(0.06, 0.06, 0.07), Color(0.9, 0.9, 0.95), 3],
		"hover_pressed": [Color(0.08, 0.08, 0.1), Color(0.95, 0.95, 1.0), 3],
		"disabled": [Color(0.1, 0.1, 0.11), Color(0.2, 0.2, 0.22), 2],
	}
	for st in states:
		var v: Array = states[st]
		var sb := StyleBoxFlat.new()
		sb.bg_color = v[0]
		sb.set_corner_radius_all(6)
		sb.border_color = PREF_COLOR if pref else v[1]
		var selected_state: bool = st == "pressed" or st == "hover_pressed"
		sb.set_border_width_all((7 if selected_state else 4) if pref else int(v[2])) # 선호 + 선택 = 더 굵게
		c.add_theme_stylebox_override(st, sb)


## 완성 요리 모습(접시 + 첫 재료 색) — 밤 주방의 요리 표시와 같은 그림.
static func dish_visual(d: Dictionary, px: float) -> Control:
	var k = _KI.new()
	k.custom_minimum_size = Vector2(px, px)
	k.size = Vector2(px, px)
	k.set_item({"type": "dish", "recipe": d, "grade": ""})
	return k


## 숙련도 게이지: 금색 = 다음 레벨 강화까지, 초록 = 최대 레벨.
static func mastery_bar(id: String, h: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, h)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var req := RecipeDB.mastery_required(id)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.16, 0.16, 0.18)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.95, 0.75, 0.3) if req >= 0 else Color(0.5, 0.9, 0.55)
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	if req < 0:
		bar.max_value = 1
		bar.value = 1
	else:
		bar.max_value = maxi(1, req)
		bar.value = mini(RecipeDB.mastery_of(id), req)
	return bar


static func section_label(text: String) -> Label:
	var lb := Label.new()
	lb.text = "── %s ──" % text
	lb.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	return lb


## 상세 패널 내용 채우기(기존 자식은 비움). show_stock = 재료별 보유 수(가방+창고) 표시.
## 버튼(구입·강화·메뉴 포함 등)은 호출 측이 이어서 추가한다.
static func fill_detail(box: VBoxContainer, id: String, show_stock: bool, dish_px := 120.0) -> void:
	for ch in box.get_children():
		ch.queue_free()
	var owned := RecipeDB.is_unlocked(id)
	var pref := BelamiManager.is_preferred(id)
	var d := RecipeDB.cook_data(id)
	var dish := dish_visual(d, dish_px)
	dish.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(dish)
	var name_lb := Label.new()
	name_lb.text = String(d["display_name"])
	name_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lb.add_theme_font_size_override("font_size", 36)
	box.add_child(name_lb)
	var lv := Label.new()
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.text = ("Lv%d / %d" % [int(d["level"]), RecipeDB.max_level(id)]) if owned else "🔒 미해금 — 구입하면 Lv1"
	lv.modulate = Color(0.7, 0.95, 0.7) if owned else Color(0.7, 0.7, 0.7)
	box.add_child(lv)
	if pref:
		var pl := Label.new()
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pl.text = "♥ 오늘 god의 선호 음식 — 만족도·토큰 ×%s" % str(RecipeDB.setting("preferred_bonus", 1.5))
		pl.add_theme_color_override("font_color", PREF_COLOR)
		box.add_child(pl)

	box.add_child(section_label("필요한 재료"))
	var counts := {}
	for ing in d.get("ingredients", []):
		counts[String(ing)] = int(counts.get(String(ing), 0)) + 1
	for ing in counts:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var icon = _KI.new()
		icon.custom_minimum_size = Vector2(42, 42)
		icon.set_item(_KI.make_ingredient(ing))
		row.add_child(icon)
		var t := Label.new()
		var chop := RecipeDB.chop_count(ing)
		t.text = "%s ×%d    %s" % [ItemDB.display_name(ing), int(counts[ing]),
			("조리대에서 %d번 썰기" % chop) if chop > 0 else "손질 없이 사용"]
		row.add_child(t)
		if show_stock:
			var have := GameManager.cooking_stock(ing)
			var st := Label.new()
			st.text = "보유 %d" % have
			st.modulate = Color(0.6, 0.95, 0.6) if have >= int(counts[ing]) else Color(1.0, 0.45, 0.4)
			row.add_child(st)
		box.add_child(row)

	box.add_child(section_label("조리"))
	var stn := String(d.get("station", ""))
	var t_sec := float(d.get("timer_seconds", 0.0))
	var st_lb := Label.new()
	st_lb.text = String(CookStation.INFO.get(stn, {}).get("name", stn)) + (" · %s초" % str(t_sec).trim_suffix(".0") if t_sec > 0.0 else " · 바로 완성")
	box.add_child(st_lb)
	var sat: Dictionary = d.get("sat", {})
	var sat_lb := Label.new()
	sat_lb.text = "만족도  A %d · B %d · C %d" % [int(sat.get("A", 0)), int(sat.get("B", 0)), int(sat.get("C", 0))]
	box.add_child(sat_lb)

	box.add_child(section_label("숙련도"))
	var req := RecipeDB.mastery_required(id)
	var ms := Label.new()
	ms.text = ("%d / %d  (Lv%d 강화까지)" % [RecipeDB.mastery_of(id), req, int(d["level"]) + 1]) if req >= 0 else "%d  (최대 레벨)" % RecipeDB.mastery_of(id)
	box.add_child(ms)
	box.add_child(mastery_bar(id, 18.0))
	if not owned:
		for ch in box.get_children():
			ch.modulate = ch.modulate * LOCKED_TINT.lightened(0.3)
