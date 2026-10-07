# god — 코드 구조 & 아키텍처

Godot 4.7 / GDScript. 수치·콘텐츠는 엑셀(→json) 데이터 드리븐, 화면은 페이즈 씬 단위로 교체.
기획 내용은 `docs/GDD.md`, 작업 방법·검증은 `docs/HANDOFF.md`.

## 폴더 구조

```
hilling-game/
├── project.godot            # autoload 등록, 시작 씬 = scenes/ui/lobby.tscn, 1280×720
├── autoload/                # 싱글톤(아래 표)
├── data/                    # *.xlsx(기획자 편집) + *.json(변환 결과, 게임이 읽음)
├── tools/convert_*.py       # xlsx → json 변환기(openpyxl). DataImport 가 실행 시 자동 호출
├── scenes/
│   ├── main.tscn            # 루트: PhaseContainer(페이즈 씬 자리) + UILayer(CanvasLayer 10, 전역 HUD)
│   ├── ui/                  # lobby.tscn, hud.tscn(일차·페이즈 표시 + 인벤토리 오버레이)
│   ├── phases/              # morning_prep(캠프) / scavenge(탐사) / night_session(밤 쿠킹)
│   ├── entities/            # player, monster, bullet, pickups(ammo, resource_node), props(tree)
│   └── minigames/cooking/   # cook_station.tscn (밤 조리 기구 1개)
├── scripts/                 # 씬 스크립트(scenes 구조 미러) + 공용 빌더
│   ├── player_frames.gd     # 플레이어 SpriteFrames 빌더(idle/run, idle_hand/run_hand)
│   ├── god_frames.gd        # god idle 프레임 빌더
│   ├── phases/ entities/ ui/
│   └── minigames/           # cook_station.gd(CookStation), kitchen_item.gd(KitchenItem)
├── resources/
│   ├── data/                # Resource 클래스(item_data, region_data, npc_data, weapon_data)
│   ├── items/               # 아이템 .tres(도감 카테고리 판정용)
│   └── regions/ruins.tres   # 탐사 지역(음식/재료 풀, 보스 id, 탄약 지점 수 …)
├── assets/                  # characters, monsters, npc, items, backgrounds, environment …
└── docs/                    # GDD.md, HANDOFF.md, ARCHITECTURE.md
```

## Autoload (project.godot 등록 순서)

| 이름 | 파일 | 역할 |
|---|---|---|
| DataImport | data_import.gd | **가장 먼저** 실행. 에디터/개발 실행 시 `tools/convert_*.py` 전부 실행해 json 갱신 |
| Config | config.gd | 게이지 노출 등 설정 |
| Balance | balance.gd | `balance.json` 키-값 조회(`get_float`) |
| SaveManager | save_manager.gd | `user://savegame.json` 읽기/쓰기/삭제(슬롯 1개) |
| BelamiManager | belami_manager.gd | god 누적 만족도(trust, 비노출)·불만도·선호 음식(옛 이름 유지) |
| NpcUnlockDB | npc_unlock_db.gd | `npc_unlocks.json` (임계값·해금 기능·캠프 위치) |
| NPCManager | npc_manager.gd | 부활한 NPC, 밤 배치 슬롯(kitchen/serving) |
| WeaponDB | weapon_db.gd | `weapons.json` (스프라이트 경로, 총구 위치 등) |
| WeaponManager | weapon_manager.gd | 보유/장착 무기, 탄약, 강화 레벨, 사거리 |
| PlayerStats | player_stats.gd | 체력·이동속도 업그레이드(`stat_*`) |
| CodexManager | codex_manager.gd | 도감(획득한 아이템 → 레시피 해금 판정) |
| RecipeDB | recipe_db.gd | `cooking.json` — 쿠킹 settings, ingredients, recipes + **레시피 레벨·숙련도(세이브)** |
| MonsterDB | monster_db.gd | `monsters.json` (일반/보스 구분) |
| ItemDB | item_db.gd | `items.json` (이름·무게·스택·회복·아이콘) |
| GameManager | game_manager.gd | 하루 루프 상태머신, 페이즈 씬 교체, 자동 저장, 가방(run_inventory)·창고(storage)·토큰·퀵슬롯 |

## 하루 루프 (GameManager)

```
lobby ─(새 게임/불러오기)─▶ MORNING_PREP ─▶ SCAVENGE ─▶ NIGHT ─▶ (day+1) MORNING_PREP …
                              [저장:morning]            [저장:night]
```
- `advance()`가 다음 스텝 씬을 `Main/PhaseContainer`에 로드(이전 씬 free). 씬 경로는 `_SCENES` 상수.
- 아침 진입 시 `deposit_all_to_storage()`(가방 → 창고, 총알은 WeaponManager 별도) 후 저장.
- 세이브 키: `day, phase, tokens, quick_slot, belami, player_stats, weapons, world_state{run_inventory, storage, region}, npcs, codex, cooking`.
- 밤 요리 재료: `cooking_stock(id)` = 가방 + 창고, `consume_for_cooking()` = 가방 먼저 차감.

## 탐사 (scavenge)
- `scavenge.gd`가 지역(ruins.tres) + MonsterDB 로 몬스터(일반 순환 + 보스)·채집 노드·탄약 픽업 스폰.
  `_apply_monster_type()`이 몬스터 종류별 능력치·드롭·크기를 주입.
- `add_loot(id, n)` → 무게 한도(`GameManager.units_that_fit`) 안에서 담고 실제 담은 수 반환.
  `drop_on_floor()`는 바닥에 `resource_node`(E로 줍기) 생성.
- `monster.gd`: IDLE(배회)/CHASE, 공격 예고(`_draw`), 장애물 회피(슬라이드 충돌 노말 기준 접선 이동),
  사망 → 시체(`_dead`) → E 2초 → `_do_loot()`(반드시 드롭, 못 담은 만큼 바닥).
- 충돌 레이어: 플레이어 mask 8, 몬스터 layer 2 / mask 8, 벽·나무 layer 8.

## 밤 쿠킹 (night_session)
`night_session.gd` 하나가 준비 화면·필드·결과 화면을 모두 담당. 필드는 `Field`(Panel) 좌표계.

- **조리 기구** = `Field` 아래 `CookStation` 인스턴스(Counter/Fryer/Pot/Bowl/Table/Trash). 위치·크기는 씬 데이터
  (에디터 드래그 또는 게임 내 배치 편집 → `PackedScene.pack` + `ResourceSaver.save`로 tscn 저장).
  `CookStation.INFO`에 기구별 이름·색, `show_items()`로 기구 위 물건 표시.
- **물건(item)** = Dictionary, 형식은 `KitchenItem` 주석 참고:
  재료 `{type:"ing", id, chopped, chops, grade, floor_t}` / 요리 `{type:"dish", recipe, grade}` / `burnt` / `rotten`.
  `KitchenItem`(Control)이 아이콘 또는 임시 도형으로 그림 + `label_of()`, `is_usable()`, `grade_down()` 헬퍼.
- **상태**: `_held`(손), `_counter_item`(조리대 1개), `_cookers[st]`(fryer/pot/bowl: items·state(fill|cooking|ready)·recipe·base 등급·elapsed·target·dish),
  `_table`(최대 table_slots), `_floor`(바닥 물건 + 노드).
- **레시피 판별**: `_menu_recipes(st)` = 오늘 메뉴 ∩ 해금 ∩ 해당 기구. 재료 개수 사전(`_counts`)으로 부분집합(`_fits`) 판정 →
  넣을 수 있는지 / 정확히 일치하는지 / 더 큰 레시피가 있는지.
- **입력**: E(`_on_e`) 집기, R(`_on_r`) 내려놓기, `_input`에서 조리대 왼클릭 → `_chop()`, 하단 목록(`_tray`) 버튼.
- **이동·충돌**: 수동 좌표(`_player_pos`) + 발 상자(`_FOOT_OFFSET/_FOOT_SIZE`) vs 장애물(기구 사각형 + `_god_rect`),
  축 분리 이동(`_move_body`/`_push_out`, 4px 이하 모서리는 미끄러짐). 깊이 = `z_index`를 발 y로(`_update_depth`),
  안내·오버레이는 `Z_UI`/`Z_OVERLAY`로 항상 위.
- **카밀라(서빙 NPC)**: `AStarGrid2D`(16px, 장애물을 발 크기만큼 부풀림) 경로 + 같은 발 충돌. 테이블 요리 최우선.
- **배치 편집(개발용)**: `_layout_input` — 범위(`Field/PlaceArea`) 클램프, 자석(`_snap_pos`, x 먼저 → y), 겹침 거부(`_try_place`), 방향키 미세 조정.
- **주의**: 전역 HUD(CanvasLayer 10)가 모든 페이즈 위에 있음. HUD 노드에 `mouse_filter`가 STOP/PASS인 컨트롤을 넣으면
  아래 페이즈 UI 클릭을 가로챔(상단 바는 IGNORE로 설정됨).

## 캠프 (morning_prep)
- NPC 그림·위치(엑셀 비율 좌표), 부활 컷씬, 카터 근처 E → 대장간(강화·제작), Tab 능력치, 탐험 준비(`inv_slot.gd` 드래그앤드롭).

## 설계 원칙
- **trust 비노출**: god 누적 만족도는 UI에 직접 표시하지 않음.
- **엑셀이 원본**: 수치 하드코딩 대신 `RecipeDB.setting()`, `Balance.get_float()` 등 기본값 있는 조회.
- **씬 템플릿**: 탐사는 scavenge.tscn 1개 + RegionData 로 지역 확장.
