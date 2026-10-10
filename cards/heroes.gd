extends RefCounted


static func register(r: Dictionary) -> void:
	r["VAN_HERO_08bp"] = {  # Fireblast
		"target": T.ANY,
		"hero_power": func(g, me, t): g.damage(me, t, g.hp_dmg(me, 1)),
	}
