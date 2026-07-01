# 벨라미 — 씬 구조 & 아키텍처

PRD 9장(기술 스택)을 따른 골격. Godot 4.7 / GDScript / 데이터 드리븐(.tres).

## 폴더 구조

```
hilling-game/
├── project.godot              # Autoload 등록 + main_scene = scenes/main.tscn
├── autoload/                  # Autoload 싱글톤 (PRD 9)
│   ├── game_manager.gd        # 하루 사이클 상태머신 + 씬 전환 + 자동 저장 호출
│   ├── save_manager.gd        # JSON 세이브/로드 (페이즈 단위)
│   ├── belami_manager.gd      # trust(비노출), 선호 음식, 급식 반응
│   ├── npc_manager.gd         # 고정 부활 시퀀스, 배치 슬롯
│   ├── weapon_manager.gd      # 무기/탄약, '하나' 업그레이드 해금
│   └── codex_manager.gd       # 도감 발견 상태
├── scenes/
│   ├── main.tscn              # 루트: PhaseContainer + UILayer(HUD)
│   ├── phases/                # 하루 사이클 페이즈 (씬 전환 단위)
│   │   ├── morning_prep.tscn  #  아침 준비
│   │   ├── scavenge.tscn      #  탐사(지역 템플릿 — RegionData 로 확장)
│   │   └── night_session.tscn #  밤 세션: 쿠킹+서빙+급식(3분 타이머)
│   ├── ui/hud.tscn            # 최소 HUD (trust 비노출)
│   ├── entities/              # player / belami / npc (예정)
│   └── minigames/cooking/     # 쿠킹 미니게임 (예정)
├── scripts/                   # 씬에 붙는 스크립트 (scenes 구조 미러)
├── resources/
│   ├── data/                  # Resource 클래스 정의(.gd)
│   │   ├── item_data.gd  recipe_data.gd  region_data.gd
│   │   ├── npc_data.gd   weapon_data.gd
│   ├── items/ recipes/ regions/ npcs/   # 실제 .tres 데이터 (콘텐츠)
└── assets/  sprites/ audio/ fonts/
```

## 하루 사이클 상태머신 (GameManager)

```
MORNING_PREP ─▶ SCAVENGE ─▶ NIGHT ─▶ (day+1) MORNING_PREP
   │                          │
 [저장:morning]           [저장:night]   (NIGHT = 3분 쿠킹/급식 세션)
```

- `GameManager.advance()` 가 현재 스텝에서 다음 스텝으로 전환하며, 해당 페이즈 씬을
  `Main/PhaseContainer` 에 로드한다(이전 페이즈 씬은 free).
- 페이즈 시작 시점(MORNING_PREP / SHELTER)에서만 자동 저장 — 미드세션 세이브 없음(PRD 3.7).
- 재진입 시 `phase`(morning/night) 기준으로 해당 페이즈 시작점부터 복귀.

## 핵심 설계 원칙 (PRD 반영)

- **trust 비노출**: BelamiManager.trust 는 UI에 직접 표시하지 않는다. HUD 도 표시 금지.
- **데이터 드리븐**: 지역/레시피/아이템/NPC/무기는 `resources/data/*.gd` 클래스의
  `.tres` 인스턴스로 추가 — 씬을 새로 만들지 않고 콘텐츠 확장.
- **씬 템플릿**: 탐사는 scavenge.tscn 1개 + RegionData 주입으로 지역 확장(PRD 3.1).

## 다음 작업 (TODO)

1. 엔티티: player.tscn(이동/사격/근접), belami.tscn(반응 애니메이션 세트).
2. 탐사: RegionData 주입, 채집/전투/탄약 고정 드롭, 스태미나·시간 제한.
3. 쿠킹 미니게임: 서브 메커닉(조합 순서형/타이머형) 2종 + 등급 산정.
4. 부활 컷씬 + 콘텐츠 unlock 연결('하나' → 무기 업그레이드).
5. 도감 UI(그리드, 미발견 실루엣), 인벤토리 UI.
6. 모바일 입력/레이아웃 분기(PRD 8).
```
