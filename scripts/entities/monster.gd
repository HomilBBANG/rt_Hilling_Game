extends CharacterBody2D
## 일반 몬스터 (PRD 3.1).
## 감지 반경(detection_range) 안에 플레이어가 들어오면 추적(CHASE) 시작.
## 추적 중 chase_duration 초 동안 공격도 못하면 추적을 멈추고 제자리로(IDLE).
## 플레이어에게 파고들지 않고 stop_distance(코앞)에서 멈춰, 공격 범위(attack_range)를
## 표시한 뒤 짧은 준비동작(windup) 후 공격 스킬로 데미지(쿨다운 attack_cooldown).
## 능력치는 몬스터마다 다르게 설정(스폰 시 엑셀 데이터 주입).

enum State { IDLE, CHASE }

@export var speed := 95.0
@export var max_hp := 50.0
@export var contact_damage := 15.0     # 공격 스킬 1회 데미지
@export var detection_range := 180.0   # 감지 반경 (몬스터마다 다름)
@export var chase_duration := 4.0      # 무공격 시 추적 유지 시간 (몬스터마다 다름)
@export var wander_radius := 90.0      # 대기 시 배회 반경(스폰 지점 기준)
@export var wander_speed := 40.0       # 배회 이동 속도(추적보다 느림)

## 공격 스킬 파라미터.
@export var stop_distance := 26.0      # 플레이어 코앞에서 멈추는 거리(겹침 방지, ≈몸 반지름 합+1px)
@export var attack_range := 48.0       # 공격 범위(표시됨). 이 안의 플레이어에게 데미지
@export var attack_cooldown := 1.2     # 공격 간 간격(초)
@export var attack_windup := 0.35      # 공격 준비동작(텔레그래프) 시간(초)

## idle 애니 폴더 id(assets/monsters/<sprite_id>/<sprite_id>_idle_N.png). 비우면 사각형 유지.
@export var sprite_id: String = ""

## 드롭 테이블(스폰 시 엑셀에서 주입).
@export var drop_chance := 1.0   # 드롭 확률(0~1)
@export var drop_min := 1        # 최소 수량
@export var drop_max := 1        # 최대 수량

const _LOOT_RANGE := 46.0        # 시체 루팅 상호작용 거리
const _LOOT_TIME := 2.0          # E 누른 뒤 아이템이 나오기까지 시간(초)

var hp := 50.0
var drop_item_id: String = ""

var _dead := false               # 시체 상태
var _loot_t := -1.0              # >=0 이면 루팅 진행 중(남은 시간)
var _e_was_down := false
var _corpse_hint: Label = null

var _sprite: AnimatedSprite2D = null # sprite_id 지정 시 사용
var _has_walk := false               # walk 애니 존재 여부

var _state: int = State.IDLE
var _chase_timer := 0.0
var _player: Node2D = null
var _attack_cd := 0.0     # 남은 공격 쿨다운
var _windup := -1.0       # >=0 이면 공격 준비동작 진행 중(남은 시간)

var _home := Vector2.ZERO
var _home_set := false
var _wander_target := Vector2.ZERO
var _wander_pause := 0.0


func _ready() -> void:
	hp = max_hp
	_setup_visual()
	# 인스턴스별 고유 감지 반경 적용(공유 리소스 오염 방지).
	var det := CircleShape2D.new()
	det.radius = detection_range
	$DetectionArea/DetCol.shape = det
	$DetectionArea.body_entered.connect(_on_detect)
	$HitBox.body_entered.connect(_on_hit_entered)
	# 감지 반경 디버그 표시 토글(테스트용).
	Config.detection_range_visibility_changed.connect(func(_v): queue_redraw())
	queue_redraw()


## sprite_id 가 지정되고 프레임이 있으면 AnimatedSprite2D 로 표시(idle + walk), 없으면 사각형 유지.
func _setup_visual() -> void:
	if sprite_id == "":
		return
	var sf := SpriteFrames.new()
	sf.remove_animation("default") # 기본 빈 애니 제거
	var idle_n := _add_anim(sf, "idle", "res://assets/monsters/%s/%s_idle_%%d.png" % [sprite_id, sprite_id], 2.5)
	var walk_n := _add_anim(sf, "walk", "res://assets/monsters/%s/%s_walk_%%d.png" % [sprite_id, sprite_id], 8.0)
	if idle_n == 0 and walk_n == 0:
		return # 프레임 하나도 없으면 플레이스홀더 유지
	_has_walk = walk_n > 0
	_sprite = $Sprite as AnimatedSprite2D
	_sprite.sprite_frames = sf
	_sprite.play("idle" if idle_n > 0 else "walk")
	_sprite.visible = true
	$Body.visible = false


## 패턴(…_%d.png)으로 프레임을 로드해 애니 추가. 로드한 프레임 수 반환(0이면 애니 제거).
func _add_anim(sf: SpriteFrames, anim: String, pattern: String, fps: float) -> int:
	sf.add_animation(anim)
	sf.set_animation_loop(anim, true)
	sf.set_animation_speed(anim, fps)
	var i := 0
	while ResourceLoader.exists(pattern % i):
		sf.add_frame(anim, load(pattern % i))
		i += 1
	if i == 0:
		sf.remove_animation(anim)
	return i


## 이동 여부에 따라 walk/idle 전환 + 좌우 반전.
func _update_anim() -> void:
	if _sprite == null:
		return
	var moving := velocity.length() > 5.0
	var want := "walk" if (moving and _has_walk) else "idle"
	if not _sprite.sprite_frames.has_animation(want):
		want = "idle" if _sprite.sprite_frames.has_animation("idle") else "walk"
	if _sprite.animation != want:
		_sprite.play(want)
	if absf(velocity.x) > 1.0:
		_sprite.flip_h = velocity.x < 0.0 # 왼쪽 이동 시 반전(원본이 오른쪽을 향한다고 가정)


func _draw() -> void:
	if _dead:
		return
	# 공격 범위 표시(추적 중일 때만). 준비동작 중이면 채워서 임박함을 알림.
	if _state == State.CHASE:
		var attacking := _windup >= 0.0
		var edge := Color(1.0, 0.3, 0.2, 0.7 if attacking else 0.25)
		if attacking:
			draw_circle(Vector2.ZERO, attack_range, Color(1.0, 0.3, 0.2, 0.18))
		draw_arc(Vector2.ZERO, attack_range, 0.0, TAU, 48, edge, 2.0, true)
	# 감지 반경 디버그 시각화(Config 스위치로 토글).
	if Config.show_detection_range:
		var col := Color(1.0, 0.4, 0.4, 0.5) if _state == State.CHASE else Color(0.6, 0.6, 0.6, 0.3)
		draw_arc(Vector2.ZERO, detection_range, 0.0, TAU, 64, col, 2.0, true)


func _physics_process(delta: float) -> void:
	if _dead: # 시체 상태: AI 정지, E 루팅만 처리
		_dead_process(delta)
		return
	# 스폰 위치를 배회 기준점(home)으로 최초 1회 캡처.
	if not _home_set:
		_home = global_position
		_home_set = true
		_pick_wander_target()

	_attack_cd = maxf(0.0, _attack_cd - delta)

	if _state == State.CHASE:
		_chase_timer -= delta
		if _chase_timer <= 0.0 or _player == null or not is_instance_valid(_player):
			_end_chase()
		else:
			_chase_and_attack(delta)
	else:
		_wander(delta) # 대기 시 home 주변을 배회

	_update_anim() # 이동 여부에 따라 walk/idle 전환


## 플레이어를 stop_distance 코앞까지 쫓아가 멈춘 뒤 공격 스킬을 사용.
func _chase_and_attack(delta: float) -> void:
	var to: Vector2 = _player.global_position - global_position
	var dist := to.length()
	if dist > stop_distance:
		# 코앞에서 딱 멈추도록 남은 거리만큼만 이동(오버슈트로 인한 버벅임 방지).
		var reach := minf(speed, (dist - stop_distance) / maxf(delta, 0.0001))
		velocity = to.normalized() * reach
		move_and_slide()
		if _windup >= 0.0: # 이동하면 준비동작 취소
			_windup = -1.0
			queue_redraw()
	else:
		# 코앞 도착 → 정지 후 공격.
		velocity = Vector2.ZERO
		if _sprite and absf(to.x) > 1.0:
			_sprite.flip_h = to.x < 0.0 # 플레이어 쪽을 바라봄
		_attack_tick(delta)


## 정지 상태에서 공격 사이클: 쿨다운 → 준비동작(windup) → 데미지.
func _attack_tick(delta: float) -> void:
	if _windup >= 0.0:
		_windup -= delta
		if _windup <= 0.0:
			_windup = -1.0
			_do_attack()
		queue_redraw()
		return
	if _attack_cd <= 0.0:
		_windup = attack_windup      # 텔레그래프 시작
		_chase_timer = chase_duration # 공격 시도 중이면 추적 유지
		queue_redraw()


## 공격 발동: attack_range 안의 플레이어에게 데미지.
func _do_attack() -> void:
	_attack_cd = attack_cooldown
	if _player and is_instance_valid(_player) and _player.has_method("take_hit"):
		if _player.global_position.distance_to(global_position) <= attack_range:
			_player.take_hit(contact_damage)
	queue_redraw()


func _on_detect(body: Node) -> void:
	if body.is_in_group("player") and _state == State.IDLE:
		_player = body
		_state = State.CHASE
		_chase_timer = chase_duration
		queue_redraw()


## 근접 접촉은 데미지 없이 플레이어 참조만 갱신(공격은 stop_distance에서 스킬로 처리).
func _on_hit_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player = body


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


## 사망 → 즉시 사라지지 않고 어두운 시체로 제자리에 남는다(E 로 루팅).
func _die() -> void:
	if _dead:
		return
	_dead = true
	remove_from_group("monster") # 더는 공격/탐지 대상 아님
	velocity = Vector2.ZERO
	_state = State.IDLE
	# 시체 시각: 비주얼만 어둡게(png 그대로, modulate). 애니는 멈춤. (안내 라벨은 밝게 유지)
	var dark := Color(0.42, 0.42, 0.48)
	if _sprite:
		_sprite.modulate = dark
		_sprite.stop()
	if has_node("Body"):
		$Body.modulate = dark
	# 상호작용 안내 라벨.
	_corpse_hint = Label.new()
	_corpse_hint.modulate = Color(1.0, 0.95, 0.5)
	_corpse_hint.position = Vector2(-24.0, -46.0)
	_corpse_hint.visible = false
	add_child(_corpse_hint)
	# 탐지/피격 영역 비활성(재추적·재피격 방지).
	if has_node("DetectionArea"):
		$DetectionArea.monitoring = false
	if has_node("HitBox"):
		$HitBox.monitoring = false
	queue_redraw() # 공격 범위 원 제거


## 시체: 플레이어가 가까이서 E → _LOOT_TIME 뒤 드롭. 멀어지면 취소.
func _dead_process(delta: float) -> void:
	if _corpse_hint == null:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	var near := _player != null and _player.global_position.distance_to(global_position) < _LOOT_RANGE
	if _loot_t >= 0.0: # 루팅 진행 중
		if not near: # 멀어지면 취소
			_loot_t = -1.0
		else:
			_loot_t -= delta
			_corpse_hint.text = "수거 중… %.1f" % maxf(0.0, _loot_t)
			if _loot_t <= 0.0:
				_do_loot()
				return
	else:
		var e_down := Input.is_physical_key_pressed(KEY_E)
		if e_down and not _e_was_down and near:
			_loot_t = _LOOT_TIME # 루팅 시작
		_e_was_down = e_down
	_corpse_hint.visible = near
	if near and _loot_t < 0.0:
		_corpse_hint.text = "E: 줍기"


## 드롭 실행: 확률 판정 후 수량만큼 인벤토리에 지급(도감 등록 포함), 시체 제거.
func _do_loot() -> void:
	if drop_item_id != "" and randf() < drop_chance:
		var amount := randi_range(mini(drop_min, drop_max), maxi(drop_min, drop_max))
		var s := get_tree().get_first_node_in_group("scavenge")
		if s and s.has_method("add_loot") and amount > 0:
			s.add_loot(drop_item_id, amount)
	queue_free()
