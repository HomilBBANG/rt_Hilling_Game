extends Node
## 루트 씬. 페이즈 씬을 담는 PhaseContainer 를 GameManager 에 등록하고,
## 영속 UI(HUD)는 UILayer(CanvasLayer)에 유지한다.

func _ready() -> void:
	GameManager.register_phase_container($PhaseContainer)
	# 로비에서 지정한 모드대로 시작. 직접 실행 등으로 모드가 없으면
	# 세이브 유무로 자동 판단(이어하기/새 게임, PRD 3.7).
	var mode := GameManager.boot_mode
	GameManager.boot_mode = "" # 소비
	match mode:
		"new":
			GameManager.start_new_game()
		"load":
			GameManager.continue_game()
		_:
			if SaveManager.has_save():
				GameManager.continue_game()
			else:
				GameManager.start_new_game()
