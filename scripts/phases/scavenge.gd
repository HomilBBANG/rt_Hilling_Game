extends Node2D
## 탐사 페이즈 (PRD 3.1) — 탑다운 전투형 채집 슬라이스.
## 몬스터 1패턴, 채집, 탄약 고정 드롭, 시간/스태미나 제한, 출구 귀환.
## 바닥/타일셋/장애물은 제거됨(새 리소스로 교체 예정).

const REGION_PATH := "res://resources/regions/ruins.tres"

## 맵 크기. 스폰 분산 범위 + 카메라 경계 기준.
const MAP_SIZE := Vector2(3200, 2400)
const SPAWN_MARGIN := 140.0    # 벽에서 떨어뜨릴 여백
const PLAYER_CLEAR := 500.0    # 플레이어 시작 주변엔 몬스터 스폰 금지

@export var player_scene: PackedScene
@export var monster_scene: PackedScene
@export var resource_scene: PackedScene
@export var ammo_scene: PackedScene
@export var run_seconds := 90.0
@export var monster_count := 16
@export var resource_count := 24

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

	# 몬스터마다 감지 반경/추적 시간/속도가 다르도록 프로필 순환.
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


## 맵 내 랜덤 위치. avoid_player=true 면 플레이어 시작 지점 주변은 피함.
func _random_spawn_pos(avoid_player: bool) -> Vector2:
	var start: Vector2 = $PlayerStart.global_position
	for attempt in 25:
		var p := Vector2(
			randf_range(SPAWN_MARGIN, MAP_SIZE.x - SPAWN_MARGIN),
			randf_range(SPAWN_MARGIN, MAP_SIZE.y - SPAWN_MARGIN))
		if avoid_player and p.distance_to(start) < PLAYER_CLEAR:
			continue
		return p
	return start + Vector2(PLAYER_CLEAR, 0.0)


## 플레이어 카메라가 맵 밖(벽 너머)을 보지 않도록 경계 제한.
func _set_camera_limits() -> void:
	var cam := _player.get_node_or_null("Camera")
	if cam:
		cam.limit_left = 0
		cam.limit_top = 0
		cam.limit_right = int(MAP_SIZE.x)
		cam.limit_bottom = int(MAP_SIZE.y)
