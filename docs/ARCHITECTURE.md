# god — 코드 구조 & 아키텍처

Godot 4.7 / GDScript. 수치·콘텐츠는 엑셀(→json) 데이터 드리븐, 화면은 페이즈 씬 단위로 교체. 기준 해상도 1920×1080.
기획 내용은 `docs/GDD.md`, 작업 방법·검증은 `docs/HANDOFF.md`.
최종 갱신: 2026-10-09

## 폴더 구조

```
hilling-game/
├── project.godot            # autoload 등록, 시작 씬 = scenes/ui/lobby.tscn, 1920×1080, UI 기본 글자 24px
├── autoload/                # 싱글톤(아래 표)
├── data/                    # *.xlsx(기획자 편집) + *.json(변환 결과, 게임이 읽음)
├── tools/convert_*.py       # xlsx → json 변환기(openpyxl). DataImport 가 실행 시 자동 호출
├── scenes/
│   ├── main.tscn            # 루트: PhaseContainer(페이즈 씬 자리) + UILayer(CanvasLayer 10, 전역 HUD)
│   ├── ui/                  # lobby.tscn, hud.tscn(일차·페이즈 표시 + 인벤토리 오버레이)
│   ├── phases/              # morning_prep(캠프) / scavenge(탐사) / night_session(밤 쿠킹)
│   ├── entities/            # player, monster, bullet, pickups(ammo, resource_node), props(tree)
│   └── minigames/cooking/   # cook_station.tscn (밤 조리 기구 1개 — 구입 시 이 씬을 인스턴스)
├── scripts/                 # 씬 스크립트(scenes 구조 미러) + 공용 빌더
│   ├── player_frames.gd     # PlayerFrames — 플레이어 SpriteFrames 빌더(idle/run, idle_hand/run_hand)
│   ├── god_frames.gd        # GodFrames — god idle 프레임 빌더
│   ├── phases/              # morning_prep.gd, scavenge.gd, night_session.gd
│   ├── entities/            # player, monster, bullet, resource_node, ammo_pickup, spawn_point(SpawnPoint)
│   ├── ui/                  # hud.gd, inv_slot.gd, lobby.gd, recipe_cards.gd(RecipeCards — 레시피 카드·상세 공용)
│   └── minigames/           # cook_station.gd(CookStation), kitchen_item.gd(KitchenItem)
├── resources/
│   ├── data/                # Resource 클래스(item_data, region_data, npc_data, weapon_data)
│   ├── items/               # 아이템 .tres(도감 카테고리 판정용 — 음식 아이템은 category 0)
│   └── regions/ruins.tres   # 탐사 지역(몬스터 폴백 재료 등 — 채집 풀·보스·탄약 수 필드는 현재 미사용)
├── assets/                  # characters, monsters, npc, items, backgrounds, environment …
└── docs/                    # GDD.md, HANDOFF.md, ARCHITECTURE.md
```

### class_name 목록
| 클래스 | 파일 | 용도 |
|---|---|---|
| `PlayerFrames` / `GodFrames` | scripts/*_frames.gd | 캐릭터 애니메이션 프레임 빌더 |
| `SpawnPoint` | scripts/entities/spawn_point.gd | 탐사 고정 스폰 지점(@tool, 에디터에서 id 표시) |
| `CookStation` | scripts/minigames/cook_station.gd | 밤 조리 기구(@tool) — `INFO`(종류별 이름·색), `show_items`, `pulse`, 게이지·상태 문구 |
| `KitchenItem` | scripts/minigames/kitchen_item.gd | 주방 물건 그리기 + 물건 헬퍼(`make_ingredient`, `label_of`, `is_usable`, `grade_down`) |
| `RecipeCards` | scripts/ui/recipe_cards.gd | 레시피 카드 격자·상세 패널 공용 빌더(캠프 레시피 북 / 밤 주방 준비) |

## Autoload (project.godot 등록 순서)

| 이름 | 파일 | 역할 |
|---|---|---|
| DataImport | data_import.gd | **가장 먼저** 실행. 에디터/개발 실행 시 `tools/convert_*.py` 전부 실행해 json 갱신(엑셀이 잠겨 있으면 건너뜀) |
| Config | config.gd | 게이지 노출 등 설정, `SCREEN_SCALE`(1.5 — 720p→1080p 화면 좌표 배율, 캠프·밤 이동 속도에 곱함) |
| Balance | balance.gd | `balance.json` 키-값 조회(`get_float`), 날짜별 목표 만족도 `day_target(day, 기본값)` |
| SaveManager | save_manager.gd | `user://savegame.json` 읽기/쓰기/삭제(슬롯 1개) |
| BelamiManager | belami_manager.gd | god 누적 만족도(trust, 비노출)·불만도·선호 음식(옛 이름 유지) |
| NpcUnlockDB | npc_unlock_db.gd | `npc_unlocks.json` (임계값·해금 기능·캠프 위치) |
| NPCManager | npc_manager.gd | 부활한 NPC, 밤 배치 슬롯(kitchen/serving), 엠마가 맡은 요리 `kitchen_recipe` |
| WeaponDB | weapon_db.gd | `weapons.json` (스프라이트 경로, 총구 위치 등) |
| WeaponManager | weapon_manager.gd | 보유/장착 무기, 탄약, 강화 레벨, 사거리 |
| PlayerStats | player_stats.gd | 체력·이동속도 업그레이드(`stat_*`) |
| CodexManager | codex_manager.gd | 도감(획득한 아이템 기록 — `item:` 해금 조건 판정에도 사용) |
| RecipeDB | recipe_db.gd | `cooking.json` — settings·ingredients·stations·recipes 조회 + **세이브 상태**: 레시피 레벨·숙련도, 레시피 구입(`purchased`, `buy`), 주방 배치(`kitchen_layout`). `describe()` = 재료→기구 요약 |
| MonsterDB | monster_db.gd | `monsters.json` (`get_by_id`, 일반/보스 구분) |
| ItemDB | item_db.gd | `items.json` (이름·무게·스택·회복·아이콘 경로) |
| GameManager | game_manager.gd | 하루 루프 상태머신, 페이즈 씬 교체, 자동 저장, 가방(run_inventory)·창고(storage)·토큰·퀵슬롯, 게임 오버 재시작 |

## 하루 루프 (GameManager)

```
lobby ─(새 게임/불러오기)─▶ MORNING_PREP ─▶ SCAVENGE ─▶ NIGHT ─▶ (day+1) MORNING_PREP …
                              [저장:morning]            [저장:night]
                                     ▲                       │ 게임 오버
                                     └──── restart_day() ────┘ (morning_snapshot 으로 되돌림)
```
- `advance()`가 다음 스텝 씬을 `Main/PhaseContainer`에 로드(이전 씬 free). 씬 경로는 `_SCENES` 상수.
- 아침 진입 시 `deposit_all_to_storage()`(가방 → 창고, 총알은 WeaponManager 별도) 후 저장.
- 세이브 키: `day, phase, tokens, quick_slot, belami, player_stats, weapons, world_state{run_inventory, storage, region}, npcs, codex, cooking`
  (+ 밤 세이브에만 `morning_snapshot`). 아침 저장 때 `_morning_snapshot`을 메모리에 보관, 밤 저장에 함께 기록 → `restart_day()`가 그 사본을 세이브로 쓰고 `continue_game()`.
- 밤 요리 재료: `cooking_stock(id)` = 가방 + 창고, `consume_for_cooking()` = 가방 먼저 차감(고철 기구 구입에도 같은 함수 사용).

## 탐사 (scavenge)
- `scavenge.gd`가 씬의 고정 지점에서 스폰: `MonsterSpawns`/`ItemSpawns` 아래 `SpawnPoint`, `AmmoSpawns` 마커.
  `_apply_monster_type()`이 몬스터 종류별 능력치·드롭·크기(보스 포함)를 주입. 지역을 늘리면 지역마다 탐사 씬(고정 배치)을 따로 두는 구조.
- `add_loot(id, n)` → 무게 한도(`GameManager.units_that_fit`) 안에서 담고 실제 담은 수 반환(첫 획득 시 도감 등록).
  `drop_on_floor()`는 바닥에 `resource_node`(E로 줍기) 생성.
- `resource_node.gd`: `item_id` setter 에서 겉모습 결정 — 아이콘(items.xlsx icon) 있으면 아이콘, 없으면 재료 색 사각형.
- `monster.gd`: IDLE(배회)/CHASE, 공격 예고(`_draw`), 장애물 회피(슬라이드 충돌 노말 기준 접선 이동),
  사망 → 시체(`_dead`) → E 2초 → `_do_loot()`(반드시 드롭, 못 담은 만큼 바닥).
- 충돌 레이어: 플레이어 mask 8, 몬스터 layer 2 / mask 8, 벽·나무 layer 8.
- 월드 라벨(탄약 부족·너무 무거워·시체/채집 안내)은 글자 16px 고정(카메라 줌 기준, 전역 기본 24 미적용).

## 밤 쿠킹 (night_session)
`night_session.gd` 하나가 준비 화면·필드·배치 편집·결과 화면을 모두 담당. 필드는 `Field`(Panel) 좌표계.

### 조리 기구
- `Field` 아래 `CookStation` 인스턴스. **키 = 노드 이름**(Counter, Fryer, Fryer2 …), **종류 = `station_id`**
  (counter/fryer/pot/bowl/table/trash/helper). `_st_nodes[key]`, `_type(key)`, `_keys_of(type)`.
- 같은 종류 여러 개 가능 — 상태는 키별:
  `_counter_items[key]`(조리대 위 재료 1개), `_cookers[key]`(fryer/pot/bowl: items·state(fill|cooking|ready)·recipe·base 등급·elapsed·target·dish), `_tables[key]`(최대 table_slots).
  그 밖에 `_held`(손), `_floor`(바닥 물건 + 노드).
- **배치**: 기본 = 씬 데이터. 세이브별 배치·구입 기구 = `RecipeDB.kitchen_layout`([{key,type,x,y}]) — `_apply_saved_layout`이
  씬 위에 적용(없는 키는 `cook_station.tscn`으로 생성) → `_collect_stations` → `_init_station_states`.
- **엠마 조리대**(`Field/Helper`, type helper): 주방 도우미 배치 시에만 `_st_nodes`에 등록(`_sync_helper_station`).

### 물건 · 레시피 판별 · 입력
- **물건(item)** = Dictionary(`KitchenItem` 주석): 재료 `{type:"ing", id, chopped, chops, grade, floor_t}` / 요리 `{type:"dish", recipe, grade}` / `burnt` / `rotten`.
- **레시피 판별**: `_menu_recipes(type)` = 오늘 메뉴 ∩ 해금 ∩ 해당 기구 종류. 재료 개수 사전(`_counts`)으로 부분집합(`_fits`) 판정 →
  넣을 수 있는지 / 정확히 일치하는지 / 더 큰 레시피가 있는지(있으면 대기, E로 시작).
- **입력**: E(`_on_e`) 집기, R(`_on_r`) 내려놓기, `_input`에서 조리대 왼클릭 → `_chop(key)`, 하단 목록(`_tray`, 근접한 조리대=재고 / 테이블=올린 물건) 버튼.

### 이동 · 충돌 · 그리기
- 수동 좌표(`_player_pos`) + 발 상자(`_FOOT_OFFSET/_FOOT_SIZE`, `_SPRITE_SCALE`(4)에서 계산) vs 장애물(`_obstacles` = 기구 사각형 + `_god_rect`),
  축 분리 이동(`_move_body`/`_push_out`, `_SLIP`(6px) 이하 모서리는 미끄러짐). 상호작용 거리 = 발 ↔ 기구 가장자리(`station_range`).
- 깊이 = `z_index`를 발 y로(`_update_depth`). 기구 위 물건은 z 1900 고정(캐릭터보다 위), 안내·말풍선은 `Z_UI`(2000), 준비/결과/배치 화면은 `Z_OVERLAY`(3000).

### NPC
- **카밀라(서빙)**: `AStarGrid2D`(24px, 장애물을 발 크기만큼 부풀림) 경로 + 같은 발 충돌.
  요리가 놓인 테이블 중 가까운 곳(`_table_with_dish`)에서 최우선으로 가져가고, 없으면 곁에 온 플레이어 손에서 받음.
- **엠마(주방)**: `_update_emma` — idle(재고 확인 → 재료 소모) → cooking(`helper_cook_seconds` + 레시피 시간) → waiting(빈 테이블에 올림, `_place_on_any_table`).
  엠마 조리대 뒤에 서서(발 = 조리대 윗변) 머리 위에 이름·게이지 표시. 등급 `helper_grade`, 숙련도 없음.

### 진행 · 종료
- 준비 화면: NPC 행(엠마 배치 시 맡길 요리 `OptionButton`) + `RecipeCards` 격자(카드 체크 = 오늘 메뉴) + 상세(강화·구입).
- `_start_cooking` → 오늘 메뉴 재료(`_menu_ings`), 왼쪽 위 레시피 표(`_build_recipe_panel`, 메뉴 수에 따라 1~3열).
- 목표 만족도 = `Balance.day_target(GameManager.day)`. `_out_of_food()`(서빙 가능한 요리·재료·엠마 작업이 하나도 없으면) → `_start_hungry`(시간 2배)
  → 타임오버 시 `_game_over`(잡아먹는 연출) → 게임 오버 화면 → `GameManager.restart_day`. 그 외 타임오버는 `_end_session`(성공/실패, 토큰, 누적 만족도).

### 기구 배치 · 구입 (게임 기능)
- `🛠 기구 배치 / 구입` → `_layout_input`: 범위(`Field/PlaceArea`) 클램프, 자석(`_snap_pos`, x 먼저 → y), 겹침 거부(`_try_place`), 방향키 미세 조정.
- 구입: `_buy_station(type)` — 가격·최대 개수 = cooking.xlsx stations, 고철 차감, `_new_key`(Fryer2 …) 이름으로 생성, `_free_spot`에 배치.
- 저장: `_store_layout` → `RecipeDB.kitchen_layout`(엠마 조리대는 숨겨져 있어도 위치 저장). 취소는 위치만 되돌리고, 산 기구는 저장.
- 에디터 전용 `_save_layout_to_scene`: `PackedScene.pack` + `ResourceSaver.save`로 `night_session.tscn` 기본 배치 수정(구입 기구 제외).

## 캠프 (morning_prep)
- NPC 그림·위치(엑셀 비율 좌표), 부활 컷씬, 카터 근처 E → 대장간(강화·제작), Tab 능력치, 탐험 준비(`inv_slot.gd` 드래그앤드롭).
- 📖 레시피 북: `RecipeCards` 격자 + 상세, 미해금은 `RecipeDB.buy`로 구입.

## 주의
- 전역 HUD(CanvasLayer 10)가 모든 페이즈 위에 있음. HUD 노드에 `mouse_filter`가 STOP/PASS인 컨트롤을 넣으면
  아래 페이즈 UI 클릭을 가로챔(상단 바는 IGNORE로 설정됨).
- 화면 좌표로 움직이는 것(캠프·밤 이동, 카밀라 속도)은 `Config.SCREEN_SCALE`을 곱함.

## 설계 원칙
- **trust 비노출**: god 누적 만족도는 UI에 직접 표시하지 않음.
- **엑셀이 원본**: 수치 하드코딩 대신 `RecipeDB.setting()`, `Balance.get_float()` 등 기본값 있는 조회.
- **배치는 씬에서**: 탐사 스폰·밤 기구 기본 위치는 씬 노드(에디터에서 드래그). 세이브별로 바뀌는 것(주방 배치·구입 기구)만 세이브 데이터.
- **UI 공용화**: 같은 정보를 보여주는 화면은 공용 빌더(`RecipeCards`)를 써서 한쪽만 고쳐도 둘 다 바뀌게.
