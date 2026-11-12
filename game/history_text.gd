class_name HistoryText
extends RefCounted
## Human-readable lines for match history entries. Cards the viewer may not
## see (the opponent's draws and hand additions, the opponent's Secrets) stay hidden.

## Event types that produce no line (they repeat other events).
const SILENT := ["after_summon", "after_spell", "after_attack", "turn_end", "mulligan_chosen", "create", "game_start"]


static func _t(s: String) -> String:
	return TranslationServer.translate(s)


static func _you(p: int, viewer: int) -> bool:
	return p == viewer


static func _who(p: int, viewer: int) -> String:
	return _t("You") if _you(p, viewer) else _t("Opponent")


## "You play X" / "Opponent plays X": separate keys keep translations natural.
static func _say(p: int, viewer: int, mine: String, theirs: String, args: Array) -> String:
	return (_t(mine) if _you(p, viewer) else _t(theirs)) % args


static func _name(g: GameView, id: int, loc: String) -> String:
	var e := g.ent(id)
	return CardText.name(e.card_id, loc) if e else "?"


## The card a to_deck event names: its own, or the one whose effect shuffles itself back (Kingsbane's Deathrattle: it
## was in sight of both); "" = hidden.
static func _deck_card(ev: Dictionary) -> String:
	var c := str(ev.get("card", ""))
	return c if c != "" or int(ev.get("by_id", -1)) != int(ev.get("entity", -2)) else str(ev.get("by", ""))


## Lines for one history entry ({"turn", "player", "action", "events"}).
static func lines(entry: Dictionary, g: GameView, viewer: int, loc := "") -> Array[String]:
	var out: Array[String] = []
	for r in rows(entry, g, viewer, loc):
		out.append(r.text)
	return out


## Rows {"text", "turn": bool} — "turn" marks the turn header line (for styling).
static func rows(entry: Dictionary, g: GameView, viewer: int, loc := "") -> Array:
	var out: Array = []
	var played := {}
	var chosen: bool = entry.action.get("type", "") == "choose"
	var run := {}  # hidden cards shuffled into one deck one after another (King Togwaggle's swap): one row
	var cast: Array = entry.events.filter(func(e): return e.type == "cast_when_drawn").map(func(e): return e.entity)
	for ev: Dictionary in entry.events:
		if ev.type == "draw" and cast.has(ev.entity):
			continue  # (its own line says it: drawn and cast)
		if ev.type == "to_deck" and _deck_card(ev) == "":
			if run.get("player") == ev.player and run.row == out.size() - 1:
				run.n += 1
				out[run.row].text = _say(ev.player, viewer, "%d cards are shuffled into your deck", "%d cards are shuffled into Opponent's deck", [run.n])
				continue
			run = {"player": ev.player, "row": out.size(), "n": 1}
		if ev.type == "play":
			played[ev.entity] = true
		if ev.type == "summon" and played.has(ev.entity):
			continue
		if chosen and ev.type == "discard" and ev.player != viewer:
			out.append({"text": _t("Opponent discards a card"), "turn": false})  # unchosen options stay secret (Tracking)
			continue
		for text in event_lines(ev, g, viewer, loc):
			out.append({"text": text, "turn": ev.type == "turn_start"})
	return out


static func event_lines(ev: Dictionary, g: GameView, viewer: int, loc := "") -> Array[String]:
	var out: Array[String] = []
	if SILENT.has(ev.type):
		return out
	var n := func(id: int) -> String: return _name(g, id, loc)
	var p: int = ev.get("player", -1)
	var s := ""
	match ev.type:
		"turn_start":
			s = _t("Turn %d: %s") % [ev.turn, _who(p, viewer)] if ev.has("turn") else ""
		"mulligan":
			s = _say(p, viewer, "You replace %d cards", "Opponent replaces %d cards", [ev.count])
		"draw":
			s = _t("You draw %s") % n.call(ev.entity) if _you(p, viewer) else _t("Opponent draws a card")
		"burn":
			s = _say(p, viewer, "You burn %s", "Opponent burns %s", [CardText.name(ev.card, loc)])
		"fatigue":
			s = _say(p, viewer, "You take %d fatigue damage", "Opponent takes %d fatigue damage", [ev.amount])
		"play":
			if ev.get("secret", false) and not _you(p, viewer):
				s = _t("Opponent plays a Secret")
			else:
				s = _say(p, viewer, "You play %s", "Opponent plays %s", [n.call(ev.entity)])
				if ev.get("target", -1) >= 0:
					s += " " + _t("on %s") % n.call(ev.target)
		"summon":
			if CardDb.has(str(ev.get("by", ""))) and CardDb.card(ev.by).get("referencedTags", []).has("SUMMON_FROM_DECK"):  # Recruit
				s = _say(p, viewer, "%s is summoned from your deck", "%s is summoned from Opponent's deck", [n.call(ev.entity)])
			else:
				s = _t("%s is summoned") % n.call(ev.entity)
		"attack":
			s = _t("%s attacks %s") % [n.call(ev.attacker), n.call(ev.defender)]
		"damage":
			if ev.source >= 0:
				s = _t("%s deals %d damage to %s") % [n.call(ev.source), ev.amount, n.call(ev.target)]
			else:
				s = _t("%s takes %d damage") % [n.call(ev.target), ev.amount]
		"heal":
			s = _t("%s restores %d Health to %s") % [n.call(ev.source), ev.amount, n.call(ev.target)] \
				if ev.source >= 0 else _t("%s is healed for %d") % [n.call(ev.target), ev.amount]
		"death":
			s = _t("%s dies") % n.call(ev.entity) if ev.minion else _t("%s is destroyed") % n.call(ev.entity)
		"divine_shield_lost":
			s = _t("%s loses Divine Shield") % n.call(ev.target)
		"armor":
			s = _say(p, viewer, "You gain %d Armor", "Opponent gains %d Armor", [ev.amount])
		"armor_lost":
			s = _t("Armor absorbs %d damage to %s") % [ev.amount, n.call(ev.target)]
		"equip":
			s = _say(p, viewer, "You equip %s", "Opponent equips %s", [n.call(ev.entity)])
		"destroy":
			s = _t("%s is destroyed") % n.call(ev.target)
		"transform":
			if not ev.has("entity"):
				s = _t("%s becomes %s") % [n.call(ev.from), CardText.name(ev.card, loc)]
			elif _you(p, viewer):  # a card in the hand or the deck (Shifter Zerus): only its owner sees it
				s = _t("Your %s becomes %s") % [n.call(ev.from), CardText.name(ev.card, loc)]
			else:
				s = _t("A card of Opponent's changes")
		"return_to_hand":
			s = _t("%s returns to its owner's hand") % n.call(ev.entity)
		"take_control":
			s = _say(ev.player, viewer, "You take control of %s", "Opponent takes control of %s", [n.call(ev.target)])
		"freeze":
			s = _t("%s is frozen") % n.call(ev.target)
		"silence":
			s = _t("%s is silenced") % n.call(ev.target)
		"buff":
			if ev.has("atk"):
				s = _t("%s gets %+d/%+d") % [n.call(ev.target), ev.atk, ev.hp]
			else:
				s = _t("%s changes to %s/%s") % [n.call(ev.target),
					str(ev.set_atk) if ev.set_atk >= 0 else "-", str(ev.set_hp) if ev.set_hp >= 0 else "-"]
		"secret_revealed":
			s = _t("Secret revealed: %s") % CardText.name(ev.card, loc)
		"quest_done":
			s = _t("Quest completed: %s") % CardText.name(ev.card, loc)
		"removed_from_deck":  # (Keening Banshee, Gnomeferatu, Army of the Dead): not drawn, not burned
			s = _say(p, viewer, "%s is removed from your deck", "%s is removed from Opponent's deck", [CardText.name(ev.card, loc)])
		"stolen":  # (Death Grip): a minion taken from the other player's deck
			s = _say(p, viewer, "You steal %s", "Opponent steals %s", [CardText.name(ev.card, loc)])
		"extra_turn":
			s = _say(p, viewer, "You take an extra turn", "Opponent takes an extra turn", [])
		"trap_put":
			s = _say(p, viewer, "You put a Secret into play", "Opponent puts a Secret into play", [])
		"add_to_hand":
			s = _t("%s is added to your hand") % CardText.name(ev.card, loc) if _you(p, viewer) \
				else _t("A card is added to Opponent's hand")
		"discard":
			s = _say(p, viewer, "You discard %s", "Opponent discards %s", [CardText.name(ev.card, loc)])
		"add_to_deck":  # (Prince Malchezaar's Legendaries, Gang Up…): a card in a deck is hidden from both players
			if str(ev.get("card", "")) == "":
				s = _say(p, viewer, "A card is shuffled into your deck", "A card is shuffled into Opponent's deck", [])
			else:
				s = _say(p, viewer, "%s is shuffled into your deck", "%s is shuffled into Opponent's deck", [CardText.name(ev.card, loc)])
		"to_deck":  # a card shuffled back (Kingsbane) or into the other deck (King Togwaggle): hidden in a deck
			var c := _deck_card(ev)
			if c == "":
				s = _say(p, viewer, "A card is shuffled into your deck", "A card is shuffled into Opponent's deck", [])
			else:
				s = _say(p, viewer, "%s is shuffled into your deck", "%s is shuffled into Opponent's deck", [CardText.name(c, loc)])
		"cast_when_drawn":  # (Spider Ambush!, Darkness Candle): both players see it
			s = _say(p, viewer, "You draw %s: it casts itself", "Opponent draws %s: it casts itself", [CardText.name(ev.card, loc)])
		"awaken":  # a Dormant minion wakes up (The Darkness, its candles snuffed)
			s = _t("%s awakens") % CardText.name(ev.card, loc)
		"removed_from_hand":  # (Unstable Evolution at the end of the turn); no line if the view hides it
			if str(ev.get("card", "")) != "":
				s = _say(p, viewer, "%s is removed from your hand", "%s is removed from Opponent's hand", [CardText.name(ev.card, loc)])
		"reveal":  # a deck's card shown to both players (Seeping Oozeling, Dragon's Fury); no line if the view hides it
			if str(ev.get("card", "")) != "":
				s = _say(p, viewer, "You reveal %s", "Opponent reveals %s", [CardText.name(ev.card, loc)])
		"faded":  # an Echo copy goes away at the end of the turn; no line if the view hides it
			if str(ev.get("card", "")) != "":
				s = _say(p, viewer, "%s fades from your hand", "%s fades from Opponent's hand", [CardText.name(ev.card, loc)])
		"start_of_game":  # (Baku the Mooneater, Genn Greymane): both players see it
			s = _say(p, viewer, "Start of Game: your %s", "Start of Game: Opponent's %s", [CardText.name(ev.card, loc)])
		"battlecry":  # a Battlecry repeated (Shudderwock)
			s = _t("%s repeats the Battlecry of %s") % [n.call(ev.entity), CardText.name(ev.card, loc)]
			if int(ev.get("target", -1)) >= 0:
				s += " " + _t("on %s") % n.call(ev.target)
		"hero_power":
			s = _say(p, viewer, "You use %s", "Opponent uses %s", [n.call(ev.entity)])
			if ev.get("target", -1) >= 0:
				s += " " + _t("on %s") % n.call(ev.target)
		"game_over":
			s = _t("Draw") if ev.winner == -1 else _say(ev.winner, viewer, "You win", "Opponent wins", [])
		"choice":
			s = _say(p, viewer, "You choose a card", "Opponent chooses a card", [])
		"cast":
			if ev.get("random", false):  # Yogg-Saron: a spell cast with random targets and choices
				s = _t("%s casts %s") % [n.call(ev.get("by_id", -1)), CardText.name(ev.card, loc)]
				if ev.get("target", -1) >= 0:
					s += " " + _t("on %s") % n.call(ev.target)
			else:
				s = _t("A copy of %s is cast on %s") % [CardText.name(ev.card, loc), n.call(ev.target)]
		"fizzle":
			s = _t("%s fizzles") % CardText.name(ev.card, loc)
		"retarget":  # (Mayor Noggenfogger): the chosen target became a random one
			s = _t("The target is chosen at random: %s") % n.call(ev.get("to", -1))
		"cthun":
			s = _say(p, viewer, "Your C'Thun is now %d/%d", "Opponent's C'Thun is now %d/%d", [ev.atk, ev.health])
		"to_hand":
			s = _t("%s is put into your hand") % CardText.name(ev.card, loc) if _you(p, viewer) \
				else _t("A card is put into Opponent's hand")
		"choice_cancelled":
			s = _t("The choice is cancelled: no options left")
		"mana":
			s = _say(p, viewer, "You now have %d/%d mana", "Opponent now has %d/%d mana", [ev.mana, ev.max])
		"set_health":
			s = _t("%s Health is set to %d") % [n.call(ev.target), ev.health]
		"hero_power_changed":
			s = _say(p, viewer, "Your Hero Power becomes %s", "Opponent's Hero Power becomes %s", [CardText.name(ev.card, loc)])
		"joust":
			var foe: String = CardText.name(ev.foe_card, loc) if str(ev.get("foe_card", "")) != "" else _t("no minion")
			if str(ev.get("card", "")) == "":
				s = _say(p, viewer, "Your Joust: no minion to reveal, lost", "Opponent's Joust: no minion to reveal, lost", [])
			elif ev.get("won", false):
				s = _say(p, viewer, "Your Joust: %s against %s, won", "Opponent's Joust: %s against %s, won", [CardText.name(ev.card, loc), foe])
			else:
				s = _say(p, viewer, "Your Joust: %s against %s, lost", "Opponent's Joust: %s against %s, lost", [CardText.name(ev.card, loc), foe])
		"hero_replaced":
			s = _say(p, viewer, "Your hero becomes %s", "Opponent's hero becomes %s", [CardText.name(ev.card, loc)])
		_:
			s = ev.type
	if s != "":
		out.append(s)
	return out


## The line saying who made the move of an entry ("You play X on Y", "Opponent
## uses…"); "" for moves without a card (end of turn, mulligan).
static func title(entry: Dictionary, g: GameView, viewer: int, loc := "") -> String:
	for ev: Dictionary in entry.events:
		if ev.type in ["play", "attack", "hero_power"]:
			return event_lines(ev, g, viewer, loc)[0]
	return ""


## The card that made the move of an entry (played, attacking, Hero Power), or -1.
static func actor(entry: Dictionary, g: GameView) -> int:
	var a: Dictionary = entry.action
	var id: int = {"play": a.get("entity", -1), "attack": a.get("attacker", -1), "hero_power": a.get("entity", -1)}.get(a.get("type", ""), -1)
	if a.get("type") == "hero_power" and id < 0:
		id = g.players[int(a.get("player", 0))].hero_power.id
	return id


## What one entry did, for the history pop-up: rows {"card", "name", "text",
## "color", "from"} in event order. "card" is the picture ("" for none), "name"
## the affected card ("" when "text" is a whole sentence), "color" good/bad/"",
## "from" the trigger that caused it (a Deathrattle, a Secret, Knife Juggler…),
## "" for the move itself. The opponent's draws and hand cards stay hidden.
static func effects(entry: Dictionary, g: GameView, viewer: int, loc := "") -> Array:
	var out := []
	var a: Dictionary = entry.action
	var main := actor(entry, g)
	var chosen: bool = a.get("type", "") == "choose"
	var dead := {}
	var gone := {}  # destroyed: their "death" adds nothing
	for ev: Dictionary in entry.events:
		var row := {}
		if chosen and ev.type == "discard" and ev.player != viewer:
			row = {"card": "", "name": "", "text": _t("Opponent discards a card"), "color": ""}  # unchosen options stay secret
		else:
			row = _effect(ev, g, viewer, loc, main, gone)
		var by: int = ev.get("by_id", -1)
		if not row.is_empty():
			row.from = (_t("Deathrattle") + ": " if dead.has(by) else "") + _name(g, by, loc) \
				if by >= 0 and by != main and g.ent(by) else ""
			out.append(row)
		if ev.type == "death":
			dead[ev.entity] = true
	return out


static func _effect(ev: Dictionary, g: GameView, viewer: int, loc: String, main: int, gone: Dictionary) -> Dictionary:
	var row := func(id: int, text: String, color := "") -> Dictionary:
		var e := g.ent(id)
		return {"card": e.card_id if e else "", "name": _name(g, id, loc), "text": text, "color": color}
	var mine: bool = ev.get("player", -1) == viewer
	match ev.type:
		"play", "attack", "hero_power":
			if ev.get("entity", ev.get("attacker", -1)) == main:
				return {}
		"turn_start", "mana":
			return {}
		"damage":
			return row.call(ev.target, _t("-%d Health") % ev.amount, "bad")
		"heal":
			return row.call(ev.target, _t("+%d Health") % ev.amount, "good")
		"armor":
			return row.call(g.hero(ev.player).id, _t("+%d Armor") % ev.amount, "good")
		"armor_lost":
			return row.call(ev.target, _t("-%d Armor") % ev.amount, "bad")
		"buff":
			if ev.has("atk"):
				return row.call(ev.target, "%+d/%+d" % [ev.atk, ev.hp], "good" if ev.atk + ev.hp >= 0 else "bad")
			return row.call(ev.target, "= %s/%s" % [str(ev.set_atk) if ev.set_atk >= 0 else "-", str(ev.set_hp) if ev.set_hp >= 0 else "-"])
		"freeze":
			return row.call(ev.target, _t("Frozen"), "bad")
		"silence":
			return row.call(ev.target, _t("Silenced"), "bad")
		"divine_shield_lost":
			return row.call(ev.target, _t("Loses Divine Shield"), "bad")
		"destroy":
			gone[ev.target] = true
			return row.call(ev.target, _t("Destroyed"), "bad")
		"death":
			return {} if gone.has(ev.entity) else row.call(ev.entity, _t("Dies") if ev.minion else _t("Destroyed"), "bad")
		"summon":
			return {} if ev.entity == main else row.call(ev.entity, _t("Summoned"), "good")
		"equip":
			return row.call(g.hero(ev.player).id, _t("Equips %s") % _name(g, ev.entity, loc), "good")
		"transform":
			if not ev.has("entity"):
				return row.call(ev.from, _t("Becomes %s") % CardText.name(ev.card, loc))
		"return_to_hand":
			return row.call(ev.entity, _t("Returned to hand"))
		"take_control":
			return row.call(ev.target, _t("Changes sides"))
		"draw":
			if mine:
				return row.call(ev.entity, _t("Drawn"), "good")
		"add_to_hand":
			if mine:
				return row.call(ev.entity, _t("Added to hand"), "good")
	var lines := event_lines(ev, g, viewer, loc)  # whole sentences, which already hide the opponent's cards
	return {} if lines.is_empty() else {"card": "", "name": "", "text": lines[0], "color": ""}
