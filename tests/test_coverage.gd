extends TestCase

## Text parts the engine handles from card data (mechanics, spellDamage, overload).
const KEYWORDS := ["taunt", "charge", "divine shield", "stealth", "windfury", "elusive", "can't attack"]
## Cards whose effect lives outside the rules engine.
const NO_HOOK := ["VAN_EX1_560"]  # Nozdormu: turn timer belongs to UI/network


static func _clean(t: String) -> String:
	var re := RegEx.create_from_string("<[^>]+>|\\[x\\]")
	return re.sub(t, "", true).strip_edges()


static func _keyword_only(c: Dictionary) -> bool:
	var text := _clean(c.get("text", {}).get("enUS", "")).to_lower().replace("\n", ",")
	for part in text.split(".", false):
		for p2 in part.split(",", false):
			var p := p2.strip_edges()
			if p == "" or KEYWORDS.has(p) or p.begins_with("spell damage +") or p.begins_with("overload: ("):
				continue
			return false
	return true


func test_keyword_filter_examples() -> void:
	check(_keyword_only(CardDb.card("VAN_EX1_067")), "Argent Commander: newline-separated keywords")
	check(_keyword_only(CardDb.card("VAN_EX1_045")), "Ancient Watcher: can't attack")
	check(not _keyword_only(CardDb.card("VAN_CS2_029")), "Fireball has an effect")


func test_every_collectible_card_with_effect_has_hook() -> void:
	var missing := []
	for id in CardDb.collectible():
		var c := CardDb.card(id)
		if _keyword_only(c) or NO_HOOK.has(id):
			continue
		if Cards.of(id).is_empty():
			missing.append("%s %s" % [id, c.name.enUS])
	eq(missing, [], "cards without hooks")


func test_every_hero_power_used_in_classic_has_hook() -> void:
	for id in GameState.HERO_POWERS.values() + ["VAN_EX1_tk33", "EX1_625t", "EX1_625t2"]:
		check(Cards.of(id).has("hero_power"), "hero power " + id)


func test_hooks_reference_known_cards() -> void:
	for id: String in Cards.all_ids():
		if id.begins_with("ench:"):
			continue
		check(CardDb.has(id), "hook for unknown card " + id)


func test_summoned_and_equipped_ids_exist() -> void:
	var re := RegEx.create_from_string("\"((?:VAN_|EX1_|NEW1_|CS2_|PRO_|GAME_|Mekka|ds1_|hexfrog)[A-Za-z0-9_]*)\"")
	for f in Cards.FILES:
		var src := FileAccess.get_file_as_string("res://cards/%s.gd" % f)
		for m in re.search_all(src):
			check(CardDb.has(m.get_string(1)), "%s.gd references unknown card %s" % [f, m.get_string(1)])
