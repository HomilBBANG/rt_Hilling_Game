extends Area2D
## 채집 자원 노드 (PRD 3.1). 플레이어 접촉 시 채집 → Scavenge 씬 인벤토리에 반영.

var item_id: String = "canned_food"
var amount: int = 1


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	var s := get_tree().get_first_node_in_group("scavenge")
	if s and s.has_method("add_loot"):
		s.add_loot(item_id, amount)
	queue_free()
