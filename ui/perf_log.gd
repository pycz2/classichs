class_name PerfLog
extends Node
## The performance log, off by default. On (Settings "Performance log", `?perf=1` in the browser's
## address, `--perf` after the game's own arguments): once a second a row of Godot's monitors, the
## game's own timings (PerfLog.time / count from its hot spots: ms and calls in that second) and its
## gauges (tweens, timers, audio players, signal connections, a match's history, caches; walked from
## the tree), also as custom monitors ("chs/<key>", Godot's debugger shows them). Out: on desktop
## user://perf/perf-<date>.csv, a line a second; in the browser window.chsPerf {header, rows} (the
## test harness reads it) and save() downloads it (the settings' Save log). Off it costs one static
## bool test per timed call. main adds one; the FPS counter shows its detail line while it is on.

const KEEP := 86400  # rows kept in memory (a day)
const DIR := "user://perf"
## Godot's monitors: column -> [monitor, scale].
const MONITORS := {
	"fps": [Performance.TIME_FPS, 1.0], "process_ms": [Performance.TIME_PROCESS, 1000.0],
	"physics_ms": [Performance.TIME_PHYSICS_PROCESS, 1000.0], "objects": [Performance.OBJECT_COUNT, 1.0],
	"resources": [Performance.OBJECT_RESOURCE_COUNT, 1.0], "nodes": [Performance.OBJECT_NODE_COUNT, 1.0],
	"orphans": [Performance.OBJECT_ORPHAN_NODE_COUNT, 1.0], "mem_mb": [Performance.MEMORY_STATIC, 1.0 / 1048576.0],
	"mem_max_mb": [Performance.MEMORY_STATIC_MAX, 1.0 / 1048576.0], "draw_calls": [Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME, 1.0],
	"draw_objects": [Performance.RENDER_TOTAL_OBJECTS_IN_FRAME, 1.0], "primitives": [Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME, 1.0],
	"video_mb": [Performance.RENDER_VIDEO_MEM_USED, 1.0 / 1048576.0], "texture_mb": [Performance.RENDER_TEXTURE_MEM_USED, 1.0 / 1048576.0],
	"audio_latency_ms": [Performance.AUDIO_OUTPUT_LATENCY, 1000.0]}
## The timed spots (ms in the second, and calls) and counted ones (per second).
const TIMED := ["rules", "take_state", "on_changed", "layout", "strip", "t_page", "t_list", "bracket", "ws_parse", "opus"]
const COUNTED := ["ws_in", "ws_in_kb", "ws_out", "ws_out_kb", "t_push", "listrow_draw"]
## Sampled each second.
const GAUGES := ["frames", "slow_frames", "worst_ms", "tree_nodes", "controls", "tweens", "timers", "audio_players",
	"audio_playing", "conns", "tree_conns", "link_conns", "match_views", "sessions", "link_games", "history", "strip_rows",
	"sound_streams", "sound_mb", "heard", "art_textures", "palette_frames", "link_children", "tour_cache", "js_heap_mb"]

static var on := false
static var instance: PerfLog
static var _sum := {}  # this second: key -> ms (timed) or n (counted); key + "_n" -> calls
## The last whole second's values by column (the custom monitors and the overlay read it).
static var last := {}

var rows: Array[String] = []
var header := ""
var file_path := ""
var _file: FileAccess
var _js: JavaScriptObject
var _left := 1.0
var _t0 := 0
var _frames := 0
var _slow := 0
var _worst := 0.0
var _forced := false  # turned on by the address or the command line, not the setting


## Time spent since t0 (Time.get_ticks_usec()) at a hot spot, in ms.
static func time(key: String, t0: int) -> void:
	if on:
		_sum[key] = _sum.get(key, 0.0) + (Time.get_ticks_usec() - t0) / 1000.0
		_sum[key + "_n"] = _sum.get(key + "_n", 0) + 1


static func count(key: String, n: float = 1.0) -> void:
	if on:
		_sum[key] = _sum.get(key, 0.0) + n


static func columns() -> Array:
	var out := ["t", "uptime_s", "screen"]
	out.append_array(MONITORS.keys())
	for k in TIMED:
		out.append_array([k + "_ms", k + "_n"])
	out.append_array(COUNTED)
	out.append_array(GAUGES)
	return out


func _ready() -> void:
	name = "PerfLog"
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	_forced = "--perf" in OS.get_cmdline_user_args() or "--perf" in OS.get_cmdline_args()
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("new URLSearchParams(location.search).get('perf') || ''", true)
		_forced = _forced or str(q) in ["1", "true", "on"]
	# the harness's driver (tools/perf_drive.gd), only when asked for
	var drive := "--drive" in OS.get_cmdline_user_args() or "--drive" in OS.get_cmdline_args()
	if OS.has_feature("web"):
		drive = drive or str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('drive') || ''", true)) == "1"
	if drive:
		var d: Node = load("res://tools/perf_drive.gd").new()
		d.set("main", get_parent())
		get_parent().add_child.call_deferred(d)


func _exit_tree() -> void:
	set_on(false)
	if instance == self:
		instance = null


func _process(delta: float) -> void:
	var want := _forced or bool(Settings.data.get("perf", false))
	if want != on:
		set_on(want)
	if not on:
		return
	_frames += 1
	if delta > 0.05:
		_slow += 1
	_worst = maxf(_worst, delta * 1000.0)
	_left -= delta
	if _left <= 0.0:
		_left += 1.0
		_sample()


func set_on(v: bool) -> void:
	if v == on:
		return
	on = v
	for k in columns().slice(3):
		var id := "chs/" + str(k)
		if v and not Performance.has_custom_monitor(id):
			Performance.add_custom_monitor(id, func(): return last.get(k, 0))
		elif not v and Performance.has_custom_monitor(id):
			Performance.remove_custom_monitor(id)
	if not v:
		_file = null
		return
	_sum.clear()
	_t0 = Time.get_ticks_msec()
	_left = 1.0
	header = ",".join(columns())
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.chsPerf = {header: '', rows: []}", true)
		_js = JavaScriptBridge.get_interface("chsPerf")
		_js.header = header
	else:
		DirAccess.make_dir_recursive_absolute(DIR)
		file_path = DIR.path_join("perf-%s.csv" % Time.get_datetime_string_from_system().replace(":", "-"))
		_file = FileAccess.open(file_path, FileAccess.WRITE)
		if _file:
			_file.store_line(header)
			print("performance log: ", ProjectSettings.globalize_path(file_path))


## The log so far as CSV.
func csv() -> String:
	return header + "\n" + "\n".join(rows) + "\n"


## Desktop: the file's path (written as it goes); browser: the log downloaded. Returns where it went.
func save() -> String:
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(csv().to_utf8_buffer(), "classichs-perf.csv", "text/csv")
		return "classichs-perf.csv"
	if _file:
		_file.flush()
	return ProjectSettings.globalize_path(file_path)


func _sample() -> void:
	var v := {}
	for k in MONITORS:
		v[k] = Performance.get_monitor(MONITORS[k][0]) * MONITORS[k][1]
	for k in TIMED:
		v[k + "_ms"] = _sum.get(k, 0.0)
		v[k + "_n"] = _sum.get(k + "_n", 0)
	for k in COUNTED:
		v[k] = _sum.get(k, 0.0)
	_sum.clear()
	v.frames = _frames
	v.slow_frames = _slow
	v.worst_ms = _worst
	_frames = 0
	_slow = 0
	_worst = 0.0
	_gauges(v)
	last = v
	var main := get_parent()
	var screen = main.get("screen") if main else null
	var line := [Time.get_datetime_string_from_system(), "%.1f" % ((Time.get_ticks_msec() - _t0) / 1000.0),
		_screen_name(screen, main)]
	for k in columns().slice(3):
		var x = v.get(k, 0)
		line.append(str(x) if x is int else ("%.2f" % x))
	var row := ",".join(line)
	rows.append(row)
	if rows.size() > KEEP:
		rows = rows.slice(rows.size() - KEEP)
	if _file:
		_file.store_line(row)
		_file.flush()
	if _js:
		_js.rows.push(row)


## The screen by its class ("+Watch" while a watched game is over it).
static func _screen_name(screen: Variant, main: Node) -> String:
	if not (screen is Node and is_instance_valid(screen)):
		return ""
	var s: Script = screen.get_script()
	var n := String(s.get_global_name()) if s and s.get_global_name() != &"" else String(screen.name)
	return n + ("+Watch" if main.get("watch_view") != null else "")


## What the tree holds now (one walk; only while on).
func _gauges(v: Dictionary) -> void:
	for k in ["tree_nodes", "controls", "timers", "audio_players", "audio_playing", "match_views", "sessions",
			"history", "strip_rows"]:
		v[k] = 0
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		v.tree_nodes += 1
		if n is Control:
			v.controls += 1
		if n is Timer:
			v.timers += 1
		elif n is AudioStreamPlayer or n is AudioStreamPlayer2D:
			v.audio_players += 1
			if n.playing:
				v.audio_playing += 1
		elif n is MatchView:
			v.match_views += 1
			if n.controller:
				v.history = maxi(v.history, n.controller.game.history.size())
		elif n is ServerSession:
			v.sessions += 1
		elif n is HistoryStrip:
			v.strip_rows = maxi(v.strip_rows, n.get_child_count())
		stack.append_array(n.get_children(true))
	v.tweens = get_tree().get_processed_tweens().size()
	v.tree_conns = _conns(get_tree())
	v.link_conns = 0
	v.link_games = 0
	v.link_children = 0
	for l in get_tree().get_nodes_in_group(ServerLink.GROUP):
		v.link_conns += _conns(l)
		v.link_children += l.get_child_count()
		v.link_games += (l.get("_games") as Dictionary).size()
	v.conns = v.tree_conns + v.link_conns + _conns(Sound.instance) + _conns(get_parent())
	v.sound_streams = 0
	v.sound_mb = 0.0
	if Sound.instance:
		var streams: Dictionary = Sound.instance.get("_streams")
		v.sound_streams = streams.size()
		for s in streams.values():
			if s is AudioStreamWAV:
				v.sound_mb += s.data.size() / 1048576.0
		var m = Sound.instance.get("_music")
		if m and m.stream is AudioStreamWAV:
			v.sound_mb += m.stream.data.size() / 1048576.0
	v.heard = (Sound.instance.heard.size() if Sound.instance else 0)
	v.art_textures = Art._textures.size()
	v.palette_frames = Palette._frames.size()
	v.tour_cache = TournamentsView.cache.size()
	v.js_heap_mb = 0.0
	if OS.has_feature("web"):
		v.js_heap_mb = float(JavaScriptBridge.eval("performance.memory ? performance.memory.usedJSHeapSize : 0", true)) / 1048576.0


static func _conns(o: Object) -> int:
	if o == null:
		return 0
	var n := 0
	for s in o.get_signal_list():
		n += o.get_signal_connection_list(s.name).size()
	return n


## The overlay's line under the FPS (FpsCounter).
static func detail() -> String:
	if not on or last.is_empty():
		return ""
	return "process %.1f ms · frame %d ms · slow %d\nnodes %d (orphans %d) · objects %d · mem %.0f MB\ntweens %d · timers %d · audio %d/%d · conns %d\ndraw calls %d · history %d · sounds %d (%.0f MB)" % [
		last.process_ms, last.worst_ms, last.slow_frames, last.nodes, last.orphans, last.objects, last.mem_mb,
		last.tweens, last.timers, last.audio_playing, last.audio_players, last.conns, last.draw_calls, last.history,
		last.sound_streams, last.sound_mb]
