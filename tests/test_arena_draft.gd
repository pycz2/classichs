extends TestCase
## The Arena draft (2014 rules): 3 heroes to choose from, 30 picks of 3 cards of
## one rarity, Rare or better at picks 1, 10, 20 and 30, class cards more likely,
## no limit on copies.


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
	for seed in 10:
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


func test_picks_1_10_20_30_are_rare_or_better() -> void:
	for seed in 30:
		var d := ArenaDraft.new(seed)
		d.choose_hero(0)
		var n := 0
		while not d.done():
			if n in [0, 9, 19, 29]:
				check(ArenaDraft.tier(d.offer[0]) != "common", "pick %d is rare or better" % (n + 1))
			d.pick(1)
			n += 1


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


func test_rarity_odds() -> void:
	# normal picks: 76.5 % common, 14 % rare, 7.5 % epic, 2 % legendary
	var d := ArenaDraft.new(5)
	var count := {}
	for i in 20000:
		var t := d.roll_tier(false)
		count[t] = count.get(t, 0) + 1
	var share := func(t: String) -> float: return float(count.get(t, 0)) / 20000.0
	check(absf(share.call("common") - 0.765) < 0.015, "about 76.5 %% common: %s" % share.call("common"))
	check(absf(share.call("rare") - 0.14) < 0.01, "about 14 %% rare: %s" % share.call("rare"))
	check(absf(share.call("epic") - 0.075) < 0.008, "about 7.5 %% epic: %s" % share.call("epic"))
	check(absf(share.call("legendary") - 0.02) < 0.005, "about 2 %% legendary: %s" % share.call("legendary"))
	# picks 1, 10, 20, 30: 65 % rare, 27 % epic, 8 % legendary
	count.clear()
	for i in 20000:
		var t := d.roll_tier(true)
		count[t] = count.get(t, 0) + 1
	eq(count.get("common", 0), 0, "a special pick is never common")
	check(absf(share.call("epic") - 0.27) < 0.015, "about 27 %% epic: %s" % share.call("epic"))
	check(absf(share.call("legendary") - 0.08) < 0.01, "about 8 %% legendary: %s" % share.call("legendary"))


func test_class_cards_come_more_often() -> void:
	# common tier for a Mage: class cards weigh 1.5, neutral cards 1
	var pool := ArenaDraft.pool("MAGE", "common")
	var cls := 0
	var neu := 0
	for it in pool:
		if CardDb.card(it[0]).cardClass == "MAGE":
			cls += 1
			eq(it[1], 1.5, "class weight")
		else:
			neu += 1
			eq(it[1], 1.0, "neutral weight")
	check(cls > 0 and neu > 0, "both kinds in the pool")
	var d := ArenaDraft.new(9)
	d.hero = "HERO_08"
	var seen := 0
	var mage := 0
	for i in 600:
		for id in d.roll_offer("common"):
			seen += 1
			if CardDb.card(id).cardClass == "MAGE":
				mage += 1
	var expected := 1.5 * cls / (1.5 * cls + neu)
	check(absf(float(mage) / seen - expected) < 0.05, "class share %.2f, expected %.2f" % [float(mage) / seen, expected])


func test_mana_curve() -> void:
	var d := ArenaDraft.new(3)
	d.hero = "HERO_08"
	d.cards.assign(["VAN_CS2_027", "VAN_CS2_029", "VAN_CS2_029", "VAN_CS2_032", "VAN_EX1_279"])  # 1, 4, 4, 7, 10
	eq(d.curve(), [0, 1, 0, 0, 2, 0, 0, 2], "costs 0..6 and 7+")
