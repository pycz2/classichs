class_name Anim
extends RefCounted
## Animation timing. Every duration goes through d(): it is divided by the speed
## from the settings (1x to 4x). Tests set instant, and every duration becomes 0.

static var instant := false


static func speed() -> float:
	return clampf(float(Settings.data.get("anim_speed", 1)), 1.0, 4.0)


static func d(seconds: float) -> float:
	return 0.0 if instant else seconds / speed()
