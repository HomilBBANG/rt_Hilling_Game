extends Control
## 밤 세션 — 쿠킹 + 서빙 + 급식 (PRD 3.2/3.4/3.5 + 급식 스펙).
## 1분 타이머 동안 주방 기구를 오가며 재료를 손질·조합·조리해 god에게 서빙한다.
##
## 조작: WASD 이동 · E 집기 · R 내려놓기 · 마우스 왼클릭 = 조리대 위 재료 썰기 · 하단 목록 클릭
##
## 조리 기구(station)
##   조리대   : 근접하면 하단에 보유 재료 목록 → 클릭해 하나 꺼내면 조리대 위에 생성(한 번에 하나).
##              조리대 위 재료를 클릭(클리커)해 손질 — 재료마다 써는 횟수(cooking.xlsx ingredients).
##   튀김기/냄비: 손질 재료를 넣어(R) 오늘 메뉴 레시피와 재료가 일치하면 자동으로 조리 시작.
##              자리를 비워도 게이지가 오르고, 적정 순간 E로 꺼낸다. 너무 오래 두면 탄다.
##   믹싱볼   : 불 없이 재료가 모이면 바로 완성(무침류). E로 꺼낸다.
##   테이블   : 무엇이든 6개까지 보관. 근접하면 하단에 목록. 카밀라가 요리를 최우선으로 가져가 서빙.
##   쓰레기통 : 들고 있는 것을 버린다(R). 재료는 날아간다.
##   바닥     : 기구 근처가 아닌 곳에서 R → 바닥에 떨어짐(등급 1단계 하락), 20초 지나면 썩음.
##
## 물건 형식은 KitchenItem 참고(재료/요리/탄 요리/썩은 것). 플레이어는 한 번에 하나만 든다.
## 재료(직전 탐사 가방 + 창고)는 조리대에 꺼내는 순간 소모(가방 먼저).
## 요리 등급 = 들어간 재료 중 가장 낮은 등급과 조리 타이밍 등급 중 낮은 쪽. 완성 시 숙련도 누적.
## 서빙마다 만족↑ + 토큰↑. 종료 시 만족≥목표면 성공(토큰 획득 + 누적 만족도), 미달이면 실패.
## 모든 쿠킹 밸런스·식재료·레시피는 data/cooking.xlsx(RecipeDB).
## 기구 위치·크기는 night_session.tscn 의 Field 아래 CookStation 노드(에디터 또는 게임 내 배치 편집).

@export var run_seconds := 60.0
@export var target_satisfaction := 60.0
@export var move_speed := 260.0

## 재료를 모아 요리를 만드는 기구. 튀김기/냄비는 타이머, 믹싱볼은 즉시 완성.
const COMBINERS := ["fryer", "pot", "bowl"]
const TIMED := ["fryer", "pot"]
const Z_UI := 2000      # 필드 위 안내·말풍선(깊이 정렬보다 위)
const Z_OVERLAY := 3000 # 준비/결과/배치 화면
const _FLOOR_PICK := 45.0 # 바닥 물건을 E로 주울 수 있는 거리(발 기준)

var _time_left := 0.0
var _satisfaction := 0.0
var _tokens_pending := 0
var _fed := 0
var _ended := false

var _held: Dictionary = {}          # 손에 든 물건(KitchenItem 형식) — 비어 있으면 빈손
var _counter_item: Dictionary = {}  # 조리대 위 재료(한 번에 하나)
var _cookers := {}                  # station id -> {items, state(fill|cooking|ready), recipe, base, elapsed, target, dish}
var _table: Array = []              # 테이블 위 물건(놓은 순)
var _floor: Array = []              # 바닥 물건 [{item, pos(발 좌표), node}]

var _mastery_log: Dictionary = {} # 오늘 밤 레시피별 숙련도 획득(결과 화면 표시)
var _menu_ings: Array[String] = [] # 오늘 메뉴에 쓰이는 재료(조리대 목록에 이것만 표시)
var _recipe_panel: PanelContainer   # 요리 중 왼쪽 위 오늘 레시피 표
var _hungry := false                # 재료 소진 + 만족 미달 → 시간 2배, god 재촉, 타임오버 = 게임 오버

var _player_pos := Vector2.ZERO
var _pos_init := false
var _e_was_down := false
var _r_was_down := false
var _st_pos := {}   # station id -> 필드 좌표(중심, 매 프레임 노드에서 읽음)
var _st_nodes := {} # station id -> CookStation 노드
var _tray_key := "" # 하단 목록 내용이 바뀔 때만 다시 만들기 위한 키
var _hand_vis: KitchenItem

## 주방 준비 화면(배치+레시피 선택). _started 전에는 조리/타이머가 진행되지 않는다.
var _started := false
var _selected: Dictionary = {} # 오늘 밤 메뉴(레시피 id 집합)

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
@onready var _held_label: Label = $BottomBar/HeldLabel
@onready var _tray: HBoxContainer = $Field/Ingredients # 근접한 기구의 하단 목록(조리대=보유 재료, 테이블=올린 물건)
@onready var _server: AnimatedSprite2D = $Field/Server
@onready var _server_dish_label: Label = $Field/ServerDish
@onready var _results: Control = $Results
@onready var _prep: Control = $Prep
@onready var _npc_list: VBoxContainer = $Prep/Center/Panel/Margin/VBox/NpcList
@onready var _recipe_list: VBoxContainer = $Prep/Center/Panel/Margin/VBox/RecipeList
@onready var _start_button: Button = $Prep/Center/Panel/Margin/VBox/StartButton


func _ready() -> void:
	run_seconds = RecipeDB.setting("night_seconds", run_seconds) # cooking.xlsx settings
	target_satisfaction = Balance.day_target(GameManager.day, target_satisfaction) # balance.xlsx day_targets
	move_speed = PlayerStats.move_speed() * Config.SCREEN_SCALE # 탐사·캠프와 동일 속도(화면 좌표 1080p 배율)
	_time_left = run_seconds
	_sat_bar.max_value = target_satisfaction
	_sat_bar.value = 0
	_collect_stations()
	for st in COMBINERS:
		_reset_cooker(st)
	_hand_vis = KitchenItem.new()
	_hand_vis.visible = false
	_field.add_child(_hand_vis)
	_tray.visible = false
	_results.visible = false
	_god.sprite_frames = GodFrames.build()
	_god.play("idle")
	_belami.text = "( ˘ ᴗ ˘ )"
	_held_label.text = ""
	_apply_gauge_visibility()
	Config.gauges_visibility_changed.connect(_on_gauges_visibility_changed)
	# 요리 전 '주방 준비' 화면 먼저(배치 + 메뉴 선택/강화). 시작 버튼 전엔 조리 진행 안 함.
	_start_button.pressed.connect(_start_cooking)
	_build_prep()
	$Prep/Center/Panel/Margin/VBox/Title.text = "주방 준비  ·  Day %d 목표 만족 %d" % [GameManager.day, int(target_satisfaction)]
	_build_layout_tools() # 개발용: 게임 화면에서 기구 드래그 배치
	# 필드는 발 높이로 깊이 정렬(z_index = y)되므로, 항상 위에 보여야 하는 것들은 더 높게.
	for c in [_belami, _server_dish_label, _tray, _serve_hint, _hand_vis]:
		c.z_index = Z_UI
	for c in [_prep, _results, _layout_bar]:
		if c:
			c.z_index = Z_OVERLAY
	_prep.visible = true
	_update_hud()


func _process(delta: float) -> void:
	if _ended or not _started: # 준비 화면 동안엔 타이머·조리 정지
		return
	# 배고픈 god: 남은 시간이 2배 빠르게 흐른다.
	_time_left = maxf(0.0, _time_left - delta * (2.0 if _hungry else 1.0))
	_time_label.text = "남은 시간: %0.0f초" % _time_left
	_update_cookers(delta) # 튀김기/냄비는 플레이어 위치와 무관하게 진행
	_update_floor(delta)
	_update_field(delta)
	if not _hungry and _out_of_food():
		_start_hungry()
	if _time_left <= 0.0:
		if _hungry:
			_game_over() # 배고픈 god에게 잡아먹힘
		else:
			_end_session()


# ── 필드: 이동 · 상호작용 ───────────────────────────────

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
			_server_home = _unstick(Vector2(tr.get_center().x, tr.end.y + 90.0) - _FOOT_OFFSET)
		else:
			_server_home = _unstick(Vector2(180.0, _field.size.y * 0.5))
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
	_player_pos.x = clampf(_player_pos.x, _EDGE, _field.size.x - _EDGE)
	_player_pos.y = clampf(_player_pos.y, _EDGE, _field.size.y - _EDGE)
	_player_node.position = _player_pos
	if d != Vector2.ZERO:
		if _player_node.animation != "run":
			_player_node.play("run")
		_player_node.flip_h = d.x > 0
	elif _player_node.animation != "idle":
		_player_node.play("idle")

	var god_pos := _god_pos()
	_god.position = god_pos # AnimatedSprite2D 는 중심 기준
	_belami.position = god_pos + Vector2(0.0, -108.0) - _belami.size * 0.5 # 머리 위 반응 버블
	if _hungry: # 재촉 — 버블이 들썩인다
		_belami.position += Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))

	var near := _nearest_station()
	# E = 집기 / R = 내려놓기 (엣지)
	var e_down := Input.is_physical_key_pressed(KEY_E)
	if e_down and not _e_was_down:
		_on_e(near)
	_e_was_down = e_down
	var r_down := Input.is_physical_key_pressed(KEY_R)
	if r_down and not _r_was_down:
		_on_r(near)
	_r_was_down = r_down

	# god 곁(발 ↔ god 가장자리)에 완성 요리를 들고 오면 바로 서빙.
	if _held.get("type", "") == "dish" and _foot_dist(_player_pos, _god_rect()) <= _station_range():
		_serve_from_hands()

	_update_server(delta)
	_refresh_stations(near)
	_refresh_tray(near)
	_hand_vis.visible = not _held.is_empty()
	_hand_vis.position = _player_pos + Vector2(-21.0, -118.0)
	_update_hint(near)
	_update_depth()


func _god_pos() -> Vector2:
	return Vector2(_field.size.x - 90.0, _field.size.y * 0.5)


func _station_range() -> float:
	return RecipeDB.setting("station_range", 36.0) # 발 ↔ 기구 가장자리 거리(px)


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


# ── E 집기 / R 내려놓기 ────────────────────────────────

func _on_e(near: String) -> void:
	# 대기 중인 조합(더 큰 레시피 가능성 때문에 자동 시작 안 함)은 손 상태와 상관없이 E로 시작.
	if near in COMBINERS and _cookers[near]["state"] == "fill":
		var ex := _exact_recipe(near)
		if not ex.is_empty():
			_start_cooker(near, ex)
			return
	if not _held.is_empty():
		_toast("손이 가득 찼어요 (R로 내려놓기)")
		return
	var fi := _nearest_floor()
	if fi >= 0: # 발밑 물건 먼저
		var e: Dictionary = _floor[fi]
		e["node"].queue_free()
		_floor.remove_at(fi)
		_set_held(e["item"])
		return
	match near:
		"counter":
			if _counter_item.is_empty():
				_toast("아래 목록에서 재료를 꺼내세요")
			else:
				_set_held(_counter_item)
				_counter_item = {}
		"fryer", "pot", "bowl":
			_take_from_cooker(near)
		"table":
			if _table.is_empty():
				_toast("테이블이 비어 있어요")
			else:
				_set_held(_table.pop_back())


func _on_r(near: String) -> void:
	if _held.is_empty():
		return
	var it := _held
	var type := String(it.get("type", ""))
	match near:
		"counter":
			if type != "ing":
				_toast("조리대에는 재료만 올릴 수 있어요")
			elif not _counter_item.is_empty():
				_toast("조리대가 이미 차 있어요")
			else:
				_counter_item = it
				_set_held({})
		"fryer", "pot", "bowl":
			_add_to_cooker(near, it)
		"table":
			if type == "burnt" or type == "rotten":
				_toast("쓰레기통에 버려야 해요")
			elif _table.size() >= _table_slots():
				_toast("테이블이 가득 찼어요 (%d개)" % _table_slots())
			else:
				_table.append(it)
				_set_held({})
		"trash":
			_toast("%s 버림" % KitchenItem.label_of(it))
			_set_held({})
		_:
			_drop_floor(it)


# ── 조리대: 재료 꺼내기 · 손질(클릭) ─────────────────────

## 하단 목록에서 재료 하나 꺼내기 → 조리대 위에 생성(재고 1 소모).
func _take_from_stock(id: String) -> void:
	if _ended or _nearest_station() != "counter":
		return
	if not _counter_item.is_empty():
		_toast("조리대를 비워야 꺼낼 수 있어요 — 올려둔 재료를 테이블로 옮기세요")
		return
	if GameManager.cooking_stock(id) <= 0:
		return
	GameManager.consume_for_cooking(id, 1)
	_counter_item = KitchenItem.make_ingredient(id)
	_tray_key = "" # 수량 갱신


## 조리대 위 재료 클릭 = 한 번 썰기. 재료마다 정해진 횟수를 채우면 손질 완료.
func _chop() -> void:
	if _counter_item.is_empty():
		return
	if _nearest_station() != "counter":
		_toast("조리대 가까이에서 손질하세요")
		return
	var it := _counter_item
	var need := RecipeDB.chop_count(String(it["id"]))
	if need <= 0:
		_toast("손질 없이 바로 쓸 수 있어요")
		return
	if it.get("chopped", false):
		return
	it["chops"] = int(it["chops"]) + 1
	_st_nodes["counter"].pulse()
	if int(it["chops"]) >= need:
		it["chopped"] = true
		_toast("%s 손질 완료!" % ItemDB.display_name(String(it["id"])))


# ── 튀김기 · 냄비 · 믹싱볼 ─────────────────────────────

func _reset_cooker(st: String) -> void:
	_cookers[st] = {"items": [], "state": "fill", "recipe": {}, "base": "A",
		"elapsed": 0.0, "target": 0.0, "dish": {}}


## 오늘 메뉴 중 이 기구에서 만드는 레시피(현재 레벨).
func _menu_recipes(st: String) -> Array:
	var out: Array = []
	for id in RecipeDB.unlocked_ids():
		if bool(_selected.get(id, false)):
			var d := RecipeDB.cook_data(id)
			if String(d["station"]) == st:
				out.append(d)
	return out


func _counts(ids: Array) -> Dictionary:
	var c := {}
	for i in ids:
		c[String(i)] = int(c.get(String(i), 0)) + 1
	return c


## have 가 need 의 부분집합(개수 포함)인지.
func _fits(have: Dictionary, need: Dictionary) -> bool:
	for k in have:
		if int(have[k]) > int(need.get(k, 0)):
			return false
	return true


func _ids_of(items: Array) -> Array:
	return items.map(func(x): return String(x["id"]))


## 기구 안 재료와 정확히 일치하는 메뉴 레시피(없으면 {}).
func _exact_recipe(st: String) -> Dictionary:
	var have := _counts(_ids_of(_cookers[st]["items"]))
	if have.is_empty():
		return {}
	for r in _menu_recipes(st):
		var need := _counts(r["ingredients"])
		if _fits(have, need) and _fits(need, have):
			return r
	return {}


## 재료 넣기. 오늘 메뉴 중 이 조합으로 완성될 수 있는 레시피가 있어야 받는다.
## 정확히 일치하면 자동 시작 — 단, 재료를 더 넣어 만들 수 있는 더 큰 레시피가 있으면 대기(E로 시작).
func _add_to_cooker(st: String, it: Dictionary) -> void:
	var c: Dictionary = _cookers[st]
	var st_name: String = CookStation.INFO[st]["name"]
	if c["state"] != "fill":
		_toast("%s 사용 중이에요" % st_name)
		return
	if it.get("type", "") != "ing":
		_toast("%s에는 재료만 넣을 수 있어요" % st_name)
		return
	if not KitchenItem.is_usable(it):
		_toast("먼저 조리대에서 손질하세요")
		return
	var ids := _ids_of(c["items"])
	ids.append(String(it["id"]))
	var have := _counts(ids)
	var exact: Dictionary = {}
	var bigger := false
	for r in _menu_recipes(st):
		var need := _counts(r["ingredients"])
		if not _fits(have, need):
			continue
		if _fits(need, have):
			exact = r
		else:
			bigger = true
	if exact.is_empty() and not bigger:
		_toast("이 조합으로 만들 수 있는 메뉴가 없어요")
		return
	c["items"].append(it)
	_set_held({})
	if not exact.is_empty():
		if bigger:
			_toast("%s 가능 — E로 시작 / 재료 더 넣기" % exact["display_name"])
		else:
			_start_cooker(st, exact)


func _start_cooker(st: String, recipe: Dictionary) -> void:
	var c: Dictionary = _cookers[st]
	c["recipe"] = recipe
	c["base"] = _worst_grade(c["items"])
	if st == "bowl": # 불 없이 바로 완성
		c["dish"] = _complete_dish(recipe, c["base"])
		c["items"] = []
		c["state"] = "ready"
	else:
		c["state"] = "cooking"
		c["elapsed"] = 0.0
		c["target"] = maxf(0.5, float(recipe["timer_seconds"]))


## E(빈손): 조리 중이면 꺼내기 / 완성품 꺼내기 / 아직 시작 전이면 마지막 재료 빼기.
func _take_from_cooker(st: String) -> void:
	var c: Dictionary = _cookers[st]
	match String(c["state"]):
		"cooking":
			var recipe: Dictionary = c["recipe"]
			var elapsed: float = c["elapsed"]
			var target: float = c["target"]
			var base: String = c["base"]
			_reset_cooker(st)
			if _is_burnt(elapsed, target):
				_set_held({"type": "burnt", "recipe": recipe})
				_toast("타 버렸다… 쓰레기통에 버리세요")
			else:
				_set_held(_complete_dish(recipe, _worse(base, _timer_grade(absf(elapsed - target)))))
		"ready":
			_set_held(c["dish"])
			_reset_cooker(st)
		_:
			if c["items"].is_empty():
				_toast("%s가 비어 있어요" % CookStation.INFO[st]["name"])
			else:
				_set_held(c["items"].pop_back())


func _update_cookers(delta: float) -> void:
	for st in TIMED:
		var c: Dictionary = _cookers[st]
		if c["state"] == "cooking":
			c["elapsed"] = float(c["elapsed"]) + delta


func _is_burnt(elapsed: float, target: float) -> bool:
	return elapsed > target + RecipeDB.setting("timer_burn_seconds", 2.0)


# ── 테이블 ────────────────────────────────────────────

func _table_slots() -> int:
	return int(RecipeDB.setting("table_slots", 6.0))


## 하단 목록에서 테이블 물건 클릭 → 손에 들기.
func _take_from_table(i: int) -> void:
	if _nearest_station() != "table" or i >= _table.size():
		return
	if not _held.is_empty():
		_toast("손이 가득 찼어요 (R로 내려놓기)")
		return
	_set_held(_table.pop_at(i))


func _table_dish_index() -> int:
	for i in _table.size():
		if _table[i].get("type", "") == "dish":
			return i
	return -1


# ── 바닥 ──────────────────────────────────────────────

## 빈 바닥에 떨어뜨림 — 재료·요리는 등급 하락, 일정 시간 뒤 썩는다.
func _drop_floor(it: Dictionary) -> void:
	var type := String(it.get("type", ""))
	if type == "ing" or type == "dish":
		var before := String(it["grade"])
		it["grade"] = KitchenItem.grade_down(before, int(RecipeDB.setting("floor_grade_drop", 1.0)))
		_toast("바닥에 떨어뜨림 — 등급 %s → %s" % [before, it["grade"]])
	var pos := _player_pos + _FOOT_OFFSET + Vector2(randf_range(-9.0, 9.0), 6.0)
	var node := KitchenItem.new()
	node.size = Vector2(36, 36)
	node.position = pos - node.size * 0.5
	node.set_item(it)
	_field.add_child(node)
	_floor.append({"item": it, "pos": pos, "node": node})
	_set_held({})


func _update_floor(delta: float) -> void:
	var rot := RecipeDB.setting("floor_rot_seconds", 20.0)
	for e in _floor:
		var it: Dictionary = e["item"]
		var type := String(it.get("type", ""))
		if type != "ing" and type != "dish":
			continue
		it["floor_t"] = float(it.get("floor_t", 0.0)) + delta
		var t := float(it["floor_t"]) / rot
		e["node"].modulate = Color(1, 1, 1).lerp(Color(0.7, 0.75, 0.45), clampf(t, 0.0, 1.0))
		if t >= 1.0:
			e["item"] = {"type": "rotten", "name": _plain_name(it)}
			e["node"].modulate = Color(1, 1, 1)
			e["node"].set_item(e["item"])


func _nearest_floor() -> int:
	var foot := _player_pos + _FOOT_OFFSET
	var best := -1
	var best_d := _FLOOR_PICK
	for i in _floor.size():
		var dd := foot.distance_to(_floor[i]["pos"])
		if dd < best_d:
			best_d = dd
			best = i
	return best


func _plain_name(it: Dictionary) -> String:
	if it.get("type", "") == "ing":
		return ItemDB.display_name(String(it["id"]))
	return String(it.get("recipe", {}).get("display_name", "음식"))


# ── 완성 · 서빙 ──────────────────────────────────────

## 요리 완성 → 숙련도 누적 + 요리 물건 반환.
func _complete_dish(recipe: Dictionary, grade: String) -> Dictionary:
	var id := String(recipe["id"])
	var gain := RecipeDB.add_mastery(id, grade) # 숙련도 누적(엑셀 mastery_a/b/c)
	_mastery_log[id] = int(_mastery_log.get(id, 0)) + gain
	_toast("%s %s등급! 숙련 +%d" % [recipe["display_name"], grade, gain])
	return {"type": "dish", "recipe": recipe, "grade": grade, "floor_t": 0.0}


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


## 서빙 도우미: 테이블에 요리가 있으면 최우선으로 가져가고(재료는 건드리지 않음),
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
			if _table_dish_index() >= 0 and _st_nodes.has("table"):
				_server_state = ServerState.FETCHING
			elif _held.get("type", "") == "dish" and _player_pos.distance_to(_server_pos) < 120.0:
				_server_dish = _held
				_set_held({})
				_server_state = ServerState.CARRYING
			elif _server_state == ServerState.RETURNING:
				_server_walk(_server_home + _FOOT_OFFSET, delta)
				if _server_pos.distance_to(_server_home) < 4.0:
					_server_state = ServerState.IDLE
		ServerState.FETCHING:
			var tr: Rect2 = _st_nodes["table"].get_rect()
			_server_walk(Vector2(tr.get_center().x, tr.end.y + _FOOT_SIZE.y * 0.5 + 6.0), delta)
			if _foot_dist(_server_pos, tr) <= reach:
				var di := _table_dish_index()
				if di < 0: # 그 사이 플레이어가 집어 갔으면 복귀
					_server_state = ServerState.RETURNING
				else:
					_server_dish = _table.pop_at(di)
					_server_state = ServerState.CARRYING
		ServerState.CARRYING:
			var gr := _god_rect()
			_server_walk(Vector2(gr.position.x - _FOOT_SIZE.x * 0.5 - 6.0, gr.get_center().y), delta)
			if _foot_dist(_server_pos, gr) <= reach:
				_apply_serve(_server_dish["recipe"], _server_dish["grade"])
				_server_dish = {}
				_server_state = ServerState.RETURNING
	_server.position = _server_pos
	var carrying := _server_state == ServerState.CARRYING and not _server_dish.is_empty()
	_server_dish_label.visible = carrying
	if carrying:
		_server_dish_label.text = String(_server_dish["recipe"]["display_name"])
		_server_dish_label.position = _server_pos + Vector2(-45.0, -110.0)


# ── 충돌(발 기준) ────────────────────────────────────
## 플레이어·카밀라 스프라이트(32px ×4, 중심 기준)의 발 부분만 충돌 →
## 기구/god 아래쪽에 서면 몸이 앞에 겹쳐 보인다(깊이 정렬은 _update_depth).
## 값은 스프라이트 배율(_SPRITE_SCALE)에서 계산 — 씬의 Player/Server scale 과 맞출 것.
const _SPRITE_SCALE := 4.0
const _FOOT_OFFSET := Vector2(0.0, 12.0 * _SPRITE_SCALE)
const _FOOT_SIZE := Vector2(8.0 * _SPRITE_SCALE, 4.0 * _SPRITE_SCALE)
const _EDGE := 16.0 * _SPRITE_SCALE # 필드 가장자리 여백(스프라이트 반폭)
const _SLIP := 6.0 # 이 이하로 걸친 모서리는 미끄러져 통과
## god(64px ×3, 중심 기준)이 막는 영역 — 하반신~발밑.
const _GOD_BLOCK := Rect2(-60.0, 21.0, 120.0, 60.0)


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
	for e in _floor:
		e["node"].z_index = int(e["pos"].y)


# ── 카밀라 길찾기 ─────────────────────────────────────
## 필드를 24px 격자로 나눠 기구·god(발 크기만큼 부풀림)를 막힌 칸으로 표시 → A* 경로.
const _NAV_CELL := 24.0
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
	var walk := Rect2(Vector2(_EDGE, _EDGE) + _FOOT_OFFSET, _field.size - Vector2(_EDGE, _EDGE) * 2.0)
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
	var step := RecipeDB.setting("server_speed", 300.0) * Config.SCREEN_SCALE * delta
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


# ── 기구 · 하단 목록 · 안내 표시 ─────────────────────────

## Field 아래에 배치된 CookStation 노드를 id 별로 수집.
func _collect_stations() -> void:
	for child in _field.get_children():
		if child is CookStation:
			_st_nodes[child.station_id] = child
	for id in CookStation.INFO:
		if not _st_nodes.has(id):
			push_warning("NightSession: Field 에 '%s' 기구(CookStation)가 없습니다." % id)


## 매 프레임 기구 위 물건·게이지·상태 문구·근접 강조 갱신.
func _refresh_stations(near: String) -> void:
	for id in _st_nodes:
		_st_nodes[id].modulate = Color(1.35, 1.35, 1.35) if id == near else Color(1, 1, 1)
	# 조리대: 올려둔 재료 + 손질 진행
	if _st_nodes.has("counter"):
		var cn: CookStation = _st_nodes["counter"]
		cn.show_items([] if _counter_item.is_empty() else [_counter_item], 60.0)
		var txt := ""
		if not _counter_item.is_empty():
			var need := RecipeDB.chop_count(String(_counter_item["id"]))
			if need <= 0:
				txt = "바로 사용 가능 (E로 들기)"
			elif _counter_item.get("chopped", false):
				txt = "손질 완료 (E로 들기)"
			else:
				txt = "클릭해서 손질 %d/%d" % [int(_counter_item["chops"]), need]
		cn.status.text = txt
	# 튀김기/냄비/믹싱볼
	for st in COMBINERS:
		if not _st_nodes.has(st):
			continue
		var c: Dictionary = _cookers[st]
		var node: CookStation = _st_nodes[st]
		node.show_items([c["dish"]] if c["state"] == "ready" else c["items"], 36.0)
		node.bar.visible = c["state"] == "cooking"
		match String(c["state"]):
			"ready":
				node.status.text = "%s 완성! (E)" % c["dish"]["recipe"]["display_name"]
			"cooking":
				_refresh_timer(node, c, st)
			_:
				var ex := _exact_recipe(st)
				if not ex.is_empty():
					node.status.text = "%s 가능 — E로 시작" % ex["display_name"]
				elif not c["items"].is_empty():
					node.status.text = "재료 %d개 (E: 빼기)" % c["items"].size()
				else:
					node.status.text = ""
	# 테이블
	if _st_nodes.has("table"):
		_st_nodes["table"].show_items(_table, 36.0)
		_st_nodes["table"].status.text = "%d/%d" % [_table.size(), _table_slots()] if not _table.is_empty() else ""


## 튀김기/냄비 게이지(초록=적정 구간, 빨강=타는 중, 회색=탐).
func _refresh_timer(node: CookStation, c: Dictionary, st: String) -> void:
	var elapsed: float = c["elapsed"]
	var target: float = c["target"]
	var burn := RecipeDB.setting("timer_burn_seconds", 2.0)
	var ok := RecipeDB.setting("timer_a_max_diff", 0.4)
	node.bar.max_value = target + burn
	node.bar.value = minf(elapsed, target + burn)
	var diff := elapsed - target
	var dish_name := String(c["recipe"]["display_name"])
	if _is_burnt(elapsed, target):
		node.bar.modulate = Color(0.3, 0.3, 0.3)
		node.status.text = "%s — 탔다!" % dish_name
	elif diff > ok:
		node.bar.modulate = Color(1.0, 0.3, 0.25)
		node.status.text = "%s — 타는 중! (E)" % dish_name
	elif diff >= -ok:
		node.bar.modulate = Color(0.4, 1.0, 0.4)
		node.status.text = "%s — 지금! (E)" % dish_name
	else:
		node.bar.modulate = Color(1, 1, 1)
		node.status.text = "%s %s 중…" % [dish_name, CookStation.INFO[st]["verb"]]


## 하단 목록: 조리대 근처 = 보유 재료(클릭해 꺼내기), 테이블 근처 = 테이블 위 물건(클릭해 들기).
func _refresh_tray(near: String) -> void:
	var key := near
	if near == "counter":
		for id in _menu_ings:
			key += "|%s:%d" % [id, GameManager.cooking_stock(id)]
		key += "|busy" if not _counter_item.is_empty() else ""
	elif near == "table":
		for it in _table:
			key += "|" + KitchenItem.label_of(it)
	else:
		key = ""
	if key == _tray_key:
		return
	_tray_key = key
	for ch in _tray.get_children():
		ch.queue_free()
	_tray.visible = key != ""
	if near == "counter":
		_tray.add_child(_tray_label("재료 꺼내기"))
		var any := false
		for id in _menu_ings: # 오늘 메뉴에 쓰이는 재료 중
			var n := GameManager.cooking_stock(id)
			if n <= 0:
				continue # 보유한 것만
			any = true
			var b := _tray_button(KitchenItem.make_ingredient(id), "%s ×%d" % [ItemDB.display_name(id), n])
			b.disabled = not _counter_item.is_empty()
			b.pressed.connect(_take_from_stock.bind(id))
			_tray.add_child(b)
		if not any:
			_tray.add_child(_tray_label("오늘 메뉴에 쓸 재료가 없어요"))
	elif near == "table":
		_tray.add_child(_tray_label("테이블 %d/%d" % [_table.size(), _table_slots()]))
		for i in _table.size():
			var b := _tray_button(_table[i], KitchenItem.label_of(_table[i]))
			b.pressed.connect(_take_from_table.bind(i))
			_tray.add_child(b)


func _tray_label(text: String) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_color_override("font_outline_color", Color.BLACK)
	lb.add_theme_constant_override("outline_size", 4)
	return lb


## 아이콘(임시 도형) + 이름 버튼.
func _tray_button(it: Dictionary, text: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE # WASD 이동과 포커스 충돌 방지
	b.custom_minimum_size = Vector2(225, 66)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = "              " + text
	var vis := KitchenItem.new()
	vis.position = Vector2(12, 12)
	vis.set_item(it)
	b.add_child(vis)
	return b


## 상황별 안내 문구.
func _update_hint(near: String) -> void:
	var type := String(_held.get("type", ""))
	if type == "":
		if _nearest_floor() >= 0:
			_serve_hint.text = "E로 줍기"
			return
		match near:
			"counter":
				if _counter_item.is_empty():
					_serve_hint.text = "아래 목록에서 재료를 꺼내세요"
				elif RecipeDB.needs_chop(String(_counter_item["id"])) and not _counter_item.get("chopped", false):
					_serve_hint.text = "조리대 위 재료를 마우스로 클릭해 손질하세요"
				else:
					_serve_hint.text = "E로 들어서 튀김기·냄비·믹싱볼에 넣으세요"
			"fryer", "pot", "bowl":
				var c: Dictionary = _cookers[near]
				match String(c["state"]):
					"cooking":
						_serve_hint.text = "적정 순간에 E로 꺼내세요"
					"ready":
						_serve_hint.text = "E로 완성된 요리를 꺼내세요"
					_:
						_serve_hint.text = "재료를 넣으면(R) 메뉴와 맞을 때 조리가 시작돼요"
			"table":
				_serve_hint.text = "아래 목록을 클릭하거나 E로 집기"
			_:
				_serve_hint.text = "조리대로 가서 재료를 꺼내세요"
		return
	match type:
		"ing":
			if KitchenItem.is_usable(_held):
				_serve_hint.text = "튀김기·냄비·믹싱볼에 R로 넣기 · 테이블에 보관(R)"
			else:
				_serve_hint.text = "조리대에 R로 올려 클릭해 손질하세요"
		"dish":
			if _has_helper("serving"):
				_serve_hint.text = "테이블에 두면(R) 카밀라가 서빙해요 · 직접 god에게 가져가도 돼요"
			else:
				_serve_hint.text = "god에게 가져가 서빙 · 테이블에 잠시 둘 수 있어요(R)"
		_:
			_serve_hint.text = "쓰레기통에 R로 버리세요"


## 머리 위로 떠올랐다 사라지는 짧은 안내.
func _toast(text: String) -> void:
	var lb := Label.new()
	lb.text = text
	lb.size = Vector2(630.0, 33.0)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_color_override("font_outline_color", Color.BLACK)
	lb.add_theme_constant_override("outline_size", 4)
	lb.modulate = Color(1.0, 0.95, 0.6)
	lb.z_index = Z_UI
	var at := _player_pos if _pos_init else _field.size * 0.5 # 준비 화면에선 필드 중앙
	lb.position = at + Vector2(-315.0, -156.0)
	_field.add_child(lb)
	var tw := lb.create_tween()
	tw.tween_property(lb, "position:y", lb.position.y - 24.0, 1.0)
	tw.parallel().tween_property(lb, "modulate:a", 0.0, 0.3).set_delay(0.7)
	tw.tween_callback(lb.queue_free)


func _set_held(h: Dictionary) -> void:
	_held = h
	_held_label.text = "" if h.is_empty() else "손: %s" % KitchenItem.label_of(h)
	_hand_vis.set_item(h)


## 들어간 재료 중 가장 낮은 등급.
func _worst_grade(items: Array) -> String:
	var g := "A"
	for it in items:
		g = _worse(g, String(it.get("grade", "A")))
	return g


# ── 기구 배치 모드(개발용) ──────────────────────────────
## 주방 준비 화면의 '기구 배치 편집' → 마우스로 기구를 끌어 옮기고 '저장'하면
## night_session.tscn 에 위치가 그대로 기록된다(에디터 배치와 같은 데이터).
## 에디터/개발 실행에서만 노출(배포 빌드는 res:// 에 쓸 수 없음).
##
## - 배치 가능 범위 = Field/PlaceArea(초록 사각형, 에디터에서 크기 조절). 기구는 범위 밖으로 못 나감.
## - 자석: 다른 기구 가장자리(맞붙이기·정렬)와 범위 가장자리에 _SNAP px 안이면 달라붙음. Alt = 자석 끄기.
## - 1px 단위: 기구를 클릭해 선택 → 방향키 1px, Shift+방향키 10px.
## - 기구끼리 겹치는 위치로는 옮겨지지 않음(충돌·길찾기가 깨지지 않게).

const _SNAP := 15.0

var _layout_mode := false
var _drag: CookStation = null
var _drag_off := Vector2.ZERO
var _sel: CookStation = null # 방향키로 미세 조정할 기구
var _layout_backup := {} # station id -> 편집 전 위치(취소용)
var _layout_bar: PanelContainer
var _layout_info: Label


func _build_layout_tools() -> void:
	if not OS.has_feature("editor"):
		return
	var btn := Button.new()
	btn.text = "🛠 기구 배치 편집 (개발용)"
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 54)
	btn.pressed.connect(_enter_layout_mode)
	var vbox := _start_button.get_parent()
	vbox.add_child(btn)
	vbox.move_child(btn, _start_button.get_index()) # 요리 시작 버튼 바로 위

	_layout_bar = PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_layout_info = Label.new()
	row.add_child(_layout_info)
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
	_layout_bar.position.y = 78.0 # 전역 HUD 상단 바(일차·페이즈, y 15~63) 아래
	_layout_bar.visible = false


func _enter_layout_mode() -> void:
	_layout_backup.clear()
	for id in _st_nodes:
		_layout_backup[id] = _st_nodes[id].position
	_layout_mode = true
	_sel = null
	_prep.visible = false
	_layout_bar.visible = true
	_set_place_area_visible(true)
	_refresh_layout_info()


func _exit_layout_mode() -> void:
	_layout_mode = false
	_drag = null
	_sel = null
	for id in _st_nodes:
		_st_nodes[id].modulate = Color(1, 1, 1)
	_layout_bar.visible = false
	_set_place_area_visible(false)
	_prep.visible = true


## 초록 배치 범위(Field/PlaceArea). 없으면 필드 전체.
func _place_rect() -> Rect2:
	var a := _field.get_node_or_null("PlaceArea") as Control
	return a.get_rect() if a else Rect2(Vector2.ZERO, _field.size)


func _set_place_area_visible(on: bool) -> void:
	var a := _field.get_node_or_null("PlaceArea") as ReferenceRect
	if a:
		a.editor_only = false
		a.visible = on
		a.z_index = Z_UI - 1


func _cancel_layout() -> void:
	for id in _layout_backup:
		_st_nodes[id].position = _layout_backup[id]
	_exit_layout_mode()


func _input(event: InputEvent) -> void:
	if _layout_mode:
		_layout_input(event)
		return
	# 조리 중: 조리대 위를 왼클릭하면 한 번 썰기(클리커).
	if _started and not _ended and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and _st_nodes.has("counter"):
		if _st_nodes["counter"].get_rect().has_point(_field.get_local_mouse_position()):
			_chop()


func _layout_input(event: InputEvent) -> void:
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
					_sel = n
					_drag_off = mouse - n.position
					get_viewport().set_input_as_handled()
					break
		else:
			_drag = null
		_refresh_layout_info()
	elif event is InputEventMouseMotion and _drag:
		var p := (mouse - _drag_off).round()
		if not Input.is_key_pressed(KEY_ALT):
			p = _snap_pos(_drag, p)
		_try_place(_drag, p)
		_refresh_layout_info()
	elif event is InputEventKey and event.pressed and _sel:
		var step := 10.0 if event.shift_pressed else 1.0
		var d := Vector2.ZERO
		match event.keycode:
			KEY_LEFT:
				d.x = -step
			KEY_RIGHT:
				d.x = step
			KEY_UP:
				d.y = -step
			KEY_DOWN:
				d.y = step
		if d != Vector2.ZERO:
			_try_place(_sel, _sel.position + d)
			_refresh_layout_info()
			get_viewport().set_input_as_handled()


## 배치 범위 안으로 1px 단위 고정 + 다른 기구와 겹치면 이동하지 않음.
func _try_place(n: CookStation, p: Vector2) -> void:
	var area := _place_rect()
	p = p.round()
	p.x = clampf(p.x, area.position.x, maxf(area.position.x, area.end.x - n.size.x))
	p.y = clampf(p.y, area.position.y, maxf(area.position.y, area.end.y - n.size.y))
	var r := Rect2(p, n.size)
	for id in _st_nodes:
		var o: CookStation = _st_nodes[id]
		if o != n and r.intersects(o.get_rect()): # 맞닿는 건 허용, 겹침은 불가
			return
	n.position = p


## 자석: 축마다 가장 가까운 후보(_SNAP px 이내)에 달라붙는다.
## 후보 = 배치 범위 가장자리, 다른 기구와 가장자리 정렬(왼쪽/오른쪽/위/아래 맞춤),
## 그리고 맞붙이기(옆/위아래에 딱 붙이기) — 맞붙이기는 실제로 나란히 놓인 기구일 때만
## (예: 좌우로 붙이려면 세로 범위가 겹쳐야 함). 멀리 있는 기구에 1px 어긋나게 붙는 것 방지.
func _snap_pos(n: CookStation, p: Vector2) -> Vector2:
	var sz := n.size
	var area := _place_rect()
	# x 먼저 정한 뒤, 그 x 기준으로 위아래 맞붙이기 대상을 고른다(덜 정렬된 x로 엉뚱한 기구에 붙지 않게).
	var xs := [area.position.x, area.end.x - sz.x]
	for o in _other_rects(n):
		xs.append_array([o.position.x, o.end.x - sz.x])
		if minf(p.y + sz.y, o.end.y) - maxf(p.y, o.position.y) > 0.0: # 세로로 나란함 → 좌우 맞붙이기
			xs.append_array([o.end.x, o.position.x - sz.x])
	p.x = _nearest_snap(p.x, xs)
	var ys := [area.position.y, area.end.y - sz.y]
	for o in _other_rects(n):
		ys.append_array([o.position.y, o.end.y - sz.y])
		if minf(p.x + sz.x, o.end.x) - maxf(p.x, o.position.x) > 0.0: # 가로로 나란함 → 위아래 맞붙이기
			ys.append_array([o.end.y, o.position.y - sz.y])
	p.y = _nearest_snap(p.y, ys)
	return p


func _other_rects(n: CookStation) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for id in _st_nodes:
		if _st_nodes[id] != n:
			out.append(_st_nodes[id].get_rect())
	return out


func _nearest_snap(v: float, cands: Array) -> float:
	var best := v
	var best_d := _SNAP
	for c in cands:
		var dd := absf(float(c) - v)
		if dd <= best_d:
			best_d = dd
			best = float(c)
	return best


## 배치 바 안내 + 선택 기구 좌표, 선택/드래그 강조.
func _refresh_layout_info() -> void:
	for id in _st_nodes:
		var n: CookStation = _st_nodes[id]
		n.modulate = Color(1.45, 1.45, 1.45) if n == _drag else (Color(1.2, 1.2, 1.2) if n == _sel else Color(1, 1, 1))
	var sel := ""
	if _sel:
		sel = "   ·   %s (%d, %d)" % [_sel.display_name(), int(_sel.position.x), int(_sel.position.y)]
	_layout_info.text = "드래그로 이동(자석 정렬, Alt: 끄기) · 방향키 1px / Shift 10px" + sel


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


# ── 주방 준비 (NPC 배치 + 메뉴 선택/강화) ────────────────

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
		label.custom_minimum_size = Vector2(390, 0)
		label.text = "%s: %s" % [_role_label(String(slot)), (_npc_name(npc_id) if npc_id != "" else "-")]
		row.add_child(label)
		if npc_id != "" and NPCManager.is_revived(npc_id):
			var btn := Button.new()
			btn.focus_mode = Control.FOCUS_NONE
			btn.custom_minimum_size = Vector2(240, 51)
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


## 오늘 메뉴 선택 — 캠프 레시피 북과 같은 모습(RecipeCards).
## 왼쪽 격자: 카드(완성 요리 + 이름 + 숙련도), 보유한 레시피 먼저·미해금은 회색, 선호 음식은 분홍 테두리.
##   보유한 카드 왼쪽 위 체크 = 오늘 메뉴 포함(처음엔 전부 체크).
## 오른쪽: 선택한 레시피 상세 + 재료 보유 수 + [강화 ▲] / [구입] 버튼.
var _prep_grid: GridContainer
var _prep_detail: VBoxContainer
var _prep_sel := ""


func _build_recipe_rows() -> void:
	var unlocked := RecipeDB.unlocked_ids()
	if _selected.is_empty():
		for id in unlocked:
			_selected[id] = true
	$Prep/Center/Panel/Margin/VBox/RecipeTitle.text = "── 오늘 밤 메뉴 (체크 = 포함) · 보유 토큰 %d ──" % GameManager.tokens
	if _prep_grid == null: # 최초 1회 레이아웃
		var body := HBoxContainer.new()
		body.add_theme_constant_override("separation", 24)
		_recipe_list.add_child(body)
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(780, 600)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		body.add_child(scroll)
		_prep_grid = GridContainer.new()
		_prep_grid.columns = 4
		_prep_grid.add_theme_constant_override("h_separation", 12)
		_prep_grid.add_theme_constant_override("v_separation", 12)
		scroll.add_child(_prep_grid)
		var dp := PanelContainer.new()
		dp.custom_minimum_size = Vector2(560, 600)
		body.add_child(dp)
		var dsc := ScrollContainer.new() # 재료가 많아도 잘리지 않게
		dsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		dp.add_child(dsc)
		var dm := MarginContainer.new()
		dm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for side in ["left", "right", "top", "bottom"]:
			dm.add_theme_constant_override("margin_" + side, 18)
		dsc.add_child(dm)
		_prep_detail = VBoxContainer.new()
		_prep_detail.add_theme_constant_override("separation", 8)
		dm.add_child(_prep_detail)
	var order := RecipeCards.order()
	if _prep_sel == "" and not order.is_empty():
		_prep_sel = order[0]
	for c in _prep_grid.get_children():
		c.queue_free()
	for id in order:
		var card := RecipeCards.card(id, id == _prep_sel, _on_prep_card.bind(id))
		if id in unlocked: # 메뉴 포함 체크
			var chk := CheckBox.new()
			chk.focus_mode = Control.FOCUS_NONE
			chk.button_pressed = bool(_selected.get(id, false))
			chk.position = Vector2(6, 4)
			chk.toggled.connect(_on_toggle_recipe.bind(id))
			card.add_child(chk)
			if not chk.button_pressed:
				card.modulate = Color(0.75, 0.75, 0.75) # 메뉴에서 뺀 카드는 살짝 흐리게
		_prep_grid.add_child(card)
	_refresh_prep_detail()


func _on_prep_card(id: String) -> void:
	_prep_sel = id
	_build_recipe_rows()


func _on_toggle_recipe(pressed: bool, id: String) -> void:
	_selected[id] = pressed
	_build_recipe_rows()


func _refresh_prep_detail() -> void:
	if _prep_sel == "":
		return
	var id := _prep_sel
	RecipeCards.fill_detail(_prep_detail, id, true, 84.0)
	if RecipeDB.is_unlocked(id):
		var req := RecipeDB.mastery_required(id)
		if req >= 0:
			var up := Button.new()
			up.focus_mode = Control.FOCUS_NONE
			up.custom_minimum_size = Vector2(0, 56)
			up.text = "강화 ▲  Lv%d → Lv%d" % [RecipeDB.level_of(id), RecipeDB.level_of(id) + 1]
			up.disabled = not RecipeDB.can_upgrade(id)
			up.tooltip_text = "다음 레벨: %s" % _process_text(RecipeDB.cook_data(id, RecipeDB.level_of(id) + 1))
			up.pressed.connect(_on_upgrade_recipe.bind(id))
			_prep_detail.add_child(up)
	elif RecipeDB.is_for_sale(id):
		var buy := Button.new()
		buy.focus_mode = Control.FOCUS_NONE
		buy.custom_minimum_size = Vector2(0, 56)
		buy.text = "구입  %d토큰" % RecipeDB.price(id)
		buy.disabled = not RecipeDB.can_buy(id)
		buy.pressed.connect(_on_buy_recipe.bind(id))
		_prep_detail.add_child(buy)


## 잠긴 레시피를 토큰으로 구입 → 바로 오늘 메뉴에 포함.
func _on_buy_recipe(id: String) -> void:
	if RecipeDB.buy(id):
		_selected[id] = true
		_build_recipe_rows()
		_toast("%s 레시피를 배웠다!" % RecipeDB.display_name(id))


func _on_upgrade_recipe(id: String) -> void:
	if RecipeDB.try_upgrade(id):
		_build_recipe_rows()


## 제작 과정 요약: 재료(✂N = 썰기 횟수) → 기구(+시간). 레시피 북과 같은 표기.
func _process_text(d: Dictionary) -> String:
	return RecipeDB.describe(d)


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
	var menu: Array[String] = []
	for id in RecipeDB.unlocked_ids():
		if bool(_selected.get(id, false)):
			menu.append(RecipeDB.display_name(id) + (" ★" if BelamiManager.is_preferred(id) else ""))
	_recipe_label.text = "오늘 메뉴: " + ", ".join(menu)
	_menu_ings.clear()
	for st in COMBINERS:
		for r in _menu_recipes(st):
			for ing in r["ingredients"]:
				if not (String(ing) in _menu_ings):
					_menu_ings.append(String(ing))
	_build_recipe_panel()
	_prep.visible = false
	_started = true
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


# ── 오늘 레시피 표(왼쪽 위) ────────────────────────────

## 요리 중 왼쪽 위에 오늘 메뉴 레시피(재료·써는 횟수·기구)를 띄운다.
func _build_recipe_panel() -> void:
	if _recipe_panel:
		_recipe_panel.queue_free()
	_recipe_panel = PanelContainer.new()
	_recipe_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(9)
	_recipe_panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_recipe_panel.add_child(box)
	var title := Label.new()
	title.text = "오늘 레시피"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	box.add_child(title)
	var count := 0
	for id in RecipeDB.unlocked_ids():
		if bool(_selected.get(id, false)):
			count += 1
	var grid := GridContainer.new() # 최대 4줄 — 메뉴가 많으면 열을 늘려(최대 3열) 기구 줄을 가리지 않게
	grid.columns = clampi(ceili(count / 4.0), 1, 3)
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 0)
	box.add_child(grid)
	for id in RecipeDB.unlocked_ids():
		if not bool(_selected.get(id, false)):
			continue
		var d := RecipeDB.cook_data(id)
		var lb := Label.new()
		lb.text = "%s%s · %s" % [d["display_name"], (" ★" if BelamiManager.is_preferred(id) else ""), _process_text(d)]
		lb.add_theme_font_size_override("font_size", 18)
		grid.add_child(lb)
	add_child(_recipe_panel)
	_recipe_panel.position = Vector2(18.0, 72.0) # 전역 HUD 일차 표시(y 15~63) 아래
	_recipe_panel.z_index = Z_UI


# ── 배고픈 god (재료 소진) · 게임 오버 ───────────────────

## 만족 미달인데 더 이상 서빙할 수 있는 게 없는지:
## 어디에도 요리(완성/조리 중/카밀라 운반)가 없고, 재고 + 주방에 남은 재료로 만들 수 있는 메뉴가 없으면 true.
func _out_of_food() -> bool:
	if _satisfaction >= target_satisfaction:
		return false
	if not _server_dish.is_empty():
		return false
	var loose: Array = [] # 주방에 흩어진 재료(썩지 않은 것)
	var all_items: Array = [_held, _counter_item]
	all_items.append_array(_table)
	for e in _floor:
		all_items.append(e["item"])
	for st in COMBINERS:
		var c: Dictionary = _cookers[st]
		if c["state"] != "fill":
			return false # 조리 중이거나 완성품 대기
		all_items.append_array(c["items"])
	for it in all_items:
		match String(it.get("type", "")):
			"dish":
				return false
			"ing":
				loose.append(String(it["id"]))
	var pool := _counts(loose)
	for id in _menu_ings:
		pool[id] = int(pool.get(id, 0)) + GameManager.cooking_stock(id)
	for st in COMBINERS:
		for r in _menu_recipes(st):
			if _fits(_counts(r["ingredients"]), pool):
				return false
	return true


func _start_hungry() -> void:
	_hungry = true
	_belami.text = "배고파!!"
	_belami.add_theme_color_override("font_color", Color(1.0, 0.22, 0.18))
	_time_label.modulate = Color(1.0, 0.35, 0.3)
	_toast("재료가 다 떨어졌다… god이 배고파한다! (시간 2배)")


## 타임오버 + 배고픔 → god이 플레이어를 잡아먹는 연출 후 게임 오버 화면.
func _game_over() -> void:
	_ended = true
	_tray.visible = false
	_hand_vis.visible = false
	_serve_hint.text = ""
	_belami.text = "냠!"
	_player_node.z_index = _god.z_index + 1
	var god_scale := _god.scale
	var tw := create_tween()
	tw.tween_property(_player_node, "position", _god.position, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_player_node, "scale", Vector2.ZERO, 0.6).set_ease(Tween.EASE_IN)
	tw.tween_property(_god, "scale", god_scale * 1.2, 0.12)
	tw.tween_property(_god, "scale", god_scale, 0.15)
	tw.tween_interval(0.6)
	tw.tween_callback(_show_game_over)


func _show_game_over() -> void:
	var over := Control.new()
	over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	over.z_index = Z_OVERLAY
	add_child(over)
	var dim := ColorRect.new()
	dim.color = Color(0.25, 0.0, 0.0, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	over.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	over.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 21)
	center.add_child(box)
	var title := Label.new()
	title.text = "게임 오버"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
	box.add_child(title)
	var sub := Label.new()
	sub.text = "배고픈 god에게 잡아먹혔다…"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var btn := Button.new()
	btn.text = "Day %d 아침부터 다시 시작" % GameManager.day
	btn.custom_minimum_size = Vector2(420, 72)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(GameManager.restart_day)
	box.add_child(btn)


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


func _update_hud() -> void:
	_sat_label.text = "만족 %0.0f / %0.0f" % [_satisfaction, target_satisfaction]
	_sat_bar.value = minf(_satisfaction, target_satisfaction)
	_tokens_label.text = "토큰(예정): %d" % _tokens_pending
	_fed_label.text = "먹인 수: %d" % _fed


func _item_name(id: String) -> String:
	return ItemDB.display_name(id)
