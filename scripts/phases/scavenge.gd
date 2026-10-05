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
var _overweight_t := 0.0 # >0 이면 '무게 초과' 경고 표시 시간
var _key1_was_down := false # 퀵슬롯(1) 엣지 감지
var _overweight_label: Label = null # 플레이어 머리 위 '너무 무거워'

@onready var _time_label: Label = $HUD/Root/Stats/TimeLabel
@onready var _hp_bar: TextureProgressBar = $HUD/Root/HpBar
@onready var _qs_item: Label = $HUD/Root/QuickSlot/QSItem
@onready var _qs_count: Label = $HUD/Root/QuickSlot/QSCount
@onready var _ammo_count: Label = $HUD/Root/AmmoCount


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
	# 무게 초과 시 머리 위에 뜨는 경고 라벨(월드 좌표).
	_overweight_label = Label.new()
	_overweight_label.text = "너무 무거워"
	_overweight_label.modulate = Color(1.0, 0.25, 0.2)
	_overweight_label.z_index = 50
	_overweight_label.visible = false
	add_child(_overweight_label)
	if _player.has_signal("stamina_depleted"):
		_player.stamina_depleted.connect(_on_stamina_depleted)
	_set_camera_limits()

	# 일반 몬스터(보스 제외) 순환 배치.
	for i in monster_count:
		var mon := monster_scene.instantiate()
		_apply_monster_type(mon, MonsterDB.get_regular(i))
		if mon.drop_item_id == "": # 종류에 드롭 아이템이 없으면 지역 재료로 폴백
			mon.drop_item_id = _pick_material_id()
		add_child(mon) # exports 를 _ready 전에 주입
		mon.global_position = _random_spawn_pos(true)

	# 지역 보스(region.boss_id) 1마리 — 플레이어 시작 반대편 먼 곳에.
	if _region and _region.boss_id != "":
		var boss_data := MonsterDB.get_by_id(_region.boss_id)
		if not boss_data.is_empty():
			var boss := monster_scene.instantiate()
			_apply_monster_type(boss, boss_data)
			if boss.drop_item_id == "":
				boss.drop_item_id = _pick_material_id()
			add_child(boss)
			boss.global_position = Vector2(MAP_SIZE.x * 0.5, 320.0) # 상단 중앙(시작 지점서 멀리)

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


## 엑셀 몬스터 종류(Dictionary)의 능력치를 몬스터 인스턴스에 주입. 빈 사전이면 기본값 유지.
func _apply_monster_type(mon: Node, t: Dictionary) -> void:
	if t.is_empty():
		return
	mon.max_hp = float(t.get("max_hp", mon.max_hp))
	mon.contact_damage = float(t.get("contact_damage", mon.contact_damage))
	mon.speed = float(t.get("speed", mon.speed))
	mon.detection_range = float(t.get("detection_range", mon.detection_range))
	mon.chase_duration = float(t.get("chase_duration", mon.chase_duration))
	mon.wander_radius = float(t.get("wander_radius", mon.wander_radius))
	mon.wander_speed = float(t.get("wander_speed", mon.wander_speed))
	# 공격 스킬 파라미터(엑셀에 열이 있으면 덮어씀, 없으면 몬스터 기본값 유지).
	mon.stop_distance = float(t.get("stop_distance", mon.stop_distance))
	mon.attack_range = float(t.get("attack_range", mon.attack_range))
	mon.attack_cooldown = float(t.get("attack_cooldown", mon.attack_cooldown))
	mon.attack_windup = float(t.get("attack_windup", mon.attack_windup))
	mon.sprite_id = String(t.get("sprite", ""))
	# 드롭 테이블(아이템/확률/수량).
	mon.drop_item_id = String(t.get("drop_item", ""))
	mon.drop_chance = float(t.get("drop_chance", 1.0))
	mon.drop_min = int(t.get("drop_min", 1))
	mon.drop_max = int(t.get("drop_max", 1))
	# 보스 여부/크기.
	mon.is_boss = bool(t.get("is_boss", false))
	mon.visual_scale = float(t.get("scale", 1.0))
	mon.display_name = String(t.get("display_name", ""))


func _process(delta: float) -> void:
	if _returning:
		return
	_overweight_t = maxf(0.0, _overweight_t - delta)
	_update_overweight_label()
	_time_left = maxf(0.0, _time_left - delta)
	if _time_left <= 0.0:
		_finish(true)
		return
	if _in_exit and (Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_ENTER)):
		_finish(false)
		return
	var k1 := Input.is_physical_key_pressed(KEY_1)
	if k1 and not _key1_was_down: # 퀵슬롯 즉시 사용
		_use_quick_slot()
	_key1_was_down = k1
	_update_hud()


## ResourceNode / 몬스터 드롭이 호출. 무게 한도 내에서 담을 수 있는 만큼만 채집.
## 실제로 담은 개수를 반환(0이면 무게 초과로 못 담음).
func add_loot(item_id: String, amount: int) -> int:
	var fit := GameManager.units_that_fit(item_id, amount)
	if fit <= 0:
		_overweight_t = 1.5 # HUD 경고 표시
		_update_hud()
		return 0
	_loot[item_id] = int(_loot.get(item_id, 0)) + fit # 이번 탐사분(HUD 요약 + 패널티)
	GameManager.add_item(item_id, fit)                 # 인벤토리에 누적
	_discover_item(item_id) # 도감 등록 → 레시피 해금 트리거(예: 감자 → 감자튀김)
	if _player and is_instance_valid(_player):
		_player.show_pickup("%s +%d" % [ItemDB.display_name(item_id), fit]) # 머리 위 획득 표시
	if fit < amount:
		_overweight_t = 1.5 # 일부만 담김
	_update_hud()
	return fit


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
	if forced:
		# 가벼운 패널티(PRD 3.1): 이번 탐사 채집물의 절반을 인벤토리에서 회수.
		for k in _loot.keys():
			GameManager.remove_item(String(k), int(_loot[k]) / 2)
	GameManager.finish_scavenge()


func _update_hud() -> void:
	_time_label.text = "남은 시간: %0.0f초" % _time_left
	if _player and is_instance_valid(_player):
		# HP 바(빨간 면)를 스태미나 비율로 채운다 → 깎이면 좌→우로 줄어듦.
		var mx: float = maxf(1.0, _player.max_stamina)
		_hp_bar.value = _player.stamina / mx * 100.0
	_ammo_count.text = "×%d" % WeaponManager.ammo
	_update_quick_slot_hud()


func _update_quick_slot_hud() -> void:
	var qid := GameManager.quick_slot
	if qid == "":
		_qs_item.text = "-"
		_qs_count.text = ""
	else:
		_qs_item.text = ItemDB.display_name(qid)
		_qs_count.text = "×%d" % int(GameManager.run_inventory.get(qid, 0))


## 퀵슬롯(1) 즉시 사용 — 등록된 회복 아이템으로 체력 회복(보유+체력 여유 있을 때).
func _use_quick_slot() -> void:
	var id := GameManager.quick_slot
	if id == "" or not ItemDB.is_consumable(id):
		return
	if int(GameManager.run_inventory.get(id, 0)) <= 0:
		return
	if _player == null or not is_instance_valid(_player):
		return
	if _player.stamina >= _player.max_stamina:
		return
	_player.stamina = minf(_player.max_stamina, _player.stamina + float(ItemDB.heal_amount(id)))
	GameManager.remove_item(id, 1)
	_update_hud()


func _update_overweight_label() -> void:
	if _overweight_label == null:
		return
	var show := _overweight_t > 0.0 and _player != null and is_instance_valid(_player)
	_overweight_label.visible = show
	if show:
		_overweight_label.position = _player.global_position + Vector2(-34.0, -64.0)


## 인벤토리에서 '버리기' 시 호출 — 플레이어 발밑 근처 바닥에 아이템 노드를 남긴다.
func drop_on_floor(item_id: String, amount: int, pos: Vector2) -> void:
	if amount <= 0 or item_id == "":
		return
	var node := resource_scene.instantiate()
	add_child(node)
	node.global_position = pos + Vector2(randf_range(-24.0, 24.0), randf_range(12.0, 34.0))
	node.item_id = item_id
	node.amount = amount


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
