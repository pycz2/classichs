class_name Sim
extends RefCounted
## Random-play harness for tests. Uses its own RNG; the engine RNG stays separate.

const CLASSES := {"HERO_01": "WARRIOR", "HERO_02": "SHAMAN", "HERO_03": "ROGUE",
	"HERO_04": "PALADIN", "HERO_05": "HUNTER", "HERO_06": "DRUID", "HERO_07": "WARLOCK",
	"HERO_08": "MAGE", "HERO_09": "PRIEST"}


static func random_deck(rng: RandomNumberGenerator, card_class: String) -> Array:
	var pool: Array = CardDb.collectible().filter(func(id: String) -> bool:
		var c := CardDb.card(id)
		return c.cardClass == card_class or c.cardClass == "NEUTRAL")
	var deck: Array = []
	while deck.size() < 30:
		var id: String = pool[rng.randi_range(0, pool.size() - 1)]
		var limit := 1 if CardDb.card(id).get("rarity", "") == "LEGENDARY" else 2
		if deck.count(id) < limit:
			deck.append(id)
	return deck


static func play_random(seed: int, max_steps := 400) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var heroes := CLASSES.keys()
	var h0: String = heroes[rng.randi_range(0, 8)]
	var h1: String = heroes[rng.randi_range(0, 8)]
	var g := Game.new({"hero": h0, "deck": random_deck(rng, CLASSES[h0])},
		{"hero": h1, "deck": random_deck(rng, CLASSES[h1])}, seed)
	var actions := []
	var hashes := []
	for i in max_steps:
		var legal := g.legal_actions()
		if legal.is_empty():
			break
		# Prefer anything over end_turn/concede so games progress.
		var useful := legal.filter(func(a: Dictionary) -> bool: return a.type != "concede")
		if useful.size() > 1 and rng.randf() < 0.85:
			useful = useful.filter(func(a: Dictionary) -> bool: return a.type != "end_turn")
		var a: Dictionary = useful[rng.randi_range(0, useful.size() - 1)]
		var r := g.apply(a)
		assert(r.ok, r.error)
		actions.append(a)
		hashes.append(g.state_hash())
	return {"actions": actions, "hashes": hashes, "game": g}
