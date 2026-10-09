# god — 인수인계 (HANDOFF)

새 세션에서 이 파일을 먼저 읽고 이어서 작업하세요.
게임 내용(기획·수치)은 `docs/GDD.md`, 코드 구조는 `docs/ARCHITECTURE.md`.
최종 갱신: 2026-10-09

## 프로젝트 개요
- 게임: **"god"** (구 가칭 "벨라미") — 2D 도트 생존/힐링 시뮬. 낮 = 폐허 탐사, 밤 = 요리해서 god 돌보기.
  - 코드·세이브 키 일부에 옛 이름이 남아 있음: `BelamiManager`, `_belami`(god 표정 버블), 세이브 `"belami"` 키. 의도된 것(호환성).
- 엔진: **Godot 4.7** — `C:\Users\user\Godot\Godot_v4.7-stable_win64.exe` (콘솔판 `..._console.exe` = 헤드리스 검증용)
- 프로젝트: `C:\Users\user\OneDrive\Documents\hilling-game`
- GitHub: `https://github.com/HomilBBANG/rt_Hilling_Game` (브랜치 main)
- 원본 에셋 폴더(작업자가 저장): `C:\Users\user\OneDrive\Desktop\게임\로튼_힐링\resources`
- 시작 씬: `scenes/ui/lobby.tscn` (새 게임 / 불러오기 / 진행도 초기화, 세이브 슬롯 1개)
- 기준 해상도 **1920×1080**.

## 하루 루프
로비 → 아침(캠프 `morning_prep`) → 탐사(`scavenge`) → 밤(요리 `night_session`) → 다음 날 아침 …
- `GameManager`(autoload)가 페이즈 씬을 `Main/PhaseContainer`에 로드. **아침·밤 시작 시 자동 저장**.
- 아침 시작 시 탐사 가방(총알 제외)을 창고로 자동 입고.
- 밤에 게임 오버(배고픈 god) → `GameManager.restart_day()` → 그날 아침 사본(`morning_snapshot`)으로 되돌림.

## 세이브 (`%APPDATA%\Godot\app_userdata\Hilling_Game\savegame.json`)
`day, phase, tokens, quick_slot, belami, player_stats, weapons, world_state{run_inventory, storage, region}, npcs, codex, cooking`
- `npcs`: 부활 NPC, 배치(`placement`), 엠마가 맡은 요리(`kitchen_recipe`)
- `cooking`(RecipeDB): 레시피 레벨·숙련도, 레시피 북 구입(`purchased`), **세이브별 주방 배치**(`kitchen_layout` — 구입한 기구 포함)
- 밤 세이브에만 `morning_snapshot`(그날 아침 세이브 사본)
- 게임 중 바뀐 값(구입·배치 등)은 **다음 아침/밤 자동 저장 때** 파일에 기록됨.

## 데이터 = 엑셀 (가장 중요)
수치·콘텐츠는 거의 전부 `data/*.xlsx` → `tools/convert_*.py` → `data/*.json` → autoload DB.
- **게임 실행 시 자동 변환**(`DataImport` autoload, 에디터/개발 실행만). 작업 흐름: 엑셀 수정 → **저장 후 엑셀 닫기** → 게임 실행.
- 엑셀이 열려 있으면 파일이 잠겨 변환이 건너뛰어짐(파이썬 Traceback 경고만 뜨고 기존 json 사용 — 게임은 정상 동작). 수동 변환: `python tools/convert_<이름>.py`
- 사용자가 엑셀을 직접 고치는 경우가 많음(써는 횟수·NPC 임계값 등) → 엑셀을 스크립트로 수정할 땐 **기존 행을 덮어쓰지 말고** 없는 것만 추가.
- Python + openpyxl + Pillow + numpy 설치됨. pip는 `python -m pip`. 콘솔 한글 출력은 `python -X utf8`.

| 엑셀 | 변환기 | 읽는 곳 | 내용 |
|---|---|---|---|
| `balance.xlsx` | convert_balance | `Balance` | 첫 시트(key/value): 탐사 시간, 카메라 줌 `camera_zoom`, 무기 사거리 `<무기id>_range`, 능력치 `stat_*`, 캠프 위치 `camp_*`, 가방 무게 / `day_targets` 시트: 날짜별 밤 목표 만족도(`Balance.day_target(day)`, 마지막 날 이후는 마지막 값) |
| `monsters.xlsx` | convert_monsters | `MonsterDB` | 몬스터 능력치·AI·공격·드롭(반드시 드롭, drop_min~max)·보스·크기·스프라이트 |
| `items.xlsx` | convert_items | `ItemDB` | 아이템 이름·무게·스택·소비/회복·아이콘(`assets/items/<icon>.png`) |
| `weapons.xlsx` | convert_weapons | `WeaponDB` | 무기 공격력·제작비·탄약·스프라이트·총구 위치 |
| `npc_unlocks.xlsx` | convert_npc_unlocks | `NpcUnlockDB` | NPC 부활 임계값(현재 카터 100 · 카밀라 300 · 엠마 650 · 리암 1000)·해금 기능·캠프 위치 |
| `cooking.xlsx` | convert_cooking | `RecipeDB` | 시트 4개: `settings`(쿠킹 밸런스·엠마 `helper_*`) / `ingredients`(써는 횟수·임시 도형 색) / `stations`(기구 구입 고철 가격·최대 개수) / `recipes`(레시피 × Lv1~3, `unlock` = default·shop, `price`) |

- 지역만 Godot 리소스: `resources/regions/ruins.tres`(몬스터 폴백 재료 등). `food_item_ids`·`boss_id`·`ammo_pickup_points` 는 현재 미사용.
- **탐사 배치는 전부 고정**: `scavenge.tscn` 의 `MonsterSpawns`(보스 포함) / `ItemSpawns` 아래 `SpawnPoint`(kind, spawn_id, amount) + `AmmoSpawns` 마커. 에디터에서 드래그·복제로 편집(에디터에서만 id 글자 표시).
- 아이템 리소스(`resources/items/*.tres`)는 도감 카테고리 판정용 — 새 음식 아이템을 만들면 같이 추가.

## 구현 완료 (요약 — 상세는 GDD)
- **로비**: 새 게임/불러오기/진행도 초기화.
- **캠프**: NPC 시체·부활 컷씬, 카터 대장간(무기 강화·제작), 능력치 화면(Tab), **📖 레시피 북**(카드 격자 + 상세, 토큰으로 레시피 구입), 탐험 준비(가방↔창고 드래그앤드롭, 무게 제한), 위치는 엑셀.
- **탐사**: 탑다운 이동·사격·근접, 무기별 스프라이트/총구, 몬스터 AI(배회·추적·공격 예고·장애물 우회), 보스, 시체 루팅(E 2초, 반드시 드롭 — 떠돌이 고철·추적자 고기·날쌘이 치즈, 무게 초과분은 바닥), 고정 배치 채집(통조림·들풀·감자·토마토, 아이콘 또는 재료 색), 인벤토리(I), 퀵슬롯(1), 획득 텍스트, 피격 플래시, 나무 y-정렬.
- **레시피**: 13종 × Lv1~3. **1일차엔 들풀 무침·들풀 튀김·감자튀김만**, 나머지는 레시피 북/주방 준비에서 토큰 구입. 숙련도로 수동 강화. 레시피 카드 UI는 캠프·밤 공용(`scripts/ui/recipe_cards.gd`), god 선호 음식은 분홍 테두리.
- **밤 쿠킹**: 준비 화면(NPC 배치·메뉴 체크·강화·구입), 왼쪽 위 레시피 표, 재료 꺼내기→클릭 손질→기구에 넣어 레시피 자동 판별→조리→서빙, E 집기/R 내려놓기, 바닥 낙하(등급↓·20초 후 썩음), 카밀라 서빙(길찾기), 발 기준 충돌·깊이 정렬, 날짜별 목표 만족도, 재료 소진 시 배고픈 god(시간 2배) → 타임오버 게임 오버, 결과 화면.
- **기구 배치 / 구입(게임 기능)**: 주방 준비 화면 `🛠 기구 배치 / 구입` → 드래그(자석, Alt 끄기)·방향키 1px, 초록 범위 안, 겹침 불가. 고철로 기구 추가 구입(같은 종류 여러 개 동시 사용). 저장 = 세이브별 배치. 에디터에서만 `기본 배치로 저장(개발용)` → `night_session.tscn`(새 게임 기본값).
- **엠마(주방 도우미)**: 배치 + 맡길 요리 1종 → 엠마 조리대(`Field/Helper`, 배치 시에만 기구로 등록) 뒤에서 재고로 계속 요리(B등급, 숙련도 없음) → 빈 테이블에 올림.

## 아트 규격 (반드시 준수)
- **기준 해상도 1920×1080** (`project.godot` viewport, stretch canvas_items/expand). UI 기본 글자 24px(`gui/theme/default_font_size`).
  - 2026-10 에 1280×720 → 1920×1080 으로 전환: 화면(UI) 좌표·글자·칸 크기 ×1.5, 도트 배율은 정수 유지.
  - 캠프·밤처럼 **화면 좌표로 움직이는 속도**에는 `Config.SCREEN_SCALE`(1.5)를 곱함. 탐사는 월드 좌표라 미적용.
  - 탐사 월드 라벨(탄약 부족, 너무 무거워, 시체/채집 안내)은 글자 16px 고정(카메라 줌 기준).
- **기준 타일 32px**, 모든 스프라이트 같은 픽셀 밀도, `texture_filter = Nearest`, **정수 배율만**.
- 탐사: Camera2D 줌 = `balance.xlsx` `camera_zoom`(기본 2, 3 = 예전 화면 비율). 캠프·밤: 캐릭터 scale=4, god(64px 원본) ×3.
  - 밤 캐릭터 배율을 바꾸면 `night_session.gd` 의 `_SPRITE_SCALE`도 같이 바꿀 것(발 충돌 상자가 여기서 계산됨).
- gif → 프레임 추출은 **프레임마다 독립 추출**(`frame.convert('RGBA')`). 누적 합성(alpha_composite)하면 잔상이 생김.
- 플레이어 모션: 탐사 `idle`/`run`, 캠프·요리 `idle_hand`/`run_hand` (`PlayerFrames.build(idle, run)`).
- 플레이어 원점 = 발(y-정렬용). Body/Aim/Camera가 (0,-26)에 있음.
- 이미지 없는 쿠킹 재료·요리는 `cooking.xlsx` ingredients 의 `color`로 임시 도형 표시(`KitchenItem`). `items.xlsx` 에 icon 을 넣으면 인벤토리·채집 노드·주방 모두 자동으로 아이콘.

## 검증 방법
- **임포트 검사**(문법/참조 에러): `Godot_..._console.exe --headless --editor --quit --path <proj>` → `SCRIPT ERROR`/`Parse Error` 없으면 정상.
- **로직 테스트**: 프로젝트 루트에 임시 `test_*.gd`(`extends SceneTree`) 작성 → `--headless --path <proj> -s res://test_x.gd` → 검증 후 **반드시 삭제**.
  - 테스트 스크립트에서 `KitchenItem` 같은 class_name 을 **직접 쓰지 말 것**: autoload 등록 전에 컴파일돼 `Identifier not found: RecipeDB` 가 남. `load("res://scripts/minigames/kitchen_item.gd")`로 런타임에 불러 쓰기.
  - 헤드리스는 프레임이 매우 빨라서 "N프레임 대기"로는 실제 시간이 거의 안 흐름 → 트윈·타이머 확인은 `await create_timer(초).timeout`, 수치는 `_process(delta)` 직접 호출.
  - 밤 씬은 시작 직후 첫 프레임에 플레이어 위치를 초기화함 → 위치를 지정하는 테스트는 `_start_cooking()` 뒤 몇 프레임 기다린 다음에.
  - **게임 오버·재시작·자동 저장을 부르는 테스트는 세이브 파일을 스크래치에 백업 → 테스트 → 복원**.
  - 씬 파일을 저장하는 기능(기본 배치 저장 등)을 테스트할 땐 `.tscn`을 스크래치에 백업 → 테스트 → 복원.
- **마우스 클릭(GUI) 테스트·스크린샷은 헤드리스에서 안 됨** → `--headless` 없이 실제 창으로 실행.
  - 클릭: `root.push_input(InputEventMouseButton)` (직전에 MouseMotion 도 넣기).
  - 스크린샷: `await RenderingServer.frame_post_draw` 후 `root.get_texture().get_image().save_png(경로)` → 이미지로 열어 확인.
- 특정 씬 바로 실행: `Godot_...exe --path <proj> res://scenes/phases/night_session.tscn` (밤 씬 단독 실행은 재료가 없음 — 실제 요리는 로비→탐사→밤).
- 전역 HUD(CanvasLayer 10)가 모든 페이즈 위에 있음 — HUD에 마우스를 받는 컨트롤(STOP/PASS)을 두면 아래 화면 클릭을 가로챔(상단 바는 IGNORE).

## 작업 규칙
- 사용자가 "커밋"이라고 할 때 커밋(푸시는 요청 시). 메시지는 한국어, 끝에 `Co-Authored-By` 줄.
- 기능마다 실행·테스트로 확인 → 결과 보고 → 사용자 확인 → 커밋 흐름. 화면이 바뀌는 작업은 스크린샷으로 직접 확인.
- 기획서(`docs/GDD.md`)는 기능·수치가 바뀔 때마다 함께 갱신(엑셀을 사용자가 고친 경우 포함).

## 알려진 이슈 / 다음 할 일 후보
1. 리암(새 탐사 지역) 미구현 — 지역을 늘리면 지역마다 탐사 씬(고정 배치)을 따로 두는 구조.
2. 밤이 끝나면 조리대·테이블·바닥에 남은 재료는 사라짐(꺼낼 때 이미 소모).
3. 레시피 데이터상 "들어간 재료 + 통조림" 형태가 많아 믹싱볼에서 "E로 시작" 대기가 생길 수 있음 → 메뉴를 좁히거나 레시피 재료 조정.
4. 밸런스 임시값: 레시피 구입 가격, 기구 구입 고철 가격, 엠마 요리 시간·등급, 고기·치즈·토마토 무게/회복량.
5. 아트: 조리 기구(색 사각형), 요리 완성 그림(접시 + 첫 재료 색), 들풀·토마토·고기·치즈·고철 아이콘, 엠마·카밀라 전용 스프라이트(현재 NPC 공용), monster_b/c·보스·샷건 스프라이트.
6. 도감 UI, 커스터마이징, 불만도의 게임플레이 영향.
