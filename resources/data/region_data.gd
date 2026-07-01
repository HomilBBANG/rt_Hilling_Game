class_name RegionData
extends Resource
## 탐사 지역 정의 (PRD 3.1).
## 씬 템플릿 1개(scavenge.tscn) + 지역별 데이터로 확장 — 지역마다 씬을 새로 만들지 않는다.

@export var id: String
@export var display_name: String
## 이 지역에서 채집 가능한 자원 풀(리치 데이터 — 도감/신선도 등).
@export var resource_spawn_table: Array[ItemData] = []
## 스폰 편의용 id 목록(프로토타입 스폰이 참조). resource_spawn_table 와 병행 사용.
@export var food_item_ids: PackedStringArray = []
@export var material_item_ids: PackedStringArray = []
@export var monster_ids: Array[String] = []
## 지역 보스(있으면). 일반 탐사 중 조우, 지역 진행 관문(PRD 3.1).
@export var boss_id: String = ""
## 고정 탄약 드롭 지점 수(랜덤 아님 — 동선 학습 가능, PRD 3.1).
@export var ammo_pickup_points: int = 0
## 진입에 드는 스태미나 예산.
@export var stamina_budget: int = 100
