extends Area2D
## 총알 (PRD 3.3). 지정 방향으로 직진, 몬스터 명중 시 데미지 후 소멸.

@export var speed := 640.0
@export var damage := 25.0
@export var life := 1.4

var _dir := Vector2.RIGHT


func setup(dir: Vector2) -> void:
	_dir = dir


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(life).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	global_position += _dir * speed * delta


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("monster"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free()
