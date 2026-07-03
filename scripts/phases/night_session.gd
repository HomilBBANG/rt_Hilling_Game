extends Control
## 밤 세션 — 쿠킹 + 서빙 + 급식 (PRD 3.2/3.4/3.5 + 급식 스펙).
## 1분 타이머 동안 요리해 god에게 서빙. 단, 서빙은 자동이 아니라
## 완성한 요리를 '들고' 플레이어가 직접 god에게 걸어가야 전달된다(WASD 이동).
## (추후 '서빙 보조' NPC가 부활하면 자동 서빙으로 대체될 예정 — PRD 3.5)
##
## 서빙 성공마다 만족↑ + 토큰↑ + 먹인 수↑. 재료(run_inventory)는 요리 완성 시 소모.
## 종료 시 만족≥목표면 성공(토큰 획득 + 누적 만족도), 미달이면 실패.
##
## 미니게임: STACK_ORDER(재료 순서 클릭) / TIMER(적정 순간 꺼내기). 해금은 RecipeDB 관리.

@export var run_seconds := 60.0
@export var target_satisfaction := 60.0
@export var move_speed := 260.0

var _time_left := 0.0
var _satisfaction := 0.0
var _tokens_pending := 0
var _fed := 0
var _ended := false

var _current: RecipeData = null
var _seq_index := 0
var _mistakes := 0

var _frying := false
var _fry_elapsed := 0.0
var _fry_target := 0.0

# 들고 있는 요리(비어 있으면 없음): {recipe:RecipeData, grade:String}
var _held: Dictionary = {}
var _player_pos := Vector2.ZERO
var _pos_init := false

## 주방 준비 화면(배치+레시피 선택). _started 전에는 조리/타이머가 진행되지 않는다.
var _started := false
var _selected: Dictionary = {} # 오늘 밤 조리할 레시피 id 집합

## 서빙 도우미 NPC: 요리를 받아 god 에게 걸어가 전달하고 돌아온다.
enum ServerState { IDLE, CARRYING, RETURNING }
const _SERVER_SPEED := 300.0
var _server_state: int = ServerState.IDLE
var _server_pos := Vector2.ZERO
var _server_home := Vector2.ZERO
var _server_dish: Dictionary = {}

@onready var _time_label: Label = $TopBar/TimeLabel
@onready var _sat_label: Label = $TopBar/SatLabel
@onready var _sat_bar: ProgressBar = $TopBar/SatBar
@onready var _tokens_label: Label = $TopBar/TokensLabel
@onready var _fed_label: Label = $TopBar/FedLabel
@onready var _field: Control = $Field
@onready var _player_node: AnimatedSprite2D = $Field/Player
@onready var _counter: ColorRect = $Field/Counter
@onready var _counter_label: Label = $Field/CounterLabel
@onready var _god: AnimatedSprite2D = $Field/God
@onready var _belami: Label = $Field/Belami # god 머리 위 반응(표정) 버블
@onready var _serve_hint: Label = $Field/ServeHint
@onready var _recipe_label: Label = $BottomBar/RecipeLabel
@onready var _seq_row: HBoxContainer = $Field/SequenceRow
@onready var _mistake_label: Label = $Field/MistakeLabel
@onready var _cook_progress: ProgressBar = $Field/CookProgress
@onready var _timer_hint: Label = $Field/TimerHint
@onready var _collect_button: Button = $Field/CollectButton
@onready var _held_label: Label = $BottomBar/HeldLabel
@onready var _ingredients_box: HBoxContainer = $Field/Ingredients
@onready var _server: AnimatedSprite2D = $Field/Server
@onready var _server_dish_label: Label = $Field/ServerDish
@onready var _results: Control = $Results
@onready var _prep: Control = $Prep
@onready var _npc_list: VBoxContainer = $Prep/Center/Panel/Margin/VBox/NpcList
@onready var _recipe_list: VBoxContainer = $Prep/Center/Panel/Margin/VBox/RecipeList
@onready var _start_button: Button = $Prep/Center/Panel/Margin/VBox/StartButton


func _ready() -> void:
	run_seconds = Balance.get_float("night_seconds", run_seconds) # 엑셀 조정 가능
	target_satisfaction = Balance.get_float("target_satisfaction", target_satisfaction)
	move_speed = PlayerStats.move_speed() # 탐사·캠프와 동일한 이동 속도(Tab 업그레이드 반영)
	_time_left = run_seconds
	_sat_bar.max_value = target_satisfaction
	_sat_bar.value = 0
	_build_ingredient_buttons()
	_collect_button.pressed.connect(_on_collect)
	_results.visible = false
	_god.sprite_frames = GodFrames.build()
	_god.play("idle")
	_belami.text = "( ˘ ᴗ ˘ )"
	_held_label.text = ""
	_apply_gauge_visibility()
	Config.gauges_visibility_changed.connect(_on_gauges_visibility_changed)
	# 요리 전 '주방 준비' 화면 먼저(배치 + 레시피 선택). 시작 버튼 전엔 조리 진행 안 함.
	_start_button.pressed.connect(_start_cooking)
	_build_prep()
	_prep.visible = true
	_update_hud()


func _process(delta: float) -> void:
	if _ended or not _started: # 준비 화면 동안엔 타이머·조리 정지
		return
	_time_left = maxf(0.0, _time_left - delta)
	_time_label.text = "남은 시간: %0.0f초" % _time_left
	# 튀김(타이머형)은 조리대 근처에 있을 때만 진행(자리 비우면 잠시 멈춤).
	if _frying and _near_counter():
		_update_frying(delta)
	_update_field(delta)
	if _time_left <= 0.0:
		_end_session()


# ── 플레이어 이동 & 직접 서빙 ───────────────────────────

func _update_field(_delta: float) -> void:
	if _field.size.x <= 0.0:
		return
	if not _pos_init:
		_player_pos = Vector2(40.0, _field.size.y * 0.5)
		_player_node.sprite_frames = PlayerFrames.build("idle_hand", "run_hand")
		_player_node.play("idle")
		# 서빙 도우미 초기화(조리대 아래에서 대기).
		_server_home = Vector2(120.0, _field.size.y * 0.5 + 70.0)
		_server_pos = _server_home
		_server.sprite_frames = _npc_idle_frames()
		_server.play("idle")
		_server.position = _server_pos
		_pos_init = true

	var d := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		d.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		d.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		d.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		d.y += 1.0
	_player_pos += d.normalized() * move_speed * _delta
	_player_pos.x = clampf(_player_pos.x, 48.0, _field.size.x - 48.0)
	_player_pos.y = clampf(_player_pos.y, 48.0, _field.size.y - 48.0)
	_player_node.position = _player_pos
	if d != Vector2.ZERO:
		if _player_node.animation != "run":
			_player_node.play("run")
		_player_node.flip_h = d.x > 0
	elif _player_node.animation != "idle":
		_player_node.play("idle")

	var counter_pos := Vector2(64.0, _field.size.y * 0.5)
	_counter.position = counter_pos - _counter.size * 0.5
	_counter_label.position = counter_pos - _counter_label.size * 0.5 - Vector2(0.0, 40.0)

	var belami_pos := Vector2(_field.size.x - 60.0, _field.size.y * 0.5)
	_god.position = belami_pos # AnimatedSprite2D 는 중심 기준
	_belami.position = belami_pos + Vector2(0.0, -72.0) - _belami.size * 0.5 # 머리 위 반응 버블

	# 조리대 근처에서만 요리 입력 활성화.
	var near := _player_pos.distance_to(counter_pos) < 72.0
	_set_cooking_enabled(near)

	if not _held.is_empty() and _player_pos.distance_to(belami_pos) < 56.0:
		_do_serve()

	_update_server(_delta, belami_pos) # 서빙 도우미가 요리를 받아 god 에게 걸어가 전달

	if not _held.is_empty():
		_serve_hint.text = "서빙 도우미에게 맡기는 중…" if _has_helper("serving") else "WASD로 god에게 이동해 전달하세요"
	elif not near:
		_serve_hint.text = "왼쪽 조리대로 이동해 요리하세요"
	else:
		_serve_hint.text = "조리대: 재료를 순서대로 클릭 / 튀김은 적정 순간 꺼내기"


func _near_counter() -> bool:
	if not _pos_init or _field.size.x <= 0.0:
		return false
	var counter_pos := Vector2(64.0, _field.size.y * 0.5)
	return _player_pos.distance_to(counter_pos) < 72.0


func _set_cooking_enabled(on: bool) -> void:
	for b in _ingredients_box.get_children():
		if b is Button:
			b.disabled = not on
	_collect_button.disabled = not on


func _do_serve() -> void:
	var recipe: RecipeData = _held["recipe"]
	var grade: String = _held["grade"]
	_apply_serve(recipe, grade)
	_held = {}
	_held_label.text = ""
	_next_recipe() # 다음 요리 시작


## 서빙 도우미: 대기 중 완성 요리를 받아 god 에게 걸어가 전달하고 제자리로 돌아온다.
func _update_server(delta: float, god_pos: Vector2) -> void:
	if not _has_helper("serving"):
		_server.visible = false
		_server_dish_label.visible = false
		return
	_server.visible = true
	# 대기 중이고 완성 요리가 있으면 받아서 출발(플레이어는 다음 요리 진행).
	if _server_state == ServerState.IDLE and not _held.is_empty():
		_server_dish = _held.duplicate()
		_held = {}
		_held_label.text = ""
		_server_state = ServerState.CARRYING
		_next_recipe()
	match _server_state:
		ServerState.CARRYING:
			_move_server_to(god_pos, delta)
			if _server_pos.distance_to(god_pos) < 56.0:
				if not _server_dish.is_empty():
					_apply_serve(_server_dish["recipe"], _server_dish["grade"])
				_server_dish = {}
				_server_state = ServerState.RETURNING
		ServerState.RETURNING:
			_move_server_to(_server_home, delta)
			if _server_pos.distance_to(_server_home) < 8.0:
				_server_state = ServerState.IDLE
	_server.position = _server_pos
	var carrying := _server_state == ServerState.CARRYING and not _server_dish.is_empty()
	_server_dish_label.visible = carrying
	if carrying:
		_server_dish_label.text = String(_server_dish["recipe"].display_name)
		_server_dish_label.position = _server_pos + Vector2(-30.0, -72.0)


func _move_server_to(target: Vector2, delta: float) -> void:
	var to := target - _server_pos
	if to.length() > 1.0:
		_server_pos += to.normalized() * _SERVER_SPEED * delta
		_server.flip_h = to.x > 0.0


func _npc_idle_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation("idle")
	sf.set_animation_loop("idle", true)
	sf.set_animation_speed("idle", 2.5)
	var i := 0
	while ResourceLoader.exists("res://assets/npc/npc_a_idle_%d.png" % i):
		sf.add_frame("idle", load("res://assets/npc/npc_a_idle_%d.png" % i))
		i += 1
	if sf.get_frame_count("idle") == 0:
		sf.add_frame("idle", load("res://assets/npc/npc_a_dead.png"))
	return sf


func _apply_serve(recipe: RecipeData, grade: String) -> void:
	var bonus := 1.5 if BelamiManager.is_preferred(recipe.id) else 1.0
	if _has_helper("kitchen"): # 주방 도우미: 만족/토큰 보너스
		bonus *= 1.25
	_satisfaction += _sat_gain(grade) * bonus
	_tokens_pending += int(_token_gain(grade) * bonus)
	_fed += 1
	_belami.text = _belami_face(grade)
	_update_hud()


# ── 게이지 노출 스위치 ──────────────────────────────────

func _apply_gauge_visibility() -> void:
	_sat_label.visible = Config.show_gauges
	_sat_bar.visible = Config.show_gauges


func _on_gauges_visibility_changed(_visible: bool) -> void:
	_apply_gauge_visibility()


# ── 주방 준비 (NPC 배치 + 레시피 선택) ──────────────────

func _build_prep() -> void:
	_build_npc_rows()
	_build_recipe_rows()


## 슬롯별(주방/서빙) 배치 가능한 NPC 행 구성. 부활한 NPC만 배치 가능.
func _build_npc_rows() -> void:
	for c in _npc_list.get_children():
		c.queue_free()
	for slot in NPCManager.PLACEMENT_SLOTS: # ["kitchen", "serving"]
		var npc_id := _npc_for_role(String(slot))
		var row := HBoxContainer.new()
		var label := Label.new()
		label.custom_minimum_size = Vector2(260, 0)
		label.text = "%s: %s" % [_role_label(String(slot)), (_npc_name(npc_id) if npc_id != "" else "-")]
		row.add_child(label)
		if npc_id != "" and NPCManager.is_revived(npc_id):
			var btn := Button.new()
			btn.focus_mode = Control.FOCUS_NONE
			btn.custom_minimum_size = Vector2(160, 34)
			var placed := String(NPCManager.placement.get(slot, "")) == npc_id
			btn.text = "배치 해제" if placed else "배치하기"
			btn.pressed.connect(_on_toggle_place.bind(String(slot), npc_id))
			row.add_child(btn)
		else:
			var note := Label.new()
			note.modulate = Color(0.6, 0.6, 0.6)
			note.text = "(아직 부활 안 함)"
			row.add_child(note)
		_npc_list.add_child(row)


func _on_toggle_place(slot: String, npc_id: String) -> void:
	var placed := String(NPCManager.placement.get(slot, "")) == npc_id
	NPCManager.assign(slot, "" if placed else npc_id)
	_build_npc_rows()


## 해금된 레시피를 다중 선택 토글로 구성(처음 열 때 전부 선택).
func _build_recipe_rows() -> void:
	for c in _recipe_list.get_children():
		c.queue_free()
	var unlocked := RecipeDB.unlocked()
	if _selected.is_empty():
		for r in unlocked:
			_selected[r.id] = true
	for r in unlocked:
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 34)
		btn.toggle_mode = true
		btn.button_pressed = bool(_selected.get(r.id, false))
		btn.text = _recipe_row_text(r, btn.button_pressed)
		btn.toggled.connect(_on_toggle_recipe.bind(r, btn))
		_recipe_list.add_child(btn)


func _on_toggle_recipe(pressed: bool, recipe: RecipeData, btn: Button) -> void:
	_selected[recipe.id] = pressed
	btn.text = _recipe_row_text(recipe, pressed)


func _recipe_row_text(r: RecipeData, selected: bool) -> String:
	var mark := "✓" if selected else " "
	var ings: Array[String] = []
	for ing in r.ingredient_ids:
		ings.append(_item_name(String(ing)))
	var mech := "튀김" if r.sub_mechanic == RecipeData.SubMechanic.TIMER else "순서"
	return "[%s] %s  (%s · %s)" % [mark, r.display_name, mech, ", ".join(ings)]


## '요리 시작' → 준비 화면 닫고 조리 진행. 선택이 없으면 전체 선택으로 대체.
func _start_cooking() -> void:
	var any := false
	for k in _selected.keys():
		if _selected[k]:
			any = true
			break
	if not any:
		for r in RecipeDB.unlocked():
			_selected[r.id] = true
	_prep.visible = false
	_started = true
	_next_recipe()
	_update_hud()


func _npc_for_role(role: String) -> String:
	for e in NpcUnlockDB.entries:
		if String(e.get("unlocks", "")) == role:
			return String(e.get("npc_id", ""))
	return ""


func _role_label(slot: String) -> String:
	return "주방 도우미" if slot == "kitchen" else "서빙 도우미"


func _npc_name(npc_id: String) -> String:
	return NpcUnlockDB.display_name_of(npc_id) if npc_id != "" else "-"


## 해당 슬롯에 부활한 NPC가 배치되어 있으면 true(배치 효과 판정).
func _has_helper(slot: String) -> bool:
	var id := String(NPCManager.placement.get(slot, ""))
	return id != "" and NPCManager.is_revived(id)


# ── 레시피 진행 ────────────────────────────────────────

func _build_ingredient_buttons() -> void:
	var ids := {}
	for r in RecipeDB.recipes:
		if r.sub_mechanic == RecipeData.SubMechanic.STACK_ORDER:
			for ing in r.ingredient_ids:
				ids[String(ing)] = true
	for ing in ids.keys():
		var b := Button.new()
		b.text = _item_name(ing)
		b.custom_minimum_size = Vector2(120, 44)
		b.focus_mode = Control.FOCUS_NONE # WASD 이동과 포커스 충돌 방지
		b.pressed.connect(_on_ingredient.bind(String(ing)))
		_ingredients_box.add_child(b)


func _next_recipe() -> void:
	# 들고 있는 요리가 있으면 전달 전까지 새 요리를 시작하지 않는다.
	if not _held.is_empty():
		return
	var options: Array = []
	for r in RecipeDB.unlocked():
		if not bool(_selected.get(r.id, false)): # 준비 화면에서 고른 것만
			continue
		if _can_afford(r):
			options.append(r)
	if options.is_empty():
		_current = null
		_recipe_label.text = "선택한 레시피 재료가 부족합니다"
		_show_mechanic_ui(-1)
		return
	_current = options[randi() % options.size()]
	var pref := " ★선호" if BelamiManager.is_preferred(_current.id) else ""
	_recipe_label.text = "요리: %s%s" % [_current.display_name, pref]
	if _current.sub_mechanic == RecipeData.SubMechanic.TIMER:
		_start_timer_recipe()
	else:
		_start_stack_recipe()


func _start_stack_recipe() -> void:
	_seq_index = 0
	_mistakes = 0
	_mistake_label.text = ""
	_frying = false
	_show_mechanic_ui(RecipeData.SubMechanic.STACK_ORDER)
	_render_sequence()


func _start_timer_recipe() -> void:
	_frying = true
	_fry_elapsed = 0.0
	_fry_target = maxf(0.5, _current.timer_seconds)
	_cook_progress.max_value = _fry_target
	_cook_progress.value = 0.0
	_show_mechanic_ui(RecipeData.SubMechanic.TIMER)
	_timer_hint.text = "튀기는 중..."


func _show_mechanic_ui(mechanic: int) -> void:
	var is_stack := mechanic == RecipeData.SubMechanic.STACK_ORDER
	var is_timer := mechanic == RecipeData.SubMechanic.TIMER
	_seq_row.visible = is_stack
	_mistake_label.visible = is_stack
	_ingredients_box.visible = is_stack
	_cook_progress.visible = is_timer
	_timer_hint.visible = is_timer
	_collect_button.visible = is_timer
	if not is_stack:
		_clear_sequence()


# ── 조합 순서형 입력 ───────────────────────────────────

func _on_ingredient(ing_id: String) -> void:
	if _ended or not _held.is_empty() or _current == null or not _near_counter():
		return
	if _current.sub_mechanic != RecipeData.SubMechanic.STACK_ORDER:
		return
	var expected := String(_current.ingredient_ids[_seq_index])
	if ing_id == expected:
		_seq_index += 1
		_render_sequence()
		if _seq_index >= _current.ingredient_ids.size():
			_hold_dish(_grade_for(_mistakes))
	else:
		_mistakes += 1
		_mistake_label.text = "실수 %d회" % _mistakes


# ── 타이머형(튀기기) ──────────────────────────────────

func _update_frying(delta: float) -> void:
	_fry_elapsed += delta
	_cook_progress.value = minf(_fry_elapsed, _fry_target)
	var diff := _fry_elapsed - _fry_target
	if diff < -1.0:
		_timer_hint.text = "튀기는 중..."
	elif diff <= 0.4:
		_timer_hint.text = "지금 꺼내세요!"
	else:
		_timer_hint.text = "타는 중! 빨리!"
	if _fry_elapsed > _fry_target + 2.0:
		_finish_fry()


func _on_collect() -> void:
	if _ended or not _frying or not _held.is_empty() or not _near_counter():
		return
	_finish_fry()


func _finish_fry() -> void:
	_frying = false
	var diff: float = absf(_fry_elapsed - _fry_target)
	_hold_dish(_timer_grade(diff))


# ── 요리 완성 → 들기 ──────────────────────────────────

func _hold_dish(grade: String) -> void:
	_consume(_current) # 재료는 완성 시 소모
	_held = {"recipe": _current, "grade": grade}
	_held_label.text = "들고 있는 요리: %s (%s등급)" % [_current.display_name, grade]
	_current = null
	_frying = false
	_show_mechanic_ui(-1)
	_recipe_label.text = "완성! god에게 직접 가져가세요"


# ── 세션 종료 ──────────────────────────────────────────

func _end_session() -> void:
	_ended = true
	_frying = false
	var success := _satisfaction >= target_satisfaction
	var awarded := 0
	if success:
		awarded = _tokens_pending
		GameManager.add_tokens(awarded)
	BelamiManager.complete_night(success, _satisfaction)
	_show_results(success, awarded)


func _show_results(success: bool, awarded: int) -> void:
	_results.visible = true
	$Results/Center/VBox/ResultTitle.text = "오늘 밤 — %s" % ("성공" if success else "실패")
	$Results/Center/VBox/ResultReaction.text = "god  %s  %s" % [
		_belami_face_final(success), ("만족했다" if success else "시큰둥하다")
	]
	var stats := "획득 토큰: %d   ·   먹인 음식: %d개" % [awarded, _fed]
	if Config.show_gauges:
		stats += "   ·   만족 %0.0f / %0.0f" % [_satisfaction, target_satisfaction]
	$Results/Center/VBox/ResultStats.text = stats
	$Results/Center/VBox/NextButton.pressed.connect(GameManager.advance)


# ── 헬퍼 ──────────────────────────────────────────────

func _grade_for(mistakes: int) -> String:
	if mistakes == 0:
		return "A"
	if mistakes == 1:
		return "B"
	return "C"


func _timer_grade(diff: float) -> String:
	if diff <= 0.4:
		return "A"
	if diff <= 1.0:
		return "B"
	return "C"


func _sat_gain(grade: String) -> float:
	match grade:
		"A":
			return 25.0
		"B":
			return 16.0
	return 8.0


func _token_gain(grade: String) -> int:
	match grade:
		"A":
			return 30
		"B":
			return 18
	return 8


func _belami_face(grade: String) -> String:
	match grade:
		"A":
			return "( ◕ ᴗ ◕ )"
		"B":
			return "( ˘ ᴗ ˘ )"
	return "( ・_・ )"


func _belami_face_final(success: bool) -> String:
	return "( ◕ ᴗ ◕ )" if success else "( ˘ ︵ ˘ )"


func _recipe_cost(recipe: RecipeData) -> Dictionary:
	var cost := {}
	for ing in recipe.ingredient_ids:
		var key := String(ing)
		cost[key] = int(cost.get(key, 0)) + 1
	return cost


func _can_afford(recipe: RecipeData) -> bool:
	var inv: Dictionary = GameManager.run_inventory
	var cost := _recipe_cost(recipe)
	for ing in cost:
		if int(inv.get(ing, 0)) < int(cost[ing]):
			return false
	return true


func _consume(recipe: RecipeData) -> void:
	var inv: Dictionary = GameManager.run_inventory
	var cost := _recipe_cost(recipe)
	for ing in cost:
		inv[ing] = int(inv.get(ing, 0)) - int(cost[ing])


func _render_sequence() -> void:
	_clear_sequence()
	if _current == null:
		return
	for i in _current.ingredient_ids.size():
		var lbl := Label.new()
		lbl.text = _item_name(String(_current.ingredient_ids[i]))
		if i < _seq_index:
			lbl.modulate = Color(0.5, 0.9, 0.5)
		elif i == _seq_index:
			lbl.modulate = Color(1.0, 0.9, 0.4)
		else:
			lbl.modulate = Color(0.7, 0.7, 0.7)
		_seq_row.add_child(lbl)
		if i < _current.ingredient_ids.size() - 1:
			var arrow := Label.new()
			arrow.text = "  →  "
			_seq_row.add_child(arrow)


func _clear_sequence() -> void:
	for c in _seq_row.get_children():
		c.queue_free()


func _update_hud() -> void:
	_sat_label.text = "만족 %0.0f / %0.0f" % [_satisfaction, target_satisfaction]
	_sat_bar.value = minf(_satisfaction, target_satisfaction)
	_tokens_label.text = "토큰(예정): %d" % _tokens_pending
	_fed_label.text = "먹인 수: %d" % _fed


func _item_name(id: String) -> String:
	var path := "res://resources/items/%s.tres" % id
	if ResourceLoader.exists(path):
		var it := load(path) as ItemData
		if it:
			return it.display_name
	return id
