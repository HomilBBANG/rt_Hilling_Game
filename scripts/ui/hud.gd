extends Control
## 최소 HUD (PRD 7). 표시 정보는 최소한으로.
## 주의: trust(신뢰도)는 절대 표시하지 않는다(PRD 3.4 — 비노출).

@onready var _day_label: Label = $TopBar/DayLabel
@onready var _phase_label: Label = $TopBar/PhaseLabel


func _ready() -> void:
	GameManager.step_changed.connect(_on_step_changed)
	GameManager.day_changed.connect(_on_day_changed)
	_refresh()


func _on_step_changed(_step: int) -> void:
	_refresh()


func _on_day_changed(_day: int) -> void:
	_refresh()


func _refresh() -> void:
	_day_label.text = "Day %d" % GameManager.day
	_phase_label.text = _phase_text(GameManager.current_step)


func _phase_text(step: int) -> String:
	match step:
		GameManager.Step.MORNING_PREP:
			return "아침 · 준비"
		GameManager.Step.SCAVENGE:
			return "낮 · 탐사"
		GameManager.Step.NIGHT:
			return "밤 · 벨라미"
	return ""
