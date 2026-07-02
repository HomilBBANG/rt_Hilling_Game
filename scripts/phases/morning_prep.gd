extends Control
## 캠프 (PRD 2 아침 준비 + 3.5 부활).
## 처음엔 주인공 + 벨라미 + 주변 시체들뿐. 누적 만족도로 NPC가 부활하면
## 다음날 캠프에서 '시체 → 멀쩡한 NPC' 부활 컷씬이 한 명씩 진행된다.
## '하나' 부활 후에는 캠프에서 무기 강화(하나의 대장간)를 토큰으로 진행(PRD 3.3).

const _PALETTE := [
	Color(0.9, 0.6, 0.3), Color(0.5, 0.82, 0.5),
	Color(0.6, 0.66, 0.95), Color(0.86, 0.5, 0.72), Color(0.75, 0.8, 0.4),
]
const _CORPSE_COLOR := Color(0.32, 0.32, 0.35)

var _figures := {} # npc_id -> {body:ColorRect, label:Label, color:Color}

## 캠프 내 주인공 이동(WASD). 컷씬 중에는 정지.
@export var move_speed := 260.0
var _player_pos := Vector2.ZERO
var _pos_init := false

@onready var _title: Label = $Body/VBox/Header
@onready var _ground: Control = $Body/VBox/Ground
@onready var _campfire: ColorRect = $Body/VBox/Ground/Campfire
@onready var _belami: Label = $Body/VBox/Ground/Belami
@onready var _player_fig: AnimatedSprite2D = $Body/VBox/Ground/Player
@onready var _forge: VBoxContainer = $Body/VBox/Footer/UpgradePanel
@onready var _tokens_label: Label = $Body/VBox/Footer/UpgradePanel/TokensLabel
@onready var _ranged_btn: Button = $Body/VBox/Footer/UpgradePanel/RangedButton
@onready var _melee_btn: Button = $Body/VBox/Footer/UpgradePanel/MeleeButton
@onready var _go_button: Button = $Body/VBox/Footer/GoButton
@onready var _overlay: Control = $Cutscene
@onready var _overlay_text: Label = $Cutscene/Center/Text


func _ready() -> void:
	_title.text = "캠프 — Day %d" % GameManager.day
	_go_button.pressed.connect(GameManager.advance)
	_ranged_btn.pressed.connect(_on_upgrade.bind("ranged"))
	_melee_btn.pressed.connect(_on_upgrade.bind("melee"))
	_overlay.visible = false
	# 레이아웃 확정 후 배치.
	await get_tree().process_frame
	await get_tree().process_frame
	_build_figures()
	_refresh_forge()
	await _play_cutscenes()


func _process(delta: float) -> void:
	if not _pos_init or _overlay.visible: # 컷씬 중엔 이동 정지
		return
	var dir := _input_dir()
	_apply_move(dir, delta)
	if dir != Vector2.ZERO:
		if _player_fig.animation != "run":
			_player_fig.play("run")
		_player_fig.flip_h = dir.x > 0
	elif _player_fig.animation != "idle":
		_player_fig.play("idle")


func _input_dir() -> Vector2:
	var d := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		d.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		d.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		d.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		d.y += 1.0
	return d


func _apply_move(dir: Vector2, delta: float) -> void:
	if dir == Vector2.ZERO:
		return
	_player_pos += dir.normalized() * move_speed * delta
	var g := _ground.size
	var h := 48.0
	_player_pos.x = clampf(_player_pos.x, h, g.x - h)
	_player_pos.y = clampf(_player_pos.y, h, g.y - h)
	_player_fig.position = _player_pos


# ── 캠프 배치 ──────────────────────────────────────────

func _build_figures() -> void:
	var g := _ground.size
	var center := Vector2(g.x * 0.5, g.y * 0.52)
	var radius := minf(g.x, g.y) * 0.34

	_campfire.position = center - _campfire.size * 0.5
	_player_pos = center + Vector2(-radius - 40.0, 8.0)
	_player_fig.sprite_frames = PlayerFrames.build()
	_player_fig.play("idle")
	_player_fig.position = _player_pos
	_pos_init = true
	_belami.position = center + Vector2(-radius - 40.0, -46.0) - _belami.size * 0.5

	var entries := NpcUnlockDB.entries
	var n := entries.size()
	for i in n:
		var npc_id := String(entries[i].get("npc_id", ""))
		if npc_id == "":
			continue
		var disp := String(entries[i].get("display_name", npc_id))
		var color: Color = _PALETTE[i % _PALETTE.size()]
		var ang := TAU * float(i) / maxf(1.0, float(n)) - PI * 0.5
		var pos := center + Vector2(cos(ang), sin(ang)) * radius
		_figures[npc_id] = _make_figure(npc_id, disp, color, pos)


func _make_figure(npc_id: String, disp: String, color: Color, pos: Vector2) -> Dictionary:
	var revived := NPCManager.is_revived(npc_id)
	# 컷씬 대기 중이면(부활은 했지만 아직 안 보여줌) 시체 상태로 시작해 연출로 전환.
	var shown := revived and npc_id not in NPCManager.pending_revivals()

	var body := ColorRect.new()
	body.size = Vector2(26, 30)
	body.pivot_offset = body.size * 0.5
	body.color = color if shown else _CORPSE_COLOR
	body.rotation = 0.0 if shown else PI * 0.5 # 시체 = 누워 있음
	body.position = pos - body.size * 0.5
	_ground.add_child(body)

	var label := Label.new()
	label.text = disp if shown else "???"
	label.modulate = Color(1, 1, 1) if shown else Color(0.6, 0.6, 0.6)
	label.position = pos + Vector2(-16.0, 22.0)
	_ground.add_child(label)

	return {"body": body, "label": label, "color": color, "name": disp}


# ── 부활 컷씬 ──────────────────────────────────────────

func _play_cutscenes() -> void:
	var pending := NPCManager.pending_revivals()
	if pending.is_empty():
		return
	_go_button.disabled = true
	_overlay.visible = true
	for npc_id in pending:
		await _play_one(npc_id)
		NPCManager.mark_shown(npc_id)
	_overlay.visible = false
	_go_button.disabled = false
	_refresh_forge() # 하나가 방금 부활했으면 대장간 노출


func _play_one(npc_id: String) -> void:
	var fig: Dictionary = _figures.get(npc_id, {})
	_overlay_text.text = "%s의 몸이 천천히 일어선다…" % String(fig.get("name", npc_id))
	await get_tree().create_timer(0.6).timeout
	if fig.is_empty():
		return
	var body: ColorRect = fig["body"]
	var label: Label = fig["label"]
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(body, "rotation", 0.0, 1.0)
	t.tween_property(body, "color", fig["color"], 1.0)
	t.tween_property(body, "position", body.position - Vector2(0, 6), 1.0)
	await t.finished
	label.text = String(fig["name"])
	label.modulate = Color(1, 1, 1)
	_overlay_text.text = "%s(이)가 되살아났다!" % String(fig["name"])
	await get_tree().create_timer(0.8).timeout


# ── 하나의 대장간 (무기 강화) ──────────────────────────

func _refresh_forge() -> void:
	_forge.visible = WeaponManager.upgrade_unlocked
	if not _forge.visible:
		return
	_tokens_label.text = "보유 토큰: %d" % GameManager.tokens
	_ranged_btn.text = _btn_text("ranged", "총")
	_ranged_btn.disabled = not WeaponManager.can_upgrade("ranged")
	_melee_btn.text = _btn_text("melee", "칼")
	_melee_btn.disabled = not WeaponManager.can_upgrade("melee")


func _btn_text(kind: String, label: String) -> String:
	var lv := WeaponManager.level_of(kind)
	if WeaponManager.is_max(kind):
		return "%s Lv%d — 최대 강화 (공격력 %d)" % [label, lv, int(WeaponManager.current_damage(kind))]
	return "%s Lv%d 강화 → 공격력 %d→%d  (%d토큰)" % [
		label, lv, int(WeaponManager.current_damage(kind)), int(WeaponManager.next_damage(kind)),
		WeaponManager.upgrade_cost(kind),
	]


func _on_upgrade(kind: String) -> void:
	if WeaponManager.try_upgrade(kind):
		_refresh_forge()
