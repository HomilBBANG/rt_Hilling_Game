class_name PlayerFrames
extends RefCounted
## 플레이어 애니메이션 프레임(idle / run) 공용 빌더.
## 탐사 플레이어 · 캠프 · 밤 세션이 모두 같은 프레임을 쓰도록 한 곳에서 구성.

## idle_name: idle 프레임 폴더/접두사. 기본 "idle"(탐사용).
## 요리·캠프는 "idle_hand" 를 넘겨 손 든 대기 모션을 쓴다.
## 프레임 경로: res://assets/characters/<idle_name>/<idle_name>_N.png
static func build(idle_name := "idle") -> SpriteFrames:
	var frames := SpriteFrames.new()

	frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.set_animation_speed("idle", 2.5)
	_load(frames, "idle", "res://assets/characters/%s/%s_%%d.png" % [idle_name, idle_name])
	if frames.get_frame_count("idle") == 0 and idle_name != "idle": # 폴백: 기본 idle
		_load(frames, "idle", "res://assets/characters/idle/idle_%d.png")
	if frames.get_frame_count("idle") == 0: # 폴백: 정지 스프라이트
		var t: Texture2D = load("res://assets/characters/player.png")
		if t:
			frames.add_frame("idle", t)

	frames.add_animation("run")
	frames.set_animation_loop("run", true)
	frames.set_animation_speed("run", 10.0)
	_load(frames, "run", "res://assets/characters/run/run_%d.png")

	return frames


static func _load(frames: SpriteFrames, anim: String, pattern: String) -> void:
	var i := 0
	while true:
		var p := pattern % i
		if not ResourceLoader.exists(p):
			break
		frames.add_frame(anim, load(p))
		i += 1
