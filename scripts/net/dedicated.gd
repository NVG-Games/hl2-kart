class_name DedicatedConsole
extends Node
## Dedicated server console (headless). Lives under the Net autoload and reads
## commands from stdin like the srcds console: status, say, kick, start,
## lobby, tracks, rescan, track <name>, next, set <rule> <value>, quit.
## tracks, rescan, track and next read the track folders again first: a file added or replaced
## while the server runs is found (a replaced one under its new id).
## It also prefetches the next rotation entry: once the current track is ready the server
## compiles the next custom track of the list on a worker (6.6), and nothing else.

const HELP := [
	"status | say <text> | kick <nick> | start | lobby | tracks | rescan | track <name> | next | set <rule> <value> | rules | quit",
	"rules: hostname maxplayers bot_fill bot_grid mp_laps mp_difficulty mp_hazards sv_password",
	"tracks: mp_track mp_tracklist mp_rotate sv_tracks sv_downloads sv_download_rate",
	"start skips READY, never the track; track / next during a race apply after it",
	"rescan reads the track folders again (tracks, track and next do it too)",
]

var _thread: Thread
var _quit := false
var _status_t := 0.0
var _prefetch_t := 0.0
var _prefetching := ""      # the id a prefetch compiles now
var _prefetched := {}       # id -> true: asked once (a failure marks it unusable)


func _ready() -> void:
	name = "Console"
	# commands come from a console, a pipe or a file; with none (started detached, stdin NUL)
	# there is nothing to read
	var st := OS.get_stdin_type()
	if st != OS.STD_HANDLE_CONSOLE and st != OS.STD_HANDLE_PIPE and st != OS.STD_HANDLE_FILE:
		return
	_thread = Thread.new()
	_thread.start(_read_stdin)
	print("type 'help' for commands")


## Reads command lines until quit / exit or the end of the input, so the thread is done before
## the server quits (one still looping at shutdown left a Thread warning and exit code -1).
func _read_stdin() -> void:
	while not _quit:
		var line := OS.read_string_from_stdin(1024)
		if line == "":
			return  # the end of a pipe or a file
		for l in line.split("\n", false):
			var c := l.strip_edges()
			if c.to_lower() in ["quit", "exit"]:
				_quit = true
			_command.call_deferred(c)


func _process(delta: float) -> void:
	_status_t += delta
	if _status_t > 300.0:
		_status_t = 0.0
		print("[%s] %d/%d players, %s, %s" % [Time.get_time_string_from_system(), Net.humans(), Net.cfg["max_players"], Net.state,
			str(Game.track(str(Net.cfg.get("track", ""))).get("name", ""))])
	_prefetch_t += delta
	if _prefetch_t > 1.0:
		_prefetch_t = 0.0
		_prefetch()


## The next rotation entry, compiled once the current track is ready (one at a time, once each).
func _prefetch() -> void:
	if not Net.active or not Net.is_server or Net.share == null or _prefetching != "":
		return
	if not Net.share.server_ready():
		return
	var nxt := Net.share.next_track()
	if not CustomTracks.is_custom(nxt) or CustomTracks.is_prepared(nxt) or _prefetched.has(nxt):
		return
	_prefetched[nxt] = true
	_prefetching = nxt
	CustomTracks.prepare(nxt, func(ok: bool, why: String) -> void:
		_prefetching = ""
		if ok:
			print("next track ready: %s" % _label(nxt))
		else:
			print("next track %s cannot be used: %s (the rotation skips it)" % [_label(nxt), TrackShare.clean_text(why, 120)]))


func _command(line: String) -> void:
	if line == "":
		return
	var parts := line.split(" ", false)
	var cmd := parts[0].to_lower()
	var rest := line.substr(parts[0].length()).strip_edges()
	match cmd:
		"help":
			for h in HELP:
				print(h)
		"status":
			for l in status_lines():
				print(l)
		"say":
			Net.say(rest)
		"kick":
			for id in Net.players:
				if Net.players[id]["nick"].to_lower() == rest.to_lower():
					Net.kick(id)
					return
			print("no player named ", rest)
		"start":
			# READY skipped, never the track (C1 N21)
			var why := Net.can_start(true)
			if why != "":
				print("cannot start: ", why)
				return
			Net.start_race_now(true)
		"lobby":
			Net.back_to_lobby()
		"tracks":
			Net.share.rescan()
			for l in tracks_lines():
				print(l)
		"rescan":
			Net.share.rescan()
			_prefetched.clear()
			print("%d custom tracks in the folders (%s)" % [CustomTracks.list("all").size(), ", ".join(CustomTracks.folders())])
		"track", "map":
			if rest == "":
				print("track <id, name or file name>   (now: %s)" % _label(str(Net.cfg.get("track", ""))))
				return
			_set_track(rest)
		"next":
			var was := str(Net.cfg.get("track", ""))
			# an operator's next works with mp_rotate 0 too (it reads the folders again first)
			if not Net.share.rotate_after_failure():
				print("no other usable track in mp_tracklist")
			elif Net.state != "lobby":
				print("next track after this race: %s" % _label(Net.share.pending_track))
			elif str(Net.cfg.get("track", "")) != was:
				_print_track()
		"rules":
			print(Net.cfg)
		"set":
			if parts.size() < 3:
				print("set <rule> <value>")
				return
			var key: String = DedicatedConfig.CVARS.get(parts[1].to_lower(), parts[1].to_lower())
			var value := line.substr(line.find(parts[1]) + parts[1].length()).strip_edges()
			if value.length() >= 2 and value.begins_with("\"") and value.ends_with("\""):
				value = value.substr(1, value.length() - 2)
			if key == "track":
				_set_track(value)
				return
			var o := {}
			if not DedicatedConfig.set_option(o, key, value):
				print("bad value")
				return
			for k in o:
				Net.set_rule(k, o[k])
			if key == "tracklist" or key == "rotate":
				_prefetched.clear()
			print("%s = %s" % [key, o.get(key, "")])
		"quit", "exit":
			_quit = true
			Net.leave()
			get_tree().quit()
		_:
			print("unknown command: ", cmd)


## `track <name>` / `set mp_track <name>`: resolved at once (after a rescan of the folders); during
## a race it is kept and applied when everyone is back in the lobby.
func _set_track(value: String) -> void:
	Net.share.rescan()
	var o := {"track": str(Net.cfg.get("track", ""))}
	if not DedicatedConfig.set_option(o, "track", value):
		return
	Net.set_rule("track", o["track"])
	if Net.state != "lobby":
		print("track after this race: %s" % _label(Net.share.pending_track))
	else:
		_print_track()


## "track: <name> (<id>)" once the server serves it, else why not (the failure then moves on).
func _print_track() -> void:
	var id := str(Net.cfg.get("track", ""))
	if CustomTracks.is_custom(id) and Net.share.pkg.is_empty():
		print("track %s cannot be used: its file changed or is missing" % _label(id))
		return
	print("track: %s" % _label(id))


## The status block: the server, its track and every player's track state / percent / reason.
static func status_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var info := Net.server_info()
	var id := str(Net.cfg.get("track", ""))
	var ready := Net.share != null and Net.share.server_ready()
	out.append("hostname: %s\nstate   : %s\nplayers : %d/%d" % [info["name"], info["state"], info["players"], info["max"]])
	out.append("track   : %s%s" % [_label(id), "" if ready else ("  (preparing)" if CustomTracks.is_custom(id) else "  (not built here)")])
	var nxt := Net.share.next_track() if Net.share != null else ""
	if nxt != "":
		out.append("next    : %s%s" % [_label(nxt), "  (ready)" if CustomTracks.is_custom(nxt) and CustomTracks.is_prepared(nxt) else ""])
	if Net.share != null and Net.share.pending_track != "":
		out.append("after this race: %s" % _label(Net.share.pending_track))
	var ids: Array = Net.players.keys()
	ids.sort()
	for pid in ids:
		var p: Dictionary = Net.players[pid]
		out.append("  #%d %-24s %4d ms  %s%s  %s" % [pid, TrackShare.clean_text(str(p["nick"]), 24), int(p.get("ping", 0)),
			p["character"], "  READY" if p["ready"] else "", track_state(p)])
	for a in Net.local_addresses():
		out.append("  address %s:%d" % [a, int(Net.cfg.get("port", Net.DEFAULT_PORT))])
	return out


## A player's track state for the console: "track ok", "track 42%", "track NO (download stalled)".
static func track_state(p: Dictionary) -> String:
	var st := str(p.get("track", "?"))
	match st:
		"ok":
			return "track ok"
		"get", "need":
			return "track %d%%" % int(roundf(clampf(float(p.get("dl", 0.0)), 0.0, 1.0) * 100.0))
		"prep":
			return "track preparing"
		"fail":
			return "track NO (%s)" % TrackShare.clean_text(TrackShare.words(str(p.get("why", ""))), TrackShare.REASON_MAX)
	return "track ?"


## `tracks`: the built-in circuits and the custom tracks of the folders: id, name, size, raceable.
static func tracks_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var cur := str(Net.cfg.get("track", "")) if Net.active else ""
	out.append("built-in:")
	for t in Game.TRACKS:
		out.append("  %s %-18s %-26s %s" % ["*" if t["id"] == cur else " ", t["id"], t["name"],
			"yes" if Game.track_installed(t["id"]) else "no (not built: run the setup again)"])
	var customs := CustomTracks.list("all")
	out.append("custom (%d):" % customs.size())
	for m in customs:
		var id := str(m.get("id", ""))
		var raceable := "?"
		if CustomTracks.unusable(id) != "":
			raceable = "no (%s)" % TrackShare.clean_text(CustomTracks.unusable(id), 60)
		elif CustomTracks.is_prepared(id) or bool(m.get("checked", false)):
			raceable = "yes" if bool(m.get("raceable", false)) or CustomTracks.is_prepared(id) else "no"
		else:
			raceable = "not compiled yet"
		var size := int(m.get("size", 0))
		var size_s := "%.1f MB" % (size / 1048576.0) if size >= 100 * 1024 else "%d KB" % ceili(size / 1024.0)
		out.append("  %s %s %-26s %8s  %-7s %s  %s" % ["*" if id == cur else " ", id,
			TrackShare.clean_text(str(m.get("name", "")), 26), size_s, str(m.get("kind", "")),
			str(m.get("path", "")).get_file(), raceable])
	var folders := CustomTracks.folders()
	out.append("folders: %s" % ", ".join(folders))
	return out


static func _label(id: String) -> String:
	if id == "":
		return "-"
	var t := Game.track(id)
	var nm := TrackShare.clean_text(str(t.get("name", id)), 48)
	return "%s (%s)" % [nm, id] if nm != id else id


func _exit_tree() -> void:
	_quit = true
	# a reader still waiting for a console line can not be woken: the process ends it
	if _thread and not _thread.is_alive():
		_thread.wait_to_finish()
