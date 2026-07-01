extends CharacterBody2D
## 일반 몬스터 (PRD 3.1).
## 감지 반경(detection_range) 안에 플레이어가 들어오면 추적(CHASE) 시작.
## 추적 중 chase_duration 초 동안 한 번도 데미지를 주지 못하면 추적을 멈추고
## 제자리에 머문다(IDLE). 데미지를 주면 추적 시간이 리셋되어 계속 쫓아온다.
## 감지 반경·추적 시간은 몬스터마다 다르게 설정(스폰 시 프로필로 주입).

enum State { IDLE, CHASE }

@export var speed := 95.0
@export var max_hp := 50.0
@export var contact_damage := 15.0
@export var detection_range := 180.0   # 감지 반경 (몬스터마다 다름)
@export var chase_duration := 4.0      # 무피해 시 추적 유지 시간 (몬스터마다 다름)
@export var wander_radius := 90.0      # 대기 시 배회 반경(스폰 지점 기준)
@export var wander_speed := 40.0       # 배회 이동 속도(추적보다 느림)

var hp := 50.0
var drop_item_id: String = ""

var _state: int = State.IDLE
var _chase_timer := 0.0
var _player: Node2D = null
var _touching := false
var _dmg_cd := 0.0

var _home := Vector2.ZERO
var _home_set := false
var _wander_target := Vector2.ZERO
var _wander_pause := 0.0


func _ready() -> void:
	hp = max_hp
	# 인스턴스별 고유 감지 반경 적용(공유 리소스 오염 방지).
	var det := CircleShape2D.new()
	det.radius = detection_range
	$DetectionArea/DetCol.shape = det
	$DetectionArea.body_entered.connect(_on_detect)
	$HitBox.body_entered.connect(_on_hit_entered)
	$HitBox.body_exited.connect(_on_hit_exited)
	# 감지 반경 디버그 표시 토글(테스트용).
	Config.detection_range_visibility_changed.connect(func(_v): queue_redraw())
	queue_redraw()


func _draw() -> void:
	# 몬스터 감지 반경 디버그 시각화. Config 스위치로 끌 수 있음.
	if not Config.show_detection_range:
		return
	var col := Color(1.0, 0.4, 0.4, 0.5) if _state == State.CHASE else Color(0.6, 0.6, 0.6, 0.3)
	draw_arc(Vector2.ZERO, detection_range, 0.0, TAU, 64, col, 2.0, true)


func _physics_process(delta: float) -> void:
	# 스폰 위치를 배회 기준점(home)으로 최초 1회 캡처.
	if not _home_set:
		_home = global_position
		_home_set = true
		_pick_wander_target()

	if _state == State.CHASE:
		_chase_timer -= delta
		if _chase_timer <= 0.0 or _player == null or not is_instance_valid(_player):
			_end_chase()
		else:
			velocity = (_player.global_position - global_position).normalized() * speed
			move_and_slide()
	else:
		_wander(delta) # 대기 시 home 주변을 배회

	_dmg_cd = maxf(0.0, _dmg_cd - delta)
	if _touching and _dmg_cd <= 0.0 and _player and _player.has_method("take_hit"):
		_player.take_hit(contact_damage)
		_dmg_cd = 1.0
		# 데미지 성공 → (재)추적 + 추적 시간 리셋.
		var was_chasing := _state == State.CHASE
		_state = State.CHASE
		_chase_timer = chase_duration
		if not was_chasing:
			queue_redraw()


func _on_detect(body: Node) -> void:
	if body.is_in_group("player") and _state == State.IDLE:
		_player = body
		_state = State.CHASE
		_chase_timer = chase_duration
		queue_redraw()


func _on_hit_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_touching = true
		_player = body


func _on_hit_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_touching = false


func _end_chase() -> void:
	_state = State.IDLE
	_chase_timer = 0.0
	velocity = Vector2.ZERO
	queue_redraw()


## 대기 시 스폰 지점(home) 주변을 느리게 배회한다.
func _wander(delta: float) -> void:
	if _wander_pause > 0.0:
		_wander_pause -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var to := _wander_target - global_position
	if to.length() < 8.0:
		_wander_pause = randf_range(0.4, 1.4) # 잠시 멈췄다가 다음 지점
		_pick_wander_target()
		velocity = Vector2.ZERO
	else:
		velocity = to.normalized() * wander_speed
	move_and_slide()


func _pick_wander_target() -> void:
	var ang := randf() * TAU
	var r := sqrt(randf()) * wander_radius # 원판 내 균일 분포
	_wander_target = _home + Vector2(cos(ang), sin(ang)) * r


func take_damage(amount: float) -> void:
	hp -= amount
	_aggro_from_hit() # 피격 시 감지 반경 밖이어도 추적 시작
	if hp <= 0.0:
		_die()


## 공격당하면(먼 거리 포함) 플레이어를 추적. 플레이어는 그룹으로 탐색.
func _aggro_from_hit() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return
	var was_chasing := _state == State.CHASE
	_state = State.CHASE
	_chase_timer = chase_duration
	if not was_chasing:
		queue_redraw()


func _die() -> void:
	var s := get_tree().get_first_node_in_group("scavenge")
	if s and s.has_method("on_monster_drop"):
		s.on_monster_drop(global_position, drop_item_id)
	queue_free()
