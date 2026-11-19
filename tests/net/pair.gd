extends Node
## The two-process transfer test (9.3, local, content optional), run by tests/net_track_test.tscn:
##   -- pair <port> [--rate 256] [--ack-hold 100] [--no-hostile]
##   -- client <port> --track-cache <dir> --nick <n> --phase fresh|cache|hostile --log <file> [--ack-hold <ms>]
## The host writes a test package (the oval template with random ground paint and a little height
## noise, about 1.3 MB) into user://net_track_test/pair/tracks/, starts a dedicated host on <port>
## with that folder (a test rate cap of 256 KB/s in the lobby too) and launches two headless
## clients, each with its own APPDATA (so the three processes never share settings_test.cfg) and its
## own --track-cache. Three phases, at most three processes at a time:
##   fresh:   both clients download (need -> get -> prep -> ok, >= 4 progress updates each; client
##            B acks 100 ms late); can_start() refuses until both are ok and READY; autostart fires
##            only then; every peer's _s_start_race carries the server's track_sha; both digests
##            equal the server's; lobby chat stays under 200 ms late during the downloads.
##   cache:   the same two clients again: a cache hit (no _s_xfer sent), the same start.
##   builtin: (content) Highway 17: both report ok at once, nothing sent, an empty track_sha.
##   hostile: the server serves a damaged copy (its own sha in cfg, --serve-hostile; on unless
##            --no-hostile): client A reports fail:invalid and stays connected (its exit code).
## The clients quit right after _s_start_race; the host goes back to the lobby 1.5 s after a start.
## Prints "pair: N checks, F failures" and exits 1 on any failure.

const BASE := "user://net_track_test/pair"
const PHASE_TIMEOUT := 90.0
const CLIENT_TIMEOUT := 100.0

var mode := ""
var args := PackedStringArray()
var port := 27301
var checks := 0
var failures := 0

# ---- host
var _pids: Array = []
var _ready_at_countdown := []
var _premature := false
var _refusals := 0
var _ping_t := 0.0
var _start_sha := ""
var _race_t := -1.0
var _roster_fail := ""

# ---- client
var _phase := ""
var _log: FileAccess
var _ending := false
var _states: Array = []
var _progress := 0
var _late_max := 0.0
var _late_n := 0
var _fail_t := -1.0
var _t := 0.0
var _ready_sent := false


func setup(m: String, a: PackedStringArray) -> void:
	mode = m
	args = a
	if a.size() > 0 and a[0].is_valid_int():
		port = int(a[0])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if mode == "client":
		_client()
	else:
		_host()


func _arg(flag: String, def := "") -> String:
	var i := args.find(flag)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else def


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: [pair] ", what)
	else:
		print("ok: ", what)


# ================================================================ host

func _host() -> void:
	Engine.max_fps = 120
	var base := ProjectSettings.globalize_path(BASE)
	_wipe(base)
	DirAccess.make_dir_recursive_absolute(base + "/tracks")
	var good := _package()
	var f := FileAccess.open(base + "/tracks/pair_test_oval.hl2kt", FileAccess.WRITE)
	f.store_buffer(good)
	f.close()
	var sha := LevelIO.sha256(good)
	var id := LevelIO.id_for(sha)
	print("pair: package %d bytes, %s" % [good.size(), id])
	CustomTracks.add_folder(base + "/tracks")
	CustomTracks.refresh(true)
	_check(CustomTracks.has(id), "the server's folder holds the test track")
	if Net.host({"name": "pair test", "port": port, "bots": false, "grid": 2, "laps": 1, "difficulty": 1,
			"track": id, "hazards": 0, "lan_only": true}, true) != OK:
		_check(false, "host on port %d: %s" % [port, Net.last_error])
		_finish()
		return
	Net.share.rate_cap = int(_arg("--rate", "256"))
	Net.countdown_changed.connect(func(s: float) -> void:
		if s > 0.0:
			_ready_at_countdown.append(_all_ok_ready()))
	Net.share.progress_changed.connect(func(p: int, st: String, _dl: float) -> void:
		if st == "fail" and Net.players.has(p):
			_roster_fail = str(Net.players[p].get("why", "")))
	_check(Net.can_start(true) != "" or Net.share.server_ready(), "START waits for the server's own build")
	var t0 := Time.get_ticks_msec()
	while not Net.share.server_ready() and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	_check(Net.share.server_ready(), "the dedicated server prepared its track (%d ms)" % (Time.get_ticks_msec() - t0))
	if not Net.share.server_ready():
		_finish()
		return
	var hold := _arg("--ack-hold", "100")
	# fresh: both download
	var x0: int = Net.share.stats.xfers
	var dg0: int = Net.share.stats.digest_ok
	var logs := await _run_phase("fresh", [["Alpha", "A", []], ["Bravo", "B", ["--ack-hold", hold]]], 2)
	_check(int(Net.share.stats.xfers) - x0 >= 2, "fresh: a transfer per client (%d)" % (int(Net.share.stats.xfers) - x0))
	_check(int(Net.share.stats.digest_ok) - dg0 == 2 and int(Net.share.stats.digest_bad) == 0,
		"fresh: both digests equal the server's (%d ok, %d different)" % [int(Net.share.stats.digest_ok) - dg0, int(Net.share.stats.digest_bad)])
	for nick in logs:
		var lg: Dictionary = logs[nick]
		var order := _order(lg.states, ["need", "get", "prep", "ok"])
		_check(order, "fresh %s: need -> get -> prep -> ok (%s)" % [nick, str(lg.states)])
		_check(int(lg.progress) >= 4, "fresh %s: %d progress updates" % [nick, int(lg.progress)])
		_check(lg.start == sha, "fresh %s: _s_start_race carried the server's track_sha" % nick)
		_check(lg.code == 0, "fresh %s: exit code %d (%s)" % [nick, int(lg.code), lg.result])
		if int(lg.late_n) > 0:
			_check(float(lg.late_max) < 200.0, "fresh %s: lobby chat at most %.0f ms late while downloading (%d samples)" % [nick, float(lg.late_max), int(lg.late_n)])
	# cache: the same clients again
	x0 = Net.share.stats.xfers
	logs = await _run_phase("cache", [["Alpha", "A", []], ["Bravo", "B", []]], 2)
	_check(int(Net.share.stats.xfers) == x0, "cache: no _s_xfer sent (%d)" % (int(Net.share.stats.xfers) - x0))
	for nick in logs:
		var lg: Dictionary = logs[nick]
		_check(not lg.states.has("get") and lg.states.has("ok"), "cache %s: a hit, prep -> ok (%s)" % [nick, str(lg.states)])
		_check(lg.start == sha and lg.code == 0, "cache %s: started on the same track (exit %d)" % [nick, int(lg.code)])
	# a built-in circuit (content): the plain report-ok path, an empty track_sha
	if Game.track_installed("city17_circuit"):
		Net.set_rule("track", "city17_circuit")
		x0 = Net.share.stats.xfers
		logs = await _run_phase("builtin", [["Alpha", "A", []], ["Bravo", "B", []]], 2)
		_check(int(Net.share.stats.xfers) == x0, "builtin: nothing sent")
		for nick in logs:
			var lg: Dictionary = logs[nick]
			_check(lg.states.has("ok") and lg.code == 0 and lg.start == "", "builtin %s: ok, started with no track_sha (exit %d)" % [nick, int(lg.code)])
	# hostile: a damaged copy under its own sha
	if not args.has("--no-hostile"):
		var bad := _damaged(good)
		var hid := Net.share.serve_raw(bad, "PAIR HOSTILE")
		Net.set_rule("track", hid)
		_check(str(Net.cfg.get("track", "")) == hid and str(Net.cfg.custom.sha) == LevelIO.sha256(bad), "hostile: served under its own sha")
		_roster_fail = ""
		logs = await _run_phase("hostile", [["Alpha", "A", []]], 1)
		var lg: Dictionary = logs.get("Alpha", {})
		_check(int(lg.get("code", -1)) == 0, "hostile: the client reported fail:invalid and stayed connected (exit %d, %s)" % [int(lg.get("code", -1)), str(lg.get("result", ""))])
		_check(_roster_fail == "invalid", "hostile: the server's roster says invalid (%s)" % _roster_fail)
	_finish()


## Launch the clients, watch the lobby until they are gone; their logs by nick.
func _run_phase(phase: String, clients: Array, n: int) -> Dictionary:
	print("pair: phase ", phase)
	_ready_at_countdown.clear()
	_premature = false
	_refusals = 0
	_start_sha = ""
	_race_t = -1.0
	var base := ProjectSettings.globalize_path(BASE)
	var procs := {}
	for c in clients:
		var nick: String = c[0]
		var dir: String = base + "/" + str(c[1])
		DirAccess.make_dir_recursive_absolute(dir + "/cache")
		var log_path := "%s/%s_%s.log" % [base, phase, nick]
		if FileAccess.file_exists(log_path):
			DirAccess.remove_absolute(log_path)
		var a := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://").trim_suffix("/"),
			"--max-fps", "60", "res://tests/net_track_test.tscn", "--", "client", str(port), "--track-cache", dir + "/cache",
			"--nick", nick, "--phase", phase, "--log", log_path, "--humans", str(n)])
		a.append_array(PackedStringArray(c[2]))
		var old := OS.get_environment("APPDATA")
		OS.set_environment("APPDATA", dir)
		var pid := OS.create_process(OS.get_executable_path(), a)
		OS.set_environment("APPDATA", old)
		_check(pid > 0, "%s: launched %s (pid %d)" % [phase, nick, pid])
		procs[nick] = {"pid": pid, "log": log_path}
		print("pair: launched ", nick, " pid ", pid, " APPDATA ", dir)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < PHASE_TIMEOUT * 1000.0:
		await get_tree().process_frame
		var running := false
		for nick in procs:
			if int(procs[nick].pid) > 0 and OS.is_process_running(int(procs[nick].pid)):
				running = true
		_watch(n)
		if not running:
			break
	for nick in procs:
		var pid := int(procs[nick].pid)
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
			_check(false, "%s: %s still running after %.0f s (killed)" % [phase, nick, PHASE_TIMEOUT])
	if phase != "hostile":
		_check(not _premature, "%s: can_start() refused until every client was ok and READY (%d refusals)" % [phase, _refusals])
		_check(not _ready_at_countdown.is_empty() and not _ready_at_countdown.has(false),
			"%s: autostart fired only with everyone ok and READY (%s)" % [phase, str(_ready_at_countdown)])
		_check(_race_t >= 0.0, "%s: the race started (track_sha %s)" % [phase, _start_sha.left(12)])
	if Net.state != "lobby":
		Net.back_to_lobby()
		await get_tree().process_frame
	var out := {}
	for nick in procs:
		var lg := _read_log(str(procs[nick].log))
		var pid := int(procs[nick].pid)
		lg["code"] = OS.get_process_exit_code(pid) if pid > 0 else -1
		out[nick] = lg
	return out


## Every frame of a phase: the START gate, the chat pings, the start and the way back.
func _watch(n: int) -> void:
	if Net.state == "lobby":
		if _race_t < 0.0 and Net.players.size() == n and not _all_ok_ready():
			if Net.can_start() == "":
				_premature = true
			else:
				_refusals += 1
		_ping_t -= get_process_delta_time()
		if _ping_t <= 0.0:
			_ping_t = 0.25
			Net._to_clients(&"_s_chat", ["", "PING %.4f" % Net.now(), "info"])
	elif Net.state == "race":
		if _race_t < 0.0:
			_race_t = Time.get_ticks_msec() / 1000.0
			_start_sha = str(Game.session.get("track_sha", ""))
		elif Time.get_ticks_msec() / 1000.0 - _race_t > 1.5:
			Net.back_to_lobby()


func _all_ok_ready() -> bool:
	if Net.players.is_empty():
		return false
	for p in Net.players.values():
		if str(p.get("track", "")) != "ok" or not bool(p.get("ready", false)):
			return false
	return true


func _read_log(path: String) -> Dictionary:
	var o := {"states": [], "progress": 0, "start": "", "late_max": 0.0, "late_n": 0, "result": ""}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		o.result = "no log"
		return o
	while not f.eof_reached():
		var ln := f.get_line().strip_edges()
		var parts := ln.split(" ", false)
		if parts.is_empty():
			continue
		match parts[0]:
			"STATE":
				if parts.size() > 1 and (o.states.is_empty() or o.states[-1] != parts[1]):
					o.states.append(parts[1])
			"PROGRESS":
				o.progress = int(parts[1]) if parts.size() > 1 else 0
			"START":
				o.start = parts[1] if parts.size() > 1 else ""
			"LATE":
				o.late_max = float(parts[1]) if parts.size() > 1 else 0.0
				o.late_n = int(parts[2]) if parts.size() > 2 else 0
			"RESULT":
				o.result = ln.substr(7)
	return o


static func _order(states: Array, want: Array) -> bool:
	var i := 0
	for s in states:
		if i < want.size() and s == want[i]:
			i += 1
	return i == want.size()


## The oval, its ground paint random (about 1 MB that does not compress) and its ground a little
## noisy: a package of about 1.3 MB.
func _package() -> PackedByteArray:
	var doc := LevelTemplates.make("oval", "PAIR TEST OVAL")
	var img := Image.create(96, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.5, 0.8))
	doc.thumb = img.save_png_to_buffer()
	if bool(doc.data.world.terrain):
		var rng := RandomNumberGenerator.new()
		rng.seed = 9301
		var h := doc.heights
		for i in h.size():
			h[i] += rng.randf_range(0.0, 0.03)
		doc.heights = h
		doc.splat = Crypto.new().generate_random_bytes(doc.splat.size())
	return LevelIO.pack(doc)


## The package with its doc section scrambled: the same size, its own sha, refused by the gate.
static func _damaged(good: PackedByteArray) -> PackedByteArray:
	var b := good.duplicate()
	var ml := b.decode_u32(6)
	var j := JSON.new()
	j.parse(b.slice(10, 10 + ml).get_string_from_utf8())
	var at := 10 + ml
	for s in (j.data as Dictionary).get("sections", []):
		if str(s.get("id", "")) == "doc":
			for i in range(at + 8, mini(at + 72, at + int(s.size))):
				b[i] = b[i] ^ 0xff
			break
		at += int(s.get("size", 0))
	return b


func _wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		_wipe(dir + "/" + sub)
		DirAccess.remove_absolute(dir + "/" + sub)
	for f in d.get_files():
		DirAccess.remove_absolute(dir + "/" + f)


func _finish() -> void:
	print("pair: %d checks, %d failures" % [checks, failures])
	Net.leave()
	get_tree().quit(1 if failures > 0 else 0)


# ================================================================ client

func _client() -> void:
	_phase = _arg("--phase", "fresh")
	var log_path := _arg("--log", "")
	if log_path != "":
		_log = FileAccess.open(log_path, FileAccess.WRITE)
	Game.settings["nickname"] = _arg("--nick", "Client")
	Game.settings["allow_downloads"] = true
	Net.share.local_changed.connect(_on_local)
	Net.chat_received.connect(_on_chat)
	Net.state_changed.connect(_on_state)
	Net.joined.connect(func() -> void: _line("JOINED"))
	# READY once every client is in (READY stays pressable while downloading): autostart never
	# fires before the last one joined
	var humans := int(_arg("--humans", "1"))
	Net.roster_changed.connect(func() -> void:
		if not _ready_sent and Net.state == "lobby" and Net.players.size() >= humans:
			_ready_sent = true
			_line("READY")
			Net.set_profile(Game.settings["character"], Game.settings["vehicle"], true))
	Net.connect_failed.connect(func(r: String) -> void: _end(1, "connect failed: " + r))
	Net.left.connect(func(r: String) -> void: _end(1, "left: " + r))
	if Net.join("127.0.0.1", port) != OK:
		_end(1, "join: " + Net.last_error)


func _process(delta: float) -> void:
	if mode != "client" or _ending:
		return
	_t += delta
	if _t > CLIENT_TIMEOUT:
		_end(2, "timeout")
	elif _fail_t >= 0.0 and _t - _fail_t > 3.0:
		# a failed download: the client must still be in the lobby, connected
		var stayed: bool = Net.active and Net.state == "lobby"
		_line("STAYED %s" % str(stayed))
		var why := str(Net.share.local_state().why)
		_end(0 if stayed and _phase == "hostile" and why.begins_with("This server's track could not be used") else 1, why)


func _on_local(state: String, dl: float, why: String) -> void:
	if state == "get":
		_progress += 1
	if _states.is_empty() or _states[-1] != state:
		_states.append(state)
		_line("STATE %s %.3f %s" % [state, dl, why])
	if state == "fail" and _fail_t < 0.0:
		_fail_t = _t


func _on_chat(_nick: String, text: String, _kind: String) -> void:
	if not text.begins_with("PING ") or not Net.clock_synced():
		return
	if str(Net.share.local_state().state) != "get":
		return
	var late := (Net.now() - float(text.substr(5))) * 1000.0
	_late_n += 1
	_late_max = maxf(_late_max, late)


func _on_state(s: String) -> void:
	if s == "race":
		_line("START %s" % str(Game.session.get("track_sha", "")))
		_end(0 if _phase != "hostile" else 1, "started")


func _line(s: String) -> void:
	print("[%s] %s" % [_arg("--nick", "client"), s])
	if _log != null:
		_log.store_line(s)
		_log.flush()


func _end(code: int, why: String) -> void:
	if _ending:
		return
	_ending = true
	_line("PROGRESS %d" % _progress)
	_line("LATE %.1f %d" % [_late_max, _late_n])
	_line("RESULT %d %s" % [code, why])
	if _log != null:
		_log.close()
	get_tree().quit(code)
	Net.leave.call_deferred()
