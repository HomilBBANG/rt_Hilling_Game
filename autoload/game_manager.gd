extends Node
## 게임 흐름 중앙 제어 (PRD 2 핵심 루프).
## 하루 = 3스텝: 아침 준비 → 탐사 → 밤(쿠킹/급식 세션).
## 저장은 페이즈 시작 시점(아침/밤)에 자동 수행(PRD 3.7).

enum Step { MORNING_PREP, SCAVENGE, NIGHT }

signal step_changed(step: int)
signal day_changed(day: int)

var day: int = 1
var current_step: int = Step.MORNING_PREP

## 로비에서 지정하는 부팅 모드("new"/"load"). "" 면 main.gd 가 자동 판단(세이브 유무).
var boot_mode: String = ""

## 하루 동안 탐사로 모은 채집물 {item_id: count}. 매일 아침 초기화.
## world_state 에 저장되어 밤 재진입 시에도 유지됨(PRD 3.7).
var run_inventory: Dictionary = {}
## 캠프 창고(영속). 탐험에서 돌아오면 run_inventory(총알 제외)가 여기로 예치되고,
## 탐험 준비 화면에서 원하는 것만 run_inventory(가져갈 가방)로 다시 옮긴다.
var storage: Dictionary = {}
var current_region_id: String = "ruins"
## 토큰 재화(밤 급식 성공 보상). 추후 업그레이드 등에 사용.
var tokens: int = 0
## 퀵슬롯(숫자 1)에 등록된 회복 아이템 id. 탐험 중 1키로 즉시 사용.
var quick_slot: String = ""

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
	quick_slot = ""
	run_inventory.clear()
	storage.clear()
	# 매니저 상태를 기본값으로 초기화(이전 세션 잔존 방지).
	BelamiManager.from_dict({})
	WeaponManager.from_dict({})
	PlayerStats.from_dict({})
	NPCManager.from_dict({})
	CodexManager.from_dict({})
	RecipeDB.from_dict({})
	BelamiManager.refresh_preferences(_unlocked_recipe_ids())
	_goto_step(Step.MORNING_PREP)


func continue_game() -> void:
	var data := SaveManager.load_game()
	if data.is_empty():
		start_new_game()
		return
	day = int(data.get("day", 1))
	tokens = int(data.get("tokens", 0))
	quick_slot = String(data.get("quick_slot", ""))
	BelamiManager.from_dict(data.get("belami", {}))
	WeaponManager.from_dict(data.get("weapons", {}))
	PlayerStats.from_dict(data.get("player_stats", {}))
	NPCManager.from_dict(data.get("npcs", {}))
	CodexManager.from_dict(data.get("codex", {}))
	RecipeDB.from_dict(data.get("cooking", {})) # 레시피 레벨·숙련도
	var ws: Dictionary = data.get("world_state", {})
	run_inventory = {}
	var loaded_inv: Dictionary = ws.get("run_inventory", {})
	for k in loaded_inv.keys():
		run_inventory[String(k)] = int(loaded_inv[k]) # JSON 실수 → 정수 정규화
	storage = {}
	var loaded_store: Dictionary = ws.get("storage", {})
	for k in loaded_store.keys():
		storage[String(k)] = int(loaded_store[k])
	current_region_id = String(ws.get("region", "ruins"))
	BelamiManager.refresh_preferences(_unlocked_recipe_ids())
	# 로드된 누적 만족도 기준으로 해금 재점검(엑셀에서 임계값을 낮춘 경우도 반영).
	NPCManager.check_unlocks(BelamiManager.trust)
	# 이미 부활한 NPC들의 효과도 재적용(멱등).
	for revived_id in NPCManager.revived_ids:
		_apply_npc_effect(revived_id)
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


## 인벤토리(가방)에 아이템 추가. 탐사 중 채집 즉시 호출되어 인벤토리에 바로 반영된다.
func add_item(item_id: String, amount: int) -> void:
	if item_id == "" or amount == 0:
		return
	run_inventory[item_id] = int(run_inventory.get(item_id, 0)) + amount


## ── 무게(가방 적재량) ──────────────────────────────────

## 현재 인벤토리 총 무게.
func current_weight() -> float:
	var w := 0.0
	for id in run_inventory:
		w += int(run_inventory[id]) * ItemDB.weight(String(id))
	return w


## 최대 적재 무게(balance 엑셀 carry_max_weight).
func carry_max_weight() -> float:
	return Balance.get_float("carry_max_weight", 50.0)


## item_id 를 amount 개 담으려 할 때 무게 한도 내에서 실제로 담을 수 있는 개수.
func units_that_fit(item_id: String, amount: int) -> int:
	var w := ItemDB.weight(item_id)
	if w <= 0.0:
		return amount # 무게 0 아이템은 제한 없음
	var remain := carry_max_weight() - current_weight()
	var fit := int(floor(remain / w))
	return clampi(fit, 0, amount)


## ── 창고(storage) ──────────────────────────────────────

## 캠프 복귀 시: run_inventory 의 모든 아이템을 창고로 예치하고 가방을 비운다.
func deposit_all_to_storage() -> void:
	for id in run_inventory:
		storage[id] = int(storage.get(id, 0)) + int(run_inventory[id])
	run_inventory.clear()


## 가방 → 창고. amount 개(보유량 한도) 옮긴다.
func move_to_storage(item_id: String, amount: int) -> void:
	var have := int(run_inventory.get(item_id, 0))
	var n := clampi(amount, 0, have)
	if n <= 0:
		return
	remove_item(item_id, n)
	storage[item_id] = int(storage.get(item_id, 0)) + n


## 창고 → 가방. 무게 한도 내에서 담을 수 있는 만큼만 옮긴다. 실제 옮긴 수 반환.
func move_to_carry(item_id: String, amount: int) -> int:
	var have := int(storage.get(item_id, 0))
	var want := clampi(amount, 0, have)
	var n := units_that_fit(item_id, want)
	if n <= 0:
		return 0
	# 창고에서 차감
	var left := have - n
	if left > 0:
		storage[item_id] = left
	else:
		storage.erase(item_id)
	add_item(item_id, n)
	return n


## 인벤토리에서 아이템 제거(강제 귀환 패널티 등). 0 미만으로 내려가지 않는다.
func remove_item(item_id: String, amount: int) -> void:
	if not run_inventory.has(item_id):
		return
	var left := int(run_inventory[item_id]) - amount
	if left > 0:
		run_inventory[item_id] = left
	else:
		run_inventory.erase(item_id)


## ── 밤 요리 재료(가방 + 창고) ─────────────────────────

## 요리에 쓸 수 있는 재료 수 = 직전 탐사 가방 + 창고.
func cooking_stock(item_id: String) -> int:
	return int(run_inventory.get(item_id, 0)) + int(storage.get(item_id, 0))


## 요리 재료 소모: 가방(직전 탐사분)에서 먼저, 모자라면 창고에서 차감.
func consume_for_cooking(item_id: String, amount: int) -> void:
	var from_bag := mini(amount, int(run_inventory.get(item_id, 0)))
	remove_item(item_id, from_bag)
	var rest := amount - from_bag
	if rest <= 0:
		return
	var left := int(storage.get(item_id, 0)) - rest
	if left > 0:
		storage[item_id] = left
	else:
		storage.erase(item_id)


## 탐사 종료 시 Scavenge 씬이 호출(채집물은 이미 add_item 으로 반영됨). 밤으로 진행.
func finish_scavenge() -> void:
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
		deposit_all_to_storage() # 캠프 복귀 → 가방(총알 제외)을 창고로 예치
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
		"quick_slot": quick_slot,
		"belami": BelamiManager.to_dict(),
		"player": {}, # TODO: 외형 커스터마이징 상태
		"player_stats": PlayerStats.to_dict(),
		"weapons": WeaponManager.to_dict(),
		"world_state": {
			"run_inventory": run_inventory.duplicate(),
			"storage": storage.duplicate(),
			"region": current_region_id,
		},
		"npcs": NPCManager.to_dict(),
		"codex": CodexManager.to_dict(),
		"cooking": RecipeDB.to_dict(),
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
	for npc_id in NPCManager.check_unlocks(total):
		_apply_npc_effect(npc_id)
		# TODO: 부활 컷씬. 지금은 로그.
		print("[GameManager] NPC 부활: %s (%s) → %s" % [
			npc_id, NpcUnlockDB.display_name_of(npc_id), NpcUnlockDB.unlocks_of(npc_id)])


## NPC 부활 효과 적용(멱등). unlocks 필드(엑셀)로 매핑.
func _apply_npc_effect(npc_id: String) -> void:
	match NpcUnlockDB.unlocks_of(npc_id):
		"weapon_upgrade":
			WeaponManager.unlock_upgrades() # 하나 → 무기 강화 해금
		_:
			pass # TODO: serving/kitchen/new_region 등 나머지 NPC 효과


## 현재 해금된 레시피 id 목록(도감 획득 기반 해금 포함). 선호 음식 선정에 사용.
func _unlocked_recipe_ids() -> Array[String]:
	return RecipeDB.unlocked_ids()
