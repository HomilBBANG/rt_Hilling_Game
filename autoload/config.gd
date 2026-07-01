extends Node
## 전역 표시/디버그 설정.
##
## show_gauges: 벨라미 만족 게이지 등 '정량 수치'를 화면에 노출할지 여부.
##   - true  : 테스트용 — 만족 게이지/수치를 그대로 보여줌(현재 기본값).
##   - false : PRD 3.4 방향 — 게이지/수치를 숨기고 벨라미의 표정/행동(정성적 피드백)만 남김.
##
## 나중에 숨기려면 이 값을 false 로 바꾸거나, 런타임에서 Config.show_gauges = false 로 토글.
## (게이지를 '지우는' 게 아니라 '가리는' 방식이라, 언제든 다시 켤 수 있음.)

signal gauges_visibility_changed(visible: bool)

var show_gauges: bool = true:
	set(value):
		if show_gauges == value:
			return
		show_gauges = value
		gauges_visibility_changed.emit(value)
