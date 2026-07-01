extends Node
## 루트 씬. 페이즈 씬을 담는 PhaseContainer 를 GameManager 에 등록하고,
## 영속 UI(HUD)는 UILayer(CanvasLayer)에 유지한다.

func _ready() -> void:
	GameManager.register_phase_container($PhaseContainer)
	# 세이브가 있으면 해당 페이즈 시작점부터 이어하기, 없으면 새 게임(PRD 3.7).
	if SaveManager.has_save():
		GameManager.continue_game()
	else:
		GameManager.start_new_game()
