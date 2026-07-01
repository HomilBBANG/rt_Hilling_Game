extends CharacterBody2D
## 플레이어 (탑다운, PRD 3.1). WASD 8방향 이동 + 마우스 조준 사격.
## 위험은 가벼운 패널티(PRD 3.1): 피격 시 스태미나 감소, 0이 되면 조기 귀환
## (실제 귀환 처리는 Scavenge 씬이 stamina_depleted 를 받아 수행).

signal stamina_depleted

@export var speed := 220.0
@export var max_stamina := 100.0
@export var fire_cooldown := 0.22
@export var bullet_scene: PackedScene

## 근접(칼) — 탄약 불필요, 조준 방향 부채꼴 범위 즉시 타격(PRD 3.3).
## 데미지는 WeaponManager(강화 반영)에서 읽는다.
@export var melee_range := 64.0
@export var melee_cooldown := 0.42
@export var melee_arc_dot := 0.5 # 조준 방향 기준 부채꼴(≈±60°)

var stamina := 100.0

var _invuln := 0.0
var _fire_cd := 0.0
var _melee_cd := 0.0

@onready var _aim: Node2D = $Aim
@onready var _muzzle: Marker2D = $Aim/Muzzle
@onready var _slash: Polygon2D = $Aim/Slash


func _ready() -> void:
	stamina = max_stamina
	speed = Balance.get_float("player_speed", speed) # 엑셀 조정 가능


func _physics_process(delta: float) -> void:
	_invuln = maxf(0.0, _invuln - delta)
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_melee_cd = maxf(0.0, _melee_cd - delta)

	velocity = _input_dir() * speed
	move_and_slide()

	_aim.look_at(get_global_mouse_position())

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _fire_cd <= 0.0:
		_shoot()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and _melee_cd <= 0.0:
		_melee()


func _input_dir() -> Vector2:
	var d := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		d.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		d.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		d.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		d.y += 1.0
	return d.normalized()


func _shoot() -> void:
	# 탄약 소모 실패 시 발사하지 않음(PRD 3.3 — 탄약은 소모성 자원).
	if not WeaponManager.consume_ammo(1):
		return
	_fire_cd = fire_cooldown
	if bullet_scene == null:
		return
	var b := bullet_scene.instantiate()
	get_parent().add_child(b)
	b.damage = WeaponManager.ranged_damage() # 강화 반영
	b.global_position = _muzzle.global_position
	var dir := get_global_mouse_position() - global_position
	if dir.length() < 0.01:
		dir = Vector2.RIGHT
	b.setup(dir.normalized())


func _melee() -> void:
	_melee_cd = melee_cooldown
	_flash_slash()
	var aim := get_global_mouse_position() - global_position
	if aim.length() < 0.01:
		aim = Vector2.RIGHT
	aim = aim.normalized()
	# 조준 방향 부채꼴 안의 몬스터를 즉시 타격.
	for m in get_tree().get_nodes_in_group("monster"):
		if not is_instance_valid(m):
			continue
		var to: Vector2 = m.global_position - global_position
		if to.length() <= melee_range and to.normalized().dot(aim) >= melee_arc_dot:
			if m.has_method("take_damage"):
				m.take_damage(WeaponManager.melee_damage()) # 강화 반영


func _flash_slash() -> void:
	if _slash == null:
		return
	_slash.visible = true
	get_tree().create_timer(0.12).timeout.connect(_hide_slash)


func _hide_slash() -> void:
	if is_instance_valid(_slash):
		_slash.visible = false


func take_hit(amount: float) -> void:
	if _invuln > 0.0:
		return
	_invuln = 0.8
	stamina = maxf(0.0, stamina - amount)
	if stamina <= 0.0:
		stamina_depleted.emit()
