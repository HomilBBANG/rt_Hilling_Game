extends Node2D
## 탐사 페이즈 (PRD 3.1) — 탑다운 전투형 채집 슬라이스.
## RegionData 로 스폰 구성(데이터 드리븐). 시간/스태미나 제한, 탄약 고정 드롭,
## 몬스터 1패턴, 채집, 출구 귀환. 조기 귀환(시간 초과/스태미나 소진)은 가벼운 패널티.

const REGION_PATH := "res://resources/regions/ruins.tres"

## 맵 크기(벽/바닥은 씬에서 이 값에 맞춰 배치되어 있음). 스폰 분산 범위 기준.
const MAP_SIZE := Vector2(6400, 4800)
const SPAWN_MARGIN := 140.0    # 벽에서 떨어뜨릴 여백
const PLAYER_CLEAR := 500.0    # 플레이어 시작 주변엔 몬스터 스폰 금지

@export var player_scene: PackedScene
@export var monster_scene: PackedScene
@export var resource_scene: PackedScene
@export var ammo_scene: PackedScene
@export var obstacle_scene: PackedScene
@export var run_seconds := 90.0
@export var monster_count := 16
@export var resource_count := 24

var _obstacles: Array = [] # [{pos:Vector2, radius:float}]

var _region: RegionData = null
var _time_left := 0.0
var _loot: Dictionary = {}
var _player: Node2D = null
var _in_exit := false
var _returning := false

@onready var _time_label: Label = $HUD/Root/Stats/TimeLabel
@onready var _stamina_label: Label = $HUD/Root/Stats/StaminaLabel
@onready var _ammo_label: Label = $HUD/Root/Stats/AmmoLabel
@onready var _loot_label: Label = $HUD/Root/Stats/LootLabel


func _ready() -> void:
	add_to_group("scavenge")
	run_seconds = Balance.get_float("scavenge_seconds", run_seconds) # 엑셀 조정 가능
	_time_left = run_seconds
	_region = load(REGION_PATH) as RegionData
	_spawn_world()
	_update_hud()


func _spawn_world() -> void:
	_player = player_scene.instantiate()
	add_child(_player)
	_player.global_position = $PlayerStart.global_position
	if _player.has_signal("stamina_depleted"):
		_player.stamina_depleted.connect(_on_stamina_depleted)
	_set_camera_limits()

	# 장애물을 먼저 배치 → 몬스터/자원이 그 위에 안 생기도록 회피 기준으로 사용.
	_scatter_obstacles()

	# 몬스터마다 감지 반경/추적 시간/속도가 다르도록 프로필을 순환 부여.
	# 넓은 맵 전체에 절차적으로 분산 배치(개수는 export 로 조정).
	var profiles := [
		{"detection_range": 160.0, "chase_duration": 3.0, "speed": 90.0, "wander_radius": 80.0},
		{"detection_range": 240.0, "chase_duration": 5.0, "speed": 78.0, "wander_radius": 130.0},
		{"detection_range": 120.0, "chase_duration": 2.5, "speed": 110.0, "wander_radius": 60.0},
	]
	for i in monster_count:
		var mon := monster_scene.instantiate()
		var prof: Dictionary = profiles[i % profiles.size()]
		mon.detection_range = prof["detection_range"]
		mon.chase_duration = prof["chase_duration"]
		mon.speed = prof["speed"]
		mon.wander_radius = prof["wander_radius"]
		mon.drop_item_id = _pick_material_id()
		add_child(mon) # exports 를 _ready 전에 주입
		mon.global_position = _random_spawn_pos(true)

	for i in resource_count:
		var node := resource_scene.instantiate()
		add_child(node)
		node.global_position = _random_spawn_pos(false)
		node.item_id = _pick_food_id()

	# 탄약: 맵 내 고정 지점(랜덤 아님, PRD 3.1)
	for a in $AmmoSpawns.get_children():
		var pk := ammo_scene.instantiate()
		add_child(pk)
		pk.global_position = a.global_position

	$ExitZone.body_entered.connect(_on_exit_entered)
	$ExitZone.body_exited.connect(_on_exit_exited)


func _process(delta: float) -> void:
	if _returning:
		return
	_time_left = maxf(0.0, _time_left - delta)
	if _time_left <= 0.0:
		_finish(true)
		return
	if _in_exit and (Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_ENTER)):
		_finish(false)
		return
	_update_hud()


## ResourceNode / 몬스터 드롭이 호출.
func add_loot(item_id: String, amount: int) -> void:
	_loot[item_id] = int(_loot.get(item_id, 0)) + amount
	_discover_item(item_id) # 도감 등록 → 레시피 해금 트리거(예: 감자 → 감자튀김)
	_update_hud()


func _discover_item(item_id: String) -> void:
	var path := "res://resources/items/%s.tres" % item_id
	if ResourceLoader.exists(path):
		var it := load(path) as ItemData
		if it:
			CodexManager.discover(_category_name(it.category), item_id)
			return
	CodexManager.discover("misc", item_id)


func _category_name(category: int) -> String:
	match category:
		ItemData.Category.FOOD:
			return "food"
		ItemData.Category.MATERIAL:
			return "material"
		ItemData.Category.RELIC:
			return "relic"
	return "misc"


func on_monster_drop(pos: Vector2, item_id: String) -> void:
	if item_id == "":
		return
	var node := resource_scene.instantiate()
	add_child(node)
	node.global_position = pos
	node.item_id = item_id


func _on_stamina_depleted() -> void:
	_finish(true)


func _on_exit_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_in_exit = true


func _on_exit_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_in_exit = false


func _finish(forced: bool) -> void:
	if _returning:
		return
	_returning = true
	var loot := _loot.duplicate()
	if forced:
		# 가벼운 패널티(PRD 3.1): 채집물 절반 손실
		for k in loot.keys():
			loot[k] = int(loot[k]) / 2
	GameManager.finish_scavenge(loot)


func _update_hud() -> void:
	_time_label.text = "남은 시간: %0.0f초" % _time_left
	var st := 0.0
	if _player and is_instance_valid(_player):
		st = _player.stamina
	_stamina_label.text = "스태미나: %0.0f" % st
	_ammo_label.text = "탄약: %d" % WeaponManager.ammo
	_loot_label.text = "채집: %s" % _loot_summary()


func _loot_summary() -> String:
	if _loot.is_empty():
		return "없음"
	var parts: Array[String] = []
	for k in _loot.keys():
		parts.append("%s×%d" % [k, _loot[k]])
	return ", ".join(parts)


func _pick_food_id() -> String:
	if _region and _region.food_item_ids.size() > 0:
		return _region.food_item_ids[randi() % _region.food_item_ids.size()]
	return "canned_food"


func _pick_material_id() -> String:
	if _region and _region.material_item_ids.size() > 0:
		return _region.material_item_ids[randi() % _region.material_item_ids.size()]
	return "scrap_metal"


## 맵 내 랜덤 위치. avoid_player=true 면 시작 지점 주변, 그리고 장애물 위는 피함.
func _random_spawn_pos(avoid_player: bool) -> Vector2:
	var start: Vector2 = $PlayerStart.global_position
	for attempt in 25:
		var p := Vector2(
			randf_range(SPAWN_MARGIN, MAP_SIZE.x - SPAWN_MARGIN),
			randf_range(SPAWN_MARGIN, MAP_SIZE.y - SPAWN_MARGIN))
		if avoid_player and p.distance_to(start) < PLAYER_CLEAR:
			continue
		if not _clear_of_obstacles(p, 26.0):
			continue
		return p
	return start + Vector2(PLAYER_CLEAR, 0.0)


func _clear_of_obstacles(p: Vector2, margin: float) -> bool:
	for o in _obstacles:
		if p.distance_to(o.pos) < float(o.radius) + margin:
			return false
	return true


## 장애물(나무·바위)을 맵 전체에 절차적으로 배치. 플레이어 시작·탄약 지점·기존 장애물은 회피.
func _scatter_obstacles() -> void:
	if obstacle_scene == null:
		return
	var count := 48
	if _region:
		count = _region.obstacle_count
	var start: Vector2 = $PlayerStart.global_position
	var ammo_positions: Array = []
	for a in $AmmoSpawns.get_children():
		ammo_positions.append(a.global_position)

	for i in count:
		var is_tree := randf() < 0.6
		var r := randf_range(24.0, 34.0) if is_tree else randf_range(16.0, 24.0)
		var col := Color(0.26, 0.5, 0.28) if is_tree else Color(0.46, 0.46, 0.5)
		var pos := _find_obstacle_pos(start, ammo_positions, r)
		if pos == Vector2.INF:
			continue
		var ob := obstacle_scene.instantiate()
		ob.setup(r, col) # add_child(_ready) 전에 크기/색 주입
		add_child(ob)
		ob.global_position = pos
		_obstacles.append({"pos": pos, "radius": r})


func _find_obstacle_pos(start: Vector2, ammo_positions: Array, r: float) -> Vector2:
	for attempt in 30:
		var p := Vector2(
			randf_range(SPAWN_MARGIN, MAP_SIZE.x - SPAWN_MARGIN),
			randf_range(SPAWN_MARGIN, MAP_SIZE.y - SPAWN_MARGIN))
		if p.distance_to(start) < PLAYER_CLEAR:
			continue
		var ok := true
		for ap in ammo_positions:
			if p.distance_to(ap) < 170.0:
				ok = false
				break
		if ok:
			for o in _obstacles:
				if p.distance_to(o.pos) < float(o.radius) + r + 30.0:
					ok = false
					break
		if ok:
			return p
	return Vector2.INF


## 플레이어 카메라가 맵 밖(벽 너머)을 보지 않도록 경계 제한.
func _set_camera_limits() -> void:
	var cam := _player.get_node_or_null("Camera")
	if cam:
		cam.limit_left = 0
		cam.limit_top = 0
		cam.limit_right = int(MAP_SIZE.x)
		cam.limit_bottom = int(MAP_SIZE.y)
