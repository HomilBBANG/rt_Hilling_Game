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

## ⚠️ 지금 진행 중이던 작업 (미완)
**팔/총을 어깨 위치에 붙이기 (offset 조정 필요)**
- 위치: `scenes/entities/player/player.tscn` 의 `Aim > Arm`(arm.png) + `Aim > Gun`(gun.png)
- 현재 둘 다 `offset = Vector2(16, 0)`, `flip_h = true`. `Aim`은 플레이어 원점(0,0)에서 마우스로 look_at 회전
- **문제**: 팔+총이 캐릭터 오른쪽에 붕 떠서 붙음(offset 과다)
- **다음 단계**: arm.png/gun.png 실제 그림 bbox 측정(PIL getbbox) → 어깨(그림 왼쪽 끝)가 Aim 원점에 오도록 offset 재계산. 필요 시 Aim 노드를 어깨 높이로 살짝 이동(예: position (0,-4))
- 좌우 반전 보정: `player.gd` _physics_process 에서 `_aim.scale.y = -1`(마우스 왼쪽일 때). 몸통은 `_body.flip_h = mouse.x > player.x`

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
