extends Node
## 플레이어 능력치(체력·이동속도) — 토큰으로 업그레이드. 세이브에 포함된다.
## 기본값/레벨당 증가폭/최대레벨/비용은 balance 엑셀(stat_* 키)에서 읽어 데이터로 조정.
##   stat_<hp|speed>_base       : 기본값
##   stat_<hp|speed>_per_level  : 레벨당 증가폭
##   stat_<hp|speed>_max_level  : 최대 레벨
##   stat_<hp|speed>_cost       : 기본 강화 비용(실제 비용 = base * (현재레벨+1))

var hp_level: int = 0
var speed_level: int = 0


func max_hp() -> float:
	return _base("hp") + hp_level * _per_level("hp")


func move_speed() -> float:
	return _base("speed") + speed_level * _per_level("speed")


func current_value(stat: String) -> float:
	return max_hp() if stat == "hp" else move_speed()


func next_value(stat: String) -> float:
	return current_value(stat) + _per_level(stat)


func level_of(stat: String) -> int:
	return hp_level if stat == "hp" else speed_level


func max_level(stat: String) -> int:
	return Balance.get_int("stat_%s_max_level" % stat, 5)


func is_max(stat: String) -> bool:
	return level_of(stat) >= max_level(stat)


func upgrade_cost(stat: String) -> int:
	return Balance.get_int("stat_%s_cost" % stat, 15) * (level_of(stat) + 1)


func can_upgrade(stat: String) -> bool:
	return not is_max(stat) and GameManager.tokens >= upgrade_cost(stat)


## 토큰을 소모해 강화. 성공 시 true.
func try_upgrade(stat: String) -> bool:
	if not can_upgrade(stat):
		return false
	GameManager.tokens -= upgrade_cost(stat)
	if stat == "hp":
		hp_level += 1
	else:
		speed_level += 1
	return true


func _base(stat: String) -> float:
	return Balance.get_float("stat_%s_base" % stat, 100.0 if stat == "hp" else 280.0)


func _per_level(stat: String) -> float:
	return Balance.get_float("stat_%s_per_level" % stat, 20.0)


func to_dict() -> Dictionary:
	return {"hp_level": hp_level, "speed_level": speed_level}


func from_dict(d: Dictionary) -> void:
	hp_level = int(d.get("hp_level", 0))
	speed_level = int(d.get("speed_level", 0))
