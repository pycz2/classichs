class_name I18nKeys
extends RefCounted
## Every English interface string: literals in tr()/translate()/_t()/_tr() calls,
## plus the tables that are translated through a variable.

const DIRS := ["res://game", "res://net", "res://ui"]
static var _call := RegEx.create_from_string("(?:\\btr|TranslationServer\\.translate|\\b_t|\\b_tr)\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\"")
## HistoryText._say(p, viewer, "You …", "Opponent …", args)
static var _say := RegEx.create_from_string("_say\\([^,]+,\\s*[^,]+,\\s*\"((?:[^\"\\\\]|\\\\.)*)\",\\s*\"((?:[^\"\\\\]|\\\\.)*)\"")


static func collect() -> Array:
	var keys := {}
	for dir in DIRS:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			var src := FileAccess.get_file_as_string(dir + "/" + f)
			for m in _call.search_all(src):
				keys[m.get_string(1).c_unescape()] = true
			for m in _say.search_all(src):
				keys[m.get_string(1).c_unescape()] = true
				keys[m.get_string(2).c_unescape()] = true
	var tables: Array = []
	tables.append_array(MainMenu.ITEMS)
	tables.append_array(DeckListView.BUTTONS)
	tables.append_array(DebugTable.TABS)
	tables.append_array(DebugTable.ZONES.map(func(z): return z[0]))
	tables.append_array(DebugTable.STATS.map(func(z): return z[0]))
	tables.append_array(MatchView.EMOTES.values())
	tables.append_array(DeckTrackerPanel.VIEWS.map(func(r): return r[1]))
	tables.append_array(CollectionView.RARITIES.map(func(r): return r[1]))
	tables.append_array(CollectionView.TYPES.map(func(r): return r[1]))
	tables.append_array(SettingsView.SLIDERS.map(func(r): return r[0]))
	tables.append_array(SettingsView.TOGGLES.map(func(r): return r[0]))
	tables.append_array(Tutorial.HINTS.values())
	tables.append_array(NetSession.BYE_TEXT.values())
	tables.append_array(ServerSession.GAME_OVER_TEXT.values())
	tables.append_array(Rules.MESSAGES)
	tables.append_array(Social.STATUS.values().map(func(v): return v[1]))
	for m in Missions.LIST:
		tables.append_array([m.intro, m.reward_line])
		tables.append_array(m.lines.values())
	for k in tables:
		keys[k] = true
	var out := keys.keys()
	out.sort()
	return out
