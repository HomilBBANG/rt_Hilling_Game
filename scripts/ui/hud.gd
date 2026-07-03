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

var _inv_open := false


func _ready() -> void:
	GameManager.step_changed.connect(_on_step_changed)
	GameManager.day_changed.connect(_on_day_changed)
	# 좌측 캐릭터: 탐사 플레이어와 동일한 idle 몸통(총/팔은 씬에서 겹침).
	_char_body.sprite_frames = PlayerFrames.build()
	_char_body.play("idle")
	_inventory.visible = false
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_I:
		_toggle_inventory()
		get_viewport().set_input_as_handled()


func _toggle_inventory() -> void:
	_inv_open = not _inv_open
	_inventory.visible = _inv_open
	get_tree().paused = _inv_open # 인벤토리 여는 동안 게임 정지
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
	slot.custom_minimum_size = Vector2(80, 80)
	var name_lbl := Label.new()
	name_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if item_id == "":
		slot.modulate = Color(1, 1, 1, 0.3) # 빈 칸
	else:
		name_lbl.text = _item_name(item_id)
	slot.add_child(name_lbl)
	if item_id != "" and count > 1: # 겹친 개수를 우측 하단에 표시
		var cnt_lbl := Label.new()
		cnt_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		cnt_lbl.offset_left = -34.0
		cnt_lbl.offset_top = -24.0
		cnt_lbl.offset_right = -4.0
		cnt_lbl.offset_bottom = -2.0
		cnt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		cnt_lbl.text = "×%d" % count
		slot.add_child(cnt_lbl)
	return slot


func _item_name(id: String) -> String:
	return ItemDB.display_name(id)


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
