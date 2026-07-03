# 벨라미 — 인수인계 (HANDOFF)

새 세션에서 이 파일을 먼저 읽고 이어서 작업하세요.

## 프로젝트 개요
- 게임: **"벨라미"** — 2D 도트 생존/힐링 시뮬 (데이브 더 다이버식: 낮=폐허 탐사, 밤=벨라미 돌봄)
- 엔진: **Godot 4.7** — `C:\Users\user\Godot\Godot_v4.7-stable_win64.exe` (콘솔판 `..._console.exe` = 헤드리스 검증용)
- 프로젝트: `C:\Users\user\OneDrive\Documents\hilling-game`
- GitHub: `https://github.com/HomilBBANG/rt_Hilling_Game` (브랜치 main)
- PRD: `C:\Users\user\Downloads\PRD_벨라미_v0.3.md`
- 상세 구조: `docs/ARCHITECTURE.md`
- 원본 에셋 폴더(작업자가 저장): `C:\Users\user\OneDrive\Desktop\게임\로튼_힐링\resources`

## 하루 루프 / 상태머신
- GameManager(autoload): 아침(캠프) → 탐사 → 밤(쿠킹 세션) → 다음날. 페이즈 시작 시 자동 저장(JSON).
- Autoload 순서: Config, Balance, SaveManager, BelamiManager, NpcUnlockDB, NPCManager, WeaponManager, CodexManager, RecipeDB, GameManager
- 씬: `scenes/main.tscn`(루트) + `scenes/phases/{morning_prep(캠프), scavenge(탐사), night_session(밤)}.tscn`

## 엑셀 연동 (데이터 드리븐)
- NPC 해금표: `data/npc_unlocks.xlsx` → `python tools/convert_npc_unlocks.py` → `data/npc_unlocks.json`
- 밸런스: `data/balance.xlsx` → `python tools/convert_balance.py` → `data/balance.json` (player_speed/scavenge_seconds/night_seconds/target_satisfaction)
  - **무기 사거리(px)**: `<무기id>_range` 키로 무기별 조정 — 현재 `pistol_range`(총알 이동거리), `knife_range`(칼 부채꼴 반경). WeaponManager.range_of()가 장착 무기 id로 조회, 없으면 기본값(900/64)
- Python + Pillow + numpy 설치됨(에셋 처리). pip는 `python -m pip`.

## 구현 완료
- 탐사: 탑다운 WASD, 마우스 조준 총(좌)+칼(우), 채집, 탄약 고정드롭, 시간/스태미나, 출구 귀환, 몬스터 AI(감지반경+배회+피격추적, 몬스터별 프로필)
- 밤 쿠킹: 조합순서형+타이머형 미니게임, 조리대 근처에서만 요리→완성품 들고 직접 이동해 벨라미에게 서빙, 만족/토큰/불만, 성공·실패. 감자튀김=감자 획득 시 해금
- 캠프: 시체→NPC 부활 컷씬(누적 만족도 임계), '하나' 부활 시 무기 강화(대장간, 토큰, 전투 반영)
- 아트: 플레이어 스프라이트, idle/run 애니메이션(공용 `PlayerFrames.build()`), gun.png/arm.png, 카메라 줌 2
- **제거됨**: 타일셋 / 바닥(TileMapLayer) / 장애물 — 새 리소스 대기 중

## 아트 규격 (반드시 준수)
- **기준 타일 32px**, 모든 스프라이트 같은 픽셀 밀도, `texture_filter = Nearest`(1)
- 개별 확대 금지 → **카메라 줌**으로 통일(Camera2D zoom=2). 단 캠프/밤은 UI라 AnimatedSprite2D scale=3
- 권장 크기: 배경 32×32(이음매 없는 타일), 몬스터 32×32(보스 64×64), 장애물 바위 32×32/나무 48×64~64×96, 플레이어 32×32
- gif → 프레임 추출: `assets/characters/run/run_N.png`, `assets/characters/idle/idle_N.png` (Python PIL). PlayerFrames가 경로로 로드
- 단색 배경 시트는 numpy 크로마키 후 슬라이스(과거 obj_1 방식)

## ✅ 팔/총 어깨 정렬 — 완료
- arm.png/gun.png 둘 다 원본이 **오른쪽을 향하는 그림**이었음(어깨/손잡이=왼쪽, 손/총구=오른쪽).
  → 기존 `flip_h = true` + `offset = Vector2(16,0)` 조합이 그림을 캐릭터 오른쪽으로 크게 밀어냄(이중 이동)이 원인.
- PIL getbbox 측정: arm 콘텐츠 x10..18/y9..13, gun 콘텐츠 x7..24/y13..18(손잡이≈x15, 총구=x24).
- 합성 프리뷰(python)로 검증 후 확정값:
  - `Arm`: `flip_h` 제거(false), `offset = Vector2(6, 5)` → 어깨가 Aim 원점, 팔이 +x로 뻗음(y 중앙 정렬)
  - `Gun`: `flip_h` 제거(false), `offset = Vector2(9, 2)` → 손잡이가 손 위치(local x≈8), 총구가 local x≈17
  - `Muzzle`: `Vector2(19,0)` (30에서 축소 — 총구 끝에 맞춤)
- `Aim`은 플레이어 원점(0,0)에서 look_at 회전, 좌우 반전 보정은 `player.gd`의 `_aim.scale.y = -1`(마우스 왼쪽일 때) 그대로 유지 — offset 변경과 무관하게 동작 확인.
- 헤드리스 임포트 검사 통과. **인게임 육안 확인 권장**(특히 왼쪽 조준 시 총이 바로 서는지).

## 미커밋 변경
많이 쌓여 있음. **새 세션 시작 전 커밋 권장.**

## 검증 방법(헤드리스)
- 임포트 검사: `Godot_..._console.exe --headless --editor --quit --path <proj>` → ERROR/SCRIPT 없으면 정상
- 특정 씬 실행: `project.godot`의 `run/main_scene`을 임시 변경 → `--headless --path <proj> --quit-after N` → 원복
- 임시 테스트 씬(test_*.tscn/gd)은 검증 후 삭제. 세이브: `%APPDATA%\Godot\app_userdata\Hilling_Game\savegame.json`

## 다음 할 일 후보
1. 팔/총 offset 어깨 정렬 (진행 중)
2. 새 배경/타일 리소스 → TileSet + TileMapLayer 재구성 (+ 물리 레이어로 못 가는 지형)
3. 몬스터/보스 스프라이트 교체
4. 배치형 NPC 효과(서빙/주방 보조 자동화)
5. 토큰 상점, 지역 보스, 도감 UI, 커스터마이징
