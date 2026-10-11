class_name Art
extends RefCounted
## Procedural vector art: a background in the class color and a motif chosen by
## the English card name, then race, then type and class. Shapes are plain data
## ([kind, ...]) so tests can check them; paint() draws them on a CanvasItem.

## Name keywords (start of a word) -> motif. The first match wins, so specific words come first.
const KEYWORDS := [
	["yeti", "yeti"], ["polymorph", "sheep"], ["sheep", "sheep"], ["murloc", "murloc"],
	["banana", "banana"], ["monkey", "banana"], ["mukla", "banana"], ["totem", "totem"],
	["brew", "humanoid"], ["overwhelming", "shadow"], ["skeleton", "skull"], ["ghoul", "skull"], ["abomination", "skull"],
	["axe", "axe"], ["reaper", "axe"], ["gorehowl", "axe"], ["cleave", "axe"], ["whirlwind", "axe"],
	["execute", "axe"], ["berserker", "axe"], ["grommash", "axe"], ["warsong", "axe"], ["frothing", "axe"],
	["rampage", "axe"], ["brawl", "axe"], ["heroic", "axe"], ["battle", "axe"],
	["dagger", "dagger"], ["knife", "dagger"], ["knives", "dagger"], ["assassin", "dagger"], ["poison", "dagger"],
	["backstab", "dagger"], ["shiv", "dagger"], ["sap", "dagger"], ["eviscerate", "dagger"], ["vanish", "dagger"],
	["conceal", "dagger"], ["betrayal", "dagger"], ["sinister", "dagger"], ["vancleef", "dagger"], ["defias", "dagger"],
	["nightblade", "dagger"], ["ravenholdt", "dagger"], ["agent", "dagger"], ["preparation", "dagger"], ["sprint", "dagger"],
	["sword", "sword"], ["blade", "sword"], ["knight", "sword"], ["warglaive", "sword"], ["glaive", "sword"],
	["champion", "sword"], ["squire", "sword"], ["recruit", "sword"], ["footman", "shield"],
	["hammer", "hammer"], ["justice", "hammer"], ["ashbringer", "hammer"], ["reinforce", "hammer"],
	["bow", "bow"], ["longbow", "bow"], ["shot", "bow"], ["archer", "bow"], ["snipe", "bow"], ["rifleman", "bow"],
	["commando", "bow"], ["trap", "bow"], ["flare", "bow"], ["tracking", "bow"], ["misdirection", "bow"],
	["hunter", "bow"], ["shield", "shield"], ["armor", "shield"], ["armorsmith", "shield"],
	["defender", "shield"], ["protector", "shield"], ["guardian", "shield"], ["bodyguard", "shield"],
	["block", "shield"], ["barrier", "shield"], ["tank", "shield"], ["protection", "shield"], ["warden", "shield"],
	["fire", "fire"], ["fiery", "fire"], ["flame", "fire"], ["pyro", "fire"], ["lava", "fire"], ["magma", "fire"],
	["inferno", "fire"], ["hellfire", "fire"], ["demonfire", "fire"], ["soulfire", "fire"], ["geddon", "fire"],
	["molten", "fire"], ["wild", "nature"], ["frost", "ice"], ["ice", "ice"], ["cold", "ice"], ["blizzard", "ice"],
	["freezing", "ice"], ["chillwind", "ice"], ["water", "ice"], ["lightning", "lightning"], ["storm", "lightning"],
	["stormforged", "lightning"], ["windfury", "lightning"], ["wind", "lightning"], ["windspeaker", "lightning"],
	["akir", "lightning"], ["bloodlust", "lightning"], ["forked", "lightning"], ["earth", "giant"],
	["moon", "moon"], ["moonfire", "moon"], ["starfall", "moon"], ["starfire", "moon"],
	["starlord", "moon"], ["stellar", "moon"], ["solar", "moon"], ["elune", "moon"], ["dream", "moon"], ["ysera", "moon"],
	["secret", "book"], ["secrets", "book"], ["lore", "book"], ["lorewalker", "book"], ["teachings", "book"],
	["teacher", "book"], ["wisdom", "book"], ["thoughtsteal", "book"], ["intellect", "book"], ["apprentice", "book"],
	["arcane", "arcane"], ["arcanite", "axe"], ["mana", "arcane"], ["mirror", "arcane"], ["spell", "arcane"],
	["counterspell", "arcane"], ["mage", "arcane"], ["archmage", "arcane"], ["bloodmage", "arcane"], ["kirin", "arcane"],
	["dalaran", "arcane"], ["violet", "arcane"], ["ethereal", "arcane"], ["sorcerer", "arcane"], ["vaporize", "arcane"],
	["fireblast", "fire"], ["holy", "holy"], ["light", "holy"], ["blessing", "holy"], ["blessed", "holy"],
	["divine", "holy"], ["heal", "holy"], ["healing", "holy"], ["avenging", "holy"], ["consecration", "holy"],
	["redemption", "holy"], ["repentance", "holy"], ["equality", "holy"], ["humility", "holy"], ["noble", "holy"],
	["argent", "holy"], ["crusader", "holy"], ["silver", "holy"], ["tirion", "holy"], ["velen", "holy"],
	["cleric", "holy"], ["priest", "holy"], ["priestess", "holy"], ["sunwalker", "holy"], ["aldor", "holy"],
	["lay", "holy"], ["power", "holy"], ["circle", "holy"], ["lightspawn", "holy"], ["lightwell", "holy"],
	["shadow", "shadow"], ["shadowform", "shadow"], ["mind", "shadow"], ["soul", "shadow"], ["drain", "shadow"],
	["corruption", "shadow"], ["doom", "shadow"], ["siphon", "shadow"], ["mortal", "shadow"], ["nightmare", "shadow"],
	["twisting", "shadow"], ["sacrificial", "shadow"], ["bane", "shadow"], ["life", "shadow"], ["cabal", "shadow"],
	["auchenai", "shadow"], ["coin", "coin"], ["gold", "coin"], ["auctioneer", "coin"], ["loot", "coin"],
	["venture", "coin"], ["booty", "coin"], ["pagle", "coin"], ["harrison", "coin"], ["excess", "coin"],
	["skull", "skull"], ["doomsayer", "skull"], ["sylvanas", "skull"], ["kill", "skull"], ["deadly", "skull"],
	["assassinate", "skull"], ["bear", "paw"], ["cat", "paw"], ["claw", "paw"], ["claws", "paw"], ["bite", "paw"],
	["savage", "paw"], ["savagery", "paw"], ["swipe", "paw"], ["shapeshift", "paw"], ["tiger", "paw"],
	["panther", "paw"], ["feral", "paw"], ["bestial", "paw"], ["hound", "paw"], ["houndmaster", "paw"],
	["wolf", "paw"], ["wolfrider", "paw"], ["worgen", "paw"], ["companion", "paw"], ["pack", "paw"],
	["giant", "giant"], ["golem", "giant"], ["ogre", "giant"], ["gruul", "giant"], ["boulderfist", "giant"],
	["gear", "gear"], ["gnome", "gear"], ["gnomish", "gear"], ["engineer", "gear"], ["mechanic", "gear"],
	["inventor", "gear"], ["tinkmaster", "gear"], ["mekkatorque", "gear"], ["rocketeer", "gear"], ["bomber", "gear"],
	["upgrade", "gear"], ["wisp", "orb"], ["spirit", "orb"], ["ancestral", "orb"], ["elemental", "orb"],
	["devil", "orb"], ["wraith", "orb"], ["nature", "nature"], ["growth", "nature"], ["rooted", "nature"],
	["uproot", "nature"], ["treant", "nature"], ["cenarius", "nature"], ["innervate", "nature"], ["nourish", "nature"],
	["naturalize", "nature"], ["enrich", "nature"], ["force", "nature"], ["grove", "nature"], ["ironbark", "nature"],
	["ancient", "nature"], ["wrath", "nature"], ["rampant", "nature"], ["thick", "nature"], ["touch", "nature"],
]
const RACES := {"BEAST": "paw", "DEMON": "demon", "DRAGON": "dragon", "MURLOC": "murloc",
	"MECHANICAL": "gear", "TOTEM": "totem", "PIRATE": "pirate", "UNDEAD": "skull"}
## Spells without a keyword, heroes and hero powers use the class motif.
const CLASS_MOTIF := {"MAGE": "arcane", "PRIEST": "holy", "PALADIN": "hammer", "WARLOCK": "shadow",
	"DRUID": "paw", "SHAMAN": "totem", "ROGUE": "dagger", "HUNTER": "bow", "WARRIOR": "shield"}


static func _english(c: Dictionary) -> String:
	var n = c.get("name", "")
	return str(n.get("enUS", "")) if n is Dictionary else str(n)


static func motif(card_id: String) -> String:
	var c := CardDb.card(card_id)
	var cls: String = c.get("cardClass", "NEUTRAL")
	if c.get("type") == "HERO" and CLASS_MOTIF.has(cls):
		return CLASS_MOTIF[cls]
	var words := {}
	for w in RegEx.create_from_string("[a-z]+").search_all(_english(c).to_lower()):
		words[w.get_string()] = true
	for kw in KEYWORDS:
		for w in words:
			if w.begins_with(kw[0]):
				return kw[1]
	if RACES.has(c.get("race", "")):
		return RACES[c.race]
	match c.get("type"):
		"WEAPON":
			return "sword"
		"SPELL", "HERO_POWER", "HERO":
			return CLASS_MOTIF.get(cls, "arcane" if c.type != "HERO" else "humanoid")
	return "humanoid"


## Every point a shape touches (for bounds checks).
static func points(s: Array) -> Array:
	match s[0]:
		"rect":
			return [s[1].position, s[1].end]
		"circle":
			return [s[1] - Vector2(s[2], s[2]), s[1] + Vector2(s[2], s[2])]
		"poly":
			return Array(s[1])
		"line":
			return [s[1], s[2]]
	return []


static func shapes(card_id: String, rect: Rect2) -> Array:
	var c := CardDb.card(card_id)
	var base := Palette.of_class(c.get("cardClass", "NEUTRAL"))
	var h := hash(card_id)
	var tint := Color.from_hsv(float(h % 360) / 360.0, 0.3, 0.45)
	var out := []
	# Background: two bands and a few soft dots placed by the card id.
	out.append(["rect", rect, base.darkened(0.35).lerp(tint, 0.3)])
	out.append(["rect", Rect2(rect.position + Vector2(0, rect.size.y * 0.55), rect.size * Vector2(1, 0.45)), base.darkened(0.55)])
	var side := minf(rect.size.x, rect.size.y)
	for i in 4:
		var hh := hash(card_id + str(i))
		var r := side * (0.05 + float(hh % 7) / 100.0)
		var p := rect.position + Vector2(r + float(hh % 997) / 997.0 * (rect.size.x - 2 * r), r + float((hh / 997) % 991) / 991.0 * (rect.size.y - 2 * r))
		out.append(["circle", p, r, Color(1, 1, 1, 0.06)])
	var sq := Rect2(rect.position + (rect.size - Vector2(side, side)) / 2.0, Vector2(side, side)).grow(-side * 0.04)
	var m := _Motif.new(sq, out, tint)
	m.call("m_" + motif(card_id))
	return out


static func paint(ci: CanvasItem, rect: Rect2, card_id: String) -> void:
	for s in shapes(card_id, rect):
		match s[0]:
			"rect":
				ci.draw_rect(s[1], s[2])
			"circle":
				ci.draw_circle(s[1], s[2], s[3])
			"poly":
				ci.draw_colored_polygon(s[1], s[2])
			"line":
				ci.draw_line(s[1], s[2], s[3], s[4], true)


## Motifs in unit coordinates (0..1, y down) inside a square.
class _Motif:
	var sq: Rect2
	var out: Array
	var tint: Color

	func _init(p_sq: Rect2, p_out: Array, p_tint: Color) -> void:
		sq = p_sq
		out = p_out
		tint = p_tint

	func at(x: float, y: float) -> Vector2:
		return sq.position + Vector2(x, y) * sq.size.x

	func poly(pts: Array, col: Color) -> void:
		var a := PackedVector2Array()
		for i in range(0, pts.size(), 2):
			a.append(at(pts[i], pts[i + 1]))
		out.append(["poly", a, col])

	func circle(x: float, y: float, r: float, col: Color) -> void:
		out.append(["circle", at(x, y), r * sq.size.x, col])

	func line(x0: float, y0: float, x1: float, y1: float, col: Color, w := 0.05) -> void:
		out.append(["line", at(x0, y0), at(x1, y1), col, maxf(1.0, w * sq.size.x)])

	func box(x: float, y: float, w: float, h: float, col: Color) -> void:
		out.append(["rect", Rect2(at(x, y), Vector2(w, h) * sq.size.x), col])

	func m_fire() -> void:
		poly([0.5, 0.06, 0.68, 0.34, 0.8, 0.28, 0.82, 0.6, 0.7, 0.86, 0.5, 0.94, 0.3, 0.86, 0.18, 0.6, 0.24, 0.36, 0.36, 0.46], Color("e2541b"))
		poly([0.5, 0.36, 0.64, 0.62, 0.6, 0.84, 0.5, 0.88, 0.4, 0.84, 0.36, 0.62], Color("ffd23f"))

	func m_ice() -> void:
		var col := Color("bfe9ff")
		for a in [0.0, PI / 3.0, 2.0 * PI / 3.0]:
			var d := Vector2(cos(a), sin(a)) * 0.42
			line(0.5 - d.x, 0.5 - d.y, 0.5 + d.x, 0.5 + d.y, col, 0.06)
			for sgn: float in [-1.0, 1.0]:
				var tip: Vector2 = Vector2(0.5, 0.5) + d * sgn * 0.7
				var n := Vector2(-d.y, d.x) * 0.35
				line(tip.x, tip.y, tip.x + (d.x * sgn * 0.4 + n.x), tip.y + (d.y * sgn * 0.4 + n.y), col, 0.04)
				line(tip.x, tip.y, tip.x + (d.x * sgn * 0.4 - n.x), tip.y + (d.y * sgn * 0.4 - n.y), col, 0.04)
		circle(0.5, 0.5, 0.08, Color.WHITE)

	func m_arcane() -> void:
		poly([0.5, 0.06, 0.6, 0.4, 0.94, 0.5, 0.6, 0.6, 0.5, 0.94, 0.4, 0.6, 0.06, 0.5, 0.4, 0.4], Color("c77dff"))
		circle(0.5, 0.5, 0.1, Color("f3d9ff"))
		for p in [[0.2, 0.2], [0.8, 0.2], [0.2, 0.8], [0.8, 0.8]]:
			circle(p[0], p[1], 0.05, Color("e0aaff"))

	func m_holy() -> void:
		for i in 8:
			var a := i * PI / 4.0
			line(0.5 + cos(a) * 0.28, 0.5 + sin(a) * 0.28, 0.5 + cos(a) * 0.46, 0.5 + sin(a) * 0.46, Color("ffe066"), 0.06)
		circle(0.5, 0.5, 0.24, Color("ffd43b"))
		circle(0.5, 0.5, 0.15, Color("fff3bf"))

	func m_shadow() -> void:
		circle(0.5, 0.5, 0.4, Color("5a189a"))
		circle(0.6, 0.42, 0.32, Color("240046"))
		circle(0.36, 0.56, 0.06, Color("e0aaff"))
		line(0.12, 0.85, 0.35, 0.7, Color("7b2cbf"), 0.04)
		line(0.88, 0.15, 0.7, 0.3, Color("7b2cbf"), 0.04)

	func m_nature() -> void:
		poly([0.2, 0.85, 0.22, 0.5, 0.4, 0.24, 0.8, 0.1, 0.74, 0.5, 0.52, 0.76], Color("52b788"))
		line(0.2, 0.86, 0.7, 0.22, Color("1b4332"), 0.035)
		line(0.4, 0.6, 0.32, 0.42, Color("1b4332"), 0.025)
		line(0.52, 0.46, 0.62, 0.56, Color("1b4332"), 0.025)

	func m_moon() -> void:
		circle(0.42, 0.5, 0.34, Color("f1f3f5"))
		circle(0.56, 0.42, 0.3, tint.darkened(0.5))
		for p in [[0.8, 0.2, 0.04], [0.85, 0.6, 0.03], [0.68, 0.84, 0.035]]:
			circle(p[0], p[1], p[2], Color("fff3bf"))

	func m_lightning() -> void:
		poly([0.6, 0.04, 0.24, 0.54, 0.46, 0.54, 0.34, 0.96, 0.78, 0.4, 0.54, 0.4, 0.68, 0.04], Color("ffe066"))

	func m_dagger() -> void:
		poly([0.5, 0.06, 0.6, 0.2, 0.56, 0.6, 0.44, 0.6, 0.4, 0.2], Color("dee2e6"))
		line(0.5, 0.12, 0.5, 0.56, Color("adb5bd"), 0.02)
		box(0.3, 0.6, 0.4, 0.06, Color("c9a227"))
		box(0.46, 0.66, 0.08, 0.22, Color("6f4518"))
		circle(0.5, 0.9, 0.05, Color("c9a227"))

	func m_sword() -> void:
		poly([0.5, 0.04, 0.56, 0.12, 0.56, 0.66, 0.44, 0.66, 0.44, 0.12], Color("e9ecef"))
		box(0.26, 0.66, 0.48, 0.06, Color("c9a227"))
		box(0.46, 0.72, 0.08, 0.18, Color("6f4518"))
		circle(0.5, 0.92, 0.05, Color("c9a227"))

	func m_axe() -> void:
		line(0.3, 0.92, 0.66, 0.1, Color("8b5e34"), 0.07)
		poly([0.56, 0.12, 0.92, 0.06, 0.84, 0.48, 0.5, 0.34], Color("ced4da"))
		poly([0.84, 0.48, 0.92, 0.06, 0.96, 0.28], Color("868e96"))

	func m_hammer() -> void:
		line(0.5, 0.36, 0.5, 0.94, Color("8b5e34"), 0.08)
		box(0.2, 0.12, 0.6, 0.26, Color("adb5bd"))
		box(0.2, 0.12, 0.6, 0.06, Color("f8f9fa"))
		circle(0.5, 0.25, 0.06, Color("ffd43b"))

	func m_bow() -> void:
		var pts := []
		for i in 9:
			var a := lerpf(-1.2, 1.2, i / 8.0)
			pts.append(Vector2(0.3 + cos(a) * 0.44, 0.5 + sin(a) * 0.44))
		for i in 8:
			line(pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y, Color("8b5e34"), 0.06)
		line(pts[0].x, pts[0].y, pts[8].x, pts[8].y, Color("f1f3f5"), 0.015)
		line(0.2, 0.5, 0.9, 0.5, Color("ced4da"), 0.03)
		poly([0.94, 0.5, 0.84, 0.44, 0.84, 0.56], Color("adb5bd"))

	func m_shield() -> void:
		poly([0.18, 0.12, 0.82, 0.12, 0.8, 0.52, 0.5, 0.92, 0.2, 0.52], Color("adb5bd"))
		poly([0.26, 0.2, 0.74, 0.2, 0.72, 0.5, 0.5, 0.82, 0.28, 0.5], Color("9d0208"))
		box(0.46, 0.24, 0.08, 0.5, Color("ffd43b"))
		box(0.32, 0.38, 0.36, 0.08, Color("ffd43b"))

	func m_coin() -> void:
		circle(0.5, 0.5, 0.4, Color("e0a800"))
		circle(0.5, 0.5, 0.3, Color("ffd43b"))
		circle(0.4, 0.4, 0.08, Color("fff3bf"))

	func m_skull() -> void:
		circle(0.5, 0.42, 0.32, Color("f1f3f5"))
		box(0.34, 0.62, 0.32, 0.22, Color("f1f3f5"))
		circle(0.38, 0.44, 0.08, Color("212529"))
		circle(0.62, 0.44, 0.08, Color("212529"))
		poly([0.5, 0.54, 0.46, 0.64, 0.54, 0.64], Color("212529"))
		for x in [0.4, 0.5, 0.6]:
			line(x, 0.72, x, 0.84, Color("495057"), 0.02)

	func m_paw() -> void:
		var col := Color("7f5539")
		circle(0.5, 0.64, 0.22, col)
		for p in [[0.22, 0.4], [0.38, 0.22], [0.62, 0.22], [0.78, 0.4]]:
			circle(p[0], p[1], 0.1, col)

	func m_book() -> void:
		poly([0.08, 0.2, 0.48, 0.26, 0.48, 0.86, 0.08, 0.8], Color("f8f1e5"))
		poly([0.52, 0.26, 0.92, 0.2, 0.92, 0.8, 0.52, 0.86], Color("efe3cc"))
		line(0.5, 0.24, 0.5, 0.88, Color("6f4518"), 0.04)
		for y in [0.38, 0.5, 0.62]:
			line(0.16, y, 0.4, y + 0.02, Color("adb5bd"), 0.02)
			line(0.6, y + 0.02, 0.84, y, Color("adb5bd"), 0.02)

	func m_totem() -> void:
		var cols := [Color("9c6644"), Color("b08968"), Color("7f5539")]
		for i in 3:
			box(0.3, 0.1 + i * 0.27, 0.4, 0.25, cols[i])
			circle(0.42, 0.2 + i * 0.27, 0.035, Color("212529"))
			circle(0.58, 0.2 + i * 0.27, 0.035, Color("212529"))
			line(0.4, 0.28 + i * 0.27, 0.6, 0.28 + i * 0.27, Color("212529"), 0.025)
		poly([0.3, 0.12, 0.12, 0.04, 0.3, 0.24], Color("e85d04"))
		poly([0.7, 0.12, 0.88, 0.04, 0.7, 0.24], Color("e85d04"))

	func m_giant() -> void:
		poly([0.06, 0.94, 0.3, 0.3, 0.5, 0.08, 0.72, 0.3, 0.94, 0.94], Color("6c757d"))
		poly([0.42, 0.2, 0.5, 0.08, 0.58, 0.2, 0.5, 0.26], Color("e9ecef"))
		circle(0.4, 0.52, 0.05, Color("ffd43b"))
		circle(0.6, 0.52, 0.05, Color("ffd43b"))
		line(0.38, 0.7, 0.62, 0.7, Color("343a40"), 0.04)

	func m_gear() -> void:
		var col := Color("adb5bd")
		for i in 8:
			var a := i * PI / 4.0
			var d := Vector2(cos(a), sin(a))
			var n := Vector2(-d.y, d.x) * 0.07
			var p0 := Vector2(0.5, 0.5) + d * 0.3
			var p1 := Vector2(0.5, 0.5) + d * 0.44
			poly([p0.x - n.x, p0.y - n.y, p1.x - n.x, p1.y - n.y, p1.x + n.x, p1.y + n.y, p0.x + n.x, p0.y + n.y], col)
		circle(0.5, 0.5, 0.32, col)
		circle(0.5, 0.5, 0.12, Color("495057"))

	func m_banana() -> void:
		var pts := []
		for i in 9:
			var a := lerpf(0.4, 2.7, i / 8.0)
			pts.append(Vector2(0.5 + cos(a) * 0.38, 0.2 + sin(a) * 0.6))
		for i in 8:
			line(pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y, Color("ffd43b"), 0.12)
		circle(pts[0].x, pts[0].y, 0.04, Color("6f4518"))

	func m_orb() -> void:
		circle(0.5, 0.5, 0.42, Color(0.75, 0.95, 1.0, 0.2))
		circle(0.5, 0.5, 0.3, Color(0.75, 0.95, 1.0, 0.45))
		circle(0.5, 0.5, 0.18, Color("e7f5ff"))

	func m_demon() -> void:
		poly([0.26, 0.36, 0.08, 0.04, 0.4, 0.26], Color("343a40"))
		poly([0.74, 0.36, 0.92, 0.04, 0.6, 0.26], Color("343a40"))
		circle(0.5, 0.56, 0.34, Color("9d0208"))
		poly([0.32, 0.48, 0.46, 0.54, 0.32, 0.56], Color("aaff00"))
		poly([0.68, 0.48, 0.54, 0.54, 0.68, 0.56], Color("aaff00"))
		poly([0.36, 0.7, 0.64, 0.7, 0.5, 0.8], Color("370617"))

	func m_dragon() -> void:
		poly([0.5, 0.5, 0.06, 0.1, 0.18, 0.4, 0.04, 0.5, 0.2, 0.62, 0.1, 0.8], Color("2d6a4f"))
		poly([0.5, 0.5, 0.94, 0.1, 0.82, 0.4, 0.96, 0.5, 0.8, 0.62, 0.9, 0.8], Color("2d6a4f"))
		circle(0.5, 0.52, 0.16, Color("40916c"))
		poly([0.42, 0.62, 0.58, 0.62, 0.5, 0.94], Color("40916c"))
		poly([0.42, 0.42, 0.36, 0.24, 0.48, 0.38], Color("d8f3dc"))
		poly([0.58, 0.42, 0.64, 0.24, 0.52, 0.38], Color("d8f3dc"))

	func m_murloc() -> void:
		poly([0.5, 0.06, 0.62, 0.3, 0.38, 0.3], Color("e85d04"))
		circle(0.5, 0.56, 0.36, Color("52b788"))
		circle(0.36, 0.46, 0.1, Color.WHITE)
		circle(0.64, 0.46, 0.1, Color.WHITE)
		circle(0.38, 0.47, 0.045, Color("212529"))
		circle(0.62, 0.47, 0.045, Color("212529"))
		poly([0.3, 0.68, 0.7, 0.68, 0.5, 0.82], Color("1b4332"))

	func m_pirate() -> void:
		m_skull()
		poly([0.16, 0.34, 0.5, 0.06, 0.84, 0.34, 0.5, 0.26], Color("d00000"))
		circle(0.62, 0.44, 0.1, Color("212529"))
		line(0.18, 0.3, 0.84, 0.52, Color("212529"), 0.025)

	func m_yeti() -> void:
		circle(0.5, 0.54, 0.4, Color("f8f9fa"))
		circle(0.5, 0.58, 0.24, Color("a5d8ff"))
		circle(0.42, 0.52, 0.045, Color("212529"))
		circle(0.58, 0.52, 0.045, Color("212529"))
		poly([0.4, 0.68, 0.6, 0.68, 0.5, 0.74], Color("212529"))
		poly([0.2, 0.3, 0.1, 0.06, 0.32, 0.22], Color("dee2e6"))
		poly([0.8, 0.3, 0.9, 0.06, 0.68, 0.22], Color("dee2e6"))

	func m_sheep() -> void:
		for p in [[0.36, 0.46], [0.52, 0.4], [0.66, 0.48], [0.44, 0.6], [0.6, 0.62]]:
			circle(p[0], p[1], 0.16, Color("f8f9fa"))
		circle(0.22, 0.42, 0.11, Color("343a40"))
		for x in [0.38, 0.5, 0.62, 0.72]:
			line(x, 0.74, x, 0.9, Color("343a40"), 0.04)

	func m_humanoid() -> void:
		var col := tint.lightened(0.25)
		poly([0.14, 0.96, 0.22, 0.66, 0.38, 0.56, 0.62, 0.56, 0.78, 0.66, 0.86, 0.96], col)
		circle(0.5, 0.36, 0.2, Color("f1c27d"))
		poly([0.28, 0.36, 0.34, 0.12, 0.5, 0.06, 0.66, 0.12, 0.72, 0.36, 0.64, 0.24, 0.36, 0.24], col.darkened(0.3))
		circle(0.43, 0.38, 0.025, Color("212529"))
		circle(0.57, 0.38, 0.025, Color("212529"))
