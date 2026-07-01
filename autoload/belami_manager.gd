extends Node
## 벨라미 급식/누적 만족도 관리 (PRD 3.4 + 급식 스펙).
## trust = '누적 만족도(총 만족도)'. 밤마다 그날 만족도를 누적하며, NPC 해금 기준이 된다
## (일일 만족도가 아니라 지금까지의 총합). 선호 음식은 해금 레시피 중 1~2개 매일 갱신.

signal trust_changed(new_value: float)   # 누적 만족도 변화(연출 / NPC 해금 판정)

var trust: float = 0.0            # 누적 만족도(총 만족도)
var dissatisfaction: float = 0.0
var preferred_recipe_ids: Array[String] = []


## 밤 세션 종료 결과 반영. 그날 만족도를 누적 만족도에 더한다. 실패 시 불만 누적.
func complete_night(success: bool, satisfaction_score: float) -> void:
	trust += satisfaction_score
	trust_changed.emit(trust)
	if not success:
		dissatisfaction += 10.0


## 해금된 레시피 풀에서 선호 음식 1~2개를 새로 선정(매일 아침 갱신).
func refresh_preferences(unlocked_recipe_ids: Array[String]) -> void:
	preferred_recipe_ids.clear()
	if unlocked_recipe_ids.is_empty():
		return
	var pool := unlocked_recipe_ids.duplicate()
	pool.shuffle()
	var count: int = mini(pool.size(), 1 + (randi() % 2)) # 1~2개
	for i in count:
		preferred_recipe_ids.append(pool[i])


func is_preferred(recipe_id: String) -> bool:
	return recipe_id in preferred_recipe_ids


func to_dict() -> Dictionary:
	return {"trust": trust, "dissatisfaction": dissatisfaction}


func from_dict(d: Dictionary) -> void:
	trust = float(d.get("trust", 0.0))
	dissatisfaction = float(d.get("dissatisfaction", 0.0))
