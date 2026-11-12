extends TestCase
## The performance log (PerfLog): off by default and silent then; on, a row a second with Godot's
## monitors, the timed hot spots and the gauges, written to its file and kept for Save log.


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_off_by_default_records_nothing() -> void:
	var p := PerfLog.new()
	root().add_child(p)
	eq(PerfLog.on, false, "off")
	PerfLog.time("rules", Time.get_ticks_usec())
	PerfLog.count("ws_in")
	check(PerfLog._sum.is_empty(), "no sums while off")
	p._process(1.5)
	eq(p.rows.size(), 0, "no rows while off")
	p.free()


func test_records_and_exports() -> void:
	var p := PerfLog.new()
	root().add_child(p)
	p._forced = true  # (as ?perf=1 or --perf: the setting stays off)
	p._process(0.0)
	check(Performance.has_custom_monitor("chs/take_state_ms"), "custom monitors while on")
	PerfLog.time("take_state", Time.get_ticks_usec() - 2500)
	PerfLog.count("ws_in", 3)
	p._process(0.2)
	p._process(0.9)  # a second has passed: one row
	eq(p.rows.size(), 1, "a row a second")
	var cols := p.header.split(",")
	var row := p.rows[0].split(",")
	eq(row.size(), cols.size(), "a value per column")
	var at := func(k: String) -> float: return float(row[cols.find(k)])
	check(at.call("take_state_ms") >= 2.0, "timed spot in ms: %s" % row[cols.find("take_state_ms")])
	eq(int(at.call("take_state_n")), 1, "and its calls")
	eq(int(at.call("ws_in")), 3, "counted")
	check(at.call("objects") > 0 and at.call("tree_nodes") > 0, "monitors and gauges")
	eq(PerfLog.last.ws_in, 3.0, "the custom monitors read the last second")
	var path := p.save()
	var text := FileAccess.get_file_as_string(path)
	check(text.begins_with("t,uptime_s,screen,fps"), "the file has the header: " + path)
	eq(text.strip_edges().split("\n").size(), 2, "and the row")
	check(p.csv().contains(p.rows[0]), "the CSV for the download has it too")
	p._forced = false
	p._process(0.0)
	check(not Performance.has_custom_monitor("chs/take_state_ms"), "monitors gone when off")
	p.free()
	DirAccess.remove_absolute(path)
