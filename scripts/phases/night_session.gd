extends Control
## 밤 세션 — 쿠킹 + 서빙 + 급식 (PRD 3.2/3.4/3.5 + 급식 스펙).
## 1분 타이머 동안 여러 조리 기구를 오가며 요리해 god에게 서빙한다(WASD 이동, E 상호작용).
##
## 조리 기구(station)
##   조리대   : 재료를 순서대로 손질(마우스 클릭). 무침·샐러드처럼 불이 필요 없는 요리는 여기서 완성.
##   튀김기/냄비: 손질한 재료를 넣으면(E) 플레이어가 자리를 비워도 게이지가 알아서 오른다.
##              적정 순간에 꺼내야(E) 좋은 등급. 너무 오래 두면 타서 버려야 한다.
##   테이블   : 완성 요리를 올려두는 곳(E). 서빙 도우미(카밀라)가 최우선으로 가져가 god에게 전달.
##   쓰레기통 : 들고 있는 것(손질 재료/요리/탄 요리)을 버린다(E). 재료는 날아간다.
##
## 플레이어는 한 번에 하나만 든다: 손질한 재료(prepped) / 완성 요리(dish) / 탄 요리(burnt).
## 재료(직전 탐사 가방 + 창고)는 조리대 손질이 끝나는 순간 소모(가방 먼저).
## 등급 = 손질(실수 횟수)과 조리 기구(타이밍 오차) 중 낮은 쪽. 완성 시 레시피 숙련도 누적.
## 서빙마다 만족↑ + 토큰↑. 종료 시 만족≥목표면 성공(토큰 획득 + 누적 만족도), 미달이면 실패.
## 모든 쿠킹 밸런스·레시피는 data/cooking.xlsx(RecipeDB).
## 기구 위치·크기는 night_session.tscn 의 Field 아래 CookStation 노드를 에디터에서 드래그해 조정.

@export var run_seconds := 60.0
@export var target_satisfaction := 60.0
@export var move_speed := 260.0

## 조리 기구는 Field 아래 CookStation 인스턴스(에디터에서 드래그해 배치). 이름·색은 CookStation.INFO.
const COOKERS := ["fryer", "pot"]
const Z_UI := 2000      # 필드 위 안내·말풍선(깊이 정렬보다 위)
const Z_OVERLAY := 3000 # 준비/결과/배치 화면

var _time_left := 0.0
var _satisfaction := 0.0
var _tokens_pending := 0
var _fed := 0
var _ended := false

## 조리대에서 손질 중인 요리(RecipeDB.cook_data). 비어 있으면 손질할 요리 없음.
var _current: Dictionary = {}
var _seq_index := 0
var _mistakes := 0

## 들고 있는 것: {} | {kind:"prepped", recipe, mistakes} | {kind:"dish", recipe, grade} | {kind:"burnt", recipe}
var _held: Dictionary = {}
## 튀김기/냄비 상태: {} 비어 있음 | {recipe, mistakes, elapsed, target}
var _cookers := {"fryer": {}, "pot": {}}
## 테이블 위 완성 요리(먼저 놓은 순). 원소: {kind:"dish", recipe, grade}
var _table: Array = []

var _mastery_log: Dictionary = {} # 오늘 밤 레시피별 숙련도 획득(결과 화면 표시)

var _player_pos := Vector2.ZERO
var _pos_init := false
var _e_was_down := false
var _st_pos := {}   # station id -> 필드 좌표(중심, 매 프레임 노드에서 읽음)
var _st_nodes := {} # station id -> CookStation 노드

## 주방 준비 화면(배치+레시피 선택). _started 전에는 조리/타이머가 진행되지 않는다.
var _started := false
var _selected: Dictionary = {} # 오늘 밤 조리할 레시피 id 집합

## 서빙 도우미 NPC: 테이블(최우선) 또는 곁에 온 플레이어 손에서 요리를 받아 god 에게 전달.
enum ServerState { IDLE, FETCHING, CARRYING, RETURNING }
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
@onready var _god: AnimatedSprite2D = $Field/God
@onready var _belami: Label = $Field/Belami # god 머리 위 반응(표정) 버블
@onready var _serve_hint: Label = $Field/ServeHint
@onready var _recipe_label: Label = $BottomBar/RecipeLabel
@onready var _seq_row: HBoxContainer = $Field/SequenceRow
@onready var _mistake_label: Label = $Field/MistakeLabel
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
	run_seconds = RecipeDB.setting("night_seconds", run_seconds) # cooking.xlsx settings
	target_satisfaction = RecipeDB.setting("target_satisfaction", target_satisfaction)
	move_speed = PlayerStats.move_speed() # 탐사·캠프와 동일한 이동 속도(Tab 업그레이드 반영)
	_time_left = run_seconds
	_sat_bar.max_value = target_satisfaction
	_sat_bar.value = 0
	_collect_stations()
	_build_ingredient_buttons()
	_results.visible = false
	_god.sprite_frames = GodFrames.build()
	_god.play("idle")
	_belami.text = "( ˘ ᴗ ˘ )"
	_held_label.text = ""
	_apply_gauge_visibility()
	Config.gauges_visibility_changed.connect(_on_gauges_visibility_changed)
	# 요리 전 '주방 준비' 화면 먼저(배치 + 레시피 선택/강화). 시작 버튼 전엔 조리 진행 안 함.
	_start_button.pressed.connect(_start_cooking)
	_build_prep()
	_build_layout_tools() # 개발용: 게임 화면에서 기구 드래그 배치
	# 필드는 발 높이로 깊이 정렬(z_index = y)되므로, 항상 위에 보여야 하는 것들은 더 높게.
	for c in [_belami, _server_dish_label, _seq_row, _mistake_label, _ingredients_box, _serve_hint]:
		c.z_index = Z_UI
	for c in [_prep, _results, _layout_bar]:
		if c:
			c.z_index = Z_OVERLAY
	_prep.visible = true
	_update_hud()


func _process(delta: float) -> void:
	if _ended or not _started: # 준비 화면 동안엔 타이머·조리 정지
		return
	_time_left = maxf(0.0, _time_left - delta)
	_time_label.text = "남은 시간: %0.0f초" % _time_left
	_update_cookers(delta) # 튀김기/냄비는 플레이어 위치와 무관하게 진행
	_update_field(delta)
	if _time_left <= 0.0:
		_end_session()


# ── 필드: 이동 · 기구 배치 · 상호작용 ───────────────────

func _update_field(delta: float) -> void:
	if _field.size.x <= 0.0:
		return
	for id in _st_nodes: # 에디터에서 둔 위치 그대로(중심 기준)
		_st_pos[id] = _st_nodes[id].center()
	if not _pos_init:
		_player_pos = _unstick(Vector2(_field.size.x * 0.18, _field.size.y * 0.5))
		_player_node.sprite_frames = PlayerFrames.build("idle_hand", "run_hand")
		_player_node.play("idle")
		_build_nav() # 카밀라 길찾기 격자(기구·god 위치 기준)
		# 서빙 도우미는 테이블 아래에서 대기.
		if _st_nodes.has("table"):
			var tr: Rect2 = _st_nodes["table"].get_rect()
			_server_home = _unstick(Vector2(tr.get_center().x, tr.end.y + 60.0) - _FOOT_OFFSET)
		else:
			_server_home = _unstick(Vector2(120.0, _field.size.y * 0.5))
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
	_player_pos = _move_body(_player_pos, d.normalized() * move_speed * delta) # 기구·god에 막힘(발 충돌)
	_player_pos.x = clampf(_player_pos.x, 48.0, _field.size.x - 48.0)
	_player_pos.y = clampf(_player_pos.y, 48.0, _field.size.y - 48.0)
	_player_node.position = _player_pos
	if d != Vector2.ZERO:
		if _player_node.animation != "run":
			_player_node.play("run")
		_player_node.flip_h = d.x > 0
	elif _player_node.animation != "idle":
		_player_node.play("idle")

	var god_pos := _god_pos()
	_god.position = god_pos # AnimatedSprite2D 는 중심 기준
	_belami.position = god_pos + Vector2(0.0, -72.0) - _belami.size * 0.5 # 머리 위 반응 버블

	var near := _nearest_station()
	# E(엣지) — 가까운 기구와 상호작용.
	var e_down := Input.is_physical_key_pressed(KEY_E)
	if e_down and not _e_was_down and near != "":
		_interact(near)
	_e_was_down = e_down

	# 조리대 손질은 손이 비어 있고 조리대 곁일 때만.
	_set_cooking_enabled(near == "counter" and _held.is_empty() and not _current.is_empty())

	# god 곁(발 ↔ god 가장자리)에 완성 요리를 들고 오면 바로 서빙.
	if _held.get("kind", "") == "dish" and _foot_dist(_player_pos, _god_rect()) <= _station_range():
		_serve_from_hands()

	_update_server(delta)
	_refresh_stations(near)
	_update_hint(near)
	_update_depth()


func _god_pos() -> Vector2:
	return Vector2(_field.size.x - 60.0, _field.size.y * 0.5)


func _station_range() -> float:
	return RecipeDB.setting("station_range", 24.0) # 발 ↔ 기구 가장자리 거리(px)


## 범위 안에서 가장 가까운 기구 id. 없으면 "".
## 거리 = 플레이어 발 위치에서 기구 사각형 가장자리까지(기구 크기가 달라도 일정).
func _nearest_station() -> String:
	var best := ""
	var best_d := _station_range()
	for id in _st_nodes:
		var dist := _foot_dist(_player_pos, _st_nodes[id].get_rect())
		if dist < best_d:
			best_d = dist
			best = id
	return best


# ── 충돌(발 기준) ────────────────────────────────────
## 플레이어·카밀라 스프라이트(32px ×3, 중심 기준)의 발 부분만 충돌 →
## 기구/god 아래쪽에 서면 몸이 앞에 겹쳐 보인다(깊이 정렬은 _update_depth).
const _FOOT_OFFSET := Vector2(0.0, 36.0)
const _FOOT_SIZE := Vector2(24.0, 12.0)
const _SLIP := 4.0 # 이 이하로 걸친 모서리는 미끄러져 통과
## god(64px ×2, 중심 기준)이 막는 영역 — 하반신~발밑.
const _GOD_BLOCK := Rect2(-40.0, 14.0, 80.0, 40.0)


func _god_rect() -> Rect2:
	return Rect2(_god_pos() + _GOD_BLOCK.position, _GOD_BLOCK.size)


## 발이 들어갈 수 없는 영역: 기구 전부 + god.
func _obstacles() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for id in _st_nodes:
		out.append(_st_nodes[id].get_rect())
	out.append(_god_rect())
	return out


func _foot_rect(pos: Vector2) -> Rect2:
	return Rect2(pos + _FOOT_OFFSET - _FOOT_SIZE * 0.5, _FOOT_SIZE)


## 발 위치에서 사각형 가장자리까지 거리(상호작용·서빙 판정).
func _foot_dist(pos: Vector2, r: Rect2) -> float:
	var foot := pos + _FOOT_OFFSET
	var q := Vector2(clampf(foot.x, r.position.x, r.end.x), clampf(foot.y, r.position.y, r.end.y))
	return foot.distance_to(q)


## 시작 위치가 장애물과 겹치면(기구를 스폰 지점 위로 옮긴 경우 등) 아래로 빼낸다.
func _unstick(pos: Vector2) -> Vector2:
	for i in 8:
		var hit := false
		for r in _obstacles():
			if _foot_rect(pos).intersects(r):
				pos.y = r.end.y + _FOOT_SIZE.y * 0.5 - _FOOT_OFFSET.y + 1.0
				hit = true
		if not hit:
			break
	return pos


## x → y 축을 따로 이동·보정해 장애물 가장자리를 따라 미끄러지게 한다. 새 위치 반환.
func _move_body(pos: Vector2, motion: Vector2) -> Vector2:
	pos.x += motion.x
	pos = _push_out(pos, true, motion.x)
	pos.y += motion.y
	pos = _push_out(pos, false, motion.y)
	return pos


func _push_out(pos: Vector2, horizontal: bool, m: float) -> Vector2:
	if m == 0.0:
		return pos
	for r in _obstacles():
		var f := _foot_rect(pos)
		if not f.intersects(r):
			continue
		# 모서리를 몇 px만 걸친 경우(기구 높이가 1~2px 어긋난 줄 등)는 막지 않고 옆으로 빼낸다.
		var ox := minf(f.end.x, r.end.x) - maxf(f.position.x, r.position.x)
		var oy := minf(f.end.y, r.end.y) - maxf(f.position.y, r.position.y)
		if horizontal and oy <= _SLIP:
			pos.y += oy if f.get_center().y > r.get_center().y else -oy
			continue
		if not horizontal and ox <= _SLIP:
			pos.x += ox if f.get_center().x > r.get_center().x else -ox
			continue
		if horizontal:
			pos.x = (r.position.x - _FOOT_SIZE.x * 0.5 if m > 0.0 else r.end.x + _FOOT_SIZE.x * 0.5) - _FOOT_OFFSET.x
		else:
			pos.y = (r.position.y - _FOOT_SIZE.y * 0.5 if m > 0.0 else r.end.y + _FOOT_SIZE.y * 0.5) - _FOOT_OFFSET.y
	return pos


## 발 높이(y) 순으로 그리기 — 아래쪽에 있는 것이 앞에 보인다.
func _update_depth() -> void:
	for id in _st_nodes:
		_st_nodes[id].z_index = int(_st_nodes[id].get_rect().end.y)
	_god.z_index = int(_god_rect().end.y)
	_player_node.z_index = int(_foot_rect(_player_pos).end.y)
	_server.z_index = int(_foot_rect(_server_pos).end.y)


func _set_cooking_enabled(on: bool) -> void:
	for b in _ingredients_box.get_children():
		if b is Button:
			b.disabled = not on


func _interact(station: String) -> void:
	match station:
		"fryer", "pot":
			_interact_cooker(station)
		"table":
			_interact_table()
		"trash":
			_interact_trash()


## 튀김기/냄비: 손질 재료 넣기 / 다 된 요리 꺼내기.
func _interact_cooker(st: String) -> void:
	var c: Dictionary = _cookers[st]
	if c.is_empty():
		if _held.get("kind", "") != "prepped":
			_toast("넣을 손질 재료가 없어요")
			return
		var need := String(_held["recipe"]["station"])
		if need != st:
			_toast("이 재료는 %s에서 조리해요" % CookStation.INFO[need]["name"])
			return
		_cookers[st] = {
			"recipe": _held["recipe"], "mistakes": int(_held["mistakes"]),
			"elapsed": 0.0, "target": maxf(0.5, float(_held["recipe"]["timer_seconds"])),
		}
		_set_held({})
		return
	if not _held.is_empty():
		_toast("손이 비어야 꺼낼 수 있어요")
		return
	var recipe: Dictionary = c["recipe"]
	var elapsed: float = c["elapsed"]
	var target: float = c["target"]
	_cookers[st] = {}
	if _is_burnt(elapsed, target):
		_set_held({"kind": "burnt", "recipe": recipe})
		_toast("타 버렸다… 쓰레기통에 버리세요")
		return
	# 등급 = 손질 등급과 타이밍 등급 중 낮은 쪽.
	var grade := _worse(_stack_grade(int(c["mistakes"])), _timer_grade(absf(elapsed - target)))
	_complete_dish(recipe, grade)


## 테이블: 완성 요리 올리기 / (손이 비면) 하나 집기.
func _interact_table() -> void:
	match String(_held.get("kind", "")):
		"dish":
			if _table.size() >= int(RecipeDB.setting("table_slots", 3.0)):
				_toast("테이블이 가득 찼어요")
				return
			_table.append(_held)
			_set_held({})
		"burnt":
			_toast("탄 요리는 쓰레기통에 버려야 해요")
		"prepped":
			_toast("아직 조리가 끝나지 않았어요")
		_:
			if not _table.is_empty():
				_set_held(_table.pop_back())


## 쓰레기통: 들고 있는 것을 버린다(재료 손실).
func _interact_trash() -> void:
	if _held.is_empty():
		_toast("버릴 것이 없어요")
		return
	_toast("%s 버림" % _held_name(_held))
	_set_held({})


# ── 조리대: 재료 손질(순서 클릭) ────────────────────────

## 모든 레시피·레벨에 등장하는 재료 버튼(관계없는 재료는 오답 유도).
func _build_ingredient_buttons() -> void:
	var ids := {}
	for r in RecipeDB.recipes:
		for lv in r.get("levels", []):
			for ing in lv.get("ingredients", []):
				ids[String(ing)] = true
	for ing in ids.keys():
		var b := Button.new()
		b.text = _item_name(ing)
		b.custom_minimum_size = Vector2(120, 44)
		b.focus_mode = Control.FOCUS_NONE # WASD 이동과 포커스 충돌 방지
		b.pressed.connect(_on_ingredient.bind(String(ing)))
		_ingredients_box.add_child(b)


## 조리대에 다음 요리를 올린다(선택한 레시피 중 재료가 있는 것 무작위).
func _next_recipe() -> void:
	var options: Array = []
	for id in RecipeDB.unlocked_ids():
		if not bool(_selected.get(id, false)): # 준비 화면에서 고른 것만
			continue
		var d := RecipeDB.cook_data(id)
		if _can_afford(d):
			options.append(d)
	_seq_index = 0
	_mistakes = 0
	_mistake_label.text = ""
	if options.is_empty():
		_current = {}
		_recipe_label.text = "조리대: 선택한 레시피 재료가 부족합니다"
		_render_sequence()
		return
	_current = options[randi() % options.size()]
	var pref := " ★선호" if BelamiManager.is_preferred(String(_current["id"])) else ""
	_recipe_label.text = "조리대: %s Lv%d%s" % [_current["display_name"], int(_current["level"]), pref]
	_render_sequence()


func _on_ingredient(ing_id: String) -> void:
	if _ended or not _held.is_empty() or _current.is_empty() or _nearest_station() != "counter":
		return
	var seq: Array = _current["ingredients"]
	if _seq_index >= seq.size():
		return
	if ing_id != String(seq[_seq_index]):
		_mistakes += 1
		_mistake_label.text = "실수 %d회" % _mistakes
		return
	_seq_index += 1
	_render_sequence()
	if _seq_index < seq.size():
		return
	# 손질 완료 → 재료 소모. 불 조리가 필요하면 손질 재료를 들고, 아니면 여기서 완성.
	_consume(_current)
	var recipe := _current
	if String(recipe["station"]) != "":
		_set_held({"kind": "prepped", "recipe": recipe, "mistakes": _mistakes})
		_toast("%s에 넣으세요" % CookStation.INFO[recipe["station"]]["name"])
	else:
		_complete_dish(recipe, _stack_grade(_mistakes))
	_next_recipe()


# ── 튀김기 / 냄비 ─────────────────────────────────────

func _update_cookers(delta: float) -> void:
	for st in COOKERS:
		var c: Dictionary = _cookers[st]
		if not c.is_empty():
			c["elapsed"] = float(c["elapsed"]) + delta


func _is_burnt(elapsed: float, target: float) -> bool:
	return elapsed > target + RecipeDB.setting("timer_burn_seconds", 2.0)


# ── 완성 · 서빙 ──────────────────────────────────────

## 요리 완성 → 손에 든다 + 숙련도 누적.
func _complete_dish(recipe: Dictionary, grade: String) -> void:
	var id := String(recipe["id"])
	var gain := RecipeDB.add_mastery(id, grade) # 숙련도 누적(엑셀 mastery_a/b/c)
	_mastery_log[id] = int(_mastery_log.get(id, 0)) + gain
	_set_held({"kind": "dish", "recipe": recipe, "grade": grade})
	_toast("%s %s등급! 숙련 +%d" % [recipe["display_name"], grade, gain])


func _serve_from_hands() -> void:
	_apply_serve(_held["recipe"], _held["grade"])
	_set_held({})


func _apply_serve(recipe: Dictionary, grade: String) -> void:
	var bonus := 1.0
	if BelamiManager.is_preferred(String(recipe["id"])):
		bonus *= RecipeDB.setting("preferred_bonus", 1.5)
	if _has_helper("kitchen"): # 주방 도우미: 만족/토큰 보너스
		bonus *= RecipeDB.setting("kitchen_helper_bonus", 1.25)
	_satisfaction += float(recipe["sat"].get(grade, 0.0)) * bonus # 레시피·레벨별 만족도(엑셀)
	_tokens_pending += int(_token_gain(grade) * bonus)
	_fed += 1
	_belami.text = _belami_face(grade)
	_update_hud()


## 서빙 도우미: 테이블에 요리가 있으면 최우선으로 가져가고,
## 없으면 곁에 온 플레이어의 손에서 받아 god 에게 전달한다.
## 이동은 길찾기(기구·god를 돌아서) + 발 충돌.
func _update_server(delta: float) -> void:
	if not _has_helper("serving"):
		_server.visible = false
		_server_dish_label.visible = false
		return
	_server.visible = true
	var reach := _station_range()
	match _server_state:
		ServerState.IDLE, ServerState.RETURNING:
			if not _table.is_empty() and _st_nodes.has("table"):
				_server_state = ServerState.FETCHING
			elif _held.get("kind", "") == "dish" and _player_pos.distance_to(_server_pos) < 80.0:
				_server_dish = _held
				_set_held({})
				_server_state = ServerState.CARRYING
			elif _server_state == ServerState.RETURNING:
				_server_walk(_server_home + _FOOT_OFFSET, delta)
				if _server_pos.distance_to(_server_home) < 4.0:
					_server_state = ServerState.IDLE
		ServerState.FETCHING:
			var tr: Rect2 = _st_nodes["table"].get_rect()
			_server_walk(Vector2(tr.get_center().x, tr.end.y + _FOOT_SIZE.y * 0.5 + 4.0), delta)
			if _foot_dist(_server_pos, tr) <= reach:
				if _table.is_empty(): # 그 사이 플레이어가 집어 갔으면 복귀
					_server_state = ServerState.RETURNING
				else:
					_server_dish = _table.pop_front()
					_server_state = ServerState.CARRYING
		ServerState.CARRYING:
			var gr := _god_rect()
			_server_walk(Vector2(gr.position.x - _FOOT_SIZE.x * 0.5 - 4.0, gr.get_center().y), delta)
			if _foot_dist(_server_pos, gr) <= reach:
				_apply_serve(_server_dish["recipe"], _server_dish["grade"])
				_server_dish = {}
				_server_state = ServerState.RETURNING
	_server.position = _server_pos
	var carrying := _server_state == ServerState.CARRYING and not _server_dish.is_empty()
	_server_dish_label.visible = carrying
	if carrying:
		_server_dish_label.text = String(_server_dish["recipe"]["display_name"])
		_server_dish_label.position = _server_pos + Vector2(-30.0, -72.0)


# ── 카밀라 길찾기 ─────────────────────────────────────
## 필드를 16px 격자로 나눠 기구·god(발 크기만큼 부풀림)를 막힌 칸으로 표시 → A* 경로.
const _NAV_CELL := 16.0
var _nav: AStarGrid2D
var _server_path := PackedVector2Array() # 발 기준 경유점
var _server_goal := Vector2.INF


func _build_nav() -> void:
	_nav = AStarGrid2D.new()
	_nav.region = Rect2i(0, 0, ceili(_field.size.x / _NAV_CELL), ceili(_field.size.y / _NAV_CELL))
	_nav.cell_size = Vector2(_NAV_CELL, _NAV_CELL)
	_nav.offset = Vector2(_NAV_CELL, _NAV_CELL) * 0.5 # 경유점 = 칸 중심
	_nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_nav.update()
	# 발이 갈 수 있는 범위(플레이어 이동 범위와 같음) 밖은 막음.
	var walk := Rect2(Vector2(48.0, 48.0) + _FOOT_OFFSET, _field.size - Vector2(96.0, 96.0))
	var pad := _FOOT_SIZE * 0.5 + Vector2(2.0, 2.0)
	var blocks: Array[Rect2] = []
	for r in _obstacles():
		blocks.append(r.grow_individual(pad.x, pad.y, pad.x, pad.y))
	for x in _nav.region.size.x:
		for y in _nav.region.size.y:
			var c := Vector2((x + 0.5) * _NAV_CELL, (y + 0.5) * _NAV_CELL)
			var solid := not walk.has_point(c)
			for b in blocks:
				if b.has_point(c):
					solid = true
					break
			if solid:
				_nav.set_point_solid(Vector2i(x, y))


func _nav_cell(p: Vector2) -> Vector2i:
	var c := Vector2i(floori(p.x / _NAV_CELL), floori(p.y / _NAV_CELL))
	return c.clamp(Vector2i.ZERO, _nav.region.size - Vector2i.ONE)


## 발 목표점(target_foot)까지 경로를 따라 이동. 목표가 바뀔 때만 경로 재계산.
func _server_walk(target_foot: Vector2, delta: float) -> void:
	var foot := _server_pos + _FOOT_OFFSET
	if _nav and target_foot.distance_to(_server_goal) > 4.0:
		_server_goal = target_foot
		_server_path = _nav.get_point_path(_nav_cell(foot), _nav_cell(target_foot), true)
		if not _server_path.is_empty():
			_server_path.remove_at(0) # 현재 칸
		_server_path.append(target_foot) # 마지막은 정확한 목표점
	var step := RecipeDB.setting("server_speed", 300.0) * delta
	var dest := foot
	while step > 0.0 and not _server_path.is_empty():
		var to := _server_path[0] - dest
		if to.length() <= step:
			dest = _server_path[0]
			step -= to.length()
			_server_path.remove_at(0)
		else:
			dest += to.normalized() * step
			step = 0.0
	var motion := dest - foot
	_server_pos = _move_body(_server_pos, motion) # 경로가 모서리를 스쳐도 기구에 파고들지 않게
	if absf(motion.x) > 0.5:
		_server.flip_h = motion.x > 0.0


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


# ── 기구 표시 ─────────────────────────────────────────

## Field 아래에 배치된 CookStation 노드를 id 별로 수집.
func _collect_stations() -> void:
	for child in _field.get_children():
		if child is CookStation:
			_st_nodes[child.station_id] = child
	for id in CookStation.INFO:
		if not _st_nodes.has(id):
			push_warning("NightSession: Field 에 '%s' 기구(CookStation)가 없습니다." % id)


## 매 프레임 기구 상태(게이지·문구·근접 강조) 갱신.
func _refresh_stations(near: String) -> void:
	for id in _st_nodes:
		_st_nodes[id].modulate = Color(1.35, 1.35, 1.35) if id == near else Color(1, 1, 1)
	# 조리대: 손질 중인 요리
	if _st_nodes.has("counter"):
		_st_nodes["counter"].status.text = String(_current.get("display_name", ""))
	# 튀김기/냄비: 게이지(초록=적정 구간, 빨강=타는 중)
	for st in COOKERS:
		if not _st_nodes.has(st):
			continue
		var c: Dictionary = _cookers[st]
		var bar: ProgressBar = _st_nodes[st].bar
		var status: Label = _st_nodes[st].status
		bar.visible = not c.is_empty()
		if c.is_empty():
			status.text = ""
			continue
		var elapsed: float = c["elapsed"]
		var target: float = c["target"]
		var burn := RecipeDB.setting("timer_burn_seconds", 2.0)
		bar.max_value = target + burn
		bar.value = minf(elapsed, target + burn)
		var diff := elapsed - target
		var dish_name := String(c["recipe"]["display_name"])
		if _is_burnt(elapsed, target):
			bar.modulate = Color(0.3, 0.3, 0.3)
			status.text = "%s — 탔다!" % dish_name
		elif diff > RecipeDB.setting("timer_a_max_diff", 0.4):
			bar.modulate = Color(1.0, 0.3, 0.25)
			status.text = "%s — 타는 중! (E)" % dish_name
		elif diff >= -RecipeDB.setting("timer_a_max_diff", 0.4):
			bar.modulate = Color(0.4, 1.0, 0.4)
			status.text = "%s — 지금! (E)" % dish_name
		else:
			bar.modulate = Color(1, 1, 1)
			status.text = "%s %s 중…" % [dish_name, CookStation.INFO[st]["verb"]]
	# 테이블: 올려둔 요리
	var names: Array[String] = []
	for dish in _table:
		names.append("%s(%s)" % [dish["recipe"]["display_name"], dish["grade"]])
	if _st_nodes.has("table"):
		_st_nodes["table"].status.text = ", ".join(names)


## 상황별 안내 문구.
func _update_hint(near: String) -> void:
	match String(_held.get("kind", "")):
		"prepped":
			_serve_hint.text = "손질 완료 → %s로 가서 E로 넣으세요" % CookStation.INFO[_held["recipe"]["station"]]["name"]
		"dish":
			if _has_helper("serving"):
				_serve_hint.text = "테이블에 두면(E) 카밀라가 서빙해요 · 직접 god에게 가져가도 돼요"
			else:
				_serve_hint.text = "god에게 가져가 서빙 · 테이블에 잠시 둘 수 있어요(E)"
		"burnt":
			_serve_hint.text = "탄 요리 → 쓰레기통에 버리세요(E)"
		_:
			if near == "counter" and not _current.is_empty():
				_serve_hint.text = "재료를 순서대로 클릭해 손질하세요"
			elif near in COOKERS and not _cookers[near].is_empty():
				_serve_hint.text = "적정 순간에 E로 꺼내세요"
			elif _current.is_empty():
				_serve_hint.text = "재료가 부족해 더 손질할 요리가 없어요"
			else:
				_serve_hint.text = "조리대로 가서 요리를 손질하세요"


## 머리 위로 떠올랐다 사라지는 짧은 안내.
func _toast(text: String) -> void:
	var lb := Label.new()
	lb.text = text
	lb.size = Vector2(320.0, 22.0)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_color_override("font_outline_color", Color.BLACK)
	lb.add_theme_constant_override("outline_size", 4)
	lb.modulate = Color(1.0, 0.95, 0.6)
	lb.z_index = Z_UI
	var at := _player_pos if _pos_init else _field.size * 0.5 # 준비 화면에선 필드 중앙
	lb.position = at + Vector2(-160.0, -86.0)
	_field.add_child(lb)
	var tw := lb.create_tween()
	tw.tween_property(lb, "position:y", lb.position.y - 16.0, 1.0)
	tw.parallel().tween_property(lb, "modulate:a", 0.0, 0.3).set_delay(0.7)
	tw.tween_callback(lb.queue_free)


func _set_held(h: Dictionary) -> void:
	_held = h
	_held_label.text = "" if h.is_empty() else "손: %s" % _held_name(h)


func _held_name(h: Dictionary) -> String:
	var n := String(h["recipe"]["display_name"])
	match String(h["kind"]):
		"prepped":
			return "%s 손질 재료" % n
		"dish":
			return "%s (%s등급)" % [n, h["grade"]]
		"burnt":
			return "탄 %s" % n
	return n


# ── 기구 배치 모드(개발용) ──────────────────────────────
## 주방 준비 화면의 '기구 배치 편집' → 마우스로 기구를 끌어 옮기고 '저장'하면
## night_session.tscn 에 위치가 그대로 기록된다(에디터 배치와 같은 데이터).
## 에디터/개발 실행에서만 노출(배포 빌드는 res:// 에 쓸 수 없음).

var _layout_mode := false
var _drag: CookStation = null
var _drag_off := Vector2.ZERO
var _layout_backup := {} # station id -> 편집 전 위치(취소용)
var _layout_bar: PanelContainer


func _build_layout_tools() -> void:
	if not OS.has_feature("editor"):
		return
	var btn := Button.new()
	btn.text = "🛠 기구 배치 편집 (개발용)"
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 36)
	btn.pressed.connect(_enter_layout_mode)
	var vbox := _start_button.get_parent()
	vbox.add_child(btn)
	vbox.move_child(btn, _start_button.get_index()) # 요리 시작 버튼 바로 위

	_layout_bar = PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var info := Label.new()
	info.text = "기구 배치 모드 — 마우스로 끌어서 옮기세요"
	row.add_child(info)
	var save := Button.new()
	save.text = "저장"
	save.focus_mode = Control.FOCUS_NONE
	save.pressed.connect(_save_layout)
	row.add_child(save)
	var cancel := Button.new()
	cancel.text = "취소"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(_cancel_layout)
	row.add_child(cancel)
	_layout_bar.add_child(row)
	add_child(_layout_bar)
	_layout_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_layout_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_layout_bar.position.y = 12.0
	_layout_bar.visible = false


func _enter_layout_mode() -> void:
	_layout_backup.clear()
	for id in _st_nodes:
		_layout_backup[id] = _st_nodes[id].position
	_layout_mode = true
	_prep.visible = false
	_layout_bar.visible = true


func _exit_layout_mode() -> void:
	_layout_mode = false
	_drag = null
	for id in _st_nodes:
		_st_nodes[id].modulate = Color(1, 1, 1)
	_layout_bar.visible = false
	_prep.visible = true


func _cancel_layout() -> void:
	for id in _layout_backup:
		_st_nodes[id].position = _layout_backup[id]
	_exit_layout_mode()


func _input(event: InputEvent) -> void:
	if not _layout_mode:
		return
	var mouse := _field.get_local_mouse_position()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _layout_bar.get_global_rect().has_point(get_global_mouse_position()):
				return # 저장/취소 버튼 클릭은 통과
			# 위에 그려진 기구부터 검사.
			var nodes := _st_nodes.values()
			nodes.sort_custom(func(a, b): return a.get_index() > b.get_index())
			for n in nodes:
				if n.get_rect().has_point(mouse):
					_drag = n
					_drag_off = mouse - n.position
					n.modulate = Color(1.4, 1.4, 1.4)
					get_viewport().set_input_as_handled()
					break
		elif _drag:
			_drag.modulate = Color(1, 1, 1)
			_drag = null
	elif event is InputEventMouseMotion and _drag:
		var p := (mouse - _drag_off).round()
		p.x = clampf(p.x, 0.0, maxf(0.0, _field.size.x - _drag.size.x))
		p.y = clampf(p.y, 0.0, maxf(0.0, _field.size.y - _drag.size.y))
		_drag.position = p


## 현재 기구 위치를 night_session.tscn 에 기록(씬 파일을 새로 읽어 위치만 바꿔 저장).
func _save_layout() -> void:
	var path := scene_file_path if scene_file_path != "" else "res://scenes/phases/night_session.tscn"
	var packed := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		_toast("씬을 읽지 못했어요")
		return
	var inst := packed.instantiate()
	for id in _st_nodes:
		var src: CookStation = _st_nodes[id]
		var dst := inst.get_node_or_null("Field/" + String(src.name)) as Control
		if dst:
			dst.position = src.position
	var out := PackedScene.new()
	var err := out.pack(inst)
	inst.free()
	if err == OK:
		err = ResourceSaver.save(out, path)
	if err != OK:
		push_error("NightSession: 기구 배치 저장 실패(%d)" % err)
		_toast("저장 실패 (에러 %d)" % err)
		return
	out.take_over_path(path) # 같은 실행 중 다음 밤에도 새 배치가 로드되도록 캐시 교체
	_exit_layout_mode()
	_toast("기구 배치를 저장했어요")


# ── 게이지 노출 스위치 ──────────────────────────────────

func _apply_gauge_visibility() -> void:
	_sat_label.visible = Config.show_gauges
	_sat_bar.visible = Config.show_gauges


func _on_gauges_visibility_changed(_visible: bool) -> void:
	_apply_gauge_visibility()


# ── 주방 준비 (NPC 배치 + 레시피 선택/강화) ──────────────

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


## 레시피 행: [선택 토글] [숙련도] [강화 버튼]. 잠긴 레시피는 해금 조건만 회색으로 표시.
## 처음 열 때 해금된 레시피 전부 선택.
func _build_recipe_rows() -> void:
	for c in _recipe_list.get_children():
		c.queue_free()
	var unlocked := RecipeDB.unlocked_ids()
	if _selected.is_empty():
		for id in unlocked:
			_selected[id] = true
	for r in RecipeDB.recipes:
		var id := String(r["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		if not (id in unlocked):
			var lock := Label.new()
			lock.modulate = Color(0.55, 0.55, 0.55)
			lock.text = "🔒 %s — %s" % [RecipeDB.display_name(id), RecipeDB.unlock_text(id)]
			row.add_child(lock)
			_recipe_list.add_child(row)
			continue
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 34)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.toggle_mode = true
		btn.button_pressed = bool(_selected.get(id, false))
		btn.text = _recipe_row_text(id, btn.button_pressed)
		btn.toggled.connect(_on_toggle_recipe.bind(id, btn))
		row.add_child(btn)

		var ms := Label.new()
		ms.custom_minimum_size = Vector2(110, 0)
		ms.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var req := RecipeDB.mastery_required(id)
		ms.text = "숙련 %d / %d" % [RecipeDB.mastery_of(id), req] if req >= 0 else "숙련 %d (MAX)" % RecipeDB.mastery_of(id)
		row.add_child(ms)

		var up := Button.new()
		up.focus_mode = Control.FOCUS_NONE
		up.custom_minimum_size = Vector2(96, 34)
		up.text = "강화 ▲" if req >= 0 else "최대"
		up.disabled = not RecipeDB.can_upgrade(id)
		up.tooltip_text = _upgrade_tooltip(id)
		up.pressed.connect(_on_upgrade_recipe.bind(id))
		row.add_child(up)
		_recipe_list.add_child(row)


func _on_toggle_recipe(pressed: bool, id: String, btn: Button) -> void:
	_selected[id] = pressed
	btn.text = _recipe_row_text(id, pressed)


func _on_upgrade_recipe(id: String) -> void:
	if RecipeDB.try_upgrade(id):
		_build_recipe_rows()


## "[✓] 감자튀김 Lv2  감자 → 감자 → 튀김기 4초  · 만족 32/21/10"
func _recipe_row_text(id: String, selected: bool) -> String:
	var mark := "✓" if selected else " "
	var d := RecipeDB.cook_data(id)
	var pref := " ★" if BelamiManager.is_preferred(id) else ""
	var sat: Dictionary = d.get("sat", {})
	return "[%s] %s Lv%d%s   %s   · 만족 %d/%d/%d" % [
		mark, d["display_name"], int(d["level"]), pref, _process_text(d),
		int(sat.get("A", 0)), int(sat.get("B", 0)), int(sat.get("C", 0))]


## 제작 과정 요약: 조리대 재료 순서 + (있으면) 튀김기/냄비 단계.
func _process_text(d: Dictionary) -> String:
	var parts: Array[String] = []
	for ing in d.get("ingredients", []):
		parts.append(_item_name(String(ing)))
	var st := String(d.get("station", ""))
	if st in CookStation.INFO and float(d.get("timer_seconds", 0.0)) > 0.0:
		parts.append("%s %s초" % [CookStation.INFO[st]["name"], _sec_text(d["timer_seconds"])])
	return " → ".join(parts)


## 4.0 → "4", 4.5 → "4.5"
func _sec_text(v: Variant) -> String:
	var f := float(v)
	return str(int(f)) if is_equal_approx(f, roundf(f)) else str(f)


func _upgrade_tooltip(id: String) -> String:
	var lv := RecipeDB.level_of(id)
	if lv >= RecipeDB.max_level(id):
		return "최대 레벨입니다"
	var nd := RecipeDB.cook_data(id, lv + 1)
	var sat: Dictionary = nd.get("sat", {})
	return "Lv%d → Lv%d (숙련 %d 필요)\n%s\n만족 %d/%d/%d" % [
		lv, lv + 1, RecipeDB.mastery_required(id), _process_text(nd),
		int(sat.get("A", 0)), int(sat.get("B", 0)), int(sat.get("C", 0))]


## '요리 시작' → 준비 화면 닫고 조리 진행. 선택이 없으면 전체 선택으로 대체.
func _start_cooking() -> void:
	var any := false
	for k in _selected.keys():
		if _selected[k]:
			any = true
			break
	if not any:
		for id in RecipeDB.unlocked_ids():
			_selected[id] = true
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


# ── 세션 종료 ──────────────────────────────────────────

func _end_session() -> void:
	_ended = true
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
	# 숙련도 획득 요약 + 강화 가능 알림.
	var lines: Array[String] = []
	for id in _mastery_log.keys():
		var line := "%s 숙련 +%d" % [RecipeDB.display_name(id), int(_mastery_log[id])]
		if RecipeDB.can_upgrade(id):
			line += " (강화 가능!)"
		lines.append(line)
	if not lines.is_empty():
		stats += "\n" + "   ·   ".join(lines)
	$Results/Center/VBox/ResultStats.text = stats
	$Results/Center/VBox/NextButton.pressed.connect(GameManager.advance)


# ── 헬퍼 ──────────────────────────────────────────────

func _stack_grade(mistakes: int) -> String:
	if mistakes <= int(RecipeDB.setting("stack_a_max_mistakes", 0)):
		return "A"
	if mistakes <= int(RecipeDB.setting("stack_b_max_mistakes", 1)):
		return "B"
	return "C"


func _timer_grade(diff: float) -> String:
	if diff <= RecipeDB.setting("timer_a_max_diff", 0.4):
		return "A"
	if diff <= RecipeDB.setting("timer_b_max_diff", 1.0):
		return "B"
	return "C"


## 두 등급 중 낮은 쪽(A > B > C).
func _worse(a: String, b: String) -> String:
	return a if a > b else b


func _token_gain(grade: String) -> int:
	return int(RecipeDB.setting("token_" + grade.to_lower(), 0.0))


func _belami_face(grade: String) -> String:
	match grade:
		"A":
			return "( ◕ ᴗ ◕ )"
		"B":
			return "( ˘ ᴗ ˘ )"
	return "( ・_・ )"


func _belami_face_final(success: bool) -> String:
	return "( ◕ ᴗ ◕ )" if success else "( ˘ ︵ ˘ )"


func _recipe_cost(d: Dictionary) -> Dictionary:
	var cost := {}
	for ing in d.get("ingredients", []):
		var key := String(ing)
		cost[key] = int(cost.get(key, 0)) + 1
	return cost


## 재료는 직전 탐사 가방 + 창고를 합쳐서 판정.
func _can_afford(d: Dictionary) -> bool:
	var cost := _recipe_cost(d)
	for ing in cost:
		if GameManager.cooking_stock(String(ing)) < int(cost[ing]):
			return false
	return true


## 가방에서 먼저, 모자라면 창고에서 소모.
func _consume(d: Dictionary) -> void:
	var cost := _recipe_cost(d)
	for ing in cost:
		GameManager.consume_for_cooking(String(ing), int(cost[ing]))


## 조리대 손질 순서 표시(진행=초록, 다음=노랑) + 뒤에 이어질 기구 단계.
func _render_sequence() -> void:
	for c in _seq_row.get_children():
		c.queue_free()
	var on := not _current.is_empty()
	_seq_row.visible = on
	_mistake_label.visible = on
	_ingredients_box.visible = on
	if not on:
		return
	var seq: Array = _current["ingredients"]
	for i in seq.size():
		var lbl := Label.new()
		lbl.text = _item_name(String(seq[i]))
		if i < _seq_index:
			lbl.modulate = Color(0.5, 0.9, 0.5)
		elif i == _seq_index:
			lbl.modulate = Color(1.0, 0.9, 0.4)
		else:
			lbl.modulate = Color(0.7, 0.7, 0.7)
		_seq_row.add_child(lbl)
		if i < seq.size() - 1:
			var arrow := Label.new()
			arrow.text = "  →  "
			_seq_row.add_child(arrow)
	var st := String(_current.get("station", ""))
	if st in CookStation.INFO:
		var t := Label.new()
		t.text = "  →  %s %s초" % [CookStation.INFO[st]["name"], _sec_text(_current["timer_seconds"])]
		t.modulate = Color(0.7, 0.7, 0.7)
		_seq_row.add_child(t)


func _update_hud() -> void:
	_sat_label.text = "만족 %0.0f / %0.0f" % [_satisfaction, target_satisfaction]
	_sat_bar.value = minf(_satisfaction, target_satisfaction)
	_tokens_label.text = "토큰(예정): %d" % _tokens_pending
	_fed_label.text = "먹인 수: %d" % _fed


func _item_name(id: String) -> String:
	return ItemDB.display_name(id)
