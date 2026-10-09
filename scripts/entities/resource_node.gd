extends Area2D
## 바닥 아이템 노드 (PRD 3.1). 플레이어가 가까이서 E 를 누르면 채집 → 인벤토리 반영.
## 무게 초과 시 담을 수 있는 만큼만 담기고 남은 수량은 노드로 유지된다.

## 아이템이 정해질 때마다 색을 바꾼다(스폰 쪽에서 add_child 후에 지정하므로 setter 로 처리).
var item_id: String = "canned_food":
	set(v):
		item_id = v
		_apply_color()
var amount: int = 1

## 쿠킹 재료가 아닌 아이템(고철 등)의 색.
const _OTHER_COLOR := Color(0.33, 0.35, 0.4) # 짙은 쇳빛 — 밝은 회색 통조림과 구분

var _player_near := false
var _e_was_down := false
var _hint: Label = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 16) # 월드 좌표 라벨: 카메라 줌 기준 크기 유지(전역 기본 24 미적용)
	_hint.modulate = Color(1.0, 0.95, 0.5)
	_hint.position = Vector2(-22.0, -40.0)
	_hint.visible = false
	add_child(_hint)
	_apply_color()


## 겉모습: 아이템 아이콘(items.xlsx icon)이 있으면 아이콘, 없으면 재료 색 사각형
## (색 = cooking.xlsx ingredients 의 color, 주방 임시 도형과 같은 색 / 재료가 아니면 짙은 쇳빛).
func _apply_color() -> void:
	var vis := get_node_or_null("Vis") as Polygon2D
	if vis == null:
		return
	var icon_path := ItemDB.icon_path(item_id)
	var icon := get_node_or_null("Icon") as Sprite2D
	if icon_path != "":
		if icon == null:
			icon = Sprite2D.new()
			icon.name = "Icon"
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.scale = Vector2(0.5, 0.5) # 64px 아이콘 → 사각형(22px)과 비슷한 크기
			add_child(icon)
		icon.texture = load(icon_path)
		icon.visible = true
		vis.visible = false
		return
	if icon:
		icon.visible = false
	vis.visible = true
	vis.color = RecipeDB.ingredient_color(item_id) if item_id in RecipeDB.ingredient_ids() else _OTHER_COLOR


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
