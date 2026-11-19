class_name DedicatedConfig
## Dedicated server options from a server.cfg (Source-style "cvar value" lines)
## and the command line (--port 27015 --name "..." --max 8 --bots on ...).
## The track and the track list are kept as written until every line and flag is read and the
## track folders are scanned; finish(o) resolves them then (a custom track's file name, display
## name, c_ id or sha prefix only means something after the scan, 6.8).

## server.cfg cvar -> option key
const CVARS := {
	"hostname": "name", "port": "port", "maxplayers": "max_players", "bot_fill": "bots",
	"bot_grid": "grid", "mp_laps": "laps", "mp_difficulty": "difficulty", "mp_hazards": "hazards",
	"sv_password": "password", "sv_lan": "lan_only", "sv_master": "master", "sv_upnp": "upnp", "mp_track": "track", "map": "track",
	"sv_tracks": "tracks_dir", "sv_downloads": "downloads", "sv_download_rate": "download_rate",
	"mp_tracklist": "tracklist", "mp_rotate": "rotate",
}
## command-line flag -> option key
const FLAGS := {
	"--name": "name", "--port": "port", "--max": "max_players", "--bots": "bots", "--grid": "grid",
	"--laps": "laps", "--difficulty": "difficulty", "--hazards": "hazards",
	"--password": "password", "--master": "master", "--config": "config", "--track": "track", "--map": "track",
	"--tracks": "tracks_dir", "--tracklist": "tracklist",
}
## Keys resolved by finish(o), after the scan.
const LATE := ["track", "tracklist"]


static func defaults() -> Dictionary:
	return {"name": "Half-Life 2: Kart server", "port": 27015, "max_players": 8, "bots": true, "grid": 8,
		"laps": 3, "difficulty": 1, "hazards": 1, "password": "", "lan_only": false,
		"master": "", "upnp": false, "track": "city17_circuit",
		"tracks_dir": "", "downloads": 1, "download_rate": 192, "tracklist": PackedStringArray(), "rotate": 1}


static func load_options(args: PackedStringArray) -> Dictionary:
	var o := defaults()
	var cfg_path := ""
	var i := 0
	while i < args.size():
		if args[i] == "--config" and i + 1 < args.size():
			cfg_path = args[i + 1]
		i += 1
	if cfg_path == "":
		for c in [OS.get_executable_path().get_base_dir().path_join("server.cfg"), "res://server.cfg", "user://server.cfg"]:
			if FileAccess.file_exists(c):
				cfg_path = c
				break
	if cfg_path != "":
		print("reading ", cfg_path)
		_read_cfg(cfg_path, o)
	i = 0
	while i < args.size():
		var a := args[i]
		if a == "--lan":
			o["lan_only"] = true
		elif a == "--upnp":
			o["upnp"] = true
		elif FLAGS.has(a) and i + 1 < args.size():
			_store(o, FLAGS[a], args[i + 1])
			i += 1
		i += 1
	finish(o)
	return o


## After every line and flag: the track folders (sv_tracks / --tracks first) are scanned through
## the gate, then the track and the track list are resolved (built-in ids / names, custom file
## names / display names / c_ ids / sha prefixes). A track that names nothing here keeps the
## default; list entries that name nothing are dropped, each with a line in the log.
static func finish(o: Dictionary) -> void:
	scan(str(o.get("tracks_dir", "")))
	var raw := str(o.get("track", ""))
	var id := resolve_track(raw)
	if id == "":
		var fallback := str(defaults()["track"])
		if not Game.track_installed(fallback):
			for t in Game.TRACKS:
				if Game.track_installed(t["id"]):
					fallback = t["id"]
					break
		if raw != "" and raw != fallback:
			printerr("mp_track %s: %s: racing %s" % [raw.left(64), _why_not(raw), fallback])
		id = fallback
	o["track"] = id
	var ids := PackedStringArray()
	for e in _entries(o.get("tracklist", "")):
		var tid := resolve_track(e)
		if tid == "":
			printerr("mp_tracklist %s: %s: left out" % [e.left(64), _why_not(e)])
		elif not tid in ids:
			ids.append(tid)
	o["tracklist"] = ids


## The track folders (6.8): `dir` first when given, then <exe dir>/tracks, res://tracks and
## user://tracks (CustomTracks.folders, never .autosave/, .trash/, .history/ or cache/). Every
## file goes through LevelIO.unpack and nothing more: a bad one is logged and skipped (own files
## too, which the registry only hashes). Nothing is compiled here: the server compiles its current
## track and the next rotation entry only.
static func scan(dir := "") -> void:
	if dir.strip_edges() != "":
		CustomTracks.add_folder(dir.strip_edges())
	var was := CustomTracks.auto_check
	CustomTracks.auto_check = false
	CustomTracks.refresh()
	CustomTracks.auto_check = was
	for m in CustomTracks.list("mine"):
		var id := str(m.get("id", ""))
		if CustomTracks.unusable(id) != "":
			continue
		var rep := LevelReport.new()
		if LevelIO.unpack(CustomTracks.bytes(id), rep) == null:
			var why := rep.fatal()
			print("%s skipped: %s" % [str(m.get("path", id)).get_file(), why])
			CustomTracks.mark_unusable(id, why)


## A track's id from a built-in id / name / short name or a custom file name / display name /
## c_ id / sha prefix; "" when it names nothing raceable here (a built-in this install has not
## built, a custom file the scan refused).
static func resolve_track(value: String) -> String:
	var q := value.strip_edges()
	if q == "":
		return ""
	for t in Game.TRACKS:
		if t["id"] == q.to_lower() or str(t["name"]).to_lower() == q.to_lower() or str(t.get("short", "")).to_lower() == q.to_lower():
			# (a track this install has not built yet is refused, not raced as Highway 17 while the
			# server announces it: Game.track_installed)
			return t["id"] if Game.track_installed(t["id"]) else ""
	var id := CustomTracks.find(q)
	if id == "" or CustomTracks.unusable(id) != "":
		return ""
	return id


static func _why_not(value: String) -> String:
	var q := value.strip_edges()
	for t in Game.TRACKS:
		if t["id"] == q.to_lower() or str(t["name"]).to_lower() == q.to_lower():
			return "not built on this machine (run the setup again)"
	var id := CustomTracks.find(q)
	if id != "" and CustomTracks.unusable(id) != "":
		return "unusable (%s)" % CustomTracks.unusable(id)
	return "no such track in the tracks folders"


## A track list as written: "a, b, c" or an array -> its entries.
static func _entries(v: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	var parts: Array = []
	if v is Array or v is PackedStringArray:
		parts = Array(v)
	else:
		parts = Array(str(v).split(",", false))
	for p in parts:
		var s := str(p).strip_edges()
		if s != "":
			out.append(s)
	return out


static func _read_cfg(path: String, o: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("cannot read ", path)
		return
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("//") or line.begins_with("#"):
			continue
		var sp := line.find(" ")
		if sp < 0:
			continue
		var key := line.left(sp).to_lower()
		# the value: a quoted one up to its closing quote, else up to a comment after a space (" //"
		# or " #": the example file has one on every line)
		var value := line.substr(sp + 1).strip_edges()
		if value.begins_with("\""):
			var q := value.find("\"", 1)
			value = value.substr(1, q - 1) if q > 0 else value.substr(1)
		else:
			for mark in [" //", "	//", " #", "	#"]:
				var c := value.find(mark)
				if c >= 0:
					value = value.left(c)
			value = value.strip_edges()
		if CVARS.has(key):
			_store(o, CVARS[key], value)


## While reading: the track and the list as written (finish resolves them), the rest parsed.
static func _store(o: Dictionary, key: String, value: String) -> void:
	if key in LATE:
		o[key] = value.strip_edges()
		return
	if not set_option(o, key, value):
		printerr("%s %s: bad value, kept %s" % [key, value.left(64), str(o.get(key, ""))])


## Parse a value the way the console does ("on", "1", "hard", "xen", a custom track's file name).
## The track and the list resolve at once: the console runs after the scan.
static func set_option(o: Dictionary, key: String, value: String) -> bool:
	match key:
		"port", "max_players", "grid", "laps":
			if not value.is_valid_int():
				return false
			o[key] = int(value)
		"download_rate":
			if not value.is_valid_int() or int(value) < 1:
				return false
			o[key] = clampi(int(value), 1, 100000)
		"bots", "lan_only", "upnp":
			o[key] = value.to_lower() in ["1", "on", "yes", "true"]
		"downloads", "rotate":
			var v := value.to_lower()
			if v in ["0", "off", "no", "false"]:
				o[key] = 0
			elif v in ["1", "on", "yes", "true"]:
				o[key] = 1
			else:
				return false
		"difficulty":
			var names := ["easy", "normal", "hard"]
			if value.to_lower() in names:
				o[key] = names.find(value.to_lower())
			elif value.is_valid_int():
				o[key] = clampi(int(value), 0, 2)
			else:
				return false
		"hazards":
			var v := value.to_lower()
			if v in ["0", "off", "no", "false"]:
				o[key] = 0
			elif v in ["1", "on", "yes", "true"]:
				o[key] = 1
			else:
				return false
		"track":
			var found := resolve_track(value)
			if found == "":
				printerr("track %s: %s: kept %s" % [value.left(64), _why_not(value), o.get(key, "the current track")])
				return false
			o[key] = found
		"tracklist":
			var ids := PackedStringArray()
			for e in _entries(value):
				var tid := resolve_track(e)
				if tid == "":
					printerr("mp_tracklist %s: %s: left out" % [e.left(64), _why_not(e)])
				elif not tid in ids:
					ids.append(tid)
			o[key] = ids
		"tracks_dir":
			o[key] = value.strip_edges()
		_:
			o[key] = value
	return true
