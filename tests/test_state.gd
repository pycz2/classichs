extends TestCase


func test_summon_places_and_logs() -> void:
	var g := H.state()
	var a := g.summon(0, "VAN_CS2_231")
	var b := g.summon(0, "VAN_CS2_231", 0)
	eq(g.players[0].board, [b, a], "pos 0 inserts left")
	check(a.has("EXHAUSTED"), "summoning sickness")
	check(b.play_order > a.play_order, "play order grows")
	eq(H.types(g.event_log).count("summon"), 2, "summon events")


func test_board_limit() -> void:
	var g := H.state()
	for i in 7:
		g.summon(0, "VAN_CS2_231")
	eq(g.summon(0, "VAN_CS2_231"), null, "8th summon fails")


func test_damage_and_death_phase() -> void:
	var g := H.state()
	var w := g.summon(1, "VAN_CS2_231")
	g.damage(g.players[0].hero, w, 1)
	eq(w.zone, "PLAY", "not dead before resolve")
	g.resolve()
	eq(w.zone, "GRAVEYARD", "dead after resolve")
	check(H.types(g.event_log).has("death"), "death event")


func test_divine_shield_absorbs() -> void:
	var g := H.state()
	var m := g.summon(1, "VAN_CS2_231")
	m.give_tag("DIVINE_SHIELD")
	eq(g.damage(g.players[0].hero, m, 5), 0, "no damage")
	check(not m.has("DIVINE_SHIELD"), "shield popped")
	eq(m.health(), 1, "health kept")


func test_armor_absorbs_hero_damage() -> void:
	var g := H.state()
	var hero := g.players[1].hero
	g.gain_armor(1, 3)
	eq(g.damage(g.players[0].hero, hero, 5), 2, "2 through armor")
	eq(hero.tags.ARMOR, 0, "armor spent")
	eq(hero.health(), 28, "hero hp")


func test_heal_caps_at_max() -> void:
	var g := H.state()
	var hero := g.players[0].hero
	hero.damage = 3
	eq(g.heal(hero, hero, 5), 3, "healed 3")
	eq(hero.health(), 30, "full")
	eq(g.heal(hero, hero, 5), 0, "no heal event at full health")


func test_trigger_order_by_play_order() -> void:
	var g := H.state()
	var seen: Array[int] = []
	H.card("TEST_LISTENER", {"type": "MINION", "attack": 1, "health": 5},
		{"on": {"damage": func(_g, me, _ev): seen.append(me.id)}})
	var a := g.summon(0, "TEST_LISTENER")
	var b := g.summon(1, "TEST_LISTENER")
	g.damage(g.players[0].hero, g.players[1].hero, 1)
	g.resolve()
	eq(seen, [a.id, b.id], "play order")


func test_deathrattle_after_death_at_same_position() -> void:
	var g := H.state()
	H.card("TEST_DR", {"type": "MINION", "attack": 1, "health": 1},
		{"deathrattle": func(g2, me, _ev): g2.summon(me.controller, "VAN_CS2_231", me.tags.DIED_POS)})
	var left := g.summon(0, "VAN_CS2_231")
	var dr := g.summon(0, "TEST_DR")
	var right := g.summon(0, "VAN_CS2_231")
	g.destroy(dr)
	g.resolve()
	var board := g.players[0].board
	eq(board.size(), 3, "replaced")
	eq(board[0], left, "left kept")
	eq(board[2], right, "right kept")
	eq(board[1].card_id, "VAN_CS2_231", "summoned in the middle")


func test_simultaneous_deaths() -> void:
	var g := H.state()
	var dead: Array[int] = []
	H.card("TEST_DR2", {"type": "MINION", "attack": 1, "health": 1},
		{"deathrattle": func(_g, me, _ev): dead.append(me.id)})
	var a := g.summon(0, "TEST_DR2")
	var b := g.summon(1, "TEST_DR2")
	for m in g.all_minions():
		g.damage(g.players[0].hero, m, 1)
	g.resolve()
	eq(dead, [a.id, b.id], "both deathrattles in play order")


func test_aura_and_its_loss() -> void:
	var g := H.state()
	H.card("TEST_AURA", {"type": "MINION", "attack": 1, "health": 1},
		{"aura": func(g2, me):
			for m in g2.minions(me.controller):
				if m != me:
					g2.aura_add(m, 1, 1)})
	var w := g.summon(0, "VAN_CS2_231")
	var lord := g.summon(0, "TEST_AURA")
	g.resolve()
	eq([w.atk(), w.max_health()], [2, 2], "aura applied")
	g.damage(lord, w, 1)
	g.destroy(lord)
	g.resolve()
	eq(w.zone, "PLAY", "aura loss never kills")
	eq(w.health(), 1, "hp 1")


func test_spell_damage_and_velen_style_doubling() -> void:
	var g := H.state()
	g.summon(0, "VAN_CS2_142")  # Kobold Geomancer, Spell Damage +1
	g.resolve()
	eq(g.spell_dmg(g.players[0].hero, 3), 4, "spell damage +1")
	eq(g.spell_dmg(g.players[1].hero, 3), 3, "enemy spell damage does not count")


func test_targets_respect_stealth_and_elusive() -> void:
	var g := H.state()
	var st := g.summon(1, "VAN_CS2_231")
	st.give_tag("STEALTH")
	var el := g.summon(1, "VAN_CS2_231")
	el.give_tag("ELUSIVE")
	var src := g.players[0].hero
	var spell_targets := g.targets(src, T.ENEMY_MINION, true)
	eq(spell_targets, [], "no spell targets")
	eq(g.targets(src, T.ENEMY_MINION, false), [el], "battlecry can hit elusive")


func test_trigger_loop_is_bounded() -> void:
	var g := H.state()
	H.card("TEST_LOOP", {"type": "MINION", "attack": 1, "health": 30},
		{"on": {"heal": func(g2, me, _ev): g2.emit({"type": "heal", "target": me.id, "amount": 1})}})
	g.summon(0, "TEST_LOOP")
	g.emit({"type": "heal", "target": 0, "amount": 1})
	g.resolve()
	check(g.queue.is_empty(), "queue stopped")


func test_both_heroes_die_is_draw() -> void:
	var g := H.state()
	for p in 2:
		g.damage(null, g.players[p].hero, 30)
	g.resolve()
	check(g.game_over, "over")
	eq(g.winner, -1, "draw")


func test_shuffle_is_deterministic() -> void:
	var a := H.state(5)
	var b := H.state(5)
	var arr1 := range(30)
	var arr2 := range(30)
	a.shuffle(arr1)
	b.shuffle(arr2)
	eq(arr1, arr2, "same seed same order")
	check(arr1 != range(30), "order changed")
