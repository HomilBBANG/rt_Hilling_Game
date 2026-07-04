extends Control
## 최소 HUD (PRD 7) + 인벤토리 창(I 키, 전역).
## 주의: trust(신뢰도)는 절대 표시하지 않는다(PRD 3.4 — 비노출).
##
## 인벤토리: 화면 좌=캐릭터(총 든 idle)+착용 장비, 우=가방(run_inventory).
## 1칸 = 물건 1개(수량만큼 칸을 채움). 열려 있는 동안 게임은 일시정지.

const BAG_MIN_SLOTS := 18 # 최소 표시 칸(빈 가방도 격자로 보이게). 수집분이 많으면 그만큼 늘어남

@onready var _day_label: Label = $TopBar/DayLabel
@onready var _phase_label: Label = $TopBar/PhaseLabel
@onready var _inventory: Control = $Inventory
@onready var _char_body: AnimatedSprite2D = $Inventory/CharView/Body
@onready var _ranged_label: Label = $Inventory/Equip/RangedLabel
@onready var _melee_label: Label = $Inventory/Equip/MeleeLabel
@onready var _switch_note: Label = $Inventory/Equip/SwitchNote
@onready var _weapon_list: VBoxContainer = $Inventory/Equip/WeaponList
@onready var _bag_grid: GridContainer = $Inventory/BagScroll/BagGrid
@onready var _bag_title: Label = $Inventory/RightTitle

var _inv_open := false

# 우클릭 컨텍스트 메뉴 + 버리기 수량 다이얼로그(코드로 구성).
var _ctx_panel: PanelContainer = null
var _ctx_use_btn: Button = null
var _ctx_quick_btn: Button = null
var _ctx_drop_btn: Button = null
var _ctx_item := ""
var _ctx_count := 0
var _drop_dialog: Control = null
var _drop_title: Label = null
var _drop_qty_label: Label = null
var _drop_item_id := ""
var _drop_qty := 1
var _drop_max := 1
var _inv_msg: Label = null


func _ready() -> void:
	GameManager.step_changed.connect(_on_step_changed)
	GameManager.day_changed.connect(_on_day_changed)
	# 좌측 캐릭터: 탐사 플레이어와 동일한 idle 몸통(총/팔은 씬에서 겹침).
	_char_body.sprite_frames = PlayerFrames.build()
	_char_body.play("idle")
	_build_item_menus()
	$Inventory/Dim.gui_input.connect(_on_dim_input)
	_inventory.visible = false
	_refresh()


## 우클릭 메뉴·버리기 수량 다이얼로그·안내 라벨을 코드로 생성(인벤토리 위에 겹침).
func _build_item_menus() -> void:
	_ctx_panel = PanelContainer.new()
	_ctx_panel.visible = false
	var cvb := VBoxContainer.new()
	_ctx_use_btn = _menu_button("사용하기")
	_ctx_quick_btn = _menu_button("퀵슬롯 등록")
	_ctx_drop_btn = _menu_button("버리기")
	cvb.add_child(_ctx_use_btn)
	cvb.add_child(_ctx_quick_btn)
	cvb.add_child(_ctx_drop_btn)
	_ctx_panel.add_child(cvb)
	_inventory.add_child(_ctx_panel)
	_ctx_use_btn.pressed.connect(_on_ctx_use)
	_ctx_quick_btn.pressed.connect(_on_ctx_quick)
	_ctx_drop_btn.pressed.connect(_on_ctx_drop)

	_drop_dialog = Control.new()
	_drop_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drop_dialog.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drop_dialog.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drop_dialog.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(300, 0)
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	_drop_title = Label.new()
	_drop_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_drop_title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	var minus := _menu_button("－")
	_drop_qty_label = Label.new()
	_drop_qty_label.custom_minimum_size = Vector2(60, 0)
	_drop_qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var plus := _menu_button("＋")
	row.add_child(minus)
	row.add_child(_drop_qty_label)
	row.add_child(plus)
	vb.add_child(row)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 12)
	var confirm := _menu_button("버리기")
	var cancel := _menu_button("취소")
	row2.add_child(confirm)
	row2.add_child(cancel)
	vb.add_child(row2)
	_inventory.add_child(_drop_dialog)
	minus.pressed.connect(func(): _drop_qty = maxi(1, _drop_qty - 1); _update_drop_qty_label())
	plus.pressed.connect(func(): _drop_qty = mini(_drop_max, _drop_qty + 1); _update_drop_qty_label())
	confirm.pressed.connect(_on_drop_confirm)
	cancel.pressed.connect(func(): _drop_dialog.visible = false)

	_inv_msg = Label.new()
	_inv_msg.position = Vector2(360, 300)
	_inv_msg.modulate = Color(1.0, 0.9, 0.4)
	_inv_msg.z_index = 20
	_inventory.add_child(_inv_msg)


func _menu_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(110, 34)
	return b


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_I:
		_toggle_inventory()
		get_viewport().set_input_as_handled()


func _toggle_inventory() -> void:
	_inv_open = not _inv_open
	_inventory.visible = _inv_open
	get_tree().paused = _inv_open # 인벤토리 여는 동안 게임 정지
	if _ctx_panel:
		_ctx_panel.visible = false
	if _drop_dialog:
		_drop_dialog.visible = false
	if _inv_open:
		_refresh_equip()
		_rebuild_bag()


func _refresh_equip() -> void:
	_ranged_label.text = "원거리: %s" % _weapon_name(String(WeaponManager.equipped.get("ranged", "")))
	_melee_label.text = "근접: %s" % _weapon_name(String(WeaponManager.equipped.get("melee", "")))
	_rebuild_weapon_switch()


## 보유 무기 목록 + 장착 버튼. 장비 변경은 캠프에서만 가능(다른 곳에선 비활성).
func _rebuild_weapon_switch() -> void:
	for c in _weapon_list.get_children():
		c.queue_free()
	var in_camp := GameManager.current_step == GameManager.Step.MORNING_PREP
	_switch_note.text = "── 무기 변경 ──" if in_camp else "── 무기 변경 (캠프에서만) ──"
	for raw_id in WeaponManager.owned:
		var id := String(raw_id)
		var kind := WeaponDB.kind_of(id)
		var equipped_here: bool = String(WeaponManager.equipped.get(kind, "")) == id
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(360, 32)
		btn.focus_mode = Control.FOCUS_NONE
		var tag := "장착중" if equipped_here else "장착"
		btn.text = "%s [%s] — %s" % [WeaponDB.display_name(id), _kind_label(kind), tag]
		btn.disabled = equipped_here or not in_camp
		btn.pressed.connect(_on_equip.bind(id))
		_weapon_list.add_child(btn)


func _kind_label(kind: String) -> String:
	return "원거리" if kind == "ranged" else "근접"


func _on_equip(id: String) -> void:
	if WeaponManager.equip_weapon(id):
		_refresh_equip()


## run_inventory 를 1칸=1개로 펼쳐 가방 그리드를 다시 채운다.
func _rebuild_bag() -> void:
	_bag_title.text = "가방   (무게 %0.1f / %0.0f)" % [GameManager.current_weight(), GameManager.carry_max_weight()]
	for c in _bag_grid.get_children():
		c.queue_free()
	# 같은 재료는 한 칸에 최대 max_stack(기본 99)개까지 겹침. 넘치면 다음 칸으로.
	var stacks: Array = [] # 각 원소: {id, count}
	for id in GameManager.run_inventory:
		var cnt := int(GameManager.run_inventory[id])
		var per := maxi(1, ItemDB.max_stack(String(id)))
		while cnt > 0:
			var here := mini(cnt, per)
			stacks.append({"id": String(id), "count": here})
			cnt -= here
	# 최소 칸 유지 + 열 배수로 올림(빈 가방도 격자로 보이게).
	var cols := maxi(1, _bag_grid.columns)
	var slot_count := maxi(stacks.size(), BAG_MIN_SLOTS)
	if slot_count % cols != 0:
		slot_count += cols - (slot_count % cols)
	for i in slot_count:
		if i < stacks.size():
			_bag_grid.add_child(_make_slot(String(stacks[i]["id"]), int(stacks[i]["count"])))
		else:
			_bag_grid.add_child(_make_slot("", 0))


func _make_slot(item_id: String, count: int) -> Control:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(64, 64)
	if item_id == "":
		slot.modulate = Color(1, 1, 1, 0.3) # 빈 칸
		return slot
	_add_item_visual(slot, item_id) # 아이콘 있으면 아이콘, 없으면 이름
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.gui_input.connect(_on_slot_input.bind(item_id, count))
	if count > 1: # 겹친 개수를 우측 하단에 표시
		var cnt_lbl := Label.new()
		cnt_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		cnt_lbl.offset_left = -34.0
		cnt_lbl.offset_top = -24.0
		cnt_lbl.offset_right = -4.0
		cnt_lbl.offset_bottom = -2.0
		cnt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cnt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		cnt_lbl.text = "×%d" % count
		slot.add_child(cnt_lbl)
	return slot


## 칸에 아이템 아이콘(있으면) 또는 이름 라벨을 채운다. 공용.
static func _add_item_visual(slot: Control, item_id: String) -> void:
	var icon := ItemDB.icon_path(item_id)
	if icon != "":
		var tex := TextureRect.new()
		tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tex.texture = load(icon)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(tex)
	else:
		var lbl := Label.new()
		lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.text = ItemDB.display_name(item_id)
		slot.add_child(lbl)


func _item_name(id: String) -> String:
	return ItemDB.display_name(id)


# ── 우클릭 메뉴 / 사용 / 버리기 ─────────────────────────

func _on_slot_input(event: InputEvent, item_id: String, count: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_open_ctx(item_id, count, get_global_mouse_position())


func _open_ctx(item_id: String, count: int, pos: Vector2) -> void:
	_ctx_item = item_id
	_ctx_count = count
	_ctx_use_btn.visible = ItemDB.is_consumable(item_id) # 소비 아이템만 '사용하기'
	_ctx_quick_btn.visible = ItemDB.is_consumable(item_id) # 회복 아이템만 퀵슬롯 등록
	_ctx_panel.position = pos
	_ctx_panel.visible = true
	_drop_dialog.visible = false


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_ctx_panel.visible = false # 빈 곳 클릭 시 메뉴 닫기


func _on_ctx_use() -> void:
	_ctx_panel.visible = false
	_use_item(_ctx_item)


func _on_ctx_quick() -> void:
	_ctx_panel.visible = false
	GameManager.quick_slot = _ctx_item # 퀵슬롯(1번)에 등록
	_flash("%s 을(를) 퀵슬롯 1에 등록" % ItemDB.display_name(_ctx_item))


func _on_ctx_drop() -> void:
	_ctx_panel.visible = false
	if _ctx_count >= 2: # 2개 이상이면 수량 선택
		_open_drop_dialog(_ctx_item, _ctx_count)
	else:
		_drop_item(_ctx_item, 1)


func _open_drop_dialog(item_id: String, count: int) -> void:
	_drop_item_id = item_id
	_drop_max = count
	_drop_qty = 1
	_drop_title.text = "%s 버리기 (최대 %d개)" % [ItemDB.display_name(item_id), count]
	_update_drop_qty_label()
	_drop_dialog.visible = true


func _update_drop_qty_label() -> void:
	_drop_qty_label.text = "%d개" % _drop_qty


func _on_drop_confirm() -> void:
	_drop_dialog.visible = false
	_drop_item(_drop_item_id, _drop_qty)


## 소비 아이템 사용 → 체력(스태미나) 회복. 탐험 중 + 체력이 가득 안 찼을 때만.
func _use_item(item_id: String) -> void:
	if not ItemDB.is_consumable(item_id):
		return
	if int(GameManager.run_inventory.get(item_id, 0)) <= 0:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		_flash("탐험 중에만 사용할 수 있어요")
		return
	if player.stamina >= player.max_stamina:
		_flash("체력이 가득 찼습니다")
		return
	player.stamina = minf(player.max_stamina, player.stamina + float(ItemDB.heal_amount(item_id)))
	GameManager.remove_item(item_id, 1)
	_flash("%s 사용 — 체력 +%d" % [ItemDB.display_name(item_id), ItemDB.heal_amount(item_id)])
	_rebuild_bag()


## 아이템 버리기 → 인벤토리에서 제거. 탐험 중이면 플레이어 발밑 바닥에 남긴다.
func _drop_item(item_id: String, qty: int) -> void:
	qty = clampi(qty, 1, int(GameManager.run_inventory.get(item_id, 0)))
	if qty <= 0:
		return
	GameManager.remove_item(item_id, qty)
	var s := get_tree().get_first_node_in_group("scavenge")
	var player := get_tree().get_first_node_in_group("player")
	if s and s.has_method("drop_on_floor") and player:
		s.drop_on_floor(item_id, qty, player.global_position)
	_flash("%s ×%d 버림" % [ItemDB.display_name(item_id), qty])
	_rebuild_bag()


func _flash(msg: String) -> void:
	_inv_msg.text = msg
	var t := get_tree().create_timer(2.0) # paused 여도 동작(process_always 기본)
	t.timeout.connect(func(): if _inv_msg: _inv_msg.text = "")


func _weapon_name(id: String) -> String:
	match id:
		"pistol":
			return "권총"
		"knife":
			return "나이프"
		"":
			return "-"
	return id


func _on_step_changed(_step: int) -> void:
	_refresh()


func _on_day_changed(_day: int) -> void:
	_refresh()


func _refresh() -> void:
	_day_label.text = "Day %d" % GameManager.day
	_phase_label.text = _phase_text(GameManager.current_step)


func _phase_text(step: int) -> String:
	match step:
		GameManager.Step.MORNING_PREP:
			return "아침 · 준비"
		GameManager.Step.SCAVENGE:
			return "낮 · 탐사"
		GameManager.Step.NIGHT:
			return "밤 · god"
	return ""
