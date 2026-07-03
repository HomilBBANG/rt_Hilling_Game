extends Area2D
## 총알 (PRD 3.3). 지정 방향으로 직진, 몬스터 명중 시 데미지 후 소멸.

@export var speed := 640.0
@export var damage := 25.0
@export var life := 3.0            # 안전용 최대 수명(사거리에 도달 못해도 이만큼 지나면 소멸)
@export var max_range := 900.0     # 이 거리(px)만큼 날아가면 소멸 — 무기별 사거리

var _dir := Vector2.RIGHT
var _traveled := 0.0


func setup(dir: Vector2) -> void:
	_dir = dir


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(life).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	var step := speed * delta
	global_position += _dir * step
	_traveled += step
	if _traveled >= max_range: # 사거리 소진 → 소멸
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("monster"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free()
