extends Area2D
## 탄약 픽업 (PRD 3.1). 맵 내 고정 지점에 배치(랜덤 아님 — 동선 학습).
## 플레이어 접촉 시 탄약 획득.

@export var ammo := 6


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	WeaponManager.add_ammo(ammo)
	queue_free()
