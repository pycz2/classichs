class_name HistoryText
extends RefCounted
## Human-readable lines for match history entries. Cards the viewer may not
## see (the opponent's draws and hand additions, the opponent's Secrets) stay hidden.

## Event types that produce no line (they repeat other events).
const SILENT := ["after_summon", "after_spell", "after_attack", "turn_end", "mulligan_chosen"]


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
	for ev: Dictionary in entry.events:
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
			s = _t("%s becomes %s") % [n.call(ev.from), CardText.name(ev.card, loc)]
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
		"add_to_hand":
			s = _t("%s is added to your hand") % CardText.name(ev.card, loc) if _you(p, viewer) \
				else _t("A card is added to Opponent's hand")
		"discard":
			s = _say(p, viewer, "You discard %s", "Opponent discards %s", [CardText.name(ev.card, loc)])
		"hero_power":
			s = _say(p, viewer, "You use %s", "Opponent uses %s", [n.call(ev.entity)])
			if ev.get("target", -1) >= 0:
				s += " " + _t("on %s") % n.call(ev.target)
		"game_over":
			s = _t("Draw") if ev.winner == -1 else _say(ev.winner, viewer, "You win", "Opponent wins", [])
		"choice":
			s = _say(p, viewer, "You choose a card", "Opponent chooses a card", [])
		"choice_cancelled":
			s = _t("The choice is cancelled: no options left")
		"mana":
			s = _say(p, viewer, "You now have %d/%d mana", "Opponent now has %d/%d mana", [ev.mana, ev.max])
		"set_health":
			s = _t("%s Health is set to %d") % [n.call(ev.target), ev.health]
		"hero_power_changed":
			s = _say(p, viewer, "Your Hero Power becomes %s", "Opponent's Hero Power becomes %s", [CardText.name(ev.card, loc)])
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
