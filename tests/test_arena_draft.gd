extends TestCase
## The Arena draft wrapper over the engine's `draft` op (its odds and rules are
## tested in Rust): 3 heroes, 30 picks of 3 cards, an Arena deck without copy limits.


func _drafted(seed: int) -> ArenaDraft:
	var d := ArenaDraft.new(seed)
	d.choose_hero(0)
	while not d.done():
		d.pick(0)
	return d


func test_three_different_heroes_are_offered() -> void:
	for seed in 20:
		var d := ArenaDraft.new(seed)
		eq(d.heroes.size(), 3, "three heroes")
		var classes := d.heroes.map(func(h): return Decks.card_class(h))
		check(classes[0] != classes[1] and classes[1] != classes[2] and classes[0] != classes[2], "different classes")
		for h in d.heroes:
			check(Decks.HEROES.values().has(h), "a hero card: " + h)
	eq(d_offer_before_hero(), 0, "no cards before a hero is chosen")


func d_offer_before_hero() -> int:
	return ArenaDraft.new(1).offer.size()


func test_every_offer_is_three_cards_of_one_rarity_for_the_class() -> void:
	for seed in 3:
		var d := ArenaDraft.new(seed)
		d.choose_hero(seed % 3)
		var cls := Decks.card_class(d.hero)
		while not d.done():
			eq(d.offer.size(), 3, "three cards")
			check(d.offer[0] != d.offer[1] and d.offer[1] != d.offer[2] and d.offer[0] != d.offer[2], "three different cards")
			var tiers := d.offer.map(func(id): return ArenaDraft.tier(id))
			check(tiers[0] == tiers[1] and tiers[1] == tiers[2], "one rarity: %s" % [tiers])
			for id in d.offer:
				var c := CardDb.card(id)
				check(CardDb.collectible().has(id) and c.type != "HERO", "a collectible card: " + id)
				check(c.cardClass == cls or c.cardClass == "NEUTRAL", "the hero's class or neutral: " + id)
			d.pick(seed % 3)


func test_a_full_draft_is_a_valid_arena_deck() -> void:
	var d := _drafted(7)
	eq(d.cards.size(), 30, "30 cards")
	var deck := d.deck()
	check(deck.arena, "an Arena deck")
	eq(deck.hero, d.hero, "the chosen hero")
	eq(deck.validate(), "", "valid")


func test_the_same_seed_gives_the_same_draft() -> void:
	eq(_drafted(42).cards, _drafted(42).cards, "deterministic")
	check(_drafted(42).cards != _drafted(43).cards, "another seed, another draft")


func test_arena_decks_have_no_copy_limit() -> void:
	var deck := Deck.new()
	deck.hero = "HERO_08"
	deck.arena = true
	for i in 3:
		eq(deck.add("VAN_CS2_029"), "", "a third Fireball is fine")
	for i in 2:
		eq(deck.add("VAN_EX1_559"), "", "two Antonidas are fine")
	var plain := Deck.new()
	plain.hero = "HERO_08"
	plain.add("VAN_CS2_029")
	plain.add("VAN_CS2_029")
	check(plain.add("VAN_CS2_029") != "", "a normal deck keeps the limit")
	var back := Deck.from_dict(deck.to_dict())
	check(back.arena, "the flag survives saving")
	check(Deck.from_dict({"hero": "HERO_08", "cards": ["VAN_CS2_029", "VAN_CS2_029", "VAN_CS2_029"], "arena": true}).arena, "and loading")


func test_tier_helper() -> void:
	eq([ArenaDraft.tier("VAN_CS2_029"), ArenaDraft.tier("VAN_CS2_231"), ArenaDraft.tier("VAN_EX1_559")], ["common", "common", "legendary"], "Basic counts as common")


func test_mana_curve() -> void:
	var d := ArenaDraft.new(3)
	d.cards.assign(["VAN_CS2_027", "VAN_CS2_029", "VAN_CS2_029", "VAN_CS2_032", "VAN_EX1_279"])  # 1, 4, 4, 7, 10
	eq(d.curve(), [0, 1, 0, 0, 2, 0, 0, 2], "costs 0..6 and 7+")
