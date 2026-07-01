extends Node
## NPC 부활/배치 관리 (PRD 3.5).
## 부활은 '누적 만족도(총 만족도)'가 해금 표(NpcUnlockDB, 엑셀 연동)의 임계값을
## 넘을 때 발생. 임계값/대상은 data/npc_unlocks.xlsx 에서 설정한다.

signal npc_revived(npc_id: String)

const PLACEMENT_SLOTS := ["kitchen", "serving"]

var revived_ids: Array[String] = []
var placement := {"kitchen": "", "serving": ""}


## 누적 만족도에 따라, 아직 부활하지 않은 NPC 중 임계값을 넘긴 대상을 부활시킨다.
## 새로 부활한 npc_id 목록 반환(임계값 오름차순).
func check_unlocks(total_satisfaction: float) -> Array[String]:
	var newly: Array[String] = []
	for entry in NpcUnlockDB.entries: # 임계값 오름차순 정렬됨
		var npc_id := String(entry.get("npc_id", ""))
		if npc_id == "":
			continue
		if total_satisfaction >= float(entry.get("threshold", 0)) and npc_id not in revived_ids:
			revived_ids.append(npc_id)
			npc_revived.emit(npc_id)
			newly.append(npc_id)
	return newly


func is_revived(npc_id: String) -> bool:
	return npc_id in revived_ids


func assign(slot: String, npc_id: String) -> void:
	if slot in placement:
		placement[slot] = npc_id


func to_dict() -> Dictionary:
	return {"revived": revived_ids, "placement": placement}


func from_dict(d: Dictionary) -> void:
	revived_ids = []
	for v in d.get("revived", []):
		revived_ids.append(String(v))
	placement = d.get("placement", {"kitchen": "", "serving": ""})
