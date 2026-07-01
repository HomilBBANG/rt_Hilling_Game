extends Node
## 게임 흐름 중앙 제어 (PRD 2 핵심 루프).
## 하루 = 3스텝: 아침 준비 → 탐사 → 밤(쿠킹/급식 세션).
## 저장은 페이즈 시작 시점(아침/밤)에 자동 수행(PRD 3.7).

enum Step { MORNING_PREP, SCAVENGE, NIGHT }

signal step_changed(step: int)
signal day_changed(day: int)

var day: int = 1
var current_step: int = Step.MORNING_PREP

## 하루 동안 탐사로 모은 채집물 {item_id: count}. 매일 아침 초기화.
## world_state 에 저장되어 밤 재진입 시에도 유지됨(PRD 3.7).
var run_inventory: Dictionary = {}
var current_region_id: String = "ruins"
## 토큰 재화(밤 급식 성공 보상). 추후 업그레이드 등에 사용.
var tokens: int = 0

const _SCENES := {
	Step.MORNING_PREP: "res://scenes/phases/morning_prep.tscn",
	Step.SCAVENGE: "res://scenes/phases/scavenge.tscn",
	Step.NIGHT: "res://scenes/phases/night_session.tscn",
}

var _phase_container: Node = null


func _ready() -> void:
	# 누적 만족도 변화 → 해금 표(NpcUnlockDB) 기준으로 NPC 부활 처리.
	BelamiManager.trust_changed.connect(_on_total_satisfaction_changed)


func register_phase_container(node: Node) -> void:
	_phase_container = node


func start_new_game() -> void:
	day = 1
	tokens = 0
	run_inventory.clear()
	# 매니저 상태를 기본값으로 초기화(이전 세션 잔존 방지).
	BelamiManager.from_dict({})
	WeaponManager.from_dict({})
	NPCManager.from_dict({})
	CodexManager.from_dict({})
	BelamiManager.refresh_preferences(_unlocked_recipe_ids())
	_goto_step(Step.MORNING_PREP)


func continue_game() -> void:
	var data := SaveManager.load_game()
	if data.is_empty():
		start_new_game()
		return
	day = int(data.get("day", 1))
	tokens = int(data.get("tokens", 0))
	BelamiManager.from_dict(data.get("belami", {}))
	WeaponManager.from_dict(data.get("weapons", {}))
	NPCManager.from_dict(data.get("npcs", {}))
	CodexManager.from_dict(data.get("codex", {}))
	var ws: Dictionary = data.get("world_state", {})
	run_inventory = {}
	var loaded_inv: Dictionary = ws.get("run_inventory", {})
	for k in loaded_inv.keys():
		run_inventory[String(k)] = int(loaded_inv[k]) # JSON 실수 → 정수 정규화
	current_region_id = String(ws.get("region", "ruins"))
	BelamiManager.refresh_preferences(_unlocked_recipe_ids())
	# 로드된 누적 만족도 기준으로 해금 재점검(엑셀에서 임계값을 낮춘 경우도 반영).
	NPCManager.check_unlocks(BelamiManager.trust)
	var phase := String(data.get("phase", "morning"))
	_goto_step(Step.MORNING_PREP if phase == "morning" else Step.NIGHT)


## 현재 스텝에서 다음 스텝으로 진행.
func advance() -> void:
	match current_step:
		Step.MORNING_PREP:
			_goto_step(Step.SCAVENGE)
		Step.SCAVENGE:
			_goto_step(Step.NIGHT) # 귀환 → 밤 세션 시작
		Step.NIGHT:
			_end_day()


## 탐사 종료 시 Scavenge 씬이 호출. 채집물을 합산하고 밤으로 진행.
func finish_scavenge(loot: Dictionary) -> void:
	for k in loot.keys():
		run_inventory[k] = int(run_inventory.get(k, 0)) + int(loot[k])
	advance()


func add_tokens(amount: int) -> void:
	tokens += amount


func _end_day() -> void:
	day += 1
	day_changed.emit(day)
	# 새 아침: 선호 음식 갱신(PRD 3.4 — 매일 갱신)
	BelamiManager.refresh_preferences(_unlocked_recipe_ids())
	_goto_step(Step.MORNING_PREP)


func _goto_step(step: int) -> void:
	current_step = step
	# 페이즈 시작 시점 자동 저장 (PRD 3.7: 아침 시작 / 밤 시작 두 지점)
	if step == Step.MORNING_PREP:
		run_inventory.clear() # 새 아침 → 지난날 채집물 정리
		_autosave("morning")
	elif step == Step.NIGHT:
		_autosave("night")
	_load_phase_scene(step)
	step_changed.emit(step)


func _autosave(phase: String) -> void:
	var data := {
		"day": day,
		"phase": phase,
		"tokens": tokens,
		"belami": BelamiManager.to_dict(),
		"player": {}, # TODO: 외형 커스터마이징 상태
		"weapons": WeaponManager.to_dict(),
		"world_state": {
			"run_inventory": run_inventory.duplicate(),
			"region": current_region_id,
		},
		"npcs": NPCManager.to_dict(),
		"codex": CodexManager.to_dict(),
	}
	SaveManager.save_game(data)


func _load_phase_scene(step: int) -> void:
	if _phase_container == null:
		push_error("GameManager: PhaseContainer 가 등록되지 않았습니다.")
		return
	for child in _phase_container.get_children():
		child.queue_free()
	var packed := load(_SCENES[step]) as PackedScene
	if packed == null:
		push_error("GameManager: 페이즈 씬 로드 실패 — %s" % _SCENES[step])
		return
	_phase_container.add_child(packed.instantiate())


func _on_total_satisfaction_changed(total: float) -> void:
	var newly := NPCManager.check_unlocks(total)
	for npc_id in newly:
		# TODO: 부활 컷씬 + 콘텐츠 unlock. 지금은 로그만.
		print("[GameManager] NPC 해금(부활): ", npc_id, " (", NpcUnlockDB.display_name_of(npc_id), ")")


## 현재 해금된 레시피 id 목록(도감 획득 기반 해금 포함). 선호 음식 선정에 사용.
func _unlocked_recipe_ids() -> Array[String]:
	return RecipeDB.unlocked_ids()
