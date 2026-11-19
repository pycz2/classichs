class_name Lru
extends RefCounted
## A Dictionary as a cache of the least recently used first (Godot keeps a Dictionary's order of insertion):
## get() moves a key to the end, put() drops the oldest keys past the cap.


## The value of key (null when missing), now the most recent.
static func get_of(cache: Dictionary, key: Variant) -> Variant:
	if not cache.has(key):
		return null
	var v = cache[key]
	cache.erase(key)
	cache[key] = v
	return v


static func put(cache: Dictionary, key: Variant, value: Variant, cap: int) -> void:
	cache.erase(key)
	cache[key] = value
	while cache.size() > cap:
		cache.erase(cache.keys()[0])
