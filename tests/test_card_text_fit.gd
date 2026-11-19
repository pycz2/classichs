extends TestCase
## Card faces of every pack: no card's text sticks out of its box or runs into a gem, in Russian and English,
## at the hand's scale and the big card's (CardLayout: the Classic pack's written layouts, the others' fitted
## ones); a passive Hero Power shows no cost; an Unidentified item's related cards are its own variants.

const EXPANSIONS := "res://build/packs"  # tools/build_packs.sh (./run_tests.sh builds them)
const SCALES := [1.0, 1.9]  # the hand's card, the big card (the collection's; the match's is 1.8)


func _expansion(name: String) -> Pack:
	var f := ProjectSettings.globalize_path(EXPANSIONS) + "/%s.cardpack" % name
	return Pack.open(f, "imported") if FileAccess.file_exists(f) else null


func _use(p: Pack) -> void:
	Packs._active = p
	Packs._changed()


func _classic() -> void:
	Packs.set_active(Packs.all().filter(func(p): return p.id() == Packs.CLASSIC and p.builtin())[0])


func test_no_card_text_of_any_pack_sticks_out() -> void:
	var packs: Array = Packs.all().filter(func(p: Pack): return p.builtin())
	for f in DirAccess.get_files_at(ProjectSettings.globalize_path(EXPANSIONS)):
		if f.ends_with(".cardpack"):
			packs.append(_expansion(f.get_basename()))
	check(packs.size() >= 14, "the built-in packs and the expansions: %d" % packs.size())
	var bad := []
	var seen := {}  # card id|lang|text: one check for a text that many packs share
	for p: Pack in packs:
		_use(p)
		for id in CardDb.all_ids():
			for lang in ["ru", "en"]:
				var key := "%s|%s|%s|%s" % [id, lang, CardText.rich(id, CardText.hs_locale(lang)), CardText.name(id, CardText.hs_locale(lang))]
				if seen.has(key):
					continue
				seen[key] = true
				for k: float in SCALES:
					var pr := CardLayout.problems(id, lang, k).filter(func(x): return x != "no layout")
					if not pr.is_empty():
						bad.append("%s %s %s x%s %s" % [p.id(), id, lang, k, pr])
	_classic()
	eq(bad.slice(0, 10), [], "%d card faces stick out" % bad.size())


func test_a_text_with_game_values_is_fitted_anew() -> void:
	var p := _expansion("msg")
	if p == null:
		check(false, "build/packs/msg.cardpack (tools/build_packs.sh)")
		return
	_use(p)
	var args := ["4/4", ""]
	for lang in ["ru", "en"]:  # Jade Behemoth with a 4/4 Golem next: the "4" clear of the attack gem
		var e := CardLayout.entry("CFM_343", lang, args)
		for k in SCALES:
			var para := CardLayout.paragraph("CFM_343", lang, k, args)
			check(not CardLayout.ink_rects("CFM_343", lang, para, k, args).any(CardLayout._hits_gem), "%s x%s: clear of the gems %s" % [lang, k, e])
		check("".join(e.lines).contains("4/4"), "%s: the lines say 4/4: %s" % [lang, e.lines])
	_classic()


func test_an_unidentified_item_relates_only_to_its_own_variants() -> void:
	var p := _expansion("loot")
	if p == null:
		check(false, "build/packs/loot.cardpack (tools/build_packs.sh)")
		return
	_use(p)
	eq(CardDb.related("LOOT_285"), ["LOOT_285t", "LOOT_285t2", "LOOT_285t3", "LOOT_285t4"], "Unidentified Shield: its four shields")
	eq(CardDb.related("LOOT_286"), ["LOOT_286t1", "LOOT_286t2", "LOOT_286t3", "LOOT_286t4"], "Unidentified Maul: its four mauls")
	_classic()


func test_more_than_six_related_cards_turn_on_a_wheel() -> void:
	var ids := CardDb.all_ids().slice(0, 9)
	var w := KeywordTips.Wheel.new(ids)
	(Engine.get_main_loop() as SceneTree).root.add_child(w)
	eq(str(w.name), "Related", "the same name as the grid")
	eq(w.get_child_count(), 9, "every card on it")
	var y0: float = w.get_child(0).position.y
	w._process(0.5)
	check(w.get_child(0).position.y < y0, "the front row goes up")
	var shown := w.get_children().filter(func(c): return c.visible)
	check(shown.size() < 9 and shown.size() >= 6, "a row turned away is hidden: %d shown" % shown.size())
	var tips := KeywordTips.make("VAN_NEW1_031")  # Animal Companion: three, in a grid
	check(tips.find_child("Related", true, false) is GridContainer, "six or fewer stand still")
	tips.free()
	w.free()


func test_a_passive_hero_power_shows_no_cost() -> void:
	var p := _expansion("gil")
	if p == null:
		check(false, "build/packs/gil.cardpack (tools/build_packs.sh)")
		return
	_use(p)
	var bewitch := CardView.make("GIL_504h")
	var fireblast := CardView.make("VAN_HERO_08bp")
	check(not bewitch.shows_cost(), "Hagatha's Bewitch is passive: no cost on its card")
	check(fireblast.shows_cost(), "Fireblast has its cost")
	bewitch.free()
	fireblast.free()
	_classic()
