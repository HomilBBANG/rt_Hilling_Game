# god — 인수인계 (HANDOFF)

새 세션에서 이 파일을 먼저 읽고 이어서 작업하세요.
게임 내용(기획·수치)은 `docs/GDD.md`, 코드 구조는 `docs/ARCHITECTURE.md`.

## 프로젝트 개요
- 게임: **"god"** (구 가칭 "벨라미") — 2D 도트 생존/힐링 시뮬. 낮 = 폐허 탐사, 밤 = 요리해서 god 돌보기.
  - 코드·세이브 키 일부에 옛 이름이 남아 있음: `BelamiManager`, `_belami`(god 표정 버블), 세이브 `"belami"` 키. 의도된 것(호환성).
- 엔진: **Godot 4.7** — `C:\Users\user\Godot\Godot_v4.7-stable_win64.exe` (콘솔판 `..._console.exe` = 헤드리스 검증용)
- 프로젝트: `C:\Users\user\OneDrive\Documents\hilling-game`
- GitHub: `https://github.com/HomilBBANG/rt_Hilling_Game` (브랜치 main)
- 원본 에셋 폴더(작업자가 저장): `C:\Users\user\OneDrive\Desktop\게임\로튼_힐링\resources`
- 시작 씬: `scenes/ui/lobby.tscn` (새 게임 / 불러오기 / 진행도 초기화, 세이브 슬롯 1개)

## 하루 루프
로비 → 아침(캠프 `morning_prep`) → 탐사(`scavenge`) → 밤(요리 `night_session`) → 다음 날 아침 …
- `GameManager`(autoload)가 페이즈 씬을 `Main/PhaseContainer`에 로드. 아침·밤 시작 시 자동 저장.
- 아침 시작 시 탐사 가방(총알 제외)을 창고로 자동 입고.

## 데이터 = 엑셀 (가장 중요)
수치·콘텐츠는 거의 전부 `data/*.xlsx` → `tools/convert_*.py` → `data/*.json` → autoload DB.
- **게임 실행 시 자동 변환**(`DataImport` autoload, 에디터/개발 실행만). 작업 흐름: 엑셀 수정 → **저장 후 엑셀 닫기** → 게임 실행.
- 엑셀이 열려 있으면 파일이 잠겨 변환이 건너뛰어짐(경고만 뜨고 기존 json 사용). 수동 변환: `python tools/convert_<이름>.py`
- Python + openpyxl + Pillow + numpy 설치됨. pip는 `python -m pip`.

| 엑셀 | 변환기 | 읽는 곳 | 내용 |
|---|---|---|---|
| `balance.xlsx` | convert_balance | `Balance` | 탐사 시간, 무기 사거리 `<무기id>_range`, 능력치 `stat_*`, 캠프 위치 `camp_*`, 가방 무게 |
| `monsters.xlsx` | convert_monsters | `MonsterDB` | 몬스터 능력치·AI·공격·드롭(반드시 드롭, 수량)·보스·크기·스프라이트 |
| `items.xlsx` | convert_items | `ItemDB` | 아이템 이름·무게·스택·소비/회복·아이콘 |
| `weapons.xlsx` | convert_weapons | `WeaponDB` | 무기 공격력·제작비·탄약·스프라이트·총구 위치 |
| `npc_unlocks.xlsx` | convert_npc_unlocks | `NpcUnlockDB` | NPC 부활 임계값·해금 기능·캠프 위치 |
| `cooking.xlsx` | convert_cooking | `RecipeDB` | 시트 3개: `settings`(쿠킹 밸런스) / `ingredients`(써는 횟수·임시 도형 색) / `recipes`(레시피 × Lv1~3) |

- 지역만 Godot 리소스: `resources/regions/ruins.tres`(음식/재료 풀, 보스 id 등).

## 구현 완료 (요약 — 상세는 GDD)
- **로비**: 새 게임/불러오기/진행도 초기화.
- **캠프**: NPC 시체·부활 컷씬, 카터 대장간(무기 강화·제작), 능력치 화면(Tab), 탐험 준비(가방↔창고 드래그앤드롭, 무게 제한), 위치는 엑셀.
- **탐사**: 탑다운 이동·사격·근접, 무기별 스프라이트/총구, 몬스터 AI(배회·추적·공격 예고·장애물 우회), 보스, 시체 루팅(E 2초, 반드시 드롭, 무게 초과분은 바닥), 채집, 인벤토리(I, 우클릭 사용/퀵슬롯/버리기), 퀵슬롯(1), 획득 텍스트, 피격 플래시, 나무 y-정렬.
- **밤 쿠킹**: 준비 화면(NPC 배치·메뉴 선택·레시피 강화), 왼쪽 위 레시피 표, 재료 소진 시 배고픈 god(시간 2배) → 타임오버 게임 오버 → 그날 아침부터(`GameManager.restart_day`, 밤 세이브의 `morning_snapshot`), 조리 기구 6종(조리대/튀김기/냄비/믹싱볼/테이블/쓰레기통), 재료 꺼내기→클릭 손질→기구에 넣어 레시피 자동 판별→조리→서빙, E 집기/R 내려놓기, 바닥 낙하(등급↓·20초 후 썩음), 카밀라 서빙(길찾기), 발 기준 충돌·깊이 정렬, 숙련도·강화, 결과 화면.
- **기구 배치 편집(개발용)**: 밤 준비 화면 `🛠 기구 배치 편집` → 드래그(자석 정렬, Alt 끄기), 방향키 1px/Shift 10px, 초록 범위(`Field/PlaceArea`) 안에서만, 겹침 불가, 저장 시 `night_session.tscn`에 기록.

## 아트 규격 (반드시 준수)
- **기준 타일 32px**, 모든 스프라이트 같은 픽셀 밀도, `texture_filter = Nearest`.
- 개별 확대 금지 → **카메라 줌**으로 통일(탐사 Camera2D zoom=2). 캠프·밤은 UI 화면이라 스프라이트 scale=3(god는 64px 원본 ×2).
- gif → 프레임 추출은 **프레임마다 독립 추출**(`frame.convert('RGBA')`). 누적 합성(alpha_composite)하면 잔상이 생김.
- 플레이어 모션: 탐사 `idle`/`run`, 캠프·요리 `idle_hand`/`run_hand` (`PlayerFrames.build(idle, run)`).
- 플레이어 원점 = 발(y-정렬용). Body/Aim/Camera가 (0,-26)에 있음.
- 이미지 없는 쿠킹 재료는 `cooking.xlsx` ingredients 의 `color`로 임시 도형 표시(`KitchenItem`).

## 검증 방법
- **임포트 검사**(문법/참조 에러): `Godot_..._console.exe --headless --editor --quit --path <proj>` → `SCRIPT ERROR`/`Parse Error` 없으면 정상.
- **로직 테스트**: 프로젝트 루트에 임시 `test_*.gd`(`extends SceneTree`) 작성 → `--headless --path <proj> -s res://test_x.gd` → 검증 후 **반드시 삭제**.
  - 테스트 스크립트에서 `KitchenItem` 같은 class_name 을 **직접 쓰지 말 것**: autoload 등록 전에 컴파일돼 `Identifier not found: RecipeDB` 가 남. `load("res://scripts/minigames/kitchen_item.gd")`로 런타임에 불러 쓰기.
  - **마우스 클릭(GUI) 테스트는 헤드리스에서 안 됨**(입력이 GUI에 전달되지 않음). `--headless` 없이 실제 창으로 실행하고 `root.push_input()` 사용.
  - 씬 파일을 저장하는 기능(배치 저장 등)을 테스트할 땐 `.tscn`을 스크래치에 백업 → 테스트 → 복원.
- 특정 씬 바로 실행: `Godot_...exe --path <proj> res://scenes/phases/night_session.tscn` (밤 씬 단독 실행은 재료가 없음 — 실제 요리는 로비→탐사→밤).
- 세이브 위치: `%APPDATA%\Godot\app_userdata\Hilling_Game\savegame.json`

## 작업 규칙
- 사용자가 "커밋"이라고 할 때 커밋. 메시지는 한국어, 끝에 `Co-Authored-By` 줄.
- 기능마다 실행해서 확인 → 사용자 확인 → 커밋 흐름.
- 기획서(`docs/GDD.md`)는 기능이 바뀔 때마다 함께 갱신.

## 알려진 이슈 / 다음 할 일 후보
1. 고기·치즈: 몬스터 드롭·회복 아이템으로만 쓰임. 쿠킹 재료(ingredients 시트)·레시피 미등록.
2. 엠마(주방 보조) 효과는 만족·토큰 ×1.25 배율만, 리암(새 지역) 미구현.
3. 밤이 끝나면 조리대·테이블·바닥에 남은 재료는 사라짐(꺼낼 때 이미 소모).
4. 레시피 데이터상 "들어간 재료 + 통조림" 형태가 많아 믹싱볼에서 "E로 시작" 대기가 자주 생김 → 레시피 재료 조정 검토.
5. 아트: 조리 기구(현재 색 사각형), monster_b/c·보스·샷건 스프라이트, 들풀·고철·고기·치즈 아이콘.
6. 토큰 상점, 도감 UI, 커스터마이징, 불만도의 게임플레이 영향.
