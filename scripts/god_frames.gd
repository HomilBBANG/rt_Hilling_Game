class_name GodFrames
extends RefCounted
## god(구 벨라미) 캐릭터 애니메이션 프레임 빌더.
## 캠프·밤 세션이 같은 idle 프레임을 쓰도록 한 곳에서 구성.
## 경로: res://assets/characters/god/god_idle_N.png

static func build() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.set_animation_speed("idle", 2.0)
	var i := 0
	while ResourceLoader.exists("res://assets/characters/god/god_idle_%d.png" % i):
		frames.add_frame("idle", load("res://assets/characters/god/god_idle_%d.png" % i))
		i += 1
	return frames
