class_name PackInstall
extends RefCounted
## A pack being installed: it comes into a file of Packs.user_dir (a download writes it as it
## comes), the rules engine checks it and computes both hashes (rust/engine pack::check_zip_from:
## the zip, its paths and limits; one read of each file), then Packs.store puts it into place. On
## desktop and Android the check runs in a thread of its own (the GDExtension's PackScan), in the
## browser in a Web Worker (web/rules.js), the file going over to it a piece a frame. Packs.install
## waits for it; start() runs it in the background, one check at a time, so the player can leave
## the screen or play meanwhile; `jobs` lists them for the screens (PackInstallsView). A player's
## upload to a server is shown the same way (`upload`: the server tells its stages).
## The stages are the server's (server/src/packs.rs STAGES).

signal changed
## Packs.install's {pack} or {error, detail?}; an upload's {pack: the server's entry} or {error, code}.
signal finished(result: Dictionary)

## Stage -> its name for people (translated where shown); "trial": the server's trial game (uploads).
const STAGES := {"receiving": "Receiving", "checking": "Checking", "trial": "Trial game", "storing": "Storing",
	"done": "Done"}
## The browser: the file goes to the checker in pieces, as many as fit into a few ms of a frame.
const WEB_PIECE := 1 << 18
const WEB_FRAME_MS := 6

## Installs and uploads under way, in order (one check at a time: the first one checking).
static var jobs: Array[PackInstall] = []
static var _ticking := false
static var _made := 0

var title := ""
var stage := "receiving"
## Bytes of this stage done, of total (0: not known).
var done := 0
var total := 0
var result := {}
var upload := false
## The file being installed (a temp file of Packs.user_dir, moved into place).
var file := ""
var origin := ""
var extra := {}
var want_hash := ""
var _scan: Object  # PackScan
var _web_id = null
var _web_file: FileAccess


## A job whose file comes later (a download writes `file`): received() or finish() then.
static func receiving(title_: String, origin_: String, extra_ := {}, want := "") -> PackInstall:
	var j := PackInstall.new()
	j.title = title_
	j.origin = origin_
	j.extra = extra_
	j.want_hash = want
	DirAccess.make_dir_recursive_absolute(Packs.user_dir)
	_made += 1
	j.file = "%s/incoming-%d-%d.tmp" % [Packs.user_dir, Time.get_ticks_usec(), _made]
	return j


## A job for bytes there already (a picked file, a pack from another player): they go into its file.
static func of_bytes(bytes: PackedByteArray, title_: String, origin_: String, extra_ := {}, want := "") -> PackInstall:
	var j := receiving(title_, origin_, extra_, want)
	if bytes.size() > Pack.LIMITS.pack:
		j.finish({"error": Packs.ERRORS[0]})
		return j
	var f := FileAccess.open(j.file, FileAccess.WRITE)
	if f == null:
		j.finish({"error": Packs.ERRORS[1]})
		return j
	f.store_buffer(bytes)
	f.close()
	j.received()
	return j


## Into the background: shown on every screen, checked in turn.
func start() -> PackInstall:
	if stage != "done" and not jobs.has(self):
		jobs.append(self)
		_tick_later()
	return self


## The file is all there: the check comes next.
func received() -> void:
	if stage == "done":
		return
	stage = "checking"
	done = 0
	var f := FileAccess.open(file, FileAccess.READ)
	total = f.get_length() if f else 0
	f = null
	if total > Pack.LIMITS.pack:
		finish({"error": Packs.ERRORS[0]})
		return
	changed.emit()
	_tick_later()


## Runs the check to the end now, waiting (Packs.install): the result.
func run_now() -> Dictionary:
	if stage == "checking":
		if ClassDB.class_exists("PackScan"):
			if _scan == null:
				_scan = ClassDB.instantiate("PackScan")
				_scan.start(ProjectSettings.globalize_path(file))
			_checked(JSON.parse_string(_scan.wait()))
		else:
			_web_id = null
			_checked(_check_here())
	return result


## "Checking… 45%" in the interface's language.
func text() -> String:
	var name := TranslationServer.translate(STAGES.get(stage, stage))
	return name + "…" + (" %d%%" % (100 * done / total) if total > 0 and stage != "done" else "")


func finish(r: Dictionary) -> void:
	if stage == "done":
		return
	result = r
	stage = "done"
	jobs.erase(self)
	if not upload and r.has("error"):
		DirAccess.remove_absolute(file)
	changed.emit()
	finished.emit(r)


static func _tick_later() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if not _ticking and tree:
		_ticking = true
		tree.process_frame.connect(_tick)


## Every frame: the first job that is checking goes on (one at a time).
static func _tick() -> void:
	var next: Array = jobs.filter(func(j: PackInstall): return j.stage == "checking" and not j.upload)
	if next.is_empty():
		_ticking = false
		(Engine.get_main_loop() as SceneTree).process_frame.disconnect(_tick)
		return
	next[0]._step()


func _step() -> void:
	if ClassDB.class_exists("PackScan"):
		if _scan == null:
			_scan = ClassDB.instantiate("PackScan")
			_scan.start(ProjectSettings.globalize_path(file))
		done = _scan.progress()
		var r: String = _scan.result()
		if r != "":
			_checked(JSON.parse_string(r))
			return
	elif _web() != null:
		_web_step(_web())
	else:
		_checked(_check_here())
		return
	changed.emit()


## The browser: the file goes to web/rules.js a piece at a time, then its worker checks it.
func _web_step(api: Object) -> void:
	if _web_id == null:
		_web_file = FileAccess.open(file, FileAccess.READ)
		if _web_file == null:
			_checked({"error": "cannot read the pack"})
			return
		_web_id = api.pack_begin(total)
	var t0 := Time.get_ticks_msec()
	while _web_file and Time.get_ticks_msec() - t0 < WEB_FRAME_MS:
		var piece := _web_file.get_buffer(WEB_PIECE)
		if piece.is_empty():
			_web_file = null
			api.pack_run(_web_id)
			break
		api.pack_add(_web_id, Marshalls.raw_to_base64(piece))
		done += piece.size()
	if _web_file == null:
		var r = api.pack_result(_web_id)
		if r is String and r != "":
			_checked(JSON.parse_string(r))


static func _web() -> Object:
	if not OS.has_feature("web"):
		return null
	var api = JavaScriptBridge.get_interface("ClassicRules")
	return api if api and api.pack_begin else null


## Without the rules engine (a web page without workers): the checks of game/pack.gd, at once.
func _check_here() -> Dictionary:
	var p := Pack.open(file, origin)
	if p == null:
		return {"error": "not a zip file"}
	var bad := p.problems()
	var r := {"error": bad[0]} if not bad.is_empty() else {"content_hash": p.content_hash(), "rules_hash": p.computed_rules_hash()}
	p.close()
	return r


func _checked(c: Variant) -> void:
	_scan = null
	stage = "storing"
	changed.emit()
	finish(Packs.store(file, c if c is Dictionary else {"error": "the check failed"}, origin, extra, want_hash))
