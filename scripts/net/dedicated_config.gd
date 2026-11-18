class_name DedicatedConfig
## Dedicated server options from a server.cfg (Source-style "cvar value" lines)
## and the command line (--port 27015 --name "..." --max 8 --bots on ...).

## server.cfg cvar -> option key
const CVARS := {
	"hostname": "name", "port": "port", "maxplayers": "max_players", "bot_fill": "bots",
	"bot_grid": "grid", "mp_laps": "laps", "mp_difficulty": "difficulty", "mp_hazards": "hazards",
	"sv_password": "password", "sv_lan": "lan_only", "sv_master": "master", "sv_upnp": "upnp", "mp_track": "track", "map": "track",
}
## command-line flag -> option key
const FLAGS := {
	"--name": "name", "--port": "port", "--max": "max_players", "--bots": "bots", "--grid": "grid",
	"--laps": "laps", "--difficulty": "difficulty", "--hazards": "hazards",
	"--password": "password", "--master": "master", "--config": "config", "--track": "track", "--map": "track",
}


static func defaults() -> Dictionary:
	return {"name": "Half-Life 2: Kart server", "port": 27015, "max_players": 8, "bots": true, "grid": 8,
		"laps": 3, "difficulty": 1, "hazards": 1, "password": "", "lan_only": false,
		"master": "", "upnp": false, "track": "city17_circuit"}


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
			set_option(o, FLAGS[a], args[i + 1])
			i += 1
		i += 1
	return o


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
			set_option(o, CVARS[key], value)


## Parse a value the way the console does ("on", "1", "hard", "xen").
static func set_option(o: Dictionary, key: String, value: String) -> bool:
	match key:
		"port", "max_players", "grid", "laps":
			if not value.is_valid_int():
				return false
			o[key] = int(value)
		"bots", "lan_only", "upnp":
			o[key] = value.to_lower() in ["1", "on", "yes", "true"]
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
			var found := ""
			for t in Game.TRACKS:
				if t["id"] == value.to_lower() or t["name"].to_lower() == value.to_lower():
					found = t["id"]
			# (a track this install has not built yet is refused, not raced as Highway 17 while the
			# server announces it: Game.track_installed)
			if found == "":
				return false
			if not Game.track_installed(found):
				printerr("track %s is not built on this machine (run the setup again): kept %s" % [found, o.get(key, "the current track")])
				return false
			o[key] = found
		_:
			o[key] = value
	return true
