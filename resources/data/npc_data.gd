class_name NPCData
extends Resource
## 부활 NPC 정의 (PRD 3.5).
## UNIQUE: 고유 콘텐츠 담당(예: 하나=무기 제작), 배치 불가.
## PLACEABLE: 배치형(주방 보조 / 서빙).

enum Role { UNIQUE, PLACEABLE }

@export var id: String
@export var display_name: String
@export var role: Role = Role.PLACEABLE
@export_multiline var bio: String
## 부활 시 해금하는 콘텐츠 id(탐사 지역/레시피/제작 도구 등).
@export var unlocks: Array[String] = []
