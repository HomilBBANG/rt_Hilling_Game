extends Control
## 밤 세션 — 쿠킹 + 서빙 + 급식 (PRD 3.2/3.4 + 급식 스펙).
## 3분 타이머 동안 요리해 벨라미에게 자동 서빙. 서빙마다 만족↑ + 토큰↑ + 먹인 수↑.
## 재료(run_inventory) 소모. 종료 시 만족≥목표면 성공(토큰 획득 + 신뢰도),
## 미달이면 실패(토큰 0, 재료 손실, 불만↑). 이후 결과 화면 → 다음 날.
##
## 미니게임 서브 메커닉(레시피별):
##  - STACK_ORDER(조합 순서형): 재료 버튼을 정해진 순서대로 클릭.
##  - TIMER(타이머형): 튀김기 진행 바를 보고 적정 타이밍에 '꺼내기'.
## 해금은 RecipeDB 가 관리(감자튀김은 감자 획득 시 해금).

@export var run_seconds := 180.0        # 약 3분
@export var target_satisfaction := 60.0

var _time_left := 0.0
var _satisfaction := 0.0
var _tokens_pending := 0
var _fed := 0
var _ended := false

var _current: RecipeData = null
var _seq_index := 0
var _mistakes := 0

# 타이머형(튀기기) 상태
var _frying := false
var _fry_elapsed := 0.0
var _fry_target := 0.0

@onready var _time_label: Label = $Margin/Main/TopBar/TimeLabel
@onready var _sat_label: Label = $Margin/Main/TopBar/SatLabel
@onready var _sat_bar: ProgressBar = $Margin/Main/TopBar/SatBar
@onready var _tokens_label: Label = $Margin/Main/TopBar/TokensLabel
@onready var _fed_label: Label = $Margin/Main/TopBar/FedLabel
@onready var _belami: Label = $Margin/Main/BelamiFace
@onready var _recipe_label: Label = $Margin/Main/CookArea/RecipeLabel
@onready var _seq_row: HBoxContainer = $Margin/Main/CookArea/SequenceRow
@onready var _mistake_label: Label = $Margin/Main/CookArea/MistakeLabel
@onready var _cook_progress: ProgressBar = $Margin/Main/CookArea/CookProgress
@onready var _timer_hint: Label = $Margin/Main/CookArea/TimerHint
@onready var _collect_button: Button = $Margin/Main/CookArea/CollectButton
@onready var _ingredients_box: HBoxContainer = $Margin/Main/Ingredients
@onready var _results: Control = $Results


func _ready() -> void:
	_time_left = run_seconds
	_sat_bar.max_value = target_satisfaction
	_sat_bar.value = 0
	_build_ingredient_buttons()
	_collect_button.pressed.connect(_on_collect)
	_results.visible = false
	_belami.text = "( ˘ ᴗ ˘ )"
	_apply_gauge_visibility()
	Config.gauges_visibility_changed.connect(_on_gauges_visibility_changed)
	_next_recipe()
	_update_hud()


func _process(delta: float) -> void:
	if _ended:
		return
	_time_left = maxf(0.0, _time_left - delta)
	_time_label.text = "남은 시간: %0.0f초" % _time_left
	if _frying:
		_update_frying(delta)
	if _time_left <= 0.0:
		_end_session()


# ── 게이지 노출 스위치 ──────────────────────────────────

func _apply_gauge_visibility() -> void:
	_sat_label.visible = Config.show_gauges
	_sat_bar.visible = Config.show_gauges


func _on_gauges_visibility_changed(_visible: bool) -> void:
	_apply_gauge_visibility()


# ── 레시피 진행 ────────────────────────────────────────

func _build_ingredient_buttons() -> void:
	# 조합 순서형 레시피에 등장하는 재료 종류로만 버튼 생성.
	var ids := {}
	for r in RecipeDB.recipes:
		if r.sub_mechanic == RecipeData.SubMechanic.STACK_ORDER:
			for ing in r.ingredient_ids:
				ids[String(ing)] = true
	for ing in ids.keys():
		var b := Button.new()
		b.text = _item_name(ing)
		b.custom_minimum_size = Vector2(120, 48)
		b.pressed.connect(_on_ingredient.bind(String(ing)))
		_ingredients_box.add_child(b)


func _next_recipe() -> void:
	var options: Array = []
	for r in RecipeDB.unlocked():
		if _can_afford(r):
			options.append(r)
	if options.is_empty():
		_current = null
		_recipe_label.text = "재료가 부족합니다"
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


## mechanic: STACK_ORDER / TIMER / -1(둘 다 숨김)
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
	if _ended or _current == null or _current.sub_mechanic != RecipeData.SubMechanic.STACK_ORDER:
		return
	var expected := String(_current.ingredient_ids[_seq_index])
	if ing_id == expected:
		_seq_index += 1
		_render_sequence()
		if _seq_index >= _current.ingredient_ids.size():
			_serve_dish(_grade_for(_mistakes))
	else:
		_mistakes += 1
		_mistake_label.text = "실수 %d회" % _mistakes


# ── 타이머형(튀기기) 입력/진행 ─────────────────────────

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
	# 방치하면 타서 C등급으로 자동 서빙(소프트락 방지).
	if _fry_elapsed > _fry_target + 2.0:
		_finish_fry()


func _on_collect() -> void:
	if _ended or not _frying:
		return
	_finish_fry()


func _finish_fry() -> void:
	_frying = false
	var diff: float = absf(_fry_elapsed - _fry_target)
	_serve_dish(_timer_grade(diff))


# ── 서빙(공통) ─────────────────────────────────────────

func _serve_dish(grade: String) -> void:
	_consume(_current)
	var bonus := 1.5 if BelamiManager.is_preferred(_current.id) else 1.0
	_satisfaction += _sat_gain(grade) * bonus
	_tokens_pending += int(_token_gain(grade) * bonus)
	_fed += 1
	_belami.text = _belami_face(grade)
	_update_hud()
	_next_recipe()


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
	$Results/Center/VBox/ResultReaction.text = "벨라미  %s  %s" % [
		_belami_face_final(success), ("만족했다" if success else "시큰둥하다")
	]
	var stats := "획득 토큰: %d   ·   먹인 음식: %d개" % [awarded, _fed]
	if Config.show_gauges:
		# 게이지 노출 시에만 정량 만족 수치 표시(숨김 시엔 표정/반응만).
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
			lbl.modulate = Color(0.5, 0.9, 0.5)   # 완료
		elif i == _seq_index:
			lbl.modulate = Color(1.0, 0.9, 0.4)    # 현재 차례
		else:
			lbl.modulate = Color(0.7, 0.7, 0.7)    # 대기
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
