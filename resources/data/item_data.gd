class_name ItemData
extends Resource
## 아이템 정적 정의 (PRD 3.1 / 3.6). .tres 로 데이터 드리븐 확장.

enum Category { FOOD, MATERIAL, RELIC, CLUE }

@export var id: String
@export var display_name: String
@export var category: Category = Category.FOOD
@export var icon: Texture2D
@export_multiline var description: String
## 신선도 감소율(0~1). 식재료에만 의미(PRD 3.4 — 신선도가 급식 평가에 반영).
@export_range(0.0, 1.0, 0.01) var freshness_decay: float = 0.0
