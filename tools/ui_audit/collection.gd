extends RefCounted
## The collection screen: the deck list (the pack's ready decks and two with long names), its popups
## (hero, start from a template, import, export, delete), the deck builder (a full 30-card deck of long
## names with tri-class cards), the collection browser (every class tab, every set, the other filters)
## and big cards (long texts, hero cards, tri-class, Spellstones, Unidentified items, Quests, weapons)
## with the pack's custom art, a few with its default art. At phone sizes only a few big cards.

## Big cards: long texts (Russian and English), tri-class, hero cards, Spellstones, Unidentified,
## Quests, Legendary weapons, and Jade Behemoth (its "4/4").
const BIG := ["CFM_343", "AT_112", "ICC_912", "OG_134", "OG_133", "OG_280", "OG_282", "OG_118", "LOOT_101",
	"LOOT_216", "LOOT_537", "UNG_035", "CFM_781", "GVG_056", "AT_104", "LOE_027", "AT_128",
	"CFM_621", "CFM_902", "CFM_685", "CFM_649", "CFM_715",
	"ICC_833", "ICC_828", "ICC_831", "ICC_830", "ICC_314",
	"LOOT_043", "LOOT_507", "LOOT_080", "LOOT_286", "LOOT_285",
	"UNG_940", "UNG_067", "UNG_942", "LOOT_108", "LOOT_542"]
const BIG_PHONE := ["CFM_343", "OG_134", "ICC_833", "LOOT_043"]
const DEFAULT_ART := ["CFM_343", "OG_134", "ICC_833", "LOOT_043", "CFM_621"]
const LONG_NAME := {"ru": "Нефритовый друид: очень длинное название колоды для проверки",
	"en": "Jade Druid with a really long name to check the deck list row"}
const LONG_NAME_2 := {"ru": "Кабал: маг из Прибамбасска с тремя классами и длинным именем",
	"en": "Kabal Mage of Gadgetzan, three classes and a long deck name"}

var a
var m: Node
var phone := false


func run(audit) -> void:
	a = audit
	phone = a.size.x < 1280
	a.root.gui_disable_input = true  # the real mouse never hovers (or unhovers) anything in the shots
	m = await a.open_game()
	Packs.set_choice(a.main_pack, "art", "custom")
	_decks_file()
	m.show_collection()
	await a.settle(0.8)
	var dl: DeckListView = m.screen
	await _deck_list(dl)
	await _builder(dl)
	await _browser(dl.browser)
	await _big_cards(dl.browser)
	if not phone:
		await _jade_in_hand()


## The player's decks: the pack's ready ones, a long-named Jade Druid and a full long-named Kabal Mage.
func _decks_file() -> void:
	var all: Array = Decks.templates().map(func(t): return t.deck.to_dict().merged({"name": t.name}, true))
	var druid: Dictionary = {}
	for t in Decks.templates():
		if t.deck.card_class() == "DRUID":
			druid = t.deck.to_dict()
	druid.name = LONG_NAME[a.lang]
	all.push_front(druid)
	all.push_front({"name": LONG_NAME_2[a.lang], "hero": Decks.hero("MAGE"), "cards": _kabal_cards()})
	DeckStore.write(DeckStore.file(), all)


## 30 cards a Mage can use: the three-class Kazakus and Kabal Courier, then the longest names.
func _kabal_cards() -> Array:
	var ids: Array = []
	for id in CardDb.collectible():
		var c := CardDb.card(id)
		var cl: Array = c.get("classes", [])
		if c.get("type", "") == "HERO" or id in ["CFM_621", "CFM_649"]:
			continue
		if (cl.is_empty() and str(c.get("cardClass", "")) in ["MAGE", "NEUTRAL"]) or cl.has("MAGE"):
			ids.append(id)
	ids.sort_custom(func(x, y): return CardText.name(x).length() > CardText.name(y).length())
	return ["CFM_621", "CFM_649", "CFM_649"] + ids.slice(0, 27)


func _deck_list(dl: DeckListView) -> void:
	await a.shot("decks", "Колоды: список (готовые колоды игры и две с длинными названиями)")
	var scroll := dl.list.get_parent() as ScrollContainer
	scroll.scroll_vertical = 100000
	await a.wait(0.3)
	await a.shot("decks_bottom", "Колоды: список прокручен до конца")
	scroll.scroll_vertical = 0
	dl._choose_hero()
	await a.settle(0.4)
	await a.shot("decks_hero", "Новая колода: выбор героя")
	dl.choose_start("DRUID")
	await a.settle(0.4)
	await a.shot("decks_templates", "Новая колода: с нуля или из готовой колоды (друид)")
	dl.choose_start("WARLOCK")
	await a.settle(0.4)
	await a.shot("decks_templates_warlock", "Новая колода: с нуля или из готовой колоды (чернокнижник)")
	dl._close()
	dl._show_import()
	await a.settle(0.3)
	await a.shot("decks_import", "Импорт кода колоды: пустое окно")
	var ed := dl.find_child("CodeInput", true, false) as TextEdit
	ed.text = "AAECAf0EBu0F7AfqrQKWuwKmvQL2xwIM"
	(dl.find_child("DoImport", true, false) as Button).pressed.emit()
	await a.settle(0.3)
	await a.shot("decks_import_error", "Импорт кода колоды: ошибка неверного кода")
	dl._close()
	var clip := DisplayServer.clipboard_get()  # (the export copies the code: the owner's clipboard comes back)
	dl.show_export(0)
	DisplayServer.clipboard_set(clip)
	await a.settle(0.3)
	await a.shot("decks_export", "Экспорт кода колоды (Кабал, 30 карт)")
	dl._close()
	dl._confirm_delete(1)
	await a.settle(0.3)
	await a.shot("decks_delete", "Вопрос перед удалением колоды с длинным названием")
	dl._close()
	dl.message.text = tr_("You have 100 decks on this server: delete one first")  # the longest message there is
	await a.settle(0.3)
	await a.shot("decks_message", "Колоды: строка сообщения под списком")
	dl.message.text = ""


func _builder(dl: DeckListView) -> void:
	dl.edit_deck(0)
	await a.settle(0.5)
	await a.shot("builder_full", "Редактор: полная колода мага (30 карт, трёхклассовые карты, длинные названия)")
	var tiles := dl.find_child("Tiles", true, false).get_parent() as ScrollContainer
	tiles.scroll_vertical = 100000
	await a.wait(0.3)
	await a.shot("builder_full_bottom", "Редактор: список карт колоды прокручен до конца")
	dl.browser.click_card(dl.browser.shown_cards()[0])  # a full deck: the hint why
	await a.settle(0.3)
	await a.shot("builder_full_hint", "Редактор: подсказка при добавлении в полную колоду")
	dl.browser.set_tab("NEUTRAL")
	dl.browser.query = ""
	await a.settle(0.3)
	await a.shot("builder_neutral", "Редактор: вкладка нейтральных карт")
	var name_edit := dl.find_child("DeckName", true, false) as LineEdit
	name_edit.text = LONG_NAME_2[a.lang] + " ещё длиннее"
	await a.wait(0.2)
	await a.shot("builder_name_field", "Редактор: поле названия с длинным текстом (обрезано до 60 знаков)")
	dl.close_deck()
	await a.settle(0.3)
	dl.edit_deck(1)  # the long-named druid (a ready deck)
	await a.settle(0.5)
	await a.shot("builder_druid", "Редактор: нефритовый друид с длинным названием")
	dl.close_deck()
	dl.new_deck(Decks.hero("ROGUE"))
	await a.settle(0.5)
	await a.shot("builder_empty", "Редактор: новая пустая колода разбойника")
	for id in dl.browser.shown_cards().slice(0, 3):
		dl.browser.click_card(id)
		dl.browser.click_card(id)
	dl.browser.click_card(dl.browser.shown_cards()[0])  # the third copy: the hint why not
	await a.settle(0.3)
	await a.shot("builder_third_copy", "Редактор: подсказка при третьей копии карты")
	dl.close_deck()
	dl.delete_deck(dl.decks.size() - 1)
	await a.settle(0.3)


func _browser(c: CollectionView) -> void:
	for cls in Decks.classes_and_neutral():
		if phone and not cls in ["DRUID", "NEUTRAL"]:
			continue
		c.set_tab(cls)
		await a.settle(0.3)
		await a.shot("tab_" + cls.to_lower(), "Коллекция: вкладка " + cls)
	var pick := c.find_child("SetFilter", true, false) as OptionButton
	if pick == null:
		a.error("no set filter")
		return
	pick.show_popup()
	await a.wait(0.4)
	await a.shot("set_list", "Коллекция: открытый список наборов")
	pick.get_popup().hide()
	var keys := CollectionView.set_keys()
	for i in keys.size():
		if phone and i % 4 != 0:
			continue
		pick.select(i + 1)
		pick.item_selected.emit(i + 1)
		var best := "NEUTRAL"
		var most := -1
		for cls in Decks.classes_and_neutral():  # the tab with the most cards of the set
			c.tab = cls
			var n := c.filtered().size()
			if n > most:
				most = n
				best = cls
		c.set_tab(best)
		await a.settle(0.3)
		await a.shot("set_" + str(keys[i]).replace(":", "_").to_lower(), "Коллекция: фильтр по набору " + str(keys[i]))
	pick.select(0)
	pick.item_selected.emit(0)
	c.set_tab("WARLOCK")
	for spec in [["TypeSPELL", "type_spells"], ["Cost7", "cost_7"], ["RarityLEGENDARY", "rarity_legendary"]]:
		(c.find_child(spec[0], true, false) as Button).pressed.emit()
		await a.settle(0.3)
		await a.shot("filter_" + spec[1], "Коллекция: чернокнижник, фильтры добавляются один к другому: " + spec[1])
	(c.find_child("TypeSPELL", true, false) as Button).pressed.emit()
	(c.find_child("RarityLEGENDARY", true, false) as Button).pressed.emit()
	(c.find_child("Cost-1", true, false) as Button).pressed.emit()
	var search := c.find_child("Search", true, false) as LineEdit
	search.text = "zzzz нет такой карты"
	search.text_changed.emit(search.text)
	await a.settle(0.3)
	await a.shot("filter_empty", "Коллекция: поиск без результатов")
	search.text = tr_("Deathrattle").left(6) if tr_("Deathrattle") != "" else "Death"
	search.text_changed.emit(search.text)
	c.set_tab("NEUTRAL")
	await a.settle(0.3)
	await a.shot("filter_search", "Коллекция: поиск по тексту, нейтральные")
	search.text = ""
	search.text_changed.emit("")
	c.set_tab("NEUTRAL")
	c.turn_page(c.page_count())
	await a.settle(0.3)
	await a.shot("last_page", "Коллекция: нейтральные, последняя страница")
	c.turn_page(-c.page_count())


## A card shown big (as tools/expansions_shots.gd: found by its name on its class tab, then hovered).
func _big(c: CollectionView, id: String, suffix := "") -> void:
	if CardDb.card(id).is_empty():
		a.error("no card " + id)
		return
	var card := CardDb.card(id)
	var classes: Array = card.get("classes", [])
	c.set_tab(str(classes[0]) if not classes.is_empty() else str(card.get("cardClass", "NEUTRAL")))
	var search := c.find_child("Search", true, false) as LineEdit
	search.text = CardText.name(id)
	search.text_changed.emit(search.text)
	var at := c.filtered().find(id)
	if at >= 0:
		c.turn_page(at / CollectionView.PER_PAGE - c.page)
	await a.process_frame
	var hit: CardView = null
	for v in c._grid.get_children():
		if v.card_id == id:
			hit = v
	if hit == null:
		a.error("%s is not in the collection" % id)
	else:
		await a.settle(0.3)
		c._on_hover(hit, true)
		await a.wait(0.5)
		await a.shot("card_" + id + suffix, "Большая карта: %s (%s)" % [CardText.name(id), id])
		c._on_hover(null, false)
	search.text = ""
	search.text_changed.emit("")


func _big_cards(c: CollectionView) -> void:
	for id in (BIG_PHONE if phone else BIG):
		await _big(c, id)
	if phone:
		return
	var other := ""
	for st in a.main_pack.sets("art"):
		if str(st.id) != "custom" and other == "":
			other = str(st.id)
	print("default art: ", other, " of ", a.main_pack.sets("art"))
	Packs.set_choice(a.main_pack, "art", other)
	c._fill()
	for id in DEFAULT_ART:
		await _big(c, id, "_defart")
	Packs.set_choice(a.main_pack, "art", "custom")


## Jade Behemoth in the hand after three Jade Golems (its text says 4/4), shown big under the mouse (the
## match's hand card rises where the mouse is: one warp of the real cursor, at 1280x720 only).
func _jade_in_hand() -> void:
	var sc := JSON.parse_string(FileAccess.get_file_as_string("res://tools/expansions_report/msg.json")) as Dictionary
	var jade: Dictionary = {}
	for x in sc.scenes:
		if x.name == "jade":
			jade = x
	var v: MatchView = m.start_match({"scenario": jade.scene}, [false, false], false)
	await a.settle(0.6)
	for st in jade.steps:
		v.controller.submit(CardTests.action(v.controller, st))
		await a.settle(0.5)
	var hand: Array = v.g.players[v.viewer()].hand
	var f: Dictionary = TableLayout.hand(hand.size(), true)[0]
	a.root.warp_mouse(Vector2(f.pos.x + CardView.SIZE.x * f.scale / 2.0, 700))
	await a.wait(0.8)
	await a.shot("match_jade_behemoth", "Нефритовое чудище в руке после трёх големов: в тексте голем 4/4")
	a.root.warp_mouse(Vector2(640, 330))
	m.show_game_menu()
	await a.settle(0.3)


func tr_(s: String) -> String:
	return TranslationServer.translate(s)
