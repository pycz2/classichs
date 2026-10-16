class_name NetSession
extends Node
## The online protocol over a Transport: hello → start → actions/emotes → bye.
## The host is player 0 and chooses the seed; both sides then run the same game in
## their own rules engine with the full view (lockstep) and check each other's state
## hash after every action. Any disagreement ends the game for both (no ban).
## Packs (D13): each hello names the sender's pack; the host's pack decides. A guest
## with other rules (rules_hash) switches to the host's (if it has it) or is offered it: pack_want →
## pack_chunk {n, data, last} / pack_ack {n} … then a second hello. pack_cancel stops it.

signal started(m: Match)
signal failed(reason: String)
signal emote_received(player: int, id: String)
## The opponent hovers, aims or looks at something (not part of the game state).
signal intent_received(intent: Dictionary)
## Guest: the host plays a pack this side lacks ({name, version, size}); answer with
## accept_pack() or decline_pack().
signal pack_offer(info: Dictionary)
## The pack transfer goes on (both sides).
signal pack_progress(done_bytes: int, total_bytes: int)

const PROTOCOL := 3  # 2: portable mulligan shuffle seed (Game.mulligan_seed); 3: packs in hello, transfer
## Raw bytes per pack_chunk (~43 KB of base64: well inside a WebRTC data channel message).
const CHUNK := 32 * 1024
const EMOTES := ["greetings", "well_played", "thanks", "wow", "oops", "threaten"]

var transport: Transport
var host := false
var player_name := ""
var deck: Deck
## A game of the Arena: the opponent's deck may have any number of copies.
var arena := false
## A game on a server: the server gives the seed (it checks the host uses it).
var seed_override := -1
var version: String = ProjectSettings.get_setting("application/config/version", "0")
var remote_name := ""
var match_: Match
## The pack this side plays: the active one at setup (a guest may switch to the host's).
var pack: Pack
var _remote: Dictionary = {}
var _sent := 0
var _received := 0
var _done := false
var _hellos := 0  # hellos received: the host takes a second one after the guest changed its pack
var _host_hello := {}  # guest: the host's hello while the packs are settled
var _offer := {}  # guest: the host's pack offered ({name, version, size, content_hash})
var _wanted := false  # guest: the pack is being received
var _incoming := PackedByteArray()
var _outgoing := PackedByteArray()  # host: the pack being sent
var _chunk := -1  # host: the chunk sent last; guest: the chunks received
## Why the session ended: "left", "connection", "version", "desync", "protocol",
## "pack" (the guest could not get or declined the host's pack) or "cancel" (of the transfer).
var failure_kind := ""

## Shown on both sides when the two games disagree (an illegal move or another state).
const DESYNC := "Something does not add up: the two games differ. Nobody is banned."
const BYE_TEXT := {"left": "The opponent left the game", "version": "The opponent has a different version of the game",
	"desync": DESYNC, "protocol": "The opponent's game sent something unexpected",
	"mode": "The opponent chose the Arena, not a normal game",
	"pack": "The opponent could not get your game pack", "declined": "The game pack was not accepted"}
const CANCELLED := "The transfer of the game pack was cancelled"
const DAMAGED := "The game pack that came is damaged"


func setup(t: Transport, is_host: bool, p_name: String, d: Deck) -> void:
	transport = t
	host = is_host
	player_name = Profile.clean(p_name)
	deck = d
	pack = Packs.active()
	t.opened.connect(say_hello)
	t.received.connect(_on_message)
	t.closed.connect(_on_closed)


func local_player() -> int:
	return 0 if host else 1


func say_hello() -> void:
	transport.send({"t": "hello", "protocol": PROTOCOL, "version": version, "data": Rules.data_hash(pack),
		"name": player_name, "hero": deck.hero, "cards": deck.cards, "pack": pack_info(pack)})


## What a hello says about a pack.
static func pack_info(p: Pack) -> Dictionary:
	return {"id": p.id(), "version": p.version(), "name": p.title("en"), "rules_hash": p.rules_hash(),
		"content_hash": Packs.content_hash(p), "size": p.size, "redistributable": p.manifest.get("redistributable") == true}


func send_emote(id: String) -> void:
	if EMOTES.has(id):
		transport.send({"t": "emote", "id": id})


## What the local player points at: {"k": "hover", "i"}, {"k": "aim", "from", "to", "x", "y"},
## {"k": "look", "id"} or {"k": "none"}. Outside the lockstep: never changes the game.
func send_intent(intent: Dictionary) -> void:
	if not _done:
		transport.send({"t": "intent", "i": intent})


## A clean copy of an intent, or {} when it is malformed (then it is dropped).
static func clean_intent(i: Variant) -> Dictionary:
	if not i is Dictionary:
		return {}
	var num := func(v) -> bool: return v is int or v is float
	match i.get("k"):
		"none":
			return {"k": "none"}
		"hover":
			if num.call(i.get("i")) and int(i.i) >= 0 and int(i.i) < 10:
				return {"k": "hover", "i": int(i.i)}
		"look":
			if num.call(i.get("id")):
				return {"k": "look", "id": int(i.id)}
		"aim":
			if num.call(i.get("from")) and num.call(i.get("to")):
				return {"k": "aim", "from": int(i.from), "to": int(i.to),
					"x": clampf(float(i.get("x", 640)), 0, 1280) if num.call(i.get("x", 0)) else 640.0,
					"y": clampf(float(i.get("y", 360)), 0, 720) if num.call(i.get("y", 0)) else 360.0}
	return {}


func leave() -> void:
	if not _done:
		_done = true
		failure_kind = "left"
		transport.send({"t": "bye", "code": "left"})
		_close_soon()


## Closes on the next frame so the last message (bye) gets out first.
func _close_soon() -> void:
	if is_inside_tree():
		transport.call_deferred("close", failure_kind)
	else:
		transport.close(failure_kind)


## code: what the peer is told (the kind by default).
func _fail(reason: String, kind: String, tell_peer := true, code := "") -> void:
	if _done:
		return
	_done = true
	failure_kind = kind
	if tell_peer:
		transport.send({"t": "bye", "code": code if code != "" else kind})
	_close_soon()
	failed.emit(reason)


func _tr(s: String) -> String:
	return TranslationServer.translate(s)


func _on_message(msg: Variant) -> void:
	if _done:
		return
	if not msg is Dictionary or not msg.get("t") is String:
		_fail(_tr("The opponent sent a broken message"), "protocol")
		return
	match msg.t:
		"hello": _on_hello(msg)
		"start": _on_start(msg)
		"pack_want": _on_pack_want(msg)
		"pack_ack": _on_pack_ack(msg)
		"pack_chunk": _on_pack_chunk(msg)
		"pack_cancel": _fail(_tr(CANCELLED), "cancel", false)
		"action": _on_action(msg)
		"emote":
			if match_ and EMOTES.has(msg.get("id")):
				emote_received.emit(match_.remote, msg.id)
		"intent":
			var i := clean_intent(msg.get("i"))
			if match_ and not i.is_empty():
				intent_received.emit(i)
		"bye":
			var code := str(msg.get("code", "left"))
			_fail(_tr(BYE_TEXT.get(code, BYE_TEXT.left)), {"left": "left", "declined": "pack"}.get(code, code), false)
		_:
			_fail(_tr("The opponent sent an unknown message"), "protocol")


func _on_hello(msg: Dictionary) -> void:
	_hellos += 1
	if not _remote.is_empty() or _hellos > (2 if host else 1) or (host and _hellos == 2 and _outgoing.size() > 0):
		_fail(_tr("The opponent sent an unexpected message"), "protocol")
		return
	if msg.get("mode") == "arena":
		_fail(_tr("The opponent chose the Arena, not a normal game"), "mode")
		return
	if msg.get("protocol") != float(PROTOCOL) or msg.get("version") != version:
		_fail(_tr("Different game versions: yours %s, the opponent's %s") % [version, str(msg.get("version", "?")).left(20)], "version")
		return
	var theirs = msg.get("pack")
	if not theirs is Dictionary or not theirs.get("content_hash") is String or not theirs.get("rules_hash") is String:
		_fail(_tr("The opponent sent a broken message"), "protocol")
		return
	if theirs.rules_hash != pack.rules_hash():  # the same rules: each plays with its own art and texts (D8)
		if not host and not arena:
			_settle_pack(theirs, msg)
			return
		if host and not arena and _hellos == 1:
			return  # the guest switches, downloads or declines; a second hello follows
		_fail(_tr("Both players need the same game for the Arena") if arena else _tr("You and the opponent play different games"), "pack")
		return
	if msg.get("data") != Rules.data_hash(pack):
		_fail(_tr("Your card data differs from the opponent's: update the game on both sides"), "version")
		return
	var d := Deck.from_dict({"name": "", "hero": msg.get("hero"), "cards": msg.get("cards"), "arena": arena})
	if d == null or d.validate() != "":
		_fail(_tr("The opponent's deck is not valid"), "protocol")
		return
	_remote = msg
	remote_name = Profile.clean(str(msg.get("name", "")))
	if host:
		var seed := seed_override if seed_override >= 0 else randi()
		transport.send({"t": "start", "seed": seed, "decks": [[deck.hero, deck.cards], [d.hero, d.cards]]})
		_begin([_engine_deck(deck.hero, deck.cards, deck.arena), _engine_deck(d.hero, d.cards, arena)], seed)


func _on_start(msg: Dictionary) -> void:
	if host or match_ != null or _remote.is_empty():
		_fail(_tr("The opponent sent an unexpected message"), "protocol")
		return
	var decks = msg.get("decks")
	if not decks is Array or decks.size() != 2 or not decks[0] is Array or decks[0].size() != 2 \
			or not decks[1] is Array or decks[1].size() != 2 \
			or decks[1][0] != deck.hero or decks[1][1] != Array(deck.cards) \
			or decks[0][0] != _remote.hero or decks[0][1] != _remote.cards or not msg.get("seed") is float:
		_fail(_tr("The opponent started a different game"), "protocol")
		return
	_begin([_engine_deck(_remote.hero, _remote.cards, arena), _engine_deck(deck.hero, deck.cards, deck.arena)], int(msg.seed))


## Guest: the host plays other rules. Switch to a pack with them if this side has one, else offer the host's.
func _settle_pack(theirs: Dictionary, hello: Dictionary) -> void:
	_host_hello = hello
	var have := Packs.find(theirs.content_hash)
	if have == null or have.rules_hash() != theirs.rules_hash:
		have = Packs.find_rules(theirs.rules_hash)
	if have:
		_switch(have)
		return
	if theirs.get("redistributable") != true:
		_fail(_tr("The opponent plays a game you don't have"), "pack")
		return
	var size = theirs.get("size")
	if not size is float or size <= 0 or size > Pack.LIMITS.pack:
		_fail(_tr("The opponent's game pack is too big"), "pack")
		return
	_offer = {"name": str(theirs.get("name", "")).left(80), "version": str(theirs.get("version", "")).left(20),
		"size": int(size), "content_hash": theirs.content_hash}
	pack_offer.emit(_offer.duplicate())


## Guest: download the offered pack.
func accept_pack() -> void:
	if _done or host or _offer.is_empty() or _wanted:
		return
	_wanted = true
	_chunk = 0
	transport.send({"t": "pack_want", "content_hash": _offer.content_hash})


func decline_pack() -> void:
	_fail(_tr("The game pack was not accepted"), "pack", true, "declined")


## Stops the transfer (either side); the session ends on both.
func cancel_pack() -> void:
	if not _done:
		transport.send({"t": "pack_cancel"})
		_fail(_tr(CANCELLED), "cancel", false)


func _on_pack_want(msg: Dictionary) -> void:
	if not host or _hellos != 1 or _chunk >= 0 or msg.get("content_hash") != Packs.content_hash(pack) \
			or pack.manifest.get("redistributable") != true:
		_fail(_tr("The opponent sent an unexpected message"), "protocol")
		return
	_outgoing = Packs.bytes_of(pack)
	_send_chunk()


func _on_pack_ack(msg: Dictionary) -> void:
	if not host or _outgoing.is_empty() or msg.get("n") != float(_chunk):
		_fail(_tr("The opponent sent an unexpected message"), "protocol")
		return
	_send_chunk()


func _send_chunk() -> void:
	_chunk += 1
	var from := _chunk * CHUNK
	var last := from + CHUNK >= _outgoing.size()
	transport.send({"t": "pack_chunk", "n": _chunk, "data": Marshalls.raw_to_base64(_outgoing.slice(from, from + CHUNK)), "last": last})
	var total := _outgoing.size()
	pack_progress.emit(mini(from + CHUNK, total), total)
	if last:
		_outgoing = PackedByteArray()


func _on_pack_chunk(msg: Dictionary) -> void:
	if host or not _wanted or msg.get("n") != float(_chunk) or not msg.get("data") is String:
		_fail(_tr("The opponent sent an unexpected message"), "protocol")
		return
	var raw := Marshalls.base64_to_raw(msg.data)
	if raw.size() > CHUNK or _incoming.size() + raw.size() > _offer.size:
		_fail(_tr(DAMAGED), "pack")
		return
	_incoming.append_array(raw)
	_chunk += 1
	pack_progress.emit(_incoming.size(), _offer.size)
	if _done:  # cancelled while the bar moved
		return
	if msg.get("last") != true:
		transport.send({"t": "pack_ack", "n": _chunk - 1})
		return
	var r := Packs.install(_incoming, "p2p", {}, _offer.content_hash)
	_incoming = PackedByteArray()
	_wanted = false
	if r.has("error"):
		push_warning("received pack refused: " + str(r.error))
		_fail(_tr(DAMAGED), "pack")
		return
	_switch(r.pack)


## Guest: plays the host's pack from now on (the active pack), with a deck of it, and says hello again.
func _switch(p: Pack) -> void:
	Packs.set_active(p)
	pack = p
	if Rules.can_play(p) != "":
		_fail(_tr(Rules.NEEDS_ENGINE), "pack")
		return
	deck = null
	for d: Deck in DeckStore.load_all() + DeckStore.starter():
		if d.validate() == "":
			deck = d
			break
	if deck == null:
		_fail(_tr("You have no deck for this game"), "pack")
		return
	say_hello()
	var h := _host_hello
	_host_hello = {}
	_hellos = 0
	_on_hello(h)  # the host's deck, checked with this pack


static func _engine_deck(hero: String, cards: Array, is_arena: bool) -> Dictionary:
	return {"hero": hero, "cards": Array(cards), "arena": is_arena}


func _begin(decks: Array, seed: int) -> void:
	match_ = Match.new()
	var why := match_.setup({"decks": decks, "seed": seed}, [false, false])
	if why != "":
		match_.free()
		match_ = null
		_fail(_tr("The opponent started a different game"), "protocol")
		return
	match_.remote = 1 - local_player()
	match_.local_action.connect(_on_local_action)
	started.emit(match_)


func _on_local_action(action: Dictionary, state_hash: String) -> void:
	var simultaneous: bool = action.type in ["mulligan", "concede"]
	transport.send({"t": "action", "n": _sent, "action": action, "hash": "" if simultaneous else state_hash})
	_sent += 1


func _on_action(msg: Dictionary) -> void:
	if match_ == null:
		_fail(_tr("The opponent sent a move before the game started"), "protocol")
		return
	if msg.get("n") != float(_received):
		_fail(_tr("Out of sync: a move was lost"), "desync")
		return
	_received += 1
	var a = msg.get("action")
	var simultaneous: bool = a is Dictionary and a.get("type") in ["mulligan", "concede"]
	var expected := "" if simultaneous else str(msg.get("hash", ""))
	if not simultaneous and expected == "":
		_fail(_tr("Out of sync: a move came without a state check"), "desync")
		return
	var why := match_.submit_remote(a, expected)
	if why != "":
		push_warning("out of sync with the opponent: " + why)
		_fail(_tr(DESYNC), "desync")


func _on_closed(_reason: String) -> void:
	if match_ and match_.game.game_over:
		_done = true
		return
	_fail(_tr("Connection lost"), "connection", false)
