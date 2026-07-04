extends Control
## 캠프 (PRD 2 아침 준비 + 3.5 부활).
## 처음엔 주인공 + 벨라미 + 주변 시체들뿐. 누적 만족도로 NPC가 부활하면
## 다음날 캠프에서 '시체 → 멀쩡한 NPC' 부활 컷씬이 한 명씩 진행된다.
## '하나' 부활 후에는 캠프에서 무기 강화(하나의 대장간)를 토큰으로 진행(PRD 3.3).

const _PALETTE := [
	Color(0.9, 0.6, 0.3), Color(0.5, 0.82, 0.5),
	Color(0.6, 0.66, 0.95), Color(0.86, 0.5, 0.72), Color(0.75, 0.8, 0.4),
]
const _DEAD_TEX := preload("res://assets/npc/npc_a_dead.png") # 임시 시체 스프라이트
const _INV_SLOT := preload("res://scripts/ui/inv_slot.gd") # 드래그앤드롭 인벤토리 칸

var _figures := {} # npc_id -> {body:AnimatedSprite2D, label:Label, color:Color}
var _npc_frames: SpriteFrames = null # NPC 공용 프레임(dead=npc_a_dead, idle=npc_a_idle)

## 캠프 내 주인공 이동(WASD). 컷씬 중에는 정지. 속도는 PlayerStats.move_speed().
var _player_pos := Vector2.ZERO
var _pos_init := false

## 제작(무기 강화)은 carter 에게 다가가 E 를 눌러야 열린다.
const _INTERACT_RANGE := 90.0
var _carter_pos := Vector2.ZERO
var _carter_hint: Label = null
var _forge_open := false
var _e_was_down := false

## 능력치 화면(Tab 토글).
var _stats_open := false
var _tab_was_down := false

@onready var _title: Label = $Body/VBox/Header
@onready var _ground: Control = $Body/VBox/Ground
@onready var _campfire: ColorRect = $Body/VBox/Ground/Campfire
@onready var _belami: AnimatedSprite2D = $Body/VBox/Ground/Belami # god 캐릭터
@onready var _player_fig: AnimatedSprite2D = $Body/VBox/Ground/Player
@onready var _forge: VBoxContainer = $Body/VBox/Footer/UpgradePanel
@onready var _tokens_label: Label = $Body/VBox/Footer/UpgradePanel/TokensLabel
@onready var _ranged_btn: Button = $Body/VBox/Footer/UpgradePanel/RangedButton
@onready var _melee_btn: Button = $Body/VBox/Footer/UpgradePanel/MeleeButton
@onready var _craft_box: VBoxContainer = $Body/VBox/Footer/UpgradePanel/CraftBox
@onready var _go_button: Button = $Body/VBox/Footer/GoButton
@onready var _overlay: Control = $Cutscene
@onready var _overlay_text: Label = $Cutscene/Center/Text
@onready var _stats_screen: Control = $StatsScreen
@onready var _stats_tokens: Label = $StatsScreen/Center/Panel/Margin/VBox/Tokens
@onready var _hp_label: Label = $StatsScreen/Center/Panel/Margin/VBox/HpLabel
@onready var _hp_btn: Button = $StatsScreen/Center/Panel/Margin/VBox/HpButton
@onready var _speed_label: Label = $StatsScreen/Center/Panel/Margin/VBox/SpeedLabel
@onready var _speed_btn: Button = $StatsScreen/Center/Panel/Margin/VBox/SpeedButton
@onready var _explore_prep: Control = $ExplorePrep
@onready var _carry_grid: GridContainer = $ExplorePrep/Center/Panel/Margin/VBox/Columns/CarryVB/CarryScroll/CarryGrid
@onready var _storage_grid: GridContainer = $ExplorePrep/Center/Panel/Margin/VBox/Columns/StorageVB/StorageScroll/StorageGrid
@onready var _carry_title: Label = $ExplorePrep/Center/Panel/Margin/VBox/Columns/CarryVB/CarryTitle
@onready var _explore_start_btn: Button = $ExplorePrep/Center/Panel/Margin/VBox/StartButton


func _ready() -> void:
	_title.text = "캠프 — Day %d" % GameManager.day
	_go_button.pressed.connect(_open_explore_prep) # 탐사 나가기 → 탐험 준비 화면
	_explore_start_btn.pressed.connect(GameManager.advance) # 탐험 시작 → 탐사 진입
	_explore_prep.visible = false
	_ranged_btn.pressed.connect(_on_upgrade.bind("ranged"))
	_melee_btn.pressed.connect(_on_upgrade.bind("melee"))
	_hp_btn.pressed.connect(_on_stat_upgrade.bind("hp"))
	_speed_btn.pressed.connect(_on_stat_upgrade.bind("speed"))
	_stats_screen.visible = false
	_overlay.visible = false
	# 레이아웃 확정 후 배치.
	await get_tree().process_frame
	await get_tree().process_frame
	_build_figures()
	_refresh_forge()
	await _play_cutscenes()


func _process(delta: float) -> void:
	if _overlay.visible or _explore_prep.visible: # 컷씬·탐험 준비 중엔 이동/입력 정지
		return
	_handle_stats_toggle()
	if not _pos_init or _stats_open: # 능력치 화면 중엔 이동 정지
		return
	var dir := _input_dir()
	_apply_move(dir, delta)
	if dir != Vector2.ZERO:
		if _player_fig.animation != "run":
			_player_fig.play("run")
		_player_fig.flip_h = dir.x > 0
	elif _player_fig.animation != "idle":
		_player_fig.play("idle")

	_update_carter_interaction()


## carter 근처면 안내 표시 + E(엣지)로 제작 패널 토글. 멀어지면 자동으로 닫힘.
func _update_carter_interaction() -> void:
	if _carter_hint == null:
		return
	var near := _player_pos.distance_to(_carter_pos) < _INTERACT_RANGE
	_carter_hint.visible = near
	if near:
		_carter_hint.text = "E: 제작" if WeaponManager.upgrade_unlocked else "제작 (아직 잠김)"

	var e_down := Input.is_physical_key_pressed(KEY_E)
	if e_down and not _e_was_down and near and WeaponManager.upgrade_unlocked:
		_forge_open = not _forge_open
		_refresh_forge()
	_e_was_down = e_down

	if _forge_open and not near: # 멀어지면 닫기
		_forge_open = false
		_refresh_forge()


# ── 능력치 화면 (Tab) ──────────────────────────────────

## Tab(엣지)로 능력치 화면을 연다/닫는다.
func _handle_stats_toggle() -> void:
	var down := Input.is_physical_key_pressed(KEY_TAB)
	if down and not _tab_was_down:
		_stats_open = not _stats_open
		_stats_screen.visible = _stats_open
		if _stats_open:
			_refresh_stats()
	_tab_was_down = down


func _refresh_stats() -> void:
	_stats_tokens.text = "보유 토큰: %d" % GameManager.tokens
	_hp_label.text = "체력  %d  (Lv%d)" % [int(PlayerStats.max_hp()), PlayerStats.level_of("hp")]
	_speed_label.text = "이동속도  %d  (Lv%d)" % [int(PlayerStats.move_speed()), PlayerStats.level_of("speed")]
	_hp_btn.text = _stat_btn_text("hp")
	_hp_btn.disabled = not PlayerStats.can_upgrade("hp")
	_speed_btn.text = _stat_btn_text("speed")
	_speed_btn.disabled = not PlayerStats.can_upgrade("speed")


func _stat_btn_text(stat: String) -> String:
	if PlayerStats.is_max(stat):
		return "최대 레벨 (Lv%d)" % PlayerStats.level_of(stat)
	return "강화 → %d  (%d토큰)" % [int(PlayerStats.next_value(stat)), PlayerStats.upgrade_cost(stat)]


func _on_stat_upgrade(stat: String) -> void:
	if PlayerStats.try_upgrade(stat):
		_refresh_stats()
		_refresh_forge() # 토큰이 줄었으니 제작 패널도 갱신(열려 있으면)


# ── 탐험 준비 (가방 ↔ 창고 드래그앤드롭) ────────────────

func _open_explore_prep() -> void:
	_rebuild_prep_grids()
	_explore_prep.visible = true


func _rebuild_prep_grids() -> void:
	_fill_inv_grid(_carry_grid, GameManager.run_inventory, "carry")
	_fill_inv_grid(_storage_grid, GameManager.storage, "storage")
	_carry_title.text = "가져갈 가방  (무게 %0.1f/%0.0f)" % [GameManager.current_weight(), GameManager.carry_max_weight()]


## 인벤토리 사전을 스택 단위 칸으로 채운다(빈 칸도 드롭 대상).
func _fill_inv_grid(grid: GridContainer, inv: Dictionary, side: String) -> void:
	for c in grid.get_children():
		c.queue_free()
	var stacks: Array = []
	for id in inv:
		var cnt := int(inv[id])
		var per := maxi(1, ItemDB.max_stack(String(id)))
		while cnt > 0:
			var here := mini(cnt, per)
			stacks.append({"id": String(id), "count": here})
			cnt -= here
	var cols := maxi(1, grid.columns)
	var slot_count := maxi(stacks.size(), 12) # 빈 칸도 최소 12개(드롭 영역)
	if slot_count % cols != 0:
		slot_count += cols - (slot_count % cols)
	for i in slot_count:
		var slot: Panel = _INV_SLOT.new()
		slot.custom_minimum_size = Vector2(68, 68)
		slot.side = side
		slot.on_drop = _on_item_dropped
		if i < stacks.size():
			slot.item_id = String(stacks[i]["id"])
			slot.count = int(stacks[i]["count"])
			var lbl := Label.new()
			lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE # 드래그는 칸(Panel)이 받도록
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.text = "%s\n×%d" % [ItemDB.display_name(slot.item_id), slot.count]
			slot.add_child(lbl)
		else:
			slot.modulate = Color(1, 1, 1, 0.3)
		grid.add_child(slot)


## 칸에서 반대편 칸으로 드롭 → 아이템 이동(창고↔가방, 가방은 무게 한도).
func _on_item_dropped(data: Dictionary, to_side: String) -> void:
	var id := String(data.get("item_id", ""))
	var cnt := int(data.get("count", 0))
	if id == "" or cnt <= 0:
		return
	if to_side == "storage":
		GameManager.move_to_storage(id, cnt)
	else:
		GameManager.move_to_carry(id, cnt) # 무게 한도 내에서만
	_rebuild_prep_grids()


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
	# 탐사·요리와 동일 속도(PlayerStats). 동적으로 읽어 Tab 업그레이드가 즉시 반영됨.
	_player_pos += dir.normalized() * PlayerStats.move_speed() * delta
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
	# 플레이어·god 위치는 balance 엑셀(camp_player_x/y, camp_god_x/y, 비율 0~1)로 조정 가능.
	_player_pos = _camp_pos("camp_player", g, center + Vector2(-radius - 40.0, 8.0))
	_player_fig.sprite_frames = PlayerFrames.build("idle_hand", "run_hand")
	_player_fig.play("idle")
	_player_fig.flip_h = true # 스폰 시 오른쪽을 바라봄(이동 로직과 동일 규약: flip_h=true=우향)
	_player_fig.position = _player_pos
	_pos_init = true
	_belami.sprite_frames = GodFrames.build()
	_belami.play("idle")
	_belami.position = _camp_pos("camp_god", g, center + Vector2(-radius - 40.0, -46.0))

	var entries := NpcUnlockDB.entries
	var n := entries.size()
	for i in n:
		var npc_id := String(entries[i].get("npc_id", ""))
		if npc_id == "":
			continue
		var disp := String(entries[i].get("display_name", npc_id))
		var color: Color = _PALETTE[i % _PALETTE.size()]
		# 엑셀 x,y(바닥 비율 0~1)가 있으면 개별 배치, 없으면 원형 자동 배치.
		var pos: Vector2
		if entries[i].has("x") and entries[i].has("y"):
			pos = Vector2(float(entries[i]["x"]) * g.x, float(entries[i]["y"]) * g.y)
		else:
			var ang := TAU * float(i) / maxf(1.0, float(n)) - PI * 0.5
			pos = center + Vector2(cos(ang), sin(ang)) * radius
		_figures[npc_id] = _make_figure(npc_id, disp, color, pos)
		# 무기 제작을 해금하는 NPC(=carter)를 제작 상호작용 대상으로 지정.
		if String(entries[i].get("unlocks", "")) == "weapon_upgrade":
			_carter_pos = pos

	_build_carter_hint()


## 제작(무기강화) NPC 위에 표시할 상호작용 안내 라벨.
func _build_carter_hint() -> void:
	_carter_hint = Label.new()
	_carter_hint.text = "E: 제작"
	_carter_hint.modulate = Color(1.0, 0.95, 0.5)
	_carter_hint.position = _carter_pos + Vector2(-24.0, -60.0)
	_carter_hint.visible = false
	_ground.add_child(_carter_hint)


## balance 엑셀에 <prefix>_x/_y(바닥 비율 0~1)가 있으면 그 위치, 없으면 fallback.
func _camp_pos(prefix: String, g: Vector2, fallback: Vector2) -> Vector2:
	if Balance.has(prefix + "_x") and Balance.has(prefix + "_y"):
		return Vector2(Balance.get_float(prefix + "_x", 0.5) * g.x, Balance.get_float(prefix + "_y", 0.5) * g.y)
	return fallback


func _make_figure(npc_id: String, disp: String, color: Color, pos: Vector2) -> Dictionary:
	var revived := NPCManager.is_revived(npc_id)
	# 컷씬 대기 중이면(부활은 했지만 아직 안 보여줌) 시체 상태로 시작해 연출로 전환.
	var shown := revived and npc_id not in NPCManager.pending_revivals()

	# 시체=npc_a_dead / 부활=npc_a_idle(애니). 상태는 재생 애니 + 틴트로 구분.
	var body := AnimatedSprite2D.new()
	body.sprite_frames = _npc_sprite_frames()
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.scale = Vector2(3, 3) # 플레이어(32px @ scale 3)와 동일 크기
	body.modulate = Color(1, 1, 1) # 원본 색 그대로(틴트 없음)
	body.position = pos # AnimatedSprite2D 는 중심 기준
	body.play("idle" if shown else "dead")
	_ground.add_child(body)

	var label := Label.new()
	label.text = disp if shown else "???"
	label.modulate = Color(1, 1, 1) if shown else Color(0.6, 0.6, 0.6)
	label.position = pos + Vector2(-16.0, 54.0) # 스프라이트(96px) 아래에 이름
	_ground.add_child(label)

	return {"body": body, "label": label, "color": color, "name": disp}


## NPC 공용 프레임: "dead"(npc_a_dead 1장) + "idle"(npc_a_idle N장). 한 번만 만들어 재사용.
func _npc_sprite_frames() -> SpriteFrames:
	if _npc_frames != null:
		return _npc_frames
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation("dead")
	sf.set_animation_loop("dead", false)
	sf.add_frame("dead", _DEAD_TEX)
	sf.add_animation("idle")
	sf.set_animation_loop("idle", true)
	sf.set_animation_speed("idle", 2.5)
	var i := 0
	while ResourceLoader.exists("res://assets/npc/npc_a_idle_%d.png" % i):
		sf.add_frame("idle", load("res://assets/npc/npc_a_idle_%d.png" % i))
		i += 1
	if sf.get_frame_count("idle") == 0: # 폴백: idle 프레임 없으면 dead 이미지로
		sf.add_frame("idle", _DEAD_TEX)
	_npc_frames = sf
	return _npc_frames


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
	var body: AnimatedSprite2D = fig["body"]
	var label: Label = fig["label"]
	body.play("idle") # 시체(dead) → 살아있는 idle 애니메이션으로 전환
	var t := create_tween()
	t.tween_property(body, "position", body.position - Vector2(0, 6), 1.0) # 살짝 일어서는 연출
	await t.finished
	label.text = String(fig["name"])
	label.modulate = Color(1, 1, 1)
	_overlay_text.text = "%s(이)가 되살아났다!" % String(fig["name"])
	await get_tree().create_timer(0.8).timeout


# ── 하나의 대장간 (무기 강화) ──────────────────────────

func _refresh_forge() -> void:
	# carter 에게 다가가 E 로 열었을 때만 표시(해금 전이면 항상 숨김).
	_forge.visible = _forge_open and WeaponManager.upgrade_unlocked
	if not _forge.visible:
		return
	_tokens_label.text = "보유 토큰: %d" % GameManager.tokens
	_ranged_btn.text = _btn_text("ranged", "총")
	_ranged_btn.disabled = not WeaponManager.can_upgrade("ranged")
	_melee_btn.text = _btn_text("melee", "칼")
	_melee_btn.disabled = not WeaponManager.can_upgrade("melee")
	_rebuild_craft_buttons()


## 제작 가능한 무기 버튼을 다시 구성(장착 무기 종류 데미지 표시 + 비용).
func _rebuild_craft_buttons() -> void:
	for c in _craft_box.get_children():
		c.queue_free()
	for raw_id in WeaponManager.craftable_ids():
		var id := String(raw_id)
		var w: Dictionary = WeaponDB.get_weapon(id)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(320, 34)
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = "제작: %s (%s, 공격력 %d) — %d토큰" % [
			WeaponDB.display_name(id), _kind_label(String(w.get("kind", ""))),
			int(WeaponDB.base_damage(id)), WeaponManager.weapon_craft_cost(id)]
		btn.disabled = not WeaponManager.can_craft(id)
		btn.pressed.connect(_on_craft.bind(id))
		_craft_box.add_child(btn)


func _kind_label(kind: String) -> String:
	return "원거리" if kind == "ranged" else "근접"


func _on_craft(id: String) -> void:
	if WeaponManager.craft_weapon(id):
		_refresh_forge() # 토큰·보유 목록 갱신


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
