extends SceneTree
## Measures how the tournament screens scale with their data (tools/perf report, "bench" table): the list
## with N tournaments (every row redraws each frame), a tournament's page and bracket with N players (rebuilt
## on every `tournament` push), with vsync off so a frame takes what it costs. Windowed (it draws):
##   godot --path . --script res://tools/perf/bench_ui.gd -- [--out FILE.json]
## The data is the tournament tests' (tests/test_tournaments.gd), through a FakeLink: no server.

const T := preload("res://tests/test_tournaments.gd")
var _started := false
var out := {}


func _init() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "classichs-perf/bench")
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _frames(n: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n:
		await process_frame
	return (Time.get_ticks_usec() - t0) / 1000.0 / n


func _link() -> FakeLink:
	var l := FakeLink.new()
	l.url = "ws://bench"
	l.dispatch({"t": "auth", "ok": true, "token": "x", "me": T.ME})
	return l


func _view(page_id: Variant = null) -> TournamentsView:
	TournamentsView.cache = {}
	var v := TournamentsView.new()
	v.link = _link()
	v.page_id = page_id
	root.add_child(v)
	return v


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Settings.load_settings()
	PerfLog.on = true  # (its counters; no PerfLog node: nothing is written)
	await _frames(30)
	var empty := await _frames(120)
	out["empty_frame_ms"] = empty
	print("empty window: %.2f ms a frame" % empty)
	# the list: N rows, each redrawn every frame
	out["list"] = []
	for n in [0, 10, 25, 50, 100]:
		var v := _view()
		var rows := []
		for i in n:
			rows.append(T.summary(i + 1, "Perf %d" % (i + 1), "finished" if i % 2 else "open"))
		v.link.dispatch({"t": "t_list", "tab": "upcoming", "list": rows})
		await _frames(20)
		PerfLog._sum.clear()
		var ms := await _frames(120)
		var draws: float = PerfLog._sum.get("listrow_draw", 0.0) / 120.0
		out.list.append({"rows": n, "frame_ms": ms, "row_draws_per_frame": draws})
		print("list %3d rows: %.2f ms a frame, %.0f row draws a frame" % [n, ms, draws])
		var l: ServerLink = v.link
		v.free()
		l.free()
	# a tournament's page: N players, round robin (N(N-1)/2 matches) and single elimination
	out["page"] = []
	for fmt in ["round_robin", "elimination"]:
		for n in [6, 8, 16, 32]:
			var data: Dictionary = T.full(fmt, n, {"status": "running"})
			for tab in ["overview", "bracket"]:
				var v := _view(7)
				v.page_tab = tab
				var msg := {"t": "tournament", "tournament": data}
				var text := JSON.stringify(msg)
				var t0 := Time.get_ticks_usec()
				for k in 10:  # pushes as they come: the JSON parsed, then the page rebuilt
					v.link.dispatch(JSON.parse_string(text))
				var push_ms := (Time.get_ticks_usec() - t0) / 1000.0 / 10.0
				await _frames(10)
				var ms := await _frames(60)
				var nodes := _count(v)
				out.page.append({"format": fmt, "players": n, "matches": data.matches.size(), "tab": tab, "push_ms": push_ms,
					"frame_ms": ms, "nodes": nodes, "json_kb": text.length() / 1024.0})
				print("%s %2d players (%3d matches) %-8s: a push %.1f ms (%d KB), then %.2f ms a frame, %d nodes" % [fmt, n,
					data.matches.size(), tab, push_ms, text.length() / 1024, ms, nodes])
				var l: ServerLink = v.link
				v.free()
				l.free()
	var path := "user://bench_ui.json"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			path = a.substr(6)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("BENCH DONE ", ProjectSettings.globalize_path(path))
	quit()


static func _count(n: Node) -> int:
	var c := 1
	for k in n.get_children(true):
		c += _count(k)
	return c
