class_name EditorSession
extends RefCounted
## The open document with its history, view state and kept resources, living in Game.editor so it
## survives the test drive's scene changes: create / open / save / autosave / recovery / test drive
## start (1.7, 1.9).
##
## Saving never hitches: the header facts come from `build` when it matches the document's
## revision, else from a worker bake; LevelIO.save_async packs and writes on a worker. Before a
## file is overwritten its previous version goes to .history/<guid>/ (the last five are kept). A
## track never saved autosaves under its guid; a clean save deletes the autosave.

const RACE_SCENE := "res://scenes/race.tscn"
## The test drive's options and their ranges (Game.test_drive, 5.4).
const TEST_KEYS := {"bots": [0, 7], "laps": [1, 9], "hazards": [0, 1], "difficulty": [0, 2]}
const TEST_DEFAULTS := {"bots": 0, "laps": 1, "hazards": 1, "difficulty": 1}
const TEXT_NO_ROAD := "No road yet: draw one with {ed_tool_road} first."
const TEXT_OPEN := "Close the loop ({ed_close_loop}) to drive it."
const TEXT_BUILD := "The track could not be built: %s."

## Why the last static helper (rename_track) failed.
static var last_error := ""

var doc: LevelDoc
var history: EditHistory
var path := ""                          # "" = never saved
var camera := Transform3D()
var has_view := false
var top_view := false
var tool := "road"
var selection := PackedInt32Array()
var hidden := PackedInt32Array()
var clipboard: Array = []
var last_drive := {}
## The last WATCH A BOT LAP's result for the checklist: {line, s, pos} ({} none; the next watch drops it).
var bot_lap := {}
var return_to := ""                     # "" main menu, "home" EditorHome, "host" CREATE SERVER with host_track
var host_track := ""
var build: LevelBuild                   # the last full bake (the test drive and the editor's return use it)
var resources: Array = []               # models / materials / textures the view loaded: kept across scene changes
## The id of the file last saved or opened ("" for a track never saved).
var track_id := ""
## A save or a pre-save bake is running.
var saving := false
## True while a save writes its own meta (modified, app, content, bake) into the live document:
## no edit (the editor keeps the last drive's trail and its bake).
var saving_meta := false
## What the last open / open_copy reported (sanitize's cleaning, a recovered .tmp).
var open_report: LevelReport

var _clean_rev := -1                    # doc.revision at the last save / open (-1 = never clean)
var _autosave_rev := -1                 # doc.revision of the last autosave written
var _autosaving := false
var _autosave_again := false
var _autosave_t := 0.0
var _kept := {}                         # instance id -> true (keep)


## Game.editor, made on first use.
static func current() -> EditorSession:
	var g := _game()
	if g != null:
		var e = g.get("editor")
		if e is EditorSession:
			return e
		var s := EditorSession.new()
		g.set("editor", s)
		return s
	return EditorSession.new()


## "MY TRACK", "MY TRACK 2"... (not taken by own tracks)
static func auto_name() -> String:
	return free_name("MY TRACK")


## True for a name auto_name() makes: "MY TRACK" or "MY TRACK <n>" (any case).
static func is_auto_name(nm: String) -> bool:
	var s := nm.strip_edges().to_upper()
	if s == "MY TRACK":
		return true
	return s.begins_with("MY TRACK ") and s.trim_prefix("MY TRACK ").is_valid_int()


## base, else "base 2", "base 3"... not taken by an own track or an autosave (case-insensitive).
static func free_name(base: String) -> String:
	var b := base.strip_edges().left(44)
	if b == "":
		b = "MY TRACK"
	var taken := {}
	for e in CustomTracks.list("mine"):
		taken[str(e.name).to_lower()] = true
	var d := DirAccess.open(CustomTracks.autosave_dir())
	if d != null:
		for f in d.get_files():
			if f.ends_with(LevelIO.EXT):
				var m := LevelIO.read_meta(CustomTracks.autosave_dir().path_join(f))
				if m.has("name"):
					taken[str(m.name).to_lower()] = true
	if not taken.has(b.to_lower()):
		return b
	var n := 2
	while taken.has(("%s %d" % [b, n]).to_lower()):
		n += 1
	return "%s %d" % [b, n]


func is_open() -> bool:
	return doc != null


## "" or the reason.
func open(p: String) -> String:
	var rep := LevelReport.new()
	var d := LevelIO.load_file(p, rep)
	if d == null:
		return rep.fatal() if rep.fatal() != "" else str(LevelIO.FATAL.no_file)
	_take(d)
	open_report = rep
	path = p
	_clean_rev = doc.revision
	track_id = LevelIO.id_for(LevelIO.file_sha256(p))
	return ""


## Unsaved, auto name when "".
func create(template_id: String, track_name := "") -> void:
	var nm := track_name.strip_edges()
	if nm == "":
		nm = auto_name()
	var d := LevelTemplates.make(template_id, nm)
	d.data["author"] = _nickname()
	_take(d)
	open_report = null
	path = ""
	track_id = ""
	_clean_rev = doc.revision


## DUPLICATE / REMIX / OLDER VERSIONS: an unsaved copy with a new guid; REMIX credits the
## original (remix_of) and makes you the author. "" or the reason.
func open_copy(p: String, as_remix: bool) -> String:
	var rep := LevelReport.new()
	var d := LevelIO.load_file(p, rep)
	if d == null:
		return rep.fatal() if rep.fatal() != "" else str(LevelIO.FATAL.no_file)
	var x: Dictionary = d.data
	if as_remix:
		x["remix_of"] = {"guid": str(x.get("guid", "")), "name": str(x.get("name", "")), "author": str(x.get("author", ""))}
		x["author"] = _nickname()
	x["guid"] = Crypto.new().generate_random_bytes(16).hex_encode()
	var nm := free_name(str(x.get("name", "MY TRACK")))
	x["name"] = nm
	x["short"] = nm.to_upper().left(16)
	var now := int(Time.get_unix_time_from_system())
	x["created"] = now
	x["modified"] = now
	_take(d)
	open_report = rep
	path = ""
	track_id = ""
	_clean_rev = -1
	return ""


## SAVE AS: the live document becomes a copy (a free name from new_name, a new guid; outside the
## undo history) with no file yet; the original file stays as it was and the old guid's autosave
## goes to .trash. The next save writes a new file. The copy's name.
func become_copy(new_name: String) -> String:
	if doc == null:
		return ""
	var nm := LevelDoc.clean_text(new_name, 48)
	nm = free_name(nm if nm != "" else str(doc.data.get("name", "MY TRACK")))
	discard_autosave(autosave_path())
	var now := int(Time.get_unix_time_from_system())
	doc.apply([LevelDoc.op_set(["name"], nm), LevelDoc.op_set(["short"], nm.to_upper().left(16)),
		LevelDoc.op_set(["guid"], Crypto.new().generate_random_bytes(16).hex_encode()), LevelDoc.op_set(["created"], now)])
	path = ""
	track_id = ""
	_clean_rev = -1
	_autosave_rev = -1
	return nm


## Worker pack + atomic write, history copy, CustomTracks.note_saved; done(err). p "" = the
## current file, or (never saved) a free file name from the track's name in MY TRACKS.
func save(p := "", header_extra := {}, done := Callable()) -> void:
	if doc == null:
		if done.is_valid():
			done.call_deferred(ERR_UNCONFIGURED)
		return
	var target := p if p != "" else path
	if target == "":
		target = LevelIO.free_path(CustomTracks.mine_dir(), str(doc.data.get("name", "track")))
	saving = true
	_with_build(func(b: LevelBuild) -> void: _write(target, header_extra, b, done))


func autosave() -> void:
	if doc == null or not dirty() or doc.revision == _autosave_rev:
		return
	if _autosaving:
		_autosave_again = true
		return
	var g := str(doc.data.get("guid", ""))
	if g == "":
		return
	_autosaving = true
	var rev := doc.revision
	var dst := CustomTracks.autosave_dir().path_join(g + LevelIO.EXT)
	DirAccess.make_dir_recursive_absolute(CustomTracks.autosave_dir())
	var snap := _save_copy(int(Time.get_unix_time_from_system()))
	LevelIO.save_async(snap, dst, {"autosave": true}, func(err: Error) -> void:
		_autosaving = false
		if err == OK:
			_autosave_rev = rev
		if _autosave_again:
			_autosave_again = false
			autosave())


## The editor's frame clock: autosaves every settings.editor_autosave seconds (60) while there are
## unsaved changes.
func autosave_tick(delta: float) -> void:
	_autosave_t += delta
	var g := _game()
	var every := 60.0
	if g != null:
		every = maxf(float((g.get("settings") as Dictionary).get("editor_autosave", 60)), 5.0)
	if _autosave_t >= every:
		_autosave_t = 0.0
		autosave()


## RENAME (EditorHome, TRACK PROPERTIES): the file at p gets the new name inside and a new file
## name from it (the guid stays; the old version goes to the history). The new path, or "" with
## the reason in last_error.
static func rename_track(p: String, new_name: String) -> String:
	last_error = ""
	var nm := LevelDoc.clean_text(new_name, 48)
	if nm == "":
		last_error = "A track needs a name."
		return ""
	var rep := LevelReport.new()
	var d := LevelIO.load_file(p, rep)
	if d == null:
		last_error = rep.fatal()
		return ""
	var old_id := LevelIO.id_for(LevelIO.file_sha256(p))
	var m := CustomTracks.meta(old_id)
	var facts := {}
	if bool(m.get("checked", false)):
		for k in CustomTracks.FACT_KEYS:
			facts[k] = m[k]
	d.data["name"] = nm
	d.data["short"] = nm.to_upper().left(16)
	d.data["modified"] = int(Time.get_unix_time_from_system())
	var dst := p
	if LevelIO.slug(nm) + LevelIO.EXT != p.get_file():
		dst = LevelIO.free_path(p.get_base_dir(), nm)
	CustomTracks.keep_history(p)
	var err := LevelIO.save(d, dst, _header_of(m))
	if err != OK:
		last_error = "The track could not be written."
		return ""
	if dst != p:
		DirAccess.remove_absolute(p)
	CustomTracks.refresh()
	CustomTracks.note_saved(dst, facts)
	return dst


## The header facts an existing file had (rename keeps them).
static func _header_of(m: Dictionary) -> Dictionary:
	var h := {}
	for k in ["length", "raceable", "errors", "warnings", "outline", "view"]:
		if m.has(k) and (k != "raceable" or bool(m.get("checked", false))):
			h[k] = m[k]
	return h


## The autosave of this track's guid.
func autosave_path() -> String:
	if doc == null:
		return ""
	return CustomTracks.autosave_dir().path_join(str(doc.data.get("guid", "")) + LevelIO.EXT)


## An autosave newer than p (or of a never-saved track), "" none. p may be a track file (its
## guid's autosave when newer) or an autosave itself (itself when no own file with its guid is
## newer).
func recovery_for(p: String) -> String:
	if p == "":
		return ""
	var auto_dir := CustomTracks.autosave_dir()
	if p.get_base_dir().trim_suffix("/") == auto_dir or p.begins_with(auto_dir + "/"):
		if not FileAccess.file_exists(p):
			return ""
		var am := LevelIO.read_meta(p)
		var own := CustomTracks.id_for_guid(str(am.get("guid", "")))
		if own == "":
			return p
		var op := CustomTracks.path(own)
		return p if _stamp(p) > _stamp(op) else ""
	var m := LevelIO.read_meta(p)
	var g := str(m.get("guid", ""))
	if g == "":
		return ""
	var a := auto_dir.path_join(g + LevelIO.EXT)
	if not FileAccess.file_exists(a):
		return ""
	return a if _stamp(a) > _stamp(p) else ""


## Every autosave that recovery_for offers: [{autosave, path ("" never saved), name, modified}].
static func recoveries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := CustomTracks.autosave_dir()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	# an autosave cut between Windows' remove and rename left only <guid>.hl2kt.tmp: put it in place
	for f in d.get_files():
		if f.ends_with(LevelIO.EXT + ".tmp") and not FileAccess.file_exists(dir.path_join(f.trim_suffix(".tmp"))):
			LevelIO.load_file(dir.path_join(f.trim_suffix(".tmp")), LevelReport.new())
	var probe := EditorSession.new()
	for f in d.get_files():
		if not f.ends_with(LevelIO.EXT):
			continue
		var a := dir.path_join(f)
		if probe.recovery_for(a) == "":
			continue
		var m := LevelIO.read_meta(a)
		var own := CustomTracks.id_for_guid(str(m.get("guid", "")))
		out.append({"autosave": a, "path": CustomTracks.path(own) if own != "" else "", "name": str(m.get("name", "")),
			"modified": _stamp(a)})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.modified) > int(y.modified))
	return out


## RECOVER: opens the autosave as this session's document (unsaved, at its own file when there is
## one). "" or the reason.
func recover(autosave_p: String) -> String:
	var rep := LevelReport.new()
	var d := LevelIO.load_file(autosave_p, rep)
	if d == null:
		return rep.fatal()
	var own := CustomTracks.id_for_guid(str(d.data.get("guid", "")))
	_take(d)
	open_report = rep
	path = CustomTracks.path(own) if own != "" else ""
	track_id = own
	_clean_rev = -1
	return ""


## DISCARD: the autosave goes to .trash.
static func discard_autosave(autosave_p: String) -> void:
	if not FileAccess.file_exists(autosave_p):
		return
	DirAccess.make_dir_recursive_absolute(CustomTracks.trash_dir())
	var dst := LevelIO.free_path(CustomTracks.trash_dir(), "autosave_" + autosave_p.get_file().get_basename())
	DirAccess.rename_absolute(autosave_p, dst)


func dirty() -> bool:
	return doc != null and doc.revision != _clean_rev


func mark_clean() -> void:
	if doc != null:
		_clean_rev = doc.revision


func close() -> void:
	doc = null
	history = null
	path = ""
	track_id = ""
	build = null
	camera = Transform3D()
	has_view = false
	top_view = false
	tool = "road"
	selection = PackedInt32Array()
	hidden = PackedInt32Array()
	last_drive = {}
	bot_lap = {}
	resources.clear()
	_kept.clear()
	_clean_rev = -1
	_autosave_rev = -1
	open_report = null
	CustomTracks.forget(CustomTracks.EDIT_ID)


func keep(res: Resource) -> void:
	if res == null:
		return
	var k := res.get_instance_id()
	if _kept.has(k):
		return
	_kept[k] = true
	resources.append(res)


## Why a drive is refused: a full sentence from the report (a capital first) as it is, else in TEXT_BUILD.
static func build_text(why: String) -> String:
	if why != "" and why[0] != why[0].to_lower():
		return why if why.ends_with(".") else why + "."
	return TEXT_BUILD % why.trim_suffix(".")


## "" or why a test drive cannot run (cannot build). The texts hold {ed_*} combos for
## EditorKit.prompt.
func drive_blocker() -> String:
	if doc == null:
		return "No track is open."
	var road: Dictionary = doc.data.get("road", {})
	var pts: Array = road.get("points", [])
	if pts.size() < 3:
		return TEXT_NO_ROAD
	if not bool(road.get("closed", false)):
		return TEXT_OPEN
	if build != null and build.revision == doc.revision and build.report != null:
		var why := build.report.blocks_drive()
		if why != "" and why != "no_road" and why != "open_loop":
			return build_text(why)
	return ""


## done(reason: String) deferred: "" = the race scene is loading. Autosaves first, uses `build`
## when it matches the document (else awaits a worker bake), puts it in memory as c_edit, fills
## Game.test_drive (opts: from "start" | "here" | "watch", route, s, lat, and the TEST DRIVE
## options bots / laps / hazards / difficulty over settings.editor_test) and changes the scene.
func start_test_drive(tree: SceneTree, opts: Dictionary, done: Callable) -> void:
	# no gesture survives the drive (the history lives on in Game.editor)
	if history != null:
		history.end_gesture()
	var why := drive_blocker()
	if why != "":
		if done.is_valid():
			done.call_deferred(why)
		return
	autosave()
	_with_build(func(b: LevelBuild) -> void: _drive(tree, opts, b, done))


# ---------------------------------------------------------------- internals

static func _game() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Game")
	return null


static func _nickname() -> String:
	var g := _game()
	if g != null and g.has_method("nickname"):
		return str(g.call("nickname")).left(24)
	return ""


## The header's modified stamp (else the file's mtime).
static func _stamp(p: String) -> int:
	if p == "" or not FileAccess.file_exists(p):
		return -1
	var m := LevelIO.read_meta(p)
	if m.has("modified"):
		return int(m.modified)
	return FileAccess.get_modified_time(p)


func _take(d: LevelDoc) -> void:
	doc = d
	history = EditHistory.new(d)
	build = null
	camera = Transform3D()
	has_view = false
	top_view = false
	tool = "road"
	selection = PackedInt32Array()
	hidden = PackedInt32Array()
	last_drive = {}
	bot_lap = {}
	_autosave_rev = -1
	CustomTracks.forget(CustomTracks.EDIT_ID)


## Calls cb(build) with a full bake of the current revision: `build` when it matches, else a
## worker bake (deferred either way).
func _with_build(cb: Callable) -> void:
	if build != null and not build.partial and build.revision == doc.revision:
		cb.call_deferred(build)
		return
	var rev := doc.revision
	var d := doc
	LevelCompiler.compile_async(doc, {"id": CustomTracks.EDIT_ID, "registries": LevelCompiler.registries()},
		func(b: LevelBuild) -> void:
			if b != null and b.revision < 0:
				b.revision = rev
			if b != null and d == doc and b.revision == doc.revision:
				build = b
			cb.call(b))


## A document for the writer: the live one's sections (shared: the writer snapshots them on this
## thread) with modified / app / content set; the live document is not changed.
func _save_copy(now: int) -> LevelDoc:
	var s := LevelDoc.new()
	s.data = doc.data.duplicate(false)
	s.data["modified"] = now
	var g := _game()
	if g != null:
		s.data["app"] = str(g.get("version"))
		s.data["content"] = int(g.get("content_version"))
	s.heights = doc.heights
	s.splat = doc.splat
	s.thumb = doc.thumb
	s.thumb_custom = doc.thumb_custom
	return s


## The header's compile facts: stats, outline, the sample-count hints (2.6).
func _header(b: LevelBuild, extra: Dictionary) -> Dictionary:
	var h := {}
	var f := CustomTracks.facts_of(b)
	for k in ["length", "raceable", "errors", "warnings"]:
		if f.has(k):
			h[k] = f[k]
	var ol := _outline(b)
	if not ol.is_empty():
		h["outline"] = ol
	if has_view:
		var o := camera.origin
		var e := camera.basis.get_euler()
		h["view"] = [o.x, o.y, o.z, rad_to_deg(e.y), rad_to_deg(e.x)]
	for k in extra:
		h[k] = extra[k]
	return h


## At most 64 plan points of the main road, normalised to 0..1 over its bounding square.
func _outline(b: LevelBuild) -> Array:
	var pts := PackedVector3Array()
	if b != null:
		for r in b.roads:
			if r != null and r.key == -1 and r.pos.size() > 2:
				pts = r.pos
				break
	if pts.is_empty():
		for p in doc.data.get("road", {}).get("points", []):
			var q = p.get("pos")
			if q is Array and q.size() == 3:
				pts.append(Vector3(float(q[0]), float(q[1]), float(q[2])))
	if pts.size() < 2:
		return []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for v in pts:
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.z))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.z))
	var side := maxf(maxf(hi.x - lo.x, hi.y - lo.y), 0.001)
	var c := (lo + hi) * 0.5
	var n := mini(64, pts.size())
	var out := []
	for i in n:
		var v := pts[int(float(i) * pts.size() / n)]
		out.append([snappedf(clampf((v.x - c.x) / side + 0.5, 0.0, 1.0), 0.0001),
			snappedf(clampf((v.z - c.y) / side + 0.5, 0.0, 1.0), 0.0001)])
	return out


## The bake hints of 2.6 from a build (LevelBuild.stats.bake or meta.bake when the compiler
## gives them).
func _bake_hints(b: LevelBuild) -> Variant:
	if b == null:
		return null
	var bk = b.stats.get("bake", b.meta.get("bake"))
	if not (bk is Dictionary):
		return null
	# the document's form: string uid keys, int counts
	var out := {"main_n": int(bk.get("main_n", 0)), "branch_n": {}, "rows": {}}
	for k in ["branch_n", "rows"]:
		var src = bk.get(k)
		if src is Dictionary:
			for u in src:
				out[k][str(u)] = int(src[u])
	return out


func _write(target: String, header_extra: Dictionary, b: LevelBuild, done: Callable) -> void:
	if doc == null:
		saving = false
		if done.is_valid():
			done.call(ERR_UNCONFIGURED)
		return
	var rev := doc.revision
	var was_current := build != null and build.revision == rev
	var now := int(Time.get_unix_time_from_system())
	# the live document gets the save's meta in one apply (no undo step); the bake stays current
	var ops := [LevelDoc.op_set(["modified"], now)]
	var g := _game()
	if g != null:
		ops.append(LevelDoc.op_set(["app"], str(g.get("version"))))
		ops.append(LevelDoc.op_set(["content"], int(g.get("content_version"))))
	var bk = _bake_hints(b)
	if bk != null:
		ops.append(LevelDoc.op_set(["bake"], bk))
	saving_meta = true
	doc.apply(ops)
	saving_meta = false
	if was_current:
		build.revision = doc.revision
	if b != null and b.revision == rev:
		b.revision = doc.revision
	rev = doc.revision
	var facts := CustomTracks.facts_of(b)
	var header := _header(b, header_extra if header_extra != null else {})
	if FileAccess.file_exists(target):
		CustomTracks.keep_history(target)
	var auto := autosave_path()
	LevelIO.save_async(doc, target, header, func(err: Error) -> void:
		saving = false
		if err == OK:
			path = target
			if doc != null and doc.revision == rev:
				_clean_rev = rev
				if FileAccess.file_exists(auto):
					DirAccess.remove_absolute(auto)
			track_id = CustomTracks.note_saved(target, facts)
		if done.is_valid():
			done.call(err))


func _drive(tree: SceneTree, opts: Dictionary, b: LevelBuild, done: Callable) -> void:
	var why := ""
	if b == null:
		why = TEXT_BUILD % "the compiler gave nothing"
	elif b.report != null and b.report.blocks_drive() != "":
		why = build_text(b.report.blocks_drive())
	elif not (b.data.get("path") is Dictionary):
		why = TEXT_BUILD % "it has no road to race on"
	if why != "":
		if done.is_valid():
			done.call(why)
		return
	var m := b.meta.duplicate(true)
	m["name"] = str(doc.data.get("name", "TEST DRIVE"))
	m["short"] = str(doc.data.get("short", "TEST DRIVE"))
	m["author"] = str(doc.data.get("author", ""))
	m["rescue"] = str(doc.data.get("race", {}).get("rescue", "scanner"))
	m["guid"] = str(doc.data.get("guid", ""))
	CustomTracks.put_memory(CustomTracks.EDIT_ID, b, m)
	var g := _game()
	var td := test_options(opts)
	td["errors"] = b.report.errors() if b.report != null else 0
	if g != null:
		g.set("test_drive", td)
	if tree != null:
		var err := tree.change_scene_to_file(RACE_SCENE)
		if err != OK:
			if g != null:
				g.set("test_drive", {})
			if done.is_valid():
				done.call(TEXT_BUILD % "the race scene did not load")
			return
	if done.is_valid():
		done.call("")


## Game.test_drive for these options: {track: c_edit, laps, bots, hazards, difficulty, from,
## route, s, lat}, the TEST DRIVE options from settings.editor_test where opts leaves them out.
static func test_options(opts: Dictionary) -> Dictionary:
	var base: Dictionary = TEST_DEFAULTS.duplicate()
	var g := _game()
	if g != null:
		var st = (g.get("settings") as Dictionary).get("editor_test")
		if st is Dictionary:
			for k in TEST_KEYS:
				if st.has(k):
					base[k] = st[k]
	var td := {"track": CustomTracks.EDIT_ID}
	for k in TEST_KEYS:
		var v = opts.get(k, base[k])
		var r: Array = TEST_KEYS[k]
		td[k] = clampi(int(v) if (v is int or v is float) else int(TEST_DEFAULTS[k]), int(r[0]), int(r[1]))
	var from := str(opts.get("from", "start"))
	td["from"] = from if from in ["start", "here", "watch"] else "start"
	td["route"] = int(opts.get("route", -1))
	td["s"] = float(opts.get("s", 0.0))
	td["lat"] = clampf(float(opts.get("lat", 0.0)), -3.0, 3.0)
	return td
