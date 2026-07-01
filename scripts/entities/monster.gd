extends CharacterBody2D
## 일반 몬스터 (PRD 3.1). 단순 1패턴 — 플레이어 추격 + 접촉 데미지.
## 처치 시 재료 드롭(Scavenge 씬에 통지). 지역 보스/스토리 보스는 별도 확장.

@export var speed := 95.0
@export var max_hp := 50.0
@export var contact_damage := 15.0

var hp := 50.0
var drop_item_id: String = ""

var _player: Node2D = null
var _touching := false
var _dmg_cd := 0.0


func _ready() -> void:
	hp = max_hp
	$HitBox.body_entered.connect(_on_hit_entered)
	$HitBox.body_exited.connect(_on_hit_exited)


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player:
		velocity = (_player.global_position - global_position).normalized() * speed
		move_and_slide()

	_dmg_cd = maxf(0.0, _dmg_cd - delta)
	if _touching and _dmg_cd <= 0.0 and _player and _player.has_method("take_hit"):
		_player.take_hit(contact_damage)
		_dmg_cd = 1.0


func take_damage(amount: float) -> void:
	hp -= amount
	if hp <= 0.0:
		_die()


func _die() -> void:
	var s := get_tree().get_first_node_in_group("scavenge")
	if s and s.has_method("on_monster_drop"):
		s.on_monster_drop(global_position, drop_item_id)
	queue_free()


func _on_hit_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_touching = true


func _on_hit_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_touching = false
