class_name Entity
extends RefCounted

## Keywords that come from card mechanics and that Silence removes.
const KEYWORDS := ["TAUNT", "CHARGE", "DIVINE_SHIELD", "STEALTH", "WINDFURY", "CANT_ATTACK",
	"ELUSIVE", "FROZEN", "IMMUNE", "FROZEN_THIS_TURN"]

var id: int
var card_id: String
var controller: int
var zone := "SETASIDE"
var play_order := 0
var damage := 0
var tags: Dictionary = {}
var enchantments: Array = []
var eot_tags: Array[String] = []
var aura: Dictionary = {"atk": 0, "hp": 0, "tags": {}}
var silenced := false


func _init(p_id: int, p_card_id: String, p_controller: int) -> void:
	id = p_id
	card_id = p_card_id
	controller = p_controller
	var c := card()
	for m: String in c.get("mechanics", []):
		if m in KEYWORDS:
			tags[m] = true
	if c.has("spellDamage"):
		tags["SPELLPOWER"] = c.spellDamage
	if c.type == "WEAPON":
		tags["DURABILITY"] = c.get("durability", 0)
	if c.type == "HERO":
		tags["ARMOR"] = 0


func card() -> Dictionary:
	return CardDb.card(card_id)


func type() -> String:
	return card().type


func is_minion() -> bool:
	return type() == "MINION"


func is_hero() -> bool:
	return type() == "HERO"


func is_weapon() -> bool:
	return type() == "WEAPON"


func race() -> String:
	return card().get("race", "")


func atk() -> int:
	var v: int = card().get("attack", 0)
	for e: Dictionary in enchantments:
		if e.has("set_atk"):
			v = e.set_atk
		v += e.get("atk", 0)
	return maxi(0, v + aura.atk)


func max_health() -> int:
	var v: int = card().get("health", 0)
	for e: Dictionary in enchantments:
		if e.has("set_hp"):
			v = e.set_hp
		v += e.get("hp", 0)
	return v + aura.hp


func health() -> int:
	return max_health() - damage


func has(tag: String) -> bool:
	return bool(tags.get(tag, false)) or bool(aura.tags.get(tag, false))


func spellpower() -> int:
	return int(tags.get("SPELLPOWER", 0)) + int(aura.tags.get("SPELLPOWER", 0))


func give_tag(tag: String, eot := false) -> void:
	tags[tag] = true
	if eot and not eot_tags.has(tag):
		eot_tags.append(tag)


func add_enchant(ench: Dictionary) -> void:
	enchantments.append(ench)


## Removes "this turn" enchantments and tags. A lost Health bonus never kills.
func remove_eot() -> void:
	var old_max := max_health()
	var old_hp := health()
	enchantments = enchantments.filter(func(e: Dictionary) -> bool: return not e.get("eot", false))
	for t in eot_tags:
		tags.erase(t)
	eot_tags.clear()
	fix_health(old_max, old_hp)


func silence() -> void:
	var old_max := max_health()
	var old_hp := health()
	enchantments.clear()
	eot_tags.clear()
	for k in KEYWORDS:
		tags.erase(k)
	tags.erase("SPELLPOWER")
	silenced = true
	fix_health(old_max, old_hp)


## When max Health drops, current Health becomes min(old current, new max).
func fix_health(old_max: int, old_health: int) -> void:
	var new_max := max_health()
	if new_max < old_max:
		damage = maxi(0, new_max - mini(old_health, new_max))


func copy() -> Entity:
	var e := Entity.new(id, card_id, controller)
	e.zone = zone
	e.play_order = play_order
	e.damage = damage
	e.tags = tags.duplicate(true)
	e.enchantments = enchantments.duplicate(true)
	e.eot_tags = eot_tags.duplicate()
	e.aura = aura.duplicate(true)
	e.silenced = silenced
	return e


func snapshot() -> Dictionary:
	return {"card": card_id, "ctrl": controller, "zone": zone, "order": play_order,
		"dmg": damage, "tags": tags, "ench": enchantments, "eot": eot_tags, "sil": silenced}
