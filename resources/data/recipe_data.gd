class_name RecipeData
extends Resource
## 레시피 정의 (PRD 3.2 — 쿠킹 미니게임).
## 레시피마다 서브 메커닉이 다름. 완전히 새 미니게임을 매번 만들지 않고
## 소수의 패턴(조합 순서형 / 타이머형)을 재료에 맞게 재사용.

enum SubMechanic { STACK_ORDER, TIMER }   # 조합 순서형 / 타이머형

@export var id: String
@export var display_name: String
@export var sub_mechanic: SubMechanic = SubMechanic.STACK_ORDER
## 조합 순서(조합 순서형) 또는 필요 재료 목록. 중복 id = 해당 재료 여러 개 필요.
@export var ingredient_ids: PackedStringArray = []
## 완벽 조리 기준 기본 품질(등급 산정의 베이스).
@export var base_quality: float = 20.0
## 타이머형일 때 적정 조리 시간(초). STACK_ORDER 면 무시.
@export var timer_seconds: float = 0.0
@export var unlocked_by_default: bool = false
## 해금 조건: 이 아이템을 한 번이라도 획득(도감 등록)하면 레시피 해금.
## 비어 있으면 unlocked_by_default 만으로 판정.
@export var unlock_item_id: String = ""
