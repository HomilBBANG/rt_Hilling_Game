@tool
class_name SpawnPoint
extends Marker2D
## 탐사 맵의 고정 스폰 지점. scavenge.tscn 의 MonsterSpawns / ItemSpawns 아래에 두고
## Godot 에디터에서 드래그해 위치를 정한다(늘리려면 복제 Ctrl+D, 줄이려면 삭제).
##   kind = "monster" : spawn_id = monsters.xlsx 의 몬스터 id (보스 포함, 예: monster_a, ruins_boss)
##   kind = "item"    : spawn_id = items.xlsx 의 아이템 id(채집 노드), amount = 수량
## 에디터에서만 id 를 글자로 표시(게임 화면에는 안 보임).

@export_enum("item", "monster") var kind: String = "item":
	set(v):
		kind = v
		queue_redraw()
@export var spawn_id: String = "potato":
	set(v):
		spawn_id = v
		queue_redraw()
@export_range(1, 99) var amount: int = 1:
	set(v):
		amount = v
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var col := Color(1.0, 0.35, 0.3) if kind == "monster" else Color(0.45, 0.95, 0.5)
	draw_circle(Vector2.ZERO, 14.0, Color(col, 0.35))
	draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 24, col, 2.0)
	var label := spawn_id if kind == "monster" or amount <= 1 else "%s ×%d" % [spawn_id, amount]
	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(18.0, 6.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color.BLACK)
	draw_string(font, Vector2(18.0, 6.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
