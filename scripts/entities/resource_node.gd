extends Area2D
## 바닥 아이템 노드 (PRD 3.1). 플레이어가 가까이서 E 를 누르면 채집 → 인벤토리 반영.
## 무게 초과 시 담을 수 있는 만큼만 담기고 남은 수량은 노드로 유지된다.

var item_id: String = "canned_food"
var amount: int = 1

var _player_near := false
var _e_was_down := false
var _hint: Label = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_hint = Label.new()
	_hint.modulate = Color(1.0, 0.95, 0.5)
	_hint.position = Vector2(-22.0, -40.0)
	_hint.visible = false
	add_child(_hint)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_near = true


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_near = false
		if _hint:
			_hint.visible = false


func _process(_delta: float) -> void:
	if not _player_near:
		_e_was_down = false
		return
	_hint.visible = true
	_hint.text = "E: %s×%d 줍기" % [ItemDB.display_name(item_id), amount]
	var e_down := Input.is_physical_key_pressed(KEY_E)
	if e_down and not _e_was_down:
		_pickup()
	_e_was_down = e_down


func _pickup() -> void:
	var s := get_tree().get_first_node_in_group("scavenge")
	if s == null or not s.has_method("add_loot"):
		queue_free()
		return
	var picked: int = s.add_loot(item_id, amount)
	if picked >= amount:
		queue_free()       # 전량 획득
	elif picked > 0:
		amount -= picked   # 일부만(무게 한도) → 남은 만큼 노드 유지
