extends Node
## [개발 편의] 게임 실행 시 data/*.xlsx → *.json 을 자동 변환한다.
## Balance/MonsterDB/NpcUnlockDB 가 json 을 읽기 전에 최신값으로 갱신하므로,
## 엑셀에서 값을 고치고 '저장 → 게임 실행'만 하면 반영된다(수동 convert 불필요).
##
## 제약: Excel 이 해당 .xlsx 를 '열어 둔 채'면 파일이 잠겨 변환 실패 → 저장 후 닫아야 함.
## 배포(export) 빌드에는 python/xlsx 가 없으므로 에디터/개발 실행에서만 동작한다.
## 오토로드 순서상 Balance 보다 먼저 와야 한다(project.godot [autoload] 첫 줄).

const CONVERTERS := [
	"tools/convert_balance.py",
	"tools/convert_monsters.py",
	"tools/convert_npc_unlocks.py",
	"tools/convert_weapons.py",
	"tools/convert_items.py",
]


func _ready() -> void:
	if not OS.has_feature("editor"):
		return # 배포 빌드에서는 건너뜀
	var root := ProjectSettings.globalize_path("res://")
	for script in CONVERTERS:
		_run(root.path_join(script))


func _run(script_path: String) -> void:
	# python(또는 py 런처)로 변환기 실행. 블로킹(true)이라 json 이 갱신된 뒤 진행된다.
	for exe in ["python", "py"]:
		var out: Array = []
		var code := OS.execute(exe, [script_path], out, true)
		if code == -1:
			continue # 이 실행파일을 못 찾음 → 다음 후보
		if code != 0:
			push_warning("[DataImport] 변환 실패(%s):\n%s" % [script_path, "\n".join(out)])
		return
	push_warning("[DataImport] python 을 찾지 못해 자동 변환을 건너뜀: %s" % script_path)
