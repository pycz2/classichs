class_name Art
extends RefCounted
## Procedural vector art, a different picture for every card. A picture has
## three layers: a scene (sky and landscape in the class colours), the subject
## (a portrait, a beast, a spell effect, a weapon...) and marks for mechanics.
## design() takes every choice from the card data; one pass over all cards in
## dbfId order changes the variant of a card until its design differs from all
## earlier ones. Shapes are plain data ([kind, ...]) so tests can check them;
## paint() draws them.

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

## Words in a minion's name -> race of a humanoid (first match wins).
const RACE_WORDS := [
	["gnome", "gnome"], ["gnomish", "gnome"], ["tinkmaster", "gnome"], ["mekkatorque", "gnome"], ["millhouse", "gnome"],
	["dwarf", "dwarf"], ["ironforge", "dwarf"], ["dark", "dwarf"], ["harrison", "human"],
	["orc", "orc"], ["grunt", "orc"], ["frostwolf", "orc"], ["warsong", "orc"], ["kor", "orc"], ["grommash", "orc"],
	["thrallmar", "orc"], ["dragonmaw", "orc"], ["doomhammer", "orc"],
	["troll", "troll"], ["amani", "troll"], ["gurubashi", "troll"], ["sen", "troll"], ["voodoo", "troll"],
	["darkspear", "troll"], ["zul", "troll"], ["headhunter", "troll"],
	["elven", "elf"], ["elf", "elf"], ["silvermoon", "elf"], ["sunfury", "elf"], ["blood", "elf"], ["quel", "elf"],
	["sylvanas", "undead"], ["elune", "nightelf"], ["keeper", "nightelf"], ["illidan", "nightelf"], ["druid", "nightelf"],
	["tauren", "tauren"], ["bloodhoof", "tauren"], ["sunwalker", "tauren"], ["cairne", "tauren"], ["baine", "tauren"],
	["undead", "undead"], ["ghoul", "undead"], ["skeleton", "undead"], ["cult", "undead"], ["abomination", "undead"],
	["shade", "undead"], ["deathlord", "undead"], ["necromancer", "undead"],
	["ogre", "ogre"], ["boulderfist", "ogre"], ["gruul", "ogre"],
	["goblin", "goblin"], ["gadgetzan", "goblin"], ["venture", "goblin"], ["booty", "goblin"], ["bomber", "goblin"],
	["pandaren", "pandaren"], ["shado", "pandaren"], ["brewmaster", "pandaren"], ["lorewalker", "pandaren"], ["cho", "pandaren"],
	["naga", "naga"], ["myrmidon", "naga"], ["siren", "naga"],
	["draenei", "draenei"], ["velen", "draenei"],
	["gnoll", "gnoll"], ["hogger", "gnoll"], ["riverpaw", "gnoll"],
	["kobold", "kobold"],
]
## Words in a name -> role of a humanoid: headgear and the thing in the hand.
const ROLE_WORDS := [
	["archmage", "mage"], ["mage", "mage"], ["magi", "mage"], ["sorcerer", "mage"], ["apprentice", "mage"],
	["kirin", "mage"], ["arcanist", "mage"], ["antonidas", "mage"], ["bloodmage", "mage"], ["conjurer", "mage"],
	["millhouse", "mage"], ["teacher", "scholar"], ["lorewalker", "scholar"], ["secretkeeper", "scholar"],
	["priest", "priest"], ["priestess", "priest"], ["cleric", "priest"], ["acolyte", "priest"], ["healer", "priest"],
	["prophet", "priest"], ["sister", "priest"], ["soulpriest", "priest"], ["lightwarden", "priest"], ["mender", "priest"],
	["king", "king"], ["lord", "king"], ["chieftain", "king"], ["leader", "king"], ["commander", "king"],
	["warlord", "king"], ["ringleader", "king"], ["captain", "pirate"], ["emperor", "king"], ["baron", "king"],
	["pirate", "pirate"], ["bodyguard", "pirate"], ["swashbuckler", "pirate"], ["corsair", "pirate"],
	["assassin", "rogue"], ["bandit", "rogue"], ["nightblade", "rogue"], ["infiltrator", "rogue"], ["agent", "rogue"],
	["disguise", "rogue"], ["defias", "rogue"], ["vancleef", "rogue"], ["juggler", "rogue"], ["sylvanas", "hunter"],
	["shaman", "shaman"], ["farseer", "shaman"], ["windspeaker", "shaman"], ["earthen", "shaman"], ["doctor", "shaman"],
	["witch", "shaman"], ["thrall", "shaman"],
	["knight", "knight"], ["champion", "knight"], ["crusader", "knight"], ["defender", "knight"], ["guardian", "knight"],
	["protector", "knight"], ["squire", "knight"], ["recruit", "knight"], ["footman", "knight"], ["watcher", "knight"],
	["peacekeeper", "knight"], ["paladin", "knight"], ["shieldmasta", "knight"], ["shieldbearer", "knight"], ["warden", "knight"],
	["enforcer", "knight"], ["argent", "knight"], ["tirion", "knight"], ["sunwalker", "knight"],
	["warrior", "warrior"], ["berserker", "warrior"], ["grunt", "warrior"], ["elite", "warrior"], ["gladiator", "warrior"],
	["blademaster", "warrior"], ["sergeant", "warrior"], ["taskmaster", "warrior"], ["arena", "warrior"], ["grommash", "warrior"],
	["armorsmith", "warrior"], ["weaponsmith", "warrior"], ["swordsmith", "warrior"], ["wolfrider", "warrior"], ["mercenary", "warrior"],
	["hunter", "hunter"], ["archer", "hunter"], ["rifleman", "hunter"], ["houndmaster", "hunter"], ["scout", "hunter"],
	["commando", "hunter"], ["windrunner", "hunter"], ["nesingwary", "hunter"], ["pagle", "hunter"], ["trapper", "hunter"],
	["engineer", "engineer"], ["inventor", "engineer"], ["mechanic", "engineer"], ["tinkmaster", "engineer"],
	["alchemist", "engineer"], ["bomber", "engineer"], ["rocketeer", "engineer"], ["mekkatorque", "engineer"], ["tech", "engineer"],
	["brewmaster", "brewer"], ["brew", "brewer"], ["auctioneer", "merchant"], ["hoarder", "merchant"], ["harrison", "merchant"],
	["druid", "druid"], ["keeper", "druid"], ["elune", "druid"], ["warlock", "warlock"], ["summoner", "warlock"],
	["doomsayer", "warlock"], ["cult", "warlock"], ["shadow", "warlock"],
]
const CLASS_ROLE := {"MAGE": "mage", "PRIEST": "priest", "PALADIN": "knight", "WARRIOR": "warrior", "ROGUE": "rogue",
	"HUNTER": "hunter", "SHAMAN": "shaman", "DRUID": "druid", "WARLOCK": "warlock"}
## Words in a beast's name -> animal (first match wins).
const ANIMAL_WORDS := [
	["raptor", "raptor"], ["devilsaur", "raptor"], ["ravasaur", "raptor"], ["krush", "raptor"],
	["hyena", "hyena"], ["scavenging", "hyena"], ["wolf", "wolf"], ["worgen", "wolf"], ["hound", "wolf"], ["dog", "wolf"],
	["bear", "bear"], ["ironfur", "bear"], ["grizzly", "bear"], ["boar", "boar"], ["tusk", "boar"], ["stonetusk", "boar"],
	["panther", "cat"], ["tiger", "cat"], ["cat", "cat"], ["lion", "cat"], ["lynx", "cat"], ["leokk", "cat"], ["huffer", "wolf"],
	["misha", "bear"], ["hawk", "bird"], ["owl", "bird"], ["crow", "bird"], ["raven", "bird"], ["buzzard", "bird"],
	["bird", "bird"], ["harpy", "bird"], ["ironbeak", "bird"], ["eagle", "bird"], ["spider", "spider"], ["webspinner", "spider"],
	["snake", "snake"], ["serpent", "snake"], ["cobra", "snake"], ["viper", "snake"], ["wyrm", "snake"],
	["crab", "crab"], ["crawler", "crab"], ["turtle", "turtle"], ["tortoise", "turtle"], ["mukla", "ape"], ["gorilla", "ape"],
	["ape", "ape"], ["monkey", "ape"], ["kodo", "kodo"], ["yak", "kodo"], ["ox", "kodo"], ["bat", "bat"],
	["shark", "fish"], ["fish", "fish"], ["frog", "frog"], ["toad", "frog"], ["whelp", "whelp"], ["squirrel", "squirrel"],
	["rat", "squirrel"], ["chicken", "bird"], ["gnoll", "hyena"], ["imp", "bat"],
]
const ANIMALS := ["raptor", "hyena", "wolf", "bear", "boar", "cat", "bird", "spider", "snake", "crab", "turtle", "ape", "kodo", "bat", "fish", "frog", "whelp", "squirrel"]
## Minions that are not humanoids or beasts, by name.
const MINION_MOTIFS := [
	["yeti", "yeti"], ["sheep", "sheep"], ["wisp", "orb"], ["lightwell", "orb"], ["spirit", "orb"], ["shadow", "orb"],
	["ragnaros", "elemental"], ["geddon", "elemental"], ["akir", "elemental"], ["elemental", "elemental"], ["devil", "elemental"],
	["flame", "elemental"], ["giant", "giant"], ["golem", "giant"], ["treant", "tree"], ["ancient", "tree"], ["cenarius", "tree"],
	["ironbark", "tree"], ["ooze", "ooze"], ["faceless", "faceless"], ["imp", "demon"], ["voidwalker", "demon"],
	["felguard", "demon"], ["succubus", "demon"], ["infernal", "demon"], ["jaraxxus", "demon"], ["doomguard", "demon"],
	["whelp", "dragon"], ["wyrm", "dragon"], ["drake", "dragon"], ["onyxia", "dragon"], ["ysera", "dragon"],
	["malygos", "dragon"], ["alexstrasza", "dragon"], ["nozdormu", "dragon"], ["deathwing", "dragon"], ["mirror", "mirror"],
	["image", "mirror"], ["totem", "totem"], ["harvest", "gear"], ["bot", "gear"], ["mech", "gear"], ["robot", "gear"],
	["poultryizer", "gear"], ["repair", "gear"], ["target", "gear"], ["sapling", "tree"], ["panther", "beast"], ["snake", "beast"],
	["wolf", "beast"], ["gorilla", "beast"], ["frog", "beast"], ["squirrel", "beast"], ["chicken", "beast"],
	["brother", "beast"], ["mukla", "beast"], ["mana", "elemental"], ["wraith", "orb"], ["portal", "portal"], ["summoning", "portal"],
]
## Old name motifs -> spell element.
const ELEMENTS := {"fire": "fire", "ice": "ice", "arcane": "arcane", "moon": "moon", "holy": "holy", "shadow": "shadow",
	"nature": "nature", "lightning": "lightning", "dagger": "poison", "skull": "shadow", "paw": "nature", "book": "arcane",
	"coin": "gold", "sheep": "arcane", "totem": "nature", "banana": "nature", "orb": "holy", "axe": "steel", "sword": "steel",
	"hammer": "holy", "bow": "nature", "shield": "steel", "gear": "steel", "giant": "nature", "demon": "shadow", "murloc": "nature"}
const CLASS_ELEMENT := {"MAGE": "arcane", "PRIEST": "holy", "PALADIN": "holy", "WARLOCK": "shadow", "DRUID": "nature",
	"SHAMAN": "lightning", "ROGUE": "poison", "HUNTER": "nature", "WARRIOR": "steel", "DREAM": "moon"}
const ELEMENT_COLORS := {"fire": ["e2541b", "ffd23f"], "ice": ["4dabf7", "e7f5ff"], "arcane": ["c77dff", "f3d9ff"],
	"moon": ["adb5bd", "fff3bf"], "holy": ["fab005", "fff9db"], "shadow": ["7b2cbf", "e0aaff"], "nature": ["40c057", "d8f5a2"],
	"lightning": ["74c0fc", "fff3bf"], "poison": ["82c91e", "e9fac8"], "steel": ["868e96", "f1f3f5"], "gold": ["f59f00", "fff3bf"]}
const WEAPON_WORDS := [["doomhammer", "hammer"], ["hammer", "hammer"], ["justice", "hammer"], ["bow", "bow"], ["longbow", "bow"],
	["glaive", "glaive"], ["warglaive", "glaive"], ["warglaives", "glaive"], ["knife", "dagger"], ["assassin", "dagger"],
	["perdition", "dagger"], ["axe", "axe"], ["reaper", "axe"], ["gorehowl", "axe"], ["fury", "axe"], ["sword", "sword"]]
const SCENES := ["hills", "mountains", "forest", "sea", "castle", "night", "cave", "desert", "clouds", "arcane"]
## Hero portraits: race, role and colours of hair and clothes.
const HEROES := {"MAGE": ["human", "jaina"], "WARRIOR": ["orc", "garrosh"], "HUNTER": ["orc", "rexxar"],
	"DRUID": ["nightelf", "malfurion"], "ROGUE": ["elf", "valeera"], "PRIEST": ["human", "anduin"],
	"PALADIN": ["human", "uther"], "SHAMAN": ["orc", "thrall"], "WARLOCK": ["orc", "guldan"]}

static var _designs := {}
static var _textures := {}
## Picture sets: the active pack's art sets (art/<set>/<card id>.jpg|png|webp in the
## pack), plus the player's own folders in res://art (any folder but "cards"; "original"
## holds the original art, tools/fetch_original_art.py, local only) that have pictures of
## the pack's cards. The choice is per pack (Packs.choice "art").
static var root := "res://art"
const EXTENSIONS := ["jpg", "png", "webp", "jpeg"]

static var _word_re := RegEx.create_from_string("[a-z]+")


static func _english(c: Dictionary, field := "name") -> String:
	var n = c.get(field, "")
	return str(n.get("enUS", "")) if n is Dictionary else str(n)


static func _words(c: Dictionary) -> Array:
	var out := []
	for w in _word_re.search_all(_english(c).to_lower()):
		out.append(w.get_string())
	return out


static func _find(words: Array, table: Array, fallback: String) -> String:
	for row in table:
		for w in words:
			if w.begins_with(row[0]):
				return row[1]
	return fallback


## The name motif from KEYWORDS ("fire", "axe", "paw"...).
static func motif(card_id: String) -> String:
	return _find(_words(CardDb.card(card_id)), KEYWORDS, "")


## What the spell does, read from its English text.
static func _form(c: Dictionary) -> String:
	var t := _english(c, "text").to_lower()
	if c.get("mechanics", []).has("SECRET"):
		return "secret"
	for row in [["transform", "transform"], ["destroy", "destroy"]]:
		if t.contains(row[0]):
			return row[1]
	if t.contains("damage"):
		for w in ["all ", "adjacent", "split", "each ", "random"]:
			if t.contains(w):
				return "area"
		return "projectile"
	for row in [["restore", "heal"], ["heal", "heal"], ["draw", "draw"], ["copy", "draw"], ["summon", "summon"],
			["freeze", "area"], ["armor", "protect"], ["divine shield", "protect"], ["immune", "protect"], ["taunt", "protect"],
			["stealth", "protect"], ["return", "return"], ["silence", "silence"], ["mana", "mana"], ["attack", "buff"],
			["health", "buff"], ["+", "buff"], ["hand", "draw"]]:
		if t.contains(row[0]):
			return row[1]
	return "emblem"


## [kind, subject] before the variant is chosen.
static func _subject(c: Dictionary) -> Array:
	var words := _words(c)
	var cls: String = c.get("cardClass", "NEUTRAL")
	var type: String = c.get("type", "MINION")
	if type == "HERO":
		if words.has("jaraxxus"):
			return ["motif", ["demon"]]
		if HEROES.has(cls):
			return ["hero", [cls]]
	if type in ["SPELL", "HERO_POWER"]:
		var el: String = ELEMENTS.get(_find(words, KEYWORDS, ""), CLASS_ELEMENT.get(cls, "arcane"))
		return ["spell", [el, _form(c)]]
	if type == "WEAPON":
		return ["weapon", [_find(words, WEAPON_WORDS, "sword")]]
	match c.get("race", ""):
		"BEAST":
			return ["beast", [_find(words, ANIMAL_WORDS, ANIMALS[hash(c.get("id", "")) % ANIMALS.size()])]]
		"MURLOC":
			return ["motif", ["murloc"]]
		"DRAGON":
			return ["motif", ["dragon"]]
		"DEMON":
			return ["motif", ["demon"]]
		"MECHANICAL":
			return ["motif", ["gear"]]
		"TOTEM":
			return ["motif", ["totem"]]
	var m := _find(words, MINION_MOTIFS, "")
	if m == "beast":
		return ["beast", [_find(words, ANIMAL_WORDS, "ape")]]
	if m in ["elemental", "giant"]:
		return ["motif", [m, ELEMENTS.get(_find(words, KEYWORDS, ""), "nature")]]
	if m != "":
		return ["motif", [m]]
	var race := _find(words, RACE_WORDS, "human")
	if c.get("race", "") == "PIRATE":
		return ["humanoid", [race, "pirate"]]
	return ["humanoid", [race, _find(words, ROLE_WORDS, CLASS_ROLE.get(cls, "commoner"))]]


static func _variant(card_id: String, v: int) -> Dictionary:
	var h := hash(card_id + "#" + str(v))
	return {"scene": SCENES[h % SCENES.size()], "accent": (h >> 4) % 12, "look": (h >> 8) % 6,
		"flip": (h >> 12) % 2 == 1, "scale": (h >> 13) % 3, "shift": (h >> 15) % 3 - 1}


## The picture plan of a card: kind, subject, look, scene, accent, flip, scale, shift, marks.
static func design(card_id: String) -> Dictionary:
	if _designs.is_empty():
		_plan_all()
	if not _designs.has(card_id):  # a card defined later (tests): plan it alone
		_designs[card_id] = _plan(card_id, 0)
	return _designs[card_id]


static func _plan(card_id: String, v: int) -> Dictionary:
	var c := CardDb.card(card_id)
	var s := _subject(c)
	var d := _variant(card_id, v)
	d.id = card_id
	d.kind = s[0]
	d.subject = s[1]
	d.cost = int(c.get("cost", 0))
	d.cls = c.get("cardClass", "NEUTRAL")
	d.legendary = c.get("rarity", "") == "LEGENDARY"
	d.marks = c.get("mechanics", []).filter(func(m): return m in ["TAUNT", "DIVINE_SHIELD", "CHARGE", "WINDFURY", "STEALTH", "SPELLPOWER", "FREEZE"]) if c.get("type") == "MINION" else []
	return d


static func key(d: Dictionary) -> String:
	return "%s|%s|%d|%s|%d|%s|%d|%d" % [d.kind, d.subject, d.look, d.scene, d.accent, d.flip, d.scale, d.shift]


static func _plan_all() -> void:
	var ids := CardDb.all_ids()
	ids.sort_custom(func(a, b): return int(CardDb.card(a).get("dbfId", 0)) < int(CardDb.card(b).get("dbfId", 0)) or (CardDb.card(a).get("dbfId", 0) == CardDb.card(b).get("dbfId", 0) and a < b))
	var strict := {}
	var looks := {}
	for id in ids:
		var d := _plan(id, 0)
		for v in 3000:
			d = _plan(id, v)
			var one := "%s|%s" % [d.subject, d.scene]
			var two := "%s|%s|%s" % [d.subject, d.scene, d.look]
			if not strict.has(one) or (v > 300 and not looks.has(two)):  # common subjects: the look tells them apart
				strict[one] = true
				looks[two] = true
				break
		_designs[id] = d


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
	var d := design(card_id)
	var out := []
	var base := Palette.of_class(d.cls)
	var acc := Color.from_hsv(d.accent / 12.0, 0.55, 0.8)
	_Scene.new(rect, out, base, acc, d.scene, hash(card_id) % 100000).draw()
	var side := minf(rect.size.x, rect.size.y)
	var sq := Rect2(rect.position + (rect.size - Vector2(side, side)) / 2.0, Vector2(side, side)).grow(-side * 0.03)
	var pen := _Pen.new(sq, out, acc, d)
	pen.before_marks()
	pen.subject()
	pen.after_marks()
	return out


## The card's illustration, or null when it has none (the drawn art is used then): the
## chosen set, else the pack's default set.
static func texture(card_id: String) -> Texture2D:
	if not _textures.has(card_id):
		var p := Packs.active()
		var tex: Texture2D = null
		var chosen := Packs.choice(p, "art") if p else ""
		if p and not p.sets("art").any(func(s): return s.id == chosen) and sets().has(chosen):
			for ext in EXTENSIONS:  # a folder of the player's
				tex = _load("%s/%s/%s.%s" % [root, chosen, card_id, ext], ext)
				if tex:
					break
		for set_id in [chosen, p.default_set("art") if p else ""]:
			if tex == null and p and set_id != "":
				var f := p.find("art/" + set_id, card_id, EXTENSIONS)
				tex = p.texture(f) if f != "" else null
		_textures[card_id] = tex
	return _textures[card_id]


## Loads a picture: raw bytes when the file is there as it is, else Godot's
## imported texture (a player's set dropped in without import settings).
static func _load(path: String, ext: String) -> Texture2D:
	if FileAccess.file_exists(path):
		var img := Image.new()
		var bytes := FileAccess.get_file_as_bytes(path)
		var err: int = {"png": img.load_png_from_buffer, "webp": img.load_webp_from_buffer}.get(ext, img.load_jpg_from_buffer).call(bytes)
		if err == OK:
			return ImageTexture.create_from_image(img)
	if path.begins_with("res://") and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


static var _sets: Array = []


## The picture sets there are: the pack's (not the local ones a build marked), then the
## player's folders that have pictures of the pack's cards.
static func sets() -> Array:
	if _sets.is_empty():
		var p := Packs.active()
		var out := []
		for s in p.sets("art") if p else []:
			if not s.get("local", false) or p.builtin():
				out.append(str(s.id))
		var dirs := Array(DirAccess.get_directories_at(root)) if DirAccess.dir_exists_absolute(root) else []
		dirs.sort()
		if dirs.has("original"):  # the original art first among the folders, as before
			dirs.erase("original")
			dirs.push_front("original")
		for d in dirs:
			if d != "cards" and not d.begins_with(".") and not out.has(d) and _has_pack_cards("%s/%s" % [root, d]):
				out.append(d)
		_sets = out
	return _sets.duplicate()


## Whether a folder has a picture of one of the active pack's cards (among its first files).
static func _has_pack_cards(dir: String) -> bool:
	var files := Array(DirAccess.get_files_at(dir)).slice(0, 40)
	return files.any(func(f: String):  # an export lists imported pictures as <name>.jpg.import
		f = f.trim_suffix(".import").trim_suffix(".remap")
		return EXTENSIONS.has(f.get_extension()) and CardDb.has(f.get_basename()))


## Forgets loaded pictures (after the picture set changes).
static func reset() -> void:
	_textures = {}
	_sets = []


## Forgets everything of the pack (after the active pack changes): pictures and picture plans.
static func reset_all() -> void:
	reset()
	_designs = {}


## Points of a portrait outline inside rect: "oval", "arch", "circle" or "rect".
static func outline(shape: String, rect: Rect2, n := 32) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var c := rect.get_center()
	var rx := rect.size.x / 2.0
	var ry := rect.size.y / 2.0
	match shape:
		"oval", "circle":
			if shape == "circle":
				rx = minf(rx, ry)
				ry = rx
			for i in n:
				var a := TAU * i / n
				pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		"arch":
			pts.append(rect.position + Vector2(0, rect.size.y))
			for i in n / 2 + 1:
				var a := PI + PI * i / (n / 2)
				pts.append(Vector2(c.x + cos(a) * rx, rect.position.y + rx * 0.6 + sin(a) * rx * 0.6))
			pts.append(rect.end)
		_:
			pts.append_array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	return pts


## Draws the illustration (or the drawn art) filling a shape inside rect.
static func paint_in(ci: CanvasItem, rect: Rect2, card_id: String, shape := "rect") -> void:
	var tex := texture(card_id)
	if tex == null:
		paint(ci, rect, card_id)
		return
	var pts := outline(shape, rect)
	var side := maxf(rect.size.x, rect.size.y)  # cover: the square picture fills the longer side
	var uv_rect := Rect2(rect.get_center() - Vector2(side, side) / 2.0, Vector2(side, side))
	var uvs := PackedVector2Array()
	for p in pts:
		uvs.append((p - uv_rect.position) / uv_rect.size)
	ci.draw_colored_polygon(pts, Color.WHITE, uvs, tex)


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


## Background: sky bands and a landscape over the whole art rect (x, y in 0..1).
class _Scene:
	var rect: Rect2
	var out: Array
	var base: Color
	var acc: Color
	var kind: String
	var seed: int

	func _init(p_rect: Rect2, p_out: Array, p_base: Color, p_acc: Color, p_kind: String, p_seed: int) -> void:
		rect = p_rect
		out = p_out
		base = p_base
		acc = p_acc
		kind = p_kind
		seed = p_seed

	func p(x: float, y: float) -> Vector2:
		return rect.position + Vector2(clampf(x, 0, 1), clampf(y, 0, 1)) * rect.size

	func poly(pts: Array, col: Color) -> void:
		var a := PackedVector2Array()
		for i in range(0, pts.size(), 2):
			a.append(p(pts[i], pts[i + 1]))
		out.append(["poly", a, col])

	func band(y0: float, y1: float, col: Color) -> void:
		poly([0, y0, 1, y0, 1, y1, 0, y1], col)

	func dot(x: float, y: float, r: float, col: Color) -> void:
		var rr := r * minf(rect.size.x, rect.size.y)
		var c := p(x, y)
		c.x = clampf(c.x, rect.position.x + rr, rect.end.x - rr)
		c.y = clampf(c.y, rect.position.y + rr, rect.end.y - rr)
		out.append(["circle", c, rr, col])

	## A wavy ground line from x=0 to 1 around height y, filled down to the bottom.
	func ridge(y: float, amp: float, freq: float, col: Color) -> void:
		var pts := [0.0, 1.0]
		for i in 11:
			var x := i / 10.0
			pts.append_array([x, y + amp * sin(x * freq + seed * 0.7)])
		pts.append_array([1.0, 1.0])
		poly(pts, col)

	func r01(i: int) -> float:  # a fixed pseudo random number for this card
		return float(hash(seed * 131 + i) % 1000) / 1000.0

	func draw() -> void:
		var sky: Array = {"night": ["0b1026", "2b2d6e"], "cave": ["1b1716", "3b2f2f"], "desert": ["e8a15c", "ffe8a3"],
			"arcane": ["240046", "5a189a"], "sea": ["5c9fd6", "d0ebff"]}.get(kind, ["4a8fc2", "cfe8ff"])
		var top := Color(sky[0]).lerp(base, 0.3).darkened(0.1)
		var bottom := Color(sky[1]).lerp(base, 0.2).darkened(0.1)
		for i in 6:
			band(i / 6.0, (i + 1) / 6.0 + 0.01, top.lerp(bottom, i / 5.0))
		call("s_" + kind)

	func s_hills() -> void:
		dot(0.15 + r01(1) * 0.7, 0.18, 0.09, Color("fff3bf", 0.9))
		ridge(0.6, 0.05, 6.0, Color("74b816").lerp(base, 0.3).darkened(0.35))
		ridge(0.74, 0.05, 4.5, Color("94d82d").lerp(base, 0.25).darkened(0.25))

	func s_mountains() -> void:
		var rock := Color("6c7a89").lerp(base, 0.2)
		for m in [[0.0, 0.2, 0.42, 0.38], [0.3, 0.55, 0.8, 0.26], [0.62, 0.85, 1.0, 0.4]]:
			poly([m[0], 0.78, m[1], m[3], m[2], 0.78], rock.darkened(r01(int(m[1] * 10)) * 0.3))
			poly([m[1] - 0.06, m[3] + 0.1, m[1], m[3], m[1] + 0.06, m[3] + 0.1], Color("f1f3f5"))
		band(0.76, 1.0, Color("5c7a3a").lerp(base, 0.3).darkened(0.3))

	func s_forest() -> void:
		band(0.7, 1.0, Color("2b8a3e").lerp(base, 0.3).darkened(0.45))
		for i in 7:
			var x := i / 6.0
			var top := 0.36 + r01(i) * 0.16
			poly([x - 0.08, 0.76, x, top, x + 0.08, 0.76], Color("2f9e44").lerp(base, 0.2).darkened(0.3 + r01(i + 9) * 0.3))

	func s_sea() -> void:
		band(0.6, 1.0, Color("1971c2").lerp(base, 0.2).darkened(0.1))
		dot(0.2 + r01(2) * 0.6, 0.5, 0.1, Color("ffd43b", 0.85))
		for row in 3:
			for i in 4:
				var x := (i + r01(row * 4 + i)) / 4.0
				var y := 0.68 + row * 0.1
				poly([x - 0.06, y, x, y - 0.02, x + 0.06, y, x, y + 0.008], Color("a5d8ff", 0.7))

	func s_castle() -> void:
		var stone := Color("868e96").lerp(base, 0.2)
		band(0.78, 1.0, Color("5c940d").lerp(base, 0.3).darkened(0.35))
		band(0.56, 0.8, stone.darkened(0.15))
		for i in 8:
			var x := i / 8.0
			poly([x, 0.5, x + 0.07, 0.5, x + 0.07, 0.57, x, 0.57], stone.darkened(0.15))
		var tx := 0.7 if seed % 2 == 0 else 0.12
		poly([tx, 0.3, tx + 0.16, 0.3, tx + 0.16, 0.8, tx, 0.8], stone)
		poly([tx - 0.02, 0.3, tx + 0.08, 0.12, tx + 0.18, 0.3], Color("c92a2a").lerp(acc, 0.4))
		poly([tx + 0.06, 0.42, tx + 0.1, 0.42, tx + 0.1, 0.52, tx + 0.06, 0.52], Color("212529"))

	func s_night() -> void:
		for i in 14:
			dot(r01(i), r01(i + 50) * 0.55, 0.01 + r01(i + 90) * 0.012, Color("fff9db", 0.5 + r01(i + 20) * 0.5))
		dot(0.12 + r01(7) * 0.76, 0.2, 0.08, Color("f1f3f5"))
		ridge(0.76, 0.06, 5.0, Color("0b1026").lerp(base, 0.25))

	func s_cave() -> void:
		var rock := Color("3b2f2f").lerp(base, 0.15)
		band(0.8, 1.0, rock.darkened(0.3))
		poly([0, 0, 0.32, 0, 0.2, 0.25, 0.08, 0.6, 0, 0.8], rock)
		poly([1, 0, 0.68, 0, 0.8, 0.25, 0.92, 0.6, 1, 0.8], rock)
		for i in 5:
			var x := 0.3 + i * 0.1
			poly([x - 0.025, 0, x, 0.08 + r01(i) * 0.12, x + 0.025, 0], rock.darkened(0.2))
		for i in 3:
			var x := 0.1 + r01(i + 30) * 0.8
			poly([x - 0.03, 0.92, x, 0.78, x + 0.03, 0.92], acc.lightened(0.3))

	func s_desert() -> void:
		dot(0.25 + r01(3) * 0.5, 0.22, 0.13, Color("fff3bf", 0.9))
		ridge(0.66, 0.06, 3.5, Color("f08c00").lerp(base, 0.15).darkened(0.1))
		ridge(0.8, 0.04, 5.5, Color("ffc078").lerp(base, 0.15))

	func s_clouds() -> void:
		for i in 4:
			var x := 0.1 + r01(i) * 0.8
			var y := 0.12 + r01(i + 10) * 0.35
			for k in 3:
				dot(x + (k - 1) * 0.07, y + (0.02 if k == 1 else 0.035), 0.06 + 0.02 * float(k == 1), Color(1, 1, 1, 0.75))
		ridge(0.82, 0.03, 4.0, Color("8ce99a").lerp(base, 0.3).darkened(0.3))

	func s_arcane() -> void:
		for i in 4:
			dot(0.5, 0.5, 0.48 - i * 0.1, Color(acc.lightened(0.3), 0.08 + i * 0.03))
		for i in 10:
			var a := TAU * i / 10.0 + seed
			dot(0.5 + cos(a) * 0.4, 0.5 + sin(a) * 0.4, 0.015, Color(acc.lightened(0.5), 0.8))
		band(0.84, 1.0, Color("240046").lerp(base, 0.2).darkened(0.2))


## The subject and mechanic marks in unit coordinates (0..1, y down) inside a
## square; the design's flip, scale and shift move the whole drawing.
class _Pen:
	const SKIN := {"human": "f1c27d", "elf": "f5d0a9", "nightelf": "9c88d6", "gnome": "ffd8b1", "dwarf": "e0a370",
		"orc": "6a994e", "troll": "5f9ea0", "tauren": "8b5e34", "undead": "a3b18a", "ogre": "c08552", "goblin": "94d82d",
		"pandaren": "f8f9fa", "naga": "38d9a9", "draenei": "b197fc", "gnoll": "a47148", "kobold": "8d6e63"}
	const HUMAN_SKINS := ["f1c27d", "e0ac69", "c68642", "8d5524", "ffdbac", "d4a373"]
	const HAIR := ["3b2a1e", "e9c46a", "b5651d", "1c1c1c", "adb5bd", "6f4518"]
	const ROLE_COLOR := {"mage": "7048e8", "priest": "e9ecef", "knight": "adb5bd", "king": "c92a2a", "pirate": "1971c2",
		"rogue": "343a40", "shaman": "2f9e44", "warrior": "a61e4d", "hunter": "5c940d", "engineer": "e67700",
		"brewer": "9c6644", "merchant": "f59f00", "druid": "2b8a3e", "warlock": "5f3dc4", "scholar": "1864ab",
		"commoner": "868e96", "jaina": "4263eb", "garrosh": "5c3b1e", "rexxar": "6b4226", "malfurion": "2b8a3e",
		"valeera": "c92a2a", "anduin": "f8f9fa", "uther": "fab005", "thrall": "495057", "guldan": "5f3dc4"}
	const ANIMAL_COLOR := {"raptor": "7fb069", "hyena": "c9a227", "wolf": "868e96", "bear": "7f5539", "boar": "8d6e63",
		"cat": "e8590c", "bird": "4dabf7", "spider": "495057", "snake": "2f9e44", "crab": "e03131", "turtle": "2b8a3e",
		"ape": "495057", "kodo": "9c6644", "bat": "5f3dc4", "fish": "1c7ed6", "frog": "40c057", "whelp": "e8590c", "squirrel": "b8763e"}

	var sq: Rect2
	var out: Array
	var acc: Color
	var tint: Color
	var d: Dictionary
	var k: float
	var off: float

	func _init(p_sq: Rect2, p_out: Array, p_acc: Color, p_d: Dictionary) -> void:
		sq = p_sq
		out = p_out
		acc = p_acc
		tint = p_acc.darkened(0.3)
		d = p_d
		k = [0.8, 0.88, 0.96][d.scale]
		off = d.shift * (1.0 - k) / 2.0

	func at(x: float, y: float) -> Vector2:
		var u := 1.0 - x if d.flip else x
		var q := (Vector2(u, y) - Vector2(0.5, 0.5)) * k + Vector2(0.5 + off, 0.5 + (1.0 - k) * 0.4)
		return sq.position + q.clamp(Vector2.ZERO, Vector2.ONE) * sq.size.x

	func poly(pts: Array, col: Color) -> void:
		var a := PackedVector2Array()
		for i in range(0, pts.size(), 2):
			a.append(at(pts[i], pts[i + 1]))
		out.append(["poly", a, col])

	func circle(x: float, y: float, r: float, col: Color) -> void:
		var rr := r * k
		var cx := clampf(x, rr / k, 1.0 - rr / k)
		var cy := clampf(y, rr / k, 1.0 - rr / k)
		out.append(["circle", at(cx, cy), rr * sq.size.x, col])

	func line(x0: float, y0: float, x1: float, y1: float, col: Color, w := 0.05) -> void:
		out.append(["line", at(x0, y0), at(x1, y1), col, maxf(1.0, w * k * sq.size.x)])

	func box(x: float, y: float, w: float, h: float, col: Color) -> void:
		poly([x, y, x + w, y, x + w, y + h, x, y + h], col)

	func ellipse(x: float, y: float, rx: float, ry: float, col: Color, n := 14) -> void:
		var pts := []
		for i in n:
			var a := TAU * i / n
			pts.append_array([x + cos(a) * rx, y + sin(a) * ry])
		poly(pts, col)

	func ring(x: float, y: float, rx: float, ry: float, col: Color, w := 0.03, n := 18) -> void:
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			line(x + cos(a0) * rx, y + sin(a0) * ry, x + cos(a1) * rx, y + sin(a1) * ry, col, w)

	func sparkle(x: float, y: float, r: float, col: Color) -> void:
		poly([x, y - r, x + r * 0.3, y - r * 0.3, x + r, y, x + r * 0.3, y + r * 0.3, x, y + r, x - r * 0.3, y + r * 0.3, x - r, y, x - r * 0.3, y - r * 0.3], col)

	# --- mechanics -----------------------------------------------------------

	func before_marks() -> void:
		if d.legendary:
			for i in 10:
				var a := TAU * i / 10.0 + 0.3
				var a2 := a + 0.12
				poly([0.5, 0.5, 0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5, 0.5 + cos(a2) * 0.5, 0.5 + sin(a2) * 0.5], Color("ffd43b", 0.35))
		if "TAUNT" in d.marks:
			poly([0.1, 0.12, 0.9, 0.12, 0.88, 0.6, 0.5, 0.98, 0.12, 0.6], Color("868e96", 0.85))
			poly([0.16, 0.18, 0.84, 0.18, 0.82, 0.58, 0.5, 0.9, 0.18, 0.58], Color("495057", 0.85))

	func after_marks() -> void:
		if "DIVINE_SHIELD" in d.marks:
			ring(0.5, 0.52, 0.46, 0.46, Color("ffe066", 0.95), 0.035)
		if "CHARGE" in d.marks:
			for i in 3:
				line(0.02, 0.45 + i * 0.12, 0.18 - i * 0.03, 0.45 + i * 0.12, Color(1, 1, 1, 0.85), 0.03)
		if "WINDFURY" in d.marks:
			for i in 2:
				for s in 6:
					var a0 := -1.2 + s * 0.4
					line(0.82 + cos(a0) * (0.1 + i * 0.06), 0.3 + sin(a0) * (0.1 + i * 0.06), 0.82 + cos(a0 + 0.4) * (0.1 + i * 0.06), 0.3 + sin(a0 + 0.4) * (0.1 + i * 0.06), Color("e7f5ff", 0.9), 0.025)
		if "STEALTH" in d.marks:
			for i in 4:
				circle(0.2 + i * 0.2, 0.92, 0.12, Color(0.05, 0.05, 0.1, 0.45))
		if "SPELLPOWER" in d.marks:
			for i in 3:
				sparkle(0.15 + i * 0.35, 0.1 + (i % 2) * 0.06, 0.06, Color("e5dbff"))
		if "FREEZE" in d.marks:
			for i in 3:
				var x := 0.7 + i * 0.09
				poly([x - 0.03, 0.96, x, 0.78 - i * 0.03, x + 0.03, 0.96], Color("d0ebff", 0.95))
		if d.legendary and not (d.kind == "humanoid" and d.subject[1] == "king"):
			poly([0.38, 0.12, 0.38, 0.04, 0.44, 0.08, 0.5, 0.02, 0.56, 0.08, 0.62, 0.04, 0.62, 0.12], Color("fcc419"))

	# --- subject -------------------------------------------------------------

	func subject() -> void:
		var s: Array = d.subject
		match d.kind:
			"humanoid":
				humanoid(s[0], s[1])
			"hero":
				humanoid(Art.HEROES[s[0]][0], Art.HEROES[s[0]][1])
			"beast":
				call("b_" + s[0], Color(ANIMAL_COLOR[s[0]]).lerp(acc, 0.3))
			"spell":
				spell(s[0], s[1])
			"weapon":
				weapon(s[0])
			"motif":
				call("m_" + s[0])
				_look_extra()

	func humanoid(race: String, role: String) -> void:
		var look: int = d.look
		var skin := Color(HUMAN_SKINS[look] if race == "human" else SKIN.get(race, "f1c27d"))
		var cloth := Color(ROLE_COLOR.get(role, "868e96")).lerp(acc, 0.35)
		var hair := Color(HAIR[(look + 1) % HAIR.size()])
		var small := race in ["gnome", "goblin", "kobold"]
		var hy := 0.47 if small else 0.4
		var hr := 0.19 if small else (0.18 if race == "ogre" else 0.16)
		var sw := 0.3 if small else (0.44 if race in ["ogre", "tauren"] else 0.37)
		# cape, body, item
		if role in ["king", "jaina", "uther", "anduin", "guldan", "malfurion"]:
			poly([0.5 - sw - 0.04, 1.0, 0.5 - 0.16, 0.6, 0.5 + 0.16, 0.6, 0.5 + sw + 0.04, 1.0], cloth.darkened(0.4))
		poly([0.5 - sw, 1.0, 0.5 - sw + 0.07, 0.7, 0.5 - 0.12, 0.62, 0.5 + 0.12, 0.62, 0.5 + sw - 0.07, 0.7, 0.5 + sw, 1.0], cloth)
		poly([0.5 - 0.1, 0.62, 0.5, 0.74, 0.5 + 0.1, 0.62], cloth.darkened(0.25))
		if role in ["garrosh", "warrior", "knight", "uther", "rexxar"]:
			for sx in [-1, 1]:
				var x: float = 0.5 + sx * (sw - 0.1)
				poly([x - 0.08, 0.72, x, 0.6, x + 0.08, 0.72], Color("ced4da") if role != "garrosh" else Color("495057"))
		_item(role, look, cloth)
		if role in ["priest", "rogue", "warlock", "anduin", "valeera", "guldan"]:
			var hood := cloth.darkened(0.2) if role != "valeera" else Color("a61e1e")
			poly([0.5 - hr - 0.06, hy + 0.16, 0.5 - hr - 0.05, hy - 0.06, 0.5, hy - hr - 0.08, 0.5 + hr + 0.05, hy - 0.06, 0.5 + hr + 0.06, hy + 0.16], hood)
		_race_back(race, hy, hr, skin, role)
		circle(0.5, hy, hr, skin)
		_hair(race, role, look, hy, hr, hair)
		_face(race, role, hy, hr, skin)
		_headgear(role, look, hy, hr, cloth)

	func _race_back(race: String, hy: float, hr: float, skin: Color, role: String) -> void:
		match race:
			"elf", "nightelf", "troll":
				for sx in [-1, 1]:
					var bx: float = 0.5 + sx * (hr - 0.02)
					poly([bx, hy - 0.02, 0.5 + sx * (hr + 0.16), hy - 0.13, bx, hy + 0.05], skin.darkened(0.1))
			"goblin":
				for sx in [-1, 1]:
					var bx: float = 0.5 + sx * (hr - 0.02)
					poly([bx, hy - 0.05, 0.5 + sx * (hr + 0.17), hy - 0.04, bx, hy + 0.06], skin.darkened(0.1))
			"gnome":
				for sx in [-1, 1]:
					circle(0.5 + sx * hr, hy, 0.065, skin.darkened(0.08))
			"tauren":
				for sx in [-1, 1]:
					poly([0.5 + sx * (hr - 0.04), hy - 0.06, 0.5 + sx * (hr + 0.14), hy - 0.12, 0.5 + sx * (hr + 0.16), hy - 0.24, 0.5 + sx * (hr + 0.05), hy - 0.1, 0.5 + sx * (hr - 0.02), hy - 0.02], Color("f1e3c8"))
			"pandaren":
				for sx in [-1, 1]:
					circle(0.5 + sx * (hr - 0.04), hy - hr + 0.03, 0.06, Color("212529"))
			"gnoll":
				for sx in [-1, 1]:
					poly([0.5 + sx * (hr - 0.08), hy - hr + 0.04, 0.5 + sx * (hr + 0.02), hy - hr - 0.12, 0.5 + sx * (hr + 0.04), hy - hr + 0.08], skin.darkened(0.2))
			"draenei":
				for sx in [-1, 1]:
					poly([0.5 + sx * 0.06, hy - hr + 0.04, 0.5 + sx * 0.12, hy - hr - 0.08, 0.5 + sx * 0.12, hy - hr + 0.06], Color("343a40"))
			"naga":
				poly([0.5 - 0.1, hy - hr + 0.04, 0.5, hy - hr - 0.12, 0.5 + 0.1, hy - hr + 0.04], skin.darkened(0.25))
		if role == "malfurion" or role == "druid":
			for sx in [-1, 1]:
				var bx: float = 0.5 + sx * 0.08
				line(bx, hy - hr + 0.02, bx + sx * 0.08, hy - hr - 0.14, Color("6f4518"), 0.03)
				line(bx + sx * 0.05, hy - hr - 0.08, bx + sx * 0.14, hy - hr - 0.1, Color("6f4518"), 0.025)

	func _hair(race: String, role: String, look: int, hy: float, hr: float, hair: Color) -> void:
		var named := {"jaina": "f2d16b", "anduin": "f2d16b", "valeera": "f2d16b", "uther": "e9ecef", "thrall": "1c1c1c",
			"garrosh": "1c1c1c", "malfurion": "2b8a3e", "rexxar": "343a40", "guldan": "f1f3f5"}
		if named.has(role):
			hair = Color(named[role])
		elif race in ["undead", "pandaren", "naga", "kobold", "gnoll", "tauren"]:
			return
		var long := role in ["jaina", "valeera", "thrall"] or (race in ["elf", "nightelf", "human"] and look in [1, 5])
		if role not in ["priest", "rogue", "warlock", "anduin", "valeera", "guldan", "knight", "warrior", "uther"] or role == "valeera":
			poly([0.5 - hr - 0.01, hy - 0.01, 0.5 - hr * 0.7, hy - hr - 0.02, 0.5, hy - hr - 0.05, 0.5 + hr * 0.7, hy - hr - 0.02, 0.5 + hr + 0.01, hy - 0.01, 0.5 + hr * 0.6, hy - hr * 0.55, 0.5 - hr * 0.6, hy - hr * 0.55], hair)
			if long:
				for sx in [-1, 1]:
					poly([0.5 + sx * (hr + 0.01), hy - 0.02, 0.5 + sx * (hr + 0.05), hy + 0.22, 0.5 + sx * (hr - 0.05), hy + 0.18], hair)
		var beard := race == "dwarf" or role in ["uther", "malfurion", "guldan", "rexxar"] or (race == "human" and look in [3, 4]) or (race == "orc" and look == 2)
		if beard:
			poly([0.5 - hr * 0.85, hy + 0.02, 0.5 + hr * 0.85, hy + 0.02, 0.5 + hr * 0.6, hy + hr + 0.1, 0.5, hy + hr + 0.2, 0.5 - hr * 0.6, hy + hr + 0.1], hair)

	func _face(race: String, role: String, hy: float, hr: float, skin: Color) -> void:
		var eye := Color("212529")
		if race == "undead" or role in ["warlock", "guldan"]:
			eye = Color("d8f5a2") if role in ["warlock", "guldan"] else Color("ffe066")
		if race == "nightelf" or role == "malfurion":
			eye = Color("e5dbff")
		if race == "pandaren":
			for sx in [-1, 1]:
				circle(0.5 + sx * hr * 0.4, hy - 0.005, 0.05, Color("212529"))
			eye = Color("f8f9fa")
		var ex := hr * 0.4
		circle(0.5 - ex, hy - 0.01, 0.024, eye)
		circle(0.5 + ex, hy - 0.01, 0.024 if race != "ogre" else 0.036, eye)
		match race:
			"orc", "troll", "ogre":
				line(0.5 - hr * 0.6, hy - 0.05, 0.5 + hr * 0.6, hy - 0.05, skin.darkened(0.4), 0.025)
				var tusk := 0.1 if race == "troll" else 0.05
				for sx in [-1, 1]:
					poly([0.5 + sx * hr * 0.35, hy + hr * 0.55, 0.5 + sx * hr * 0.45, hy + hr * 0.55 - tusk, 0.5 + sx * hr * 0.55, hy + hr * 0.55], Color("f8f9fa"))
			"tauren", "gnoll", "kobold":
				ellipse(0.5, hy + hr * 0.45, hr * 0.5, hr * 0.32, skin.lightened(0.2))
				circle(0.5, hy + hr * 0.38, 0.025, Color("212529"))
			"goblin", "gnome":
				circle(0.5, hy + hr * 0.2, 0.035, skin.darkened(0.15) if race == "goblin" else Color("ffa8a8"))
			"undead":
				for i in 4:
					line(0.5 - 0.06 + i * 0.04, hy + hr * 0.5, 0.5 - 0.06 + i * 0.04, hy + hr * 0.72, Color("495057"), 0.015)
			"draenei":
				for sx in [-1, 1]:
					line(0.5 + sx * 0.05, hy + hr * 0.7, 0.5 + sx * 0.07, hy + hr + 0.1, skin.darkened(0.2), 0.025)
		if role == "garrosh":
			for i in 3:
				line(0.5 - 0.08, hy + 0.06 + i * 0.025, 0.5 + 0.08, hy + 0.06 + i * 0.025, Color("212529"), 0.012)
		if race not in ["tauren", "gnoll", "kobold", "undead"]:
			line(0.5 - 0.04, hy + hr * 0.5, 0.5 + 0.04, hy + hr * 0.5, skin.darkened(0.45), 0.018)

	func _headgear(role: String, look: int, hy: float, hr: float, cloth: Color) -> void:
		var top := hy - hr
		match role:
			"mage":
				poly([0.5 - hr - 0.07, top + 0.06, 0.5 + hr + 0.07, top + 0.06, 0.5 + hr + 0.03, top + 0.1, 0.5 - hr - 0.03, top + 0.1], cloth.darkened(0.2))
				poly([0.5 - hr * 0.8, top + 0.07, 0.5 + 0.05, maxf(0.03, top - 0.2), 0.5 + hr * 0.8, top + 0.07], cloth.darkened(0.1))
				sparkle(0.5, top - 0.03, 0.035, Color("ffe066"))
			"priest", "anduin":
				ring(0.5, maxf(0.06, top - 0.06), 0.11, 0.03, Color("ffe066"), 0.025)
			"knight", "uther":
				var metal := Color("fab005") if role == "uther" else Color("ced4da")
				poly([0.5 - hr - 0.02, hy + 0.02, 0.5 - hr * 0.8, top + 0.02, 0.5, top - 0.03, 0.5 + hr * 0.8, top + 0.02, 0.5 + hr + 0.02, hy + 0.02, 0.5 + hr * 0.6, hy - 0.04, 0.5 - hr * 0.6, hy - 0.04], metal)
				if role == "knight":
					line(0.5 - hr * 0.6, hy - 0.01, 0.5 + hr * 0.6, hy - 0.01, Color("212529"), 0.025)
				line(0.5, top - 0.03, 0.5 + 0.04 * (look % 3 - 1), maxf(0.03, top - 0.13), acc, 0.04)
			"king":
				poly([0.5 - hr * 0.8, top + 0.04, 0.5 - hr * 0.8, top - 0.06, 0.5 - hr * 0.4, top - 0.01, 0.5, top - 0.08, 0.5 + hr * 0.4, top - 0.01, 0.5 + hr * 0.8, top - 0.06, 0.5 + hr * 0.8, top + 0.04], Color("fcc419"))
				circle(0.5, top - 0.0, 0.02, Color("e03131"))
			"pirate":
				if look % 2 == 0:
					poly([0.5 - hr - 0.1, top + 0.07, 0.5 - hr * 0.5, top - 0.05, 0.5, top - 0.02, 0.5 + hr * 0.5, top - 0.05, 0.5 + hr + 0.1, top + 0.07], Color("212529"))
					circle(0.5, top + 0.02, 0.025, Color("f8f9fa"))
				else:
					poly([0.5 - hr - 0.01, hy - 0.04, 0.5, top - 0.02, 0.5 + hr + 0.01, hy - 0.04, 0.5 + hr + 0.08, hy - 0.02], Color("e03131"))
				circle(0.5 + hr * 0.4, hy - 0.01, 0.04, Color("212529"))
				line(0.5 - hr, hy - 0.08, 0.5 + hr, hy + 0.02, Color("212529"), 0.015)
			"rogue", "valeera":
				box(0.5 - hr * 0.9, hy - 0.05, hr * 1.8, 0.06, Color("212529"))
				circle(0.5 - hr * 0.4, hy - 0.02, 0.015, Color("f8f9fa"))
				circle(0.5 + hr * 0.4, hy - 0.02, 0.015, Color("f8f9fa"))
			"shaman", "thrall":
				for i in 3:
					var x := 0.5 - 0.08 + i * 0.08
					poly([x - 0.025, top + 0.04, x, maxf(0.03, top - 0.14 - (i % 2) * 0.03), x + 0.025, top + 0.04], [Color("e03131"), Color("f8f9fa"), Color("4dabf7")][(i + look) % 3])
			"warrior", "garrosh":
				poly([0.5 - hr - 0.02, hy - 0.02, 0.5 - hr * 0.7, top, 0.5, top - 0.03, 0.5 + hr * 0.7, top, 0.5 + hr + 0.02, hy - 0.02], Color("868e96") if role == "warrior" else Color("495057"))
				for sx in [-1, 1]:
					poly([0.5 + sx * hr * 0.8, top + 0.04, 0.5 + sx * (hr + 0.16), maxf(0.03, top - 0.1), 0.5 + sx * (hr + 0.04), top + 0.08], Color("f1e3c8"))
			"hunter", "rexxar":
				poly([0.5 - hr - 0.03, hy - 0.02, 0.5 - hr * 0.6, top - 0.02, 0.5 + hr * 0.6, top - 0.02, 0.5 + hr + 0.03, hy - 0.02, 0.5 + hr, hy - hr * 0.5, 0.5 - hr, hy - hr * 0.5], cloth.darkened(0.25))
				line(0.5 + hr * 0.6, top + 0.02, 0.5 + hr + 0.08, maxf(0.03, top - 0.1), Color("e03131"), 0.025)
			"engineer":
				for sx in [-1, 1]:
					circle(0.5 + sx * hr * 0.42, top + 0.06, 0.05, Color("c9a227"))
					circle(0.5 + sx * hr * 0.42, top + 0.06, 0.032, Color("a5d8ff"))
			"druid", "malfurion":
				for i in 3:
					sparkle(0.5 - 0.07 + i * 0.07, top + 0.02, 0.03, Color("8ce99a"))
			"warlock", "guldan":
				for sx in [-1, 1]:
					poly([0.5 + sx * 0.06, top - 0.0, 0.5 + sx * 0.14, maxf(0.03, top - 0.12), 0.5 + sx * 0.13, top + 0.04], Color("343a40"))
			"jaina":
				line(0.5 - hr * 0.8, top + 0.05, 0.5 + hr * 0.8, top + 0.05, Color("fcc419"), 0.02)
				circle(0.5, top + 0.05, 0.02, Color("74c0fc"))
			"scholar":
				ring(0.5 - hr * 0.4, hy - 0.01, 0.04, 0.04, Color("212529"), 0.012, 10)
				ring(0.5 + hr * 0.4, hy - 0.01, 0.04, 0.04, Color("212529"), 0.012, 10)
			"commoner", "brewer", "merchant":
				match look % 3:
					0:
						poly([0.5 - hr - 0.02, top + 0.06, 0.5 - hr * 0.7, top - 0.02, 0.5 + hr * 0.7, top - 0.02, 0.5 + hr + 0.08, top + 0.07], cloth.darkened(0.3))
					1:
						line(0.5 - hr, top + 0.06, 0.5 + hr, top + 0.06, acc, 0.03)

	func _item(role: String, look: int, cloth: Color) -> void:
		var x := 0.86
		match role:
			"mage", "jaina", "priest", "anduin", "druid", "malfurion", "shaman":
				line(x, 0.97, x, 0.34, Color("8b5e34"), 0.035)
				var orb: Color = {"mage": acc.lightened(0.3), "jaina": Color("74c0fc"), "priest": Color("ffe066"), "anduin": Color("ffe066"),
					"druid": Color("8ce99a"), "malfurion": Color("8ce99a"), "shaman": Color("4dabf7")}[role]
				circle(x, 0.3, 0.09, Color(orb, 0.35))
				circle(x, 0.3, 0.05, orb)
			"knight", "pirate", "valeera":
				poly([x - 0.025, 0.74, x - 0.02, 0.26, x, 0.2, x + 0.02, 0.26, x + 0.025, 0.74], Color("dee2e6"))
				box(x - 0.08, 0.74, 0.16, 0.04, Color("c9a227"))
				box(x - 0.02, 0.78, 0.04, 0.12, Color("6f4518"))
			"rogue":
				poly([x - 0.02, 0.8, x, 0.5, x + 0.02, 0.8], Color("dee2e6"))
				box(x - 0.05, 0.8, 0.1, 0.03, Color("c9a227"))
			"warrior", "garrosh":
				line(x, 0.97, x, 0.28, Color("6f4518"), 0.035)
				poly([x, 0.3, x + 0.12, 0.24, x + 0.1, 0.48, x, 0.42], Color("ced4da"))
				poly([x, 0.3, x - 0.12, 0.24, x - 0.1, 0.48, x, 0.42], Color("adb5bd"))
			"uther", "thrall":
				line(x, 0.97, x, 0.36, Color("6f4518"), 0.04)
				box(x - 0.09, 0.26, 0.18, 0.12, Color("fab005") if role == "uther" else Color("495057"))
				if role == "thrall":
					line(x - 0.12, 0.2, x - 0.04, 0.12, Color("74c0fc"), 0.02)
					line(x - 0.04, 0.12, x - 0.08, 0.1, Color("74c0fc"), 0.02)
			"hunter", "rexxar":
				for i in 6:
					var a0 := lerpf(-1.1, 1.1, i / 6.0)
					var a1 := lerpf(-1.1, 1.1, (i + 1) / 6.0)
					line(0.74 + cos(a0) * 0.18, 0.62 + sin(a0) * 0.3, 0.74 + cos(a1) * 0.18, 0.62 + sin(a1) * 0.3, Color("8b5e34"), 0.03)
				line(0.74 + cos(-1.1) * 0.18, 0.62 + sin(-1.1) * 0.3, 0.74 + cos(1.1) * 0.18, 0.62 + sin(1.1) * 0.3, Color("f1f3f5"), 0.01)
			"engineer":
				line(x, 0.95, x, 0.55, Color("adb5bd"), 0.035)
				ring(x, 0.5, 0.05, 0.05, Color("adb5bd"), 0.03, 10)
			"brewer":
				box(x - 0.07, 0.62, 0.12, 0.16, Color("c9a227"))
				ring(x + 0.07, 0.7, 0.03, 0.04, Color("c9a227"), 0.02, 8)
				circle(x - 0.04, 0.61, 0.035, Color("f8f9fa"))
				circle(x + 0.0, 0.6, 0.035, Color("f8f9fa"))
			"merchant", "king":
				if role == "king":
					line(x, 0.95, x, 0.4, Color("fcc419"), 0.03)
					circle(x, 0.37, 0.04, Color("e03131"))
				else:
					circle(x, 0.72, 0.07, Color("fab005"))
					circle(x, 0.72, 0.04, Color("fff3bf"))
			"warlock", "guldan":
				circle(0.8, 0.72, 0.1, Color("82c91e", 0.35))
				circle(0.8, 0.72, 0.055, Color("d8f5a2"))
			"scholar":
				poly([0.72, 0.7, 0.86, 0.66, 0.9, 0.86, 0.76, 0.9], Color("e9ecef"))
				line(0.81, 0.68, 0.83, 0.88, Color("495057"), 0.015)
			"commoner":
				if look % 2 == 1:
					line(x, 0.97, x, 0.42, Color("8b5e34"), 0.03)

	# --- beasts (front or side portraits; col = fur) -----------------------------

	func _eyes(y: float, dx: float, r: float, col := Color("212529")) -> void:
		circle(0.5 - dx, y, r, col)
		circle(0.5 + dx, y, r, col)

	func b_wolf(col: Color) -> void:
		for sx in [-1, 1]:
			poly([0.5 + sx * 0.12, 0.3, 0.5 + sx * 0.26, 0.08, 0.5 + sx * 0.3, 0.36], col.darkened(0.15))
		poly([0.2, 0.36, 0.5, 0.22, 0.8, 0.36, 0.72, 0.66, 0.5, 0.9, 0.28, 0.66], col)
		poly([0.38, 0.6, 0.5, 0.56, 0.62, 0.6, 0.5, 0.88], col.lightened(0.35))
		circle(0.5, 0.84, 0.045, Color("212529"))
		_eyes(0.46, 0.12, 0.035, Color("ffd43b") if d.look % 2 == 0 else Color("74c0fc"))

	func b_hyena(col: Color) -> void:
		b_wolf(col)
		for i in 5:
			circle(0.3 + (i * 37 % 40) / 100.0, 0.3 + (i * 23 % 30) / 100.0, 0.025, col.darkened(0.45))

	func b_bear(col: Color) -> void:
		for sx in [-1, 1]:
			circle(0.5 + sx * 0.26, 0.24, 0.09, col.darkened(0.15))
		circle(0.5, 0.52, 0.34, col)
		ellipse(0.5, 0.68, 0.16, 0.12, col.lightened(0.35))
		ellipse(0.5, 0.62, 0.06, 0.04, Color("212529"))
		_eyes(0.46, 0.13, 0.035)

	func b_boar(col: Color) -> void:
		for sx in [-1, 1]:
			poly([0.5 + sx * 0.18, 0.28, 0.5 + sx * 0.32, 0.14, 0.5 + sx * 0.3, 0.36], col.darkened(0.2))
		ellipse(0.5, 0.5, 0.32, 0.28, col)
		ellipse(0.5, 0.68, 0.16, 0.11, Color("f4a3a3").lerp(col, 0.4))
		circle(0.45, 0.68, 0.025, Color("212529"))
		circle(0.55, 0.68, 0.025, Color("212529"))
		for sx in [-1, 1]:
			poly([0.5 + sx * 0.14, 0.74, 0.5 + sx * 0.24, 0.56, 0.5 + sx * 0.2, 0.76], Color("f8f9fa"))
		_eyes(0.42, 0.13, 0.03)

	func b_cat(col: Color) -> void:
		var fur := Color("343a40") if d.look % 3 == 0 else col
		for sx in [-1, 1]:
			poly([0.5 + sx * 0.12, 0.3, 0.5 + sx * 0.28, 0.1, 0.5 + sx * 0.32, 0.38], fur.darkened(0.15))
		circle(0.5, 0.52, 0.31, fur)
		if d.look % 3 == 1:
			for i in 3:
				line(0.3 + i * 0.06, 0.3, 0.34 + i * 0.06, 0.42, Color("212529"), 0.02)
				line(0.7 - i * 0.06, 0.3, 0.66 - i * 0.06, 0.42, Color("212529"), 0.02)
		ellipse(0.5, 0.66, 0.1, 0.08, fur.lightened(0.3))
		poly([0.46, 0.6, 0.54, 0.6, 0.5, 0.65], Color("e64980"))
		for sy in [-0.02, 0.03]:
			line(0.36, 0.66 + sy, 0.16, 0.62 + sy * 2, Color(1, 1, 1, 0.7), 0.01)
			line(0.64, 0.66 + sy, 0.84, 0.62 + sy * 2, Color(1, 1, 1, 0.7), 0.01)
		for sx in [-1, 1]:
			ellipse(0.5 + sx * 0.13, 0.47, 0.05, 0.035, Color("ffd43b"))
			ellipse(0.5 + sx * 0.13, 0.47, 0.012, 0.03, Color("212529"))

	func b_raptor(col: Color) -> void:
		poly([0.08, 0.5, 0.3, 0.26, 0.6, 0.22, 0.92, 0.42, 0.9, 0.52, 0.55, 0.56, 0.86, 0.62, 0.84, 0.7, 0.45, 0.74, 0.2, 0.86, 0.1, 0.7], col)
		for i in 5:
			var x := 0.3 + i * 0.1
			poly([x, 0.27 - i * 0.008, x + 0.04, 0.12 + (i % 2) * 0.04, x + 0.08, 0.26 - i * 0.008], acc.darkened(0.2))
		for i in 6:
			var x := 0.56 + i * 0.05
			poly([x, 0.53, x + 0.02, 0.6, x + 0.04, 0.54], Color("f8f9fa"))
		circle(0.62, 0.34, 0.04, Color("ffd43b"))
		circle(0.62, 0.34, 0.018, Color("212529"))

	func b_bird(col: Color) -> void:
		poly([0.5, 0.55, 0.06, 0.3, 0.18, 0.62], col.darkened(0.2))
		poly([0.5, 0.55, 0.94, 0.3, 0.82, 0.62], col.darkened(0.2))
		ellipse(0.5, 0.66, 0.2, 0.26, col)
		circle(0.5, 0.36, 0.16, col.lightened(0.1))
		poly([0.44, 0.42, 0.56, 0.42, 0.5, 0.56], Color("fab005"))
		_eyes(0.33, 0.07, 0.03)

	func b_spider(col: Color) -> void:
		for sx in [-1, 1]:
			for i in 4:
				var y := 0.42 + i * 0.09
				line(0.5 + sx * 0.12, y, 0.5 + sx * 0.32, y - 0.14, col.darkened(0.3), 0.03)
				line(0.5 + sx * 0.32, y - 0.14, 0.5 + sx * 0.44, y + 0.14, col.darkened(0.3), 0.03)
		circle(0.5, 0.66, 0.2, col)
		circle(0.5, 0.38, 0.13, col.lightened(0.1))
		for i in 4:
			circle(0.44 + (i % 2) * 0.12, 0.34 + (i / 2) * 0.06, 0.02, Color("e03131"))
		poly([0.44, 0.72, 0.5, 0.6, 0.56, 0.72], acc)

	func b_snake(col: Color) -> void:
		var last := Vector2(0.2, 0.9)
		for i in range(1, 13):
			var t := i / 12.0
			var pnt := Vector2(0.2 + t * 0.45, 0.9 - t * 0.6) + Vector2(sin(t * 9.0) * 0.15, 0)
			line(last.x, last.y, pnt.x, pnt.y, col, 0.11 - t * 0.03)
			last = pnt
		ellipse(last.x + 0.06, last.y - 0.04, 0.12, 0.08, col.lightened(0.1))
		circle(last.x + 0.08, last.y - 0.07, 0.022, Color("ffd43b"))
		line(last.x + 0.17, last.y - 0.02, last.x + 0.26, last.y - 0.0, Color("e03131"), 0.015)

	func b_crab(col: Color) -> void:
		for sx in [-1, 1]:
			for i in 3:
				line(0.5 + sx * 0.2, 0.66 + i * 0.06, 0.5 + sx * 0.4, 0.78 + i * 0.06, col.darkened(0.25), 0.03)
			poly([0.5 + sx * 0.22, 0.52, 0.5 + sx * 0.38, 0.22, 0.5 + sx * 0.46, 0.3, 0.5 + sx * 0.36, 0.34, 0.5 + sx * 0.44, 0.4, 0.5 + sx * 0.3, 0.56], col.lightened(0.1))
		ellipse(0.5, 0.64, 0.26, 0.16, col)
		for sx in [-1, 1]:
			line(0.5 + sx * 0.07, 0.5, 0.5 + sx * 0.09, 0.4, col, 0.025)
			circle(0.5 + sx * 0.09, 0.39, 0.03, Color("212529"))

	func b_turtle(col: Color) -> void:
		for sx in [-1, 1]:
			ellipse(0.5 + sx * 0.3, 0.84, 0.08, 0.05, Color("94d82d").lerp(col, 0.4))
		circle(0.86, 0.66, 0.09, Color("94d82d").lerp(col, 0.4))
		circle(0.89, 0.64, 0.018, Color("212529"))
		poly([0.12, 0.8, 0.18, 0.56, 0.32, 0.4, 0.5, 0.36, 0.68, 0.4, 0.82, 0.56, 0.88, 0.8], col)
		for x in [0.32, 0.5, 0.68]:
			ellipse(x, 0.62, 0.07, 0.08, col.lightened(0.2))

	func b_ape(col: Color) -> void:
		circle(0.5, 0.5, 0.34, col)
		ellipse(0.5, 0.56, 0.22, 0.22, Color("c8a27c"))
		line(0.32, 0.4, 0.68, 0.4, col.darkened(0.3), 0.05)
		_eyes(0.46, 0.08, 0.03)
		ellipse(0.5, 0.66, 0.11, 0.07, Color("a07856"))
		circle(0.46, 0.64, 0.015, Color("212529"))
		circle(0.54, 0.64, 0.015, Color("212529"))
		for sx in [-1, 1]:
			circle(0.5 + sx * 0.34, 0.5, 0.06, col.darkened(0.1))

	func b_kodo(col: Color) -> void:
		for sx in [-1, 1]:
			poly([0.5 + sx * 0.2, 0.36, 0.5 + sx * 0.44, 0.3, 0.5 + sx * 0.46, 0.12, 0.5 + sx * 0.36, 0.26, 0.5 + sx * 0.18, 0.28], Color("f1e3c8"))
		ellipse(0.5, 0.52, 0.3, 0.3, col)
		poly([0.36, 0.5, 0.64, 0.5, 0.6, 0.84, 0.4, 0.84], col.lightened(0.15))
		box(0.4, 0.46, 0.2, 0.06, col.darkened(0.3))
		_eyes(0.44, 0.17, 0.028)

	func b_bat(col: Color) -> void:
		for sx in [-1, 1]:
			poly([0.5, 0.42, 0.5 + sx * 0.46, 0.22, 0.5 + sx * 0.42, 0.5, 0.5 + sx * 0.3, 0.44, 0.5 + sx * 0.22, 0.6, 0.5 + sx * 0.12, 0.52], col.darkened(0.15))
			poly([0.5 + sx * 0.05, 0.38, 0.5 + sx * 0.12, 0.18, 0.5 + sx * 0.14, 0.4], col)
		ellipse(0.5, 0.5, 0.12, 0.16, col)
		_eyes(0.44, 0.05, 0.022, Color("ff6b6b"))

	func b_fish(col: Color) -> void:
		poly([0.86, 0.5, 0.98, 0.3, 0.98, 0.7], col.darkened(0.15))
		ellipse(0.5, 0.5, 0.38, 0.22, col)
		poly([0.42, 0.3, 0.56, 0.12, 0.6, 0.3], col.darkened(0.2))
		circle(0.24, 0.45, 0.04, Color("f8f9fa"))
		circle(0.24, 0.45, 0.02, Color("212529"))
		if d.look % 2 == 1:
			for i in 4:
				poly([0.14 + i * 0.04, 0.56, 0.16 + i * 0.04, 0.62, 0.18 + i * 0.04, 0.56], Color("f8f9fa"))

	func b_frog(col: Color) -> void:
		ellipse(0.5, 0.62, 0.36, 0.24, col)
		for sx in [-1, 1]:
			circle(0.5 + sx * 0.18, 0.4, 0.1, col)
			circle(0.5 + sx * 0.18, 0.4, 0.06, Color("f8f9fa"))
			circle(0.5 + sx * 0.18, 0.4, 0.03, Color("212529"))
		line(0.28, 0.68, 0.72, 0.68, col.darkened(0.4), 0.02)

	func b_whelp(col: Color) -> void:
		poly([0.5, 0.55, 0.08, 0.2, 0.2, 0.62], col.darkened(0.2))
		poly([0.5, 0.55, 0.92, 0.2, 0.8, 0.62], col.darkened(0.2))
		circle(0.5, 0.56, 0.22, col)
		for sx in [-1, 1]:
			poly([0.5 + sx * 0.1, 0.4, 0.5 + sx * 0.18, 0.2, 0.5 + sx * 0.2, 0.42], Color("f1e3c8"))
		_eyes(0.52, 0.09, 0.03, Color("ffd43b"))
		ellipse(0.5, 0.68, 0.1, 0.06, col.lightened(0.25))

	func b_squirrel(col: Color) -> void:
		circle(0.7, 0.4, 0.2, col.darkened(0.1))
		circle(0.78, 0.6, 0.16, col.darkened(0.1))
		ellipse(0.42, 0.66, 0.18, 0.22, col)
		circle(0.4, 0.4, 0.14, col)
		poly([0.32, 0.3, 0.34, 0.16, 0.4, 0.28], col.darkened(0.2))
		circle(0.36, 0.38, 0.025, Color("212529"))

	# --- spells: element colours x form -----------------------------------------

	func spell(el: String, form: String) -> void:
		var c1 := Color(Art.ELEMENT_COLORS[el][0])
		var c2 := Color(Art.ELEMENT_COLORS[el][1])
		var n: int = clampi(d.cost, 0, 10)
		var look: int = d.look
		match form:
			"projectile":
				var ox := 0.62
				var oy := 0.38
				var r := 0.1 + n * 0.012
				for i in 3:
					var w := r * (0.9 - i * 0.25)
					poly([ox - w * 0.7, oy - w * 0.7, 0.08 + i * 0.06, 0.92 - i * 0.03, ox + w * 0.7, oy + w * 0.7], Color(c1, 0.45 + i * 0.2))
				for i in 3 + look:
					var t := (i + 1.0) / (4.0 + look)
					circle(lerpf(0.12, ox, t) + 0.05 * sin(i * 2.3), lerpf(0.88, oy, t) + 0.05 * cos(i * 1.7), 0.02, c2)
				_orb(el, ox, oy, r, c1, c2)
			"area":
				for i in 3:
					circle(0.5, 0.55, 0.4 - i * 0.1, Color(c1, 0.25 + i * 0.15))
				for i in 6 + look:
					var a := TAU * i / (6.0 + look)
					var a2 := a + 0.15
					poly([0.5, 0.55, 0.5 + cos(a) * 0.44, 0.55 + sin(a) * 0.4, 0.5 + cos(a2) * 0.3, 0.55 + sin(a2) * 0.28], Color(c2, 0.8))
				circle(0.5, 0.55, 0.1 + n * 0.006, c2)
			"transform":
				var last := Vector2(0.5, 0.5)
				for i in range(1, 30):
					var t := i / 29.0 * 3.0 * PI
					var pnt := Vector2(0.5, 0.5) + Vector2(cos(t + look), sin(t + look)) * (0.04 + t * 0.04)
					line(last.x, last.y, pnt.x, pnt.y, c1, 0.035)
					last = pnt
				for p in [[0.46, 0.5], [0.54, 0.48], [0.5, 0.56]]:
					circle(p[0], p[1], 0.06, Color("f8f9fa"))
				circle(0.4, 0.48, 0.04, Color("343a40"))
			"draw":
				circle(0.5, 0.56, 0.34, Color(c1, 0.3))
				for i in 3:
					var a := (i - 1) * 0.35
					var cx := 0.5 + (i - 1) * 0.16
					var pts := []
					for q in [[-0.1, -0.16], [0.1, -0.16], [0.1, 0.16], [-0.1, 0.16]]:
						var v := Vector2(q[0], q[1]).rotated(a)
						pts.append_array([cx + v.x, 0.6 + v.y])
					poly(pts, Color("2a2118"))
					var inner := []
					for q in [[-0.08, -0.14], [0.08, -0.14], [0.08, 0.14], [-0.08, 0.14]]:
						var v := Vector2(q[0], q[1]).rotated(a)
						inner.append_array([cx + v.x, 0.6 + v.y])
					poly(inner, c1.darkened(0.2 * i))
					circle(cx, 0.58, 0.03, c2)
			"heal":
				for i in 3:
					circle(0.5, 0.52, 0.42 - i * 0.12, Color(c1, 0.2 + i * 0.1))
				box(0.42, 0.24, 0.16, 0.56, c2)
				box(0.22, 0.44, 0.56, 0.16, c2)
				for i in 2 + look % 3:
					sparkle(0.2 + i * 0.25, 0.18 + (i % 2) * 0.62, 0.05, Color(1, 1, 1, 0.9))
			"destroy":
				circle(0.5, 0.5, 0.36, Color(c1.darkened(0.5), 0.8))
				for i in 6 + look:
					var a := TAU * i / (6.0 + look)
					var mid := Vector2(0.5, 0.5) + Vector2(cos(a + 0.2), sin(a + 0.2)) * 0.2
					var tip := Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.44
					line(0.5, 0.5, mid.x, mid.y, c2, 0.025)
					line(mid.x, mid.y, tip.x, tip.y, c2, 0.02)
				circle(0.5, 0.46, 0.14, Color("f1f3f5"))
				box(0.43, 0.54, 0.14, 0.1, Color("f1f3f5"))
				circle(0.45, 0.46, 0.035, Color("212529"))
				circle(0.55, 0.46, 0.035, Color("212529"))
			"summon":
				ellipse(0.5, 0.66, 0.38, 0.16, c1)
				ellipse(0.5, 0.66, 0.3, 0.11, Color("120a1f"))
				poly([0.4, 0.66, 0.42, 0.42, 0.5, 0.34, 0.58, 0.42, 0.6, 0.66], Color(c2, 0.85))
				circle(0.5, 0.3, 0.07, Color(c2, 0.85))
				for i in 4 + look:
					sparkle(0.12 + fmod(i * 0.17, 0.76), 0.12 + fmod(i * 0.13, 0.3), 0.03, c2)
			"protect":
				ellipse(0.5, 0.6, 0.42, 0.36, Color(c1, 0.3))
				poly([0.3, 0.3, 0.7, 0.3, 0.68, 0.6, 0.5, 0.82, 0.32, 0.6], c1)
				poly([0.36, 0.36, 0.64, 0.36, 0.62, 0.58, 0.5, 0.74, 0.38, 0.58], c2)
			"buff":
				circle(0.5, 0.55, 0.38, Color(c1, 0.3))
				for i in 3:
					var x := 0.28 + i * 0.22
					var y := 0.36 + (i % 2) * 0.12
					poly([x - 0.09, y + 0.1, x, y - 0.08, x + 0.09, y + 0.1, x + 0.04, y + 0.1, x + 0.04, y + 0.3, x - 0.04, y + 0.3, x - 0.04, y + 0.1], c2)
			"secret":
				ring(0.5, 0.52, 0.38, 0.38, c1, 0.03)
				for i in 6:
					var a := TAU * i / 6.0 + look * 0.2
					circle(0.5 + cos(a) * 0.38, 0.52 + sin(a) * 0.38, 0.03, c2)
				for i in 6:
					var a0 := lerpf(-PI, 0.4, i / 6.0)
					var a1 := lerpf(-PI, 0.4, (i + 1) / 6.0)
					line(0.5 + cos(a0) * 0.12, 0.42 + sin(a0) * 0.12, 0.5 + cos(a1) * 0.12, 0.42 + sin(a1) * 0.12, c2, 0.05)
				line(0.55, 0.5, 0.5, 0.6, c2, 0.05)
				circle(0.5, 0.7, 0.035, c2)
			"return":
				for i in 10:
					var a0 := lerpf(0.3, 5.2, i / 10.0)
					var a1 := lerpf(0.3, 5.2, (i + 1) / 10.0)
					line(0.5 + cos(a0) * 0.3, 0.52 + sin(a0) * 0.3, 0.5 + cos(a1) * 0.3, 0.52 + sin(a1) * 0.3, c1, 0.06)
				var e := Vector2(0.5, 0.52) + Vector2(cos(5.2), sin(5.2)) * 0.3
				poly([e.x - 0.1, e.y - 0.02, e.x + 0.06, e.y - 0.1, e.x + 0.02, e.y + 0.08], c1)
				box(0.42, 0.42, 0.16, 0.22, c2)
			"silence":
				ellipse(0.5, 0.55, 0.3, 0.16, c1)
				ellipse(0.5, 0.55, 0.22, 0.08, Color("212529"))
				line(0.24, 0.3, 0.76, 0.8, Color("e03131"), 0.06)
				line(0.76, 0.3, 0.24, 0.8, Color("e03131"), 0.06)
			"mana":
				circle(0.5, 0.52, 0.36, Color("4dabf7", 0.25))
				poly([0.5, 0.16, 0.76, 0.5, 0.5, 0.88, 0.24, 0.5], Color("1c7ed6"))
				poly([0.5, 0.24, 0.66, 0.5, 0.5, 0.78, 0.42, 0.5], Color("74c0fc"))
			_:
				var m := Art.motif(d.get("id", ""))
				circle(0.5, 0.5, 0.42, Color(c1, 0.25))
				if m != "" and has_method("m_" + m):
					call("m_" + m)
				else:
					call("m_" + {"fire": "fire", "ice": "ice", "arcane": "arcane", "holy": "holy", "shadow": "shadow",
						"nature": "nature", "lightning": "lightning", "moon": "moon", "poison": "dagger", "steel": "shield", "gold": "coin"}[el])

	func _orb(el: String, x: float, y: float, r: float, c1: Color, c2: Color) -> void:
		match el:
			"ice":
				poly([x, y - r * 1.4, x + r, y, x, y + r * 1.4, x - r, y], c2)
				poly([x, y - r, x + r * 0.5, y, x, y + r, x - r * 0.5, y], c1)
			"lightning":
				poly([x + 0.05, y - r * 1.5, x - r, y + 0.03, x, y + 0.03, x - 0.05, y + r * 1.5, x + r, y - 0.03, x, y - 0.03], c2)
			"steel":
				poly([x + r * 1.2, y - r * 1.2, x - r * 0.4, y + r * 0.1, x - r * 0.1, y + r * 0.4], c2)
			_:
				circle(x, y, r, c1)
				circle(x - r * 0.15, y - r * 0.15, r * 0.55, c2)
				if el == "fire":
					for i in 5:
						var a := -PI / 2 + (i - 2) * 0.45
						poly([x + cos(a - 0.2) * r, y + sin(a - 0.2) * r, x + cos(a) * r * 1.7, y + sin(a) * r * 1.7, x + cos(a + 0.2) * r, y + sin(a + 0.2) * r], c1)

	# --- weapons ------------------------------------------------------------

	func weapon(type: String) -> void:
		circle(0.5, 0.5, 0.42, Color(acc, 0.3))
		for i in 3 + d.look:
			sparkle(0.15 + fmod(i * 0.23, 0.7), 0.15 + fmod(i * 0.31, 0.7), 0.03, Color(acc.lightened(0.5), 0.9))
		call("m_" + type)
		circle(0.5, 0.62 if type != "bow" else 0.5, 0.035, acc.lightened(0.2))

	func m_glaive() -> void:
		poly([0.5, 0.08, 0.62, 0.3, 0.56, 0.5, 0.62, 0.7, 0.5, 0.92, 0.38, 0.7, 0.44, 0.5, 0.38, 0.3], Color("2b8a3e").lerp(acc, 0.3))
		poly([0.5, 0.18, 0.56, 0.32, 0.5, 0.82, 0.44, 0.32], Color("d8f5a2"))
		box(0.44, 0.46, 0.12, 0.08, Color("6f4518"))

	# --- other subjects -------------------------------------------------------

	func m_elemental() -> void:
		var el: String = d.subject[1] if d.subject.size() > 1 else "nature"
		var c1 := Color(Art.ELEMENT_COLORS[el][0])
		var c2 := Color(Art.ELEMENT_COLORS[el][1])
		poly([0.2, 0.96, 0.24, 0.6, 0.14, 0.4, 0.3, 0.46, 0.34, 0.24, 0.5, 0.1, 0.66, 0.24, 0.7, 0.46, 0.86, 0.4, 0.76, 0.6, 0.8, 0.96], c1)
		poly([0.32, 0.92, 0.36, 0.6, 0.5, 0.3, 0.64, 0.6, 0.68, 0.92], c2.lerp(c1, 0.3))
		_eyes(0.36, 0.07, 0.035, Color(1, 1, 1))
		line(0.42, 0.48, 0.58, 0.48, c1.darkened(0.4), 0.025)

	func m_giant() -> void:
		var el: String = d.subject[1] if d.subject.size() > 1 else "nature"
		var rock := Color("868e96").lerp(Color(Art.ELEMENT_COLORS[el][0]), 0.35)
		poly([0.08, 0.98, 0.14, 0.5, 0.3, 0.36, 0.7, 0.36, 0.86, 0.5, 0.92, 0.98], rock)
		poly([0.32, 0.38, 0.36, 0.12, 0.64, 0.12, 0.68, 0.38], rock.lightened(0.1))
		for i in 4:
			line(0.2 + i * 0.18, 0.55, 0.26 + i * 0.18, 0.75, rock.darkened(0.35), 0.02)
		_eyes(0.24, 0.08, 0.035, Color(Art.ELEMENT_COLORS[el][1]))
		line(0.42, 0.32, 0.58, 0.32, rock.darkened(0.4), 0.03)

	func m_tree() -> void:
		var bark := Color("6f4518").lerp(acc, 0.15)
		circle(0.5, 0.3, 0.26, Color("2f9e44").lerp(acc, 0.25))
		circle(0.3, 0.4, 0.16, Color("40c057").lerp(acc, 0.25))
		circle(0.7, 0.4, 0.16, Color("37b24d").lerp(acc, 0.25))
		poly([0.36, 0.98, 0.42, 0.44, 0.58, 0.44, 0.64, 0.98], bark)
		line(0.42, 0.62, 0.22, 0.5, bark, 0.05)
		line(0.58, 0.62, 0.78, 0.5, bark, 0.05)
		_eyes(0.6, 0.05, 0.025, Color("d8f5a2"))
		line(0.46, 0.72, 0.54, 0.72, Color("212529"), 0.02)

	func m_ooze() -> void:
		var g := Color("82c91e").lerp(acc, 0.2)
		poly([0.1, 0.92, 0.14, 0.6, 0.3, 0.38, 0.5, 0.3, 0.7, 0.38, 0.86, 0.6, 0.9, 0.92], g)
		for i in 4:
			circle(0.25 + i * 0.17, 0.92, 0.06, g)
		_eyes(0.5, 0.1, 0.05, Color("f8f9fa"))
		_eyes(0.52, 0.1, 0.022)
		for i in 3:
			circle(0.3 + i * 0.2, 0.7, 0.03, Color(1, 1, 1, 0.4))

	func m_faceless() -> void:
		poly([0.16, 0.98, 0.22, 0.4, 0.5, 0.12, 0.78, 0.4, 0.84, 0.98], Color("5f3dc4").lerp(acc, 0.2))
		ellipse(0.5, 0.46, 0.18, 0.24, Color("343a40"))
		for i in 5:
			line(0.38 + i * 0.06, 0.62, 0.36 + i * 0.07, 0.86, Color("7048e8"), 0.025)

	func m_portal() -> void:
		ellipse(0.5, 0.55, 0.32, 0.4, Color("7048e8").lerp(acc, 0.3))
		ellipse(0.5, 0.55, 0.24, 0.32, Color("120a1f"))
		for i in 8:
			var a := TAU * i / 8.0
			circle(0.5 + cos(a) * 0.32, 0.55 + sin(a) * 0.4, 0.03, Color("e5dbff"))
		sparkle(0.5, 0.55, 0.08, Color("d0bfff"))

	func m_mirror() -> void:
		humanoid("human", "mage")
		for i in 3:
			circle(0.2 + i * 0.3, 0.2, 0.05, Color(1, 1, 1, 0.5))

	# --- name motifs (also spell emblems) ---------------------------------------

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
		circle(0.5, 0.56, 0.34, Color("9d0208").lerp(acc, 0.35))
		poly([0.32, 0.48, 0.46, 0.54, 0.32, 0.56], Color("aaff00"))
		poly([0.68, 0.48, 0.54, 0.54, 0.68, 0.56], Color("aaff00"))
		poly([0.36, 0.7, 0.64, 0.7, 0.5, 0.8], Color("370617"))

	func m_dragon() -> void:
		var scale_col := Color("2d6a4f").lerp(acc, 0.6)
		poly([0.5, 0.5, 0.06, 0.1, 0.18, 0.4, 0.04, 0.5, 0.2, 0.62, 0.1, 0.8], scale_col.darkened(0.2))
		poly([0.5, 0.5, 0.94, 0.1, 0.82, 0.4, 0.96, 0.5, 0.8, 0.62, 0.9, 0.8], scale_col.darkened(0.2))
		circle(0.5, 0.52, 0.16, scale_col)
		poly([0.42, 0.62, 0.58, 0.62, 0.5, 0.94], scale_col)
		poly([0.42, 0.42, 0.36, 0.24, 0.48, 0.38], Color("d8f3dc"))
		poly([0.58, 0.42, 0.64, 0.24, 0.52, 0.38], Color("d8f3dc"))

	func _look_extra() -> void:  # a small accessory that differs by look
		match d.look:
			1:
				line(0.12, 0.95, 0.24, 0.3, Color("8b5e34"), 0.03)
				poly([0.24, 0.3, 0.2, 0.18, 0.28, 0.2], Color("ced4da"))
			2:
				poly([0.3, 0.3, 0.5, 0.18, 0.7, 0.3], Color("adb5bd"))
			3:
				circle(0.84, 0.3, 0.06, acc.lightened(0.4))
			4:
				for i in 3:
					sparkle(0.2 + i * 0.3, 0.9, 0.04, acc.lightened(0.5))
			5:
				line(0.2, 0.2, 0.8, 0.2, Color(acc, 0.8), 0.03)

	func m_murloc() -> void:
		poly([0.5, 0.06, 0.62, 0.3, 0.38, 0.3], Color("e85d04").lerp(acc, 0.4))
		circle(0.5, 0.56, 0.36, Color("52b788").lerp(acc, 0.35))
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
