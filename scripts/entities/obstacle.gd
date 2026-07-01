extends StaticBody2D
## 탐험 장애물(플레이스홀더). collision_layer=8(벽)이라 플레이어·몬스터가 막힌다.
## 아트 확정 전까지 도형으로 표시 — radius/color 로 나무(초록·큼)/바위(회색·작음) 흉내.
## 추후 Sprite2D 로 교체하면 됨(충돌/스폰 로직은 그대로).

@export var radius := 24.0
@export var body_color := Color(0.28, 0.5, 0.3)

@onready var _vis: Polygon2D = $Vis
@onready var _col: CollisionShape2D = $Col


## add_child 전에 호출해 크기/색을 정한다.
func setup(r: float, col: Color) -> void:
	radius = r
	body_color = col


func _ready() -> void:
	var shape := CircleShape2D.new()
	shape.radius = radius
	_col.shape = shape

	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * float(i) / 16.0
		pts.append(Vector2(cos(a), sin(a)) * radius)
	_vis.polygon = pts
	_vis.color = body_color
