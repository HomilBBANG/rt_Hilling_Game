extends Node
## 도감 관리 (PRD 3.6).
## 정적 데이터(아이템/생물/유물 정의)는 Resource 파일에, 여기선 '발견 여부'만 보관.
## 카테고리: food / material / relic / recipe / npc

signal entry_discovered(category: String, id: String)

var discovered: Dictionary = {}   # { category: [ids] }


## 신규 발견 시 true 반환 → 호출부에서 팝업/사운드 연출(PRD 3.6 마이크로 도파민).
func discover(category: String, id: String) -> bool:
	var list: Array = discovered.get(category, [])
	if id in list:
		return false
	list.append(id)
	discovered[category] = list
	entry_discovered.emit(category, id)
	return true


func is_discovered(category: String, id: String) -> bool:
	return id in discovered.get(category, [])


## 카테고리 무관 — 이 아이템을 한 번이라도 발견/획득했는지(레시피 해금 판정 등에 사용).
func is_item_obtained(id: String) -> bool:
	if id == "":
		return false
	for cat in discovered.keys():
		if id in discovered[cat]:
			return true
	return false


func count(category: String) -> int:
	return (discovered.get(category, []) as Array).size()


func to_dict() -> Dictionary:
	return discovered.duplicate(true)


func from_dict(d: Dictionary) -> void:
	discovered = d.duplicate(true)
