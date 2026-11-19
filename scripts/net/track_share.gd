class_name TrackShare
extends Node
## Custom tracks in a lobby (6.2-6.6): validators, who has the track, the AIMD-windowed chunk pump,
## receiving, retry, consent, the host's status line and rotation. Lives at /root/Net/TrackShare
## on every peer (Net adds it in _ready), so a download survives the lobby's scene changes.
##
## Server: keeps the current package (the saved file's bytes), answers a client's `need` with
## `_s_xfer` + 32 KiB `_s_chunk`s on rpc channel 2 (ENet channel 3), at most `win` chunks in flight
## per peer (AIMD on the ack RTT), with one shared token bucket while a race runs. Client: checks
## whether it has the track (check()), downloads into CustomTracks.cache_part(sha), verifies the
## SHA-256, unpacks (the one gate), compiles on a worker, caches and reports `ok` with its digest.
## Every received value is checked before it reaches a path, the roster or a compile (6.9).

signal progress_changed(peer: int, state: String, dl: float)
signal local_changed(state: String, dl: float, reason: String)   # this client's own download
signal thumb_arrived(tex: Texture2D)                              # the thumb section of a download, decoded

const CHUNK := 32768
const WIN_LOBBY := 4
const WIN_LOBBY_MAX := 8
const WIN_RACE := 2
const RATE_LISTEN := 48
const STALL := 20.0
const RESTARTS := 3
const PREP_TIMEOUT := 60.0
const IDLE_KICK := 120.0          # dedicated servers only

## KB/s for all downloads while a race runs on a dedicated server (sv_download_rate's default).
const RATE_DEDICATED := 192
## Acks that measure a peer's base RTT, and the acks between two window changes.
const BASE_ACKS := 8
## A smoothed RTT this far over the base halves the window (seconds).
const RTT_RISE := 0.150
## _s_dl broadcasts per second at most.
const DL_HZ := 4.0
## A RETRY (a fresh need after a failure) at most once per this many seconds, and this often per sha.
const RETRY_GAP := 30.0
const RETRY_MAX := 5
## A client reason (fail:<reason>) is cut to this many characters.
const REASON_MAX := 80
const MISSING_MAX := 100000
## A client with no chunk for this long gives up the download itself (the server's restarts first).
const CLIENT_STALL := STALL * (RESTARTS + 1) + 10.0
## The first bytes of a download kept in memory for the thumb (magic, header, a <= 1 MiB PNG).
const HEAD_MAX := 10 + 8192 + (1 << 20)
## Server-only settings Net.set_rule hands here instead of broadcasting them (6.8).
const SERVER_KEYS := ["tracks_dir", "downloads", "download_rate", "tracklist", "rotate"]
## Roster track states (6.2).
const STATES := ["?", "need", "get", "prep", "ok", "fail"]
## Readable words for the reason codes clients send (status line, console).
const WORDS := {"stalled": "download stalled", "damaged": "download damaged", "disk": "disk full",
	"invalid": "track not usable", "too big": "track too big", "downloads off": "downloads off",
	"not built": "not built", "newer": "needs a newer game", "preparation timed out": "preparation timed out"}

const TEXT_BROKEN := "The server sent a broken race setup."
const TEXT_MISMATCH := "Your copy of the track does not match the server's."
const TEXT_NOT_BUILT := "This server races %s, which this computer has not built: run the setup again."
const TEXT_NEWER := "This server's track needs a newer version of the game."
const TEXT_INVALID := "This server's track could not be used: %s"
const TEXT_DAMAGED := "The track from the server arrived damaged twice."
const TEXT_DISK := "Not enough disk space for the track."
const TEXT_STALLED := "The download stalled."
const TEXT_TOO_BIG := "The track is larger than 16 MB."
const TEXT_OFF := "Downloads from servers are off."
const TEXT_NO_SEND := "This server does not send its track."
const TEXT_PREP_KICK := "Track preparation timed out."
const TEXT_IDLE_KICK := "Could not get the track: %s."
const TEXT_MISSING := "%d objects of this track are not on this computer (other game content): they were left out."
const TEXT_DIFFERENT := "%s built the track differently: the race may not match."

## Compiles started by downloads (tests: hostile packages never get this far).
static var compiles := 0

## The Net node this works for (its parent; a test gives a fake with the same fields).
var net: Node
## Tests: outgoing RPCs go here as (peer, method, args) instead of the network.
var sink := Callable()

# ---- server settings (6.8; Net.host and Net.set_rule fill them)
## sv_downloads: false = a player without the track is turned away.
var downloads := true
## sv_download_rate: KB/s for all downloads while a race runs (a listen host always uses 48).
var download_rate := RATE_DEDICATED
## mp_tracklist: the rotation (ids, names or file names; resolved when used).
var tracklist := PackedStringArray()
## mp_rotate: the next list entry after every race.
var rotate_on := true
## A track rule given during a race, applied at back_to_lobby (C1 N22).
var pending_track := ""
## Test-only (9.3, read in test runs): a rate cap in KB/s in the lobby too (--rate), and a client
## delay of its acks in seconds (--ack-hold <ms>).
var rate_cap := 0
var ack_hold := 0.0
## Counters for tests and the console: transfers opened, chunks sent, restarts, digest checks.
var stats := {"xfers": 0, "chunks": 0, "bytes": 0, "restarts": 0, "dl_sent": 0, "digest_ok": 0,
	"digest_bad": 0, "dropped": 0, "kicks": 0}

# ---- server state
## The package served now: {id, sha, size, bytes}; {} for a built-in.
var pkg := {}
## peer -> {xid, sha, size, sent, acked, t_ack, restarts, win, srtt, base_rtt, acks, good, since, t_sent}
var pump := {}
var _peer := {}          # peer -> {t_state, t_progress, retries: {sha: n}, t_retry, logged, digest, kicked}
var _xid := 0
var _bucket := 0.0
var _dl_t := 0.0
var _deadline_t := 0.0
var _own_digest := {}    # the server's own build's digest_parts()
var _raw := {}           # tests: {id, sha, bytes} served without the registry (serve_raw)

# ---- client state
var _rx := {}            # {xid, sha, size, got, f, path, head, thumb_done, t}
var _local := {}         # {key, sha, state, dl, why, name, size, t, id}
var _bad := {}           # sha -> damaged downloads this session
var _consent := {}       # server address -> true: DOWNLOAD was answered for it
var _acks: Array = []    # held acks (test): [[due, xid, upto]]
var _hist: Array = []    # the last 3 s of progress: [[t, bytes]] (ETA)
var _work := 0           # bumps on every new local job: a stale worker result is ignored
var _thumb: Texture2D
var _time := 0.0         # this node's clock (tick deltas): stalls, deadlines, RTTs


func _init() -> void:
	_local = _blank_local()


func _ready() -> void:
	if CustomTracks.test_mode():
		var args := OS.get_cmdline_user_args()
		var i := args.find("--rate")
		if i >= 0 and i + 1 < args.size():
			rate_cap = maxi(0, int(args[i + 1]))
		i = args.find("--ack-hold")
		if i >= 0 and i + 1 < args.size():
			ack_hold = maxf(0.0, float(args[i + 1]) / 1000.0)


# ================================================================ validators (every peer, 6.2)

## A received cfg's track part: `track` a built-in id or a custom id (never c_edit), and a `custom`
## block (when there is one) with a sha matching the id, a size in 1..MAX_FILE and string labels.
static func valid_cfg(cfg: Dictionary) -> bool:
	var t = cfg.get("track")
	if not (t is String) or not known_id(t):
		return false
	if cfg.has("custom"):
		return CustomTracks.is_custom(t) and valid_custom(cfg.get("custom"), t)
	return true


## A received race rules dict: the track as in valid_cfg, `track_sha` 64 hex matching a custom id
## ("" for a built-in), numbers where numbers belong.
static func valid_rules(rules: Dictionary) -> bool:
	var t = rules.get("track")
	if not (t is String) or not known_id(t):
		return false
	var s = rules.get("track_sha", "")
	if not (s is String):
		return false
	if CustomTracks.is_custom(t):
		if not LevelIO.is_sha(s) or "c_" + str(s).left(16) != t:
			return false
	elif s != "":
		return false
	for k in ["laps", "difficulty", "hazards", "epoch"]:
		if rules.has(k) and not _num(rules[k]):
			return false
	return true


## A built-in circuit's id or a well-formed custom id (c_edit never travels).
static func known_id(t: String) -> bool:
	if CustomTracks.valid_id(t):
		return true
	for tr in Game.TRACKS:
		if tr["id"] == t:
			return true
	return false


## The custom block of a cfg for track `id`: {sha, size, name, author} with the right shapes.
static func valid_custom(c: Variant, id: String) -> bool:
	if not (c is Dictionary):
		return false
	var sha = c.get("sha")
	if not (sha is String) or not LevelIO.is_sha(sha) or "c_" + str(sha).left(16) != id:
		return false
	var size = c.get("size")
	if not _num(size) or float(size) != floorf(float(size)) or float(size) < 1.0 or float(size) > LevelIO.MAX_FILE:
		return false
	for k in ["name", "author"]:
		if c.has(k) and not (c[k] is String):
			return false
	return true


## What a client stores of a received cfg: {} when it must be refused (a bad track id); else a copy
## whose custom block is clean (labels cut and stripped) or gone when it was not valid (the client
## then waits in "?" for the next cfg).
static func clean_cfg(cfg: Dictionary) -> Dictionary:
	var t = cfg.get("track")
	if not (t is String) or not known_id(t):
		return {}
	var out := cfg.duplicate(true)
	out.erase("custom")
	if CustomTracks.is_custom(t) and valid_custom(cfg.get("custom"), t):
		var c: Dictionary = cfg["custom"]
		out["custom"] = {"sha": str(c["sha"]), "size": int(c["size"]), "name": clean_text(str(c.get("name", "")), 48),
			"author": clean_text(str(c.get("author", "")), 24)}
	if out.get("name") is String:
		out["name"] = clean_text(out["name"], 48)
	return out


## Control characters and [ ] { } stripped, edges trimmed, cut to n characters (2.10).
static func clean_text(s: String, n: int) -> String:
	var o := ""
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 32 or c == 127 or c == 91 or c == 93 or c == 123 or c == 125:
			continue
		o += String.chr(c)
	return o.strip_edges().left(n)


# ================================================================ server: the track rule

## Called by Net.set_rule("track") before its broadcast (and by Net.host before its first cfg):
## fills or erases cfg.custom, loads the package, resets every client's state to "?" (their
## transfers stop: the next need opens a new xid) and starts the server's own prepare.
func on_track_rule(id: String) -> void:
	if not _is_server():
		return
	pending_track = ""
	pump.clear()
	_own_digest = {}
	pkg = {}
	var cfg: Dictionary = net.cfg
	cfg.erase("custom")
	for pid in net.players:
		if pid == 1 and not net.dedicated:
			continue
		_set_peer(pid, "?", "", 0.0, false)
		var info := _info_of(pid)
		info["digest"] = ""
		info["kicked"] = false
	var host_state := "ok"
	if CustomTracks.is_custom(id):
		host_state = "prep"
		var raw := not _raw.is_empty() and str(_raw.get("id", "")) == id
		var b: PackedByteArray = _raw["bytes"] if raw else CustomTracks.bytes(id)
		var sha := LevelIO.sha256(b) if not b.is_empty() else ""
		var m := CustomTracks.meta(id)
		if b.is_empty() or sha == "" or LevelIO.id_for(sha) != id:
			push_warning("TrackShare: the file of %s cannot be served" % id)
			_server_prepared.call_deferred(false, "The track file of this server changed or is missing.", id)
		else:
			pkg = {"id": id, "sha": sha, "size": b.size(), "bytes": b}
			cfg["custom"] = {"sha": sha, "size": b.size(),
				"name": clean_text(str(_raw.get("name", "")) if raw else str(m.get("name", "")), 48),
				"author": clean_text(str(m.get("author", "")), 24)}
			if not raw:
				CustomTracks.set_current(id)
				CustomTracks.prepare(id, _server_prepared.bind(id))
	else:
		CustomTracks.set_current("")
		if not Game.track_installed(id):
			host_state = "fail"
	if net.players.has(1) and not net.dedicated:
		_set_peer(1, host_state, "not built" if host_state == "fail" else "", 1.0 if host_state == "ok" else 0.0, false)
	net.broadcast_roster()


## Tests (9.3 --serve-hostile, the unit cases): serve these bytes as a custom track without the
## registry or the server's own prepare. Returns the id to pass to Net.set_rule("track", id).
func serve_raw(bytes: PackedByteArray, label := "TEST TRACK") -> String:
	var sha := LevelIO.sha256(bytes)
	var id := LevelIO.id_for(sha)
	_raw = {"id": id, "sha": sha, "bytes": bytes, "name": label}
	return id


## The server's own build is ready (or not): the host's row turns "ok", early client digests are
## compared; a failure goes to Net.track_failed (info, unusable, another track).
func _server_prepared(ok: bool, why: String, id: String) -> void:
	if not _is_server() or str(net.cfg.get("track", "")) != id:
		return
	if not ok:
		net.track_failed(why if why != "" else "The track could not be built.")
		return
	var b := CustomTracks.build_for(id)
	_own_digest = b.digest_parts() if b != null else {}
	if net.players.has(1) and not net.dedicated:
		_set_peer(1, "ok", "", 1.0, true)
	for pid in _peer:
		var d := str(_peer[pid].get("digest", ""))
		if d != "":
			_compare_digest(pid, d)


## The server's own track is ready to race: a built-in it has built, a custom track compiled here.
func server_ready() -> bool:
	var id := str(net.cfg.get("track", ""))
	if CustomTracks.is_custom(id):
		return CustomTracks.is_prepared(id)
	return Game.track_installed(id)


## A server-only setting (SERVER_KEYS) from Net.host / Net.set_rule.
func set_option(key: String, value: Variant) -> void:
	match key:
		"tracks_dir":
			if str(value) != "":
				CustomTracks.add_folder(str(value))
				CustomTracks.refresh()
		"downloads":
			downloads = _flag(value)
		"download_rate":
			download_rate = clampi(int(value), 1, 100000)
		"tracklist":
			if value is Array or value is PackedStringArray:
				tracklist = PackedStringArray(value)
			else:
				tracklist = PackedStringArray()
				for s in str(value).split(",", false):
					if s.strip_edges() != "":
						tracklist.append(s.strip_edges())
		"rotate":
			rotate_on = _flag(value)


## Net.host: the server settings among its options.
func configure(options: Dictionary) -> void:
	for k in SERVER_KEYS:
		if options.has(k):
			set_option(k, options[k])


# ================================================================ server: messages from clients

@rpc("any_peer", "call_remote", "reliable", 0)
func _c_track(sha: String, state: String, have: int, digest: String, missing: int) -> void:
	_recv_track(multiplayer.get_remote_sender_id(), sha, state, have, digest, missing)


@rpc("any_peer", "call_remote", "reliable", 2)
func _c_ack(xid: int, upto: int) -> void:
	_recv_ack(multiplayer.get_remote_sender_id(), xid, upto)


## A client's report (6.3): every argument checked; anything else is dropped (logged once a peer).
func _recv_track(pid: int, sha: String, state: String, have: int, digest: String, missing: int) -> void:
	if not _is_server() or not net.players.has(pid):
		return
	var c = net.cfg.get("custom")
	var cur := str(c.get("sha", "")) if c is Dictionary else ""
	var size := int(c.get("size", 0)) if c is Dictionary else 0
	if sha != cur:
		_drop(pid, "a report for another track")
		return
	var code := state
	var reason := ""
	if state.begins_with("fail:"):
		code = "fail"
		reason = clean_text(state.substr(5), REASON_MAX)
		if reason == "":
			reason = "failed"
	elif not state in ["ok", "need", "prep"]:
		_drop(pid, "a bad state")
		return
	if have < 0 or have > size or (have % CHUNK != 0 and have != size):
		_drop(pid, "a bad resume offset")
		return
	if digest != "" and not (digest.length() == 72 and _hex(digest)):
		_drop(pid, "a bad digest")
		return
	if missing < 0 or missing > MISSING_MAX:
		_drop(pid, "a bad missing count")
		return
	var info := _info_of(pid)
	match code:
		"ok":
			pump.erase(pid)
			net.players[pid]["missing"] = missing
			_set_peer(pid, "ok", "", 1.0, true)
			_compare_digest(pid, digest)
		"prep":
			pump.erase(pid)
			_set_peer(pid, "prep", "", 1.0, true)
		"fail":
			pump.erase(pid)
			_set_peer(pid, "fail", reason, float(net.players[pid].get("dl", 0.0)), true)
		"need":
			if cur == "" or pkg.is_empty() or str(pkg.get("sha", "")) != cur:
				_drop(pid, "a need without a package")
				return
			if not downloads:
				_kick(pid, TEXT_NO_SEND)
				return
			var restarts := 0
			if str(net.players[pid].get("track", "?")) == "fail":
				# RETRY: once per 30 s, 5 times per sha
				var n := int((info["retries"] as Dictionary).get(cur, 0))
				if _time - float(info["t_retry"]) < RETRY_GAP or n >= RETRY_MAX:
					_drop(pid, "a retry too soon")
					return
				info["t_retry"] = _time
				info["retries"][cur] = n + 1
			elif pump.has(pid):
				# a fresh need during a transfer (a bad chunk): counts as a restart
				restarts = int(pump[pid]["restarts"]) + 1
				if restarts > RESTARTS:
					pump.erase(pid)
					_set_peer(pid, "fail", "stalled", float(net.players[pid].get("dl", 0.0)), true)
					return
			_start_xfer(pid, have, restarts)


func _start_xfer(pid: int, from: int, restarts: int) -> void:
	_xid += 1
	var racing := _racing()
	var st := {"xid": _xid, "sha": str(pkg["sha"]), "size": int(pkg["size"]), "sent": from, "acked": from,
		"t_ack": _time, "restarts": restarts, "win": WIN_RACE if racing else WIN_LOBBY, "srtt": -1.0,
		"base_rtt": INF, "acks": 0, "good": 0, "since": BASE_ACKS, "t_sent": {}}
	var ping := int(net.players[pid].get("ping", 0))
	if racing and ping > 0:
		# joined mid-race: its ping is the base (no lobby acks to measure)
		st["base_rtt"] = ping / 1000.0
		st["acks"] = BASE_ACKS
	pump[pid] = st
	stats["xfers"] += 1
	_info_of(pid)["t_progress"] = _time
	_send(pid, &"_s_xfer", [st["xid"], st["sha"], st["size"], from])
	_set_peer(pid, "get", "", float(from) / maxf(1.0, float(st["size"])), true)


## An ack: the current xid, monotone, within what was sent, on a chunk boundary (or the size).
func _recv_ack(pid: int, xid: int, upto: int) -> void:
	if not _is_server() or not net.players.has(pid):
		return
	var st = pump.get(pid)
	if not (st is Dictionary):
		return  # the transfer ended (prep / ok came first on channel 0) or was stopped
	if xid != int(st["xid"]):
		_drop(pid, "an ack of another transfer")
		return
	if upto < int(st["acked"]) or upto > int(st["sent"]) or (upto % CHUNK != 0 and upto != int(st["size"])):
		_drop(pid, "an ack out of range")
		return
	if upto == int(st["acked"]):
		return
	var newest := -1
	var t_sent: Dictionary = st["t_sent"]
	for off in t_sent.keys():
		if int(off) < upto:
			newest = maxi(newest, int(off))
	var rtt := _time - float(t_sent[newest]) if newest >= 0 else -1.0
	for off in t_sent.keys():
		if int(off) < upto:
			t_sent.erase(off)
	st["acked"] = upto
	st["t_ack"] = _time
	_info_of(pid)["t_progress"] = _time
	net.players[pid]["dl"] = float(upto) / maxf(1.0, float(st["size"]))
	if rtt >= 0.0:
		_aimd(st, rtt)


## AIMD on the ack RTT (C1 S11): the lowest RTT of the first 8 acks is the base; a smoothed RTT
## more than 150 ms over it halves the window (at least 1; then 8 acks before the next halving);
## every 8 acks without that, one more chunk up to 8 in the lobby, 2 while a race runs.
func _aimd(st: Dictionary, rtt: float) -> void:
	st["acks"] = int(st["acks"]) + 1
	st["srtt"] = rtt if float(st["srtt"]) < 0.0 else lerpf(float(st["srtt"]), rtt, 0.25)
	if int(st["acks"]) <= BASE_ACKS:
		st["base_rtt"] = minf(float(st["base_rtt"]), rtt)
		return
	st["since"] = int(st["since"]) + 1
	if float(st["srtt"]) > float(st["base_rtt"]) + RTT_RISE:
		st["good"] = 0
		if int(st["since"]) >= BASE_ACKS:
			st["win"] = maxi(1, int(st["win"]) / 2)
			st["since"] = 0
	else:
		st["good"] = int(st["good"]) + 1
		if int(st["good"]) >= BASE_ACKS:
			st["good"] = 0
			st["win"] = mini(int(st["win"]) + 1, WIN_RACE if _racing() else WIN_LOBBY_MAX)


# ================================================================ the pump, deadlines (tick)

## Net._process on every peer: the server's pump, stalls, deadlines and progress broadcasts; a
## client's held acks and its own stall watchdog.
func tick(delta: float) -> void:
	_time += delta
	if _is_server():
		_tick_server(delta)
	elif _is_client():
		_tick_client()


func _tick_server(delta: float) -> void:
	var racing := _racing()
	var rate := 0
	if racing:
		rate = download_rate if net.dedicated else RATE_LISTEN
	if rate_cap > 0:
		rate = mini(rate, rate_cap) if rate > 0 else rate_cap
	if rate > 0:
		_bucket = minf(_bucket + rate * 1024.0 * delta, maxf(float(CHUNK), rate * 1024.0 * 0.25))
	var bytes: PackedByteArray = pkg.get("bytes", PackedByteArray())
	for pid in pump.keys():
		if not net.players.has(pid):
			pump.erase(pid)
			continue
		var st: Dictionary = pump[pid]
		var win := mini(int(st["win"]), WIN_RACE if racing else WIN_LOBBY_MAX)
		while int(st["sent"]) < int(st["size"]) and int(st["sent"]) - int(st["acked"]) < win * CHUNK:
			var off := int(st["sent"])
			var n := mini(CHUNK, int(st["size"]) - off)
			if rate > 0:
				if _bucket < n:
					break
				_bucket -= n
			_send(pid, &"_s_chunk", [st["xid"], off, bytes.slice(off, off + n)])
			(st["t_sent"] as Dictionary)[off] = _time
			st["sent"] = off + n
			stats["chunks"] += 1
			stats["bytes"] += n
		if int(st["acked"]) < int(st["size"]) and _time - float(st["t_ack"]) > STALL:
			_restart(pid, st)
	_dl_t -= delta
	if _dl_t <= 0.0 and not pump.is_empty():
		_dl_t = 1.0 / DL_HZ
		var prog := {}
		for pid in pump:
			var dl := float(pump[pid]["acked"]) / maxf(1.0, float(pump[pid]["size"]))
			prog[pid] = dl
			progress_changed.emit(pid, "get", dl)
		for c in net._clients():
			_send(c, &"_s_dl", [prog])
		stats["dl_sent"] += 1
	_deadline_t -= delta
	if _deadline_t <= 0.0:
		_deadline_t = 1.0
		_deadlines()


## A stall: one restart from the last ack (same xid); past RESTARTS the peer is fail:stalled and
## nothing more is sent until its RETRY.
func _restart(pid: int, st: Dictionary) -> void:
	st["restarts"] = int(st["restarts"]) + 1
	stats["restarts"] += 1
	if int(st["restarts"]) > RESTARTS:
		pump.erase(pid)
		_set_peer(pid, "fail", "stalled", float(st["acked"]) / maxf(1.0, float(st["size"])), true)
		return
	st["sent"] = st["acked"]
	(st["t_sent"] as Dictionary).clear()
	st["t_ack"] = _time
	_send(pid, &"_s_xfer", [st["xid"], st["sha"], st["size"], st["acked"]])


## prep over 60 s: kicked on a dedicated server, marked failed on a listen host (it never
## auto-kicks: its status line names the player and offers KICK); on a dedicated server a player
## who stays without the track and without progress for 120 s is kicked.
func _deadlines() -> void:
	for pid in net.players.keys():
		if pid == 1 and not net.dedicated:
			continue
		var p: Dictionary = net.players[pid]
		var st := str(p.get("track", "?"))
		var info := _info_of(pid)
		if bool(info["kicked"]):
			continue
		if st == "prep" and _time - float(info["t_state"]) > PREP_TIMEOUT:
			if net.dedicated:
				_kick(pid, TEXT_PREP_KICK)
			else:
				_set_peer(pid, "fail", "preparation timed out", 1.0, true)
		elif net.dedicated and st in ["?", "need", "get", "fail"] and _time - float(info["t_progress"]) > IDLE_KICK:
			var why := str(p.get("why", ""))
			_kick(pid, TEXT_IDLE_KICK % words(why if why != "" else ("no answer" if st == "?" else "no progress")))


func _tick_client() -> void:
	while not _acks.is_empty() and float(_acks[0][0]) <= _time:
		var a: Array = _acks.pop_front()
		_send(1, &"_c_ack", [a[1], a[2]])
	if str(_local["state"]) in ["need", "get"] and _time - float(_local["t"]) > CLIENT_STALL:
		_close_rx()
		_fail_local("stalled", TEXT_STALLED)


# ================================================================ client: do I have it?

## The client's check (on _s_welcome, _s_cfg): built-in -> ok or leave; a custom track it holds ->
## prep -> ok; else the consent box state, too big, or need (resuming a .part); a custom id
## without a valid custom block waits in "?". Nothing is redone while the same track is in hand.
func check() -> void:
	_check(false)


func _check(force: bool) -> void:
	if not _is_client():
		return
	var id := str(net.cfg.get("track", ""))
	var c := _custom()
	var key := ("c:" + str(c["sha"])) if not c.is_empty() else ("b:" + id if not CustomTracks.is_custom(id) else "?:" + id)
	var mine = net.players.get(net.my_id(), {})
	var server_view := str(mine.get("track", "?")) if mine is Dictionary else "?"
	if not force and key == str(_local["key"]) and server_view != "?" and str(_local["state"]) != "?":
		return
	# a transfer in hand stops (its .part stays: the need below resumes it)
	_close_rx()
	_work += 1
	_acks.clear()
	_local = _blank_local()
	_local["key"] = key
	if not CustomTracks.is_custom(id):
		if Game.track_installed(id):
			_set_local("ok", 1.0, "")
			_report("", "ok", 0, "", 0)
		else:
			_set_local("fail", 0.0, "not built")
			_report("", "fail:not built", 0, "", 0)
			net.leave_with(TEXT_NOT_BUILT % str(Game.track(id).get("name", id)))
		return
	if c.is_empty():
		_set_local("?", 0.0, "")
		return
	var sha := str(c["sha"])
	var size := int(c["size"])
	_local["sha"] = sha
	_local["id"] = id
	_local["name"] = str(c.get("name", ""))
	_local["size"] = size
	if CustomTracks.has(id) and str(CustomTracks.meta(id).get("sha", "")) == sha:
		var bad := CustomTracks.unusable(id)
		if bad != "":
			_fail_local("invalid", TEXT_INVALID % bad)
			return
		_prepare_have(id, sha)
		return
	if size > LevelIO.MAX_FILE:
		_fail_local("too big", TEXT_TOO_BIG)
		return
	if not _downloads_allowed():
		_fail_local("downloads off", TEXT_OFF)
		return
	_need(sha, size)


## Client: a fresh need after a failure (RETRY).
func retry() -> void:
	if not _is_client() or str(_local["state"]) != "fail":
		return
	_bad.erase(str(_local["sha"]))
	_check(true)


## Client: DOWNLOAD for this server, this session.
func consent() -> void:
	if not _is_client():
		return
	_consent[str(net.get("server_addr"))] = true
	_check(true)


func _downloads_allowed() -> bool:
	if bool(Game.settings.get("allow_downloads", true)):
		return true
	return _consent.has(str(net.get("server_addr")))


## The track is in the registry: compile it (worker) unless in memory, then ok.
func _prepare_have(id: String, sha: String) -> void:
	_set_local("prep", 1.0, "")
	_report(sha, "prep", 0, "", 0)
	if CustomTracks.is_prepared(id):
		_local_ready(id, sha)
		return
	var w := _work
	CustomTracks.prepare(id, func(ok: bool, why: String) -> void:
		if w != _work or not _is_client():
			return
		if ok:
			_local_ready(id, sha)
		else:
			_fail_local("invalid", TEXT_INVALID % why))


## The build is in memory: the current track, its digest and missing count to the server.
func _local_ready(id: String, sha: String) -> void:
	CustomTracks.set_current(id)
	CustomTracks.cache_touch(sha)
	var b := CustomTracks.build_for(id)
	var digest := b.digest() if b != null else ""
	var missing := clampi(b.report.missing_total(), 0, MISSING_MAX) if b != null and b.report != null else 0
	_set_local("ok", 1.0, "")
	_report(sha, "ok", 0, digest, missing)
	if missing > 0:
		net.local_info(TEXT_MISSING % missing)


## Ask for the package, resuming from the .part (rounded down to whole chunks).
func _need(sha: String, size: int) -> void:
	var part := CustomTracks.cache_part(sha)
	var have := 0
	if part != "" and FileAccess.file_exists(part):
		have = mini(_fsize(part), size)
		have -= have % CHUNK
	_set_local("need", float(have) / maxf(1.0, float(size)), "")
	_report(sha, "need", have, "", 0)


# ================================================================ client: receiving

@rpc("authority", "call_remote", "reliable", 2)
func _s_xfer(xid: int, sha: String, size: int, from: int) -> void:
	_recv_xfer(multiplayer.get_remote_sender_id(), xid, sha, size, from)


@rpc("authority", "call_remote", "reliable", 2)
func _s_chunk(xid: int, off: int, data: PackedByteArray) -> void:
	_recv_chunk(multiplayer.get_remote_sender_id(), xid, off, data)


@rpc("authority", "call_remote", "unreliable", 0)
func _s_dl(progress: Dictionary) -> void:
	_recv_dl(multiplayer.get_remote_sender_id(), progress)


## A transfer opens (or restarts): only for the sha and size of the current cfg, while we asked.
func _recv_xfer(sender: int, xid: int, sha: String, size: int, from: int) -> void:
	if sender != 1 or not _is_client():
		return
	var c := _custom()
	if c.is_empty() or sha != str(c["sha"]) or size != int(c["size"]) or size < 1 or size > LevelIO.MAX_FILE:
		return
	if not str(_local["state"]) in ["need", "get"] or str(_local["sha"]) != sha:
		return
	if from < 0 or from > size or (from % CHUNK != 0 and from != size):
		_bad_chunk(sha, size)
		return
	var part := CustomTracks.cache_part(sha)
	if part == "":
		_fail_local("disk", TEXT_DISK)
		return
	_close_rx()
	var have := _fsize(part) if FileAccess.file_exists(part) else 0
	if from > have:
		_bad_chunk(sha, size)
		return
	var head := PackedByteArray()
	if from > 0:
		var r := FileAccess.open(part, FileAccess.READ)
		if r != null:
			head = r.get_buffer(mini(from, HEAD_MAX))
			r.close()
	var f := _open_at(part, from)
	if f == null:
		_fail_local("disk", TEXT_DISK)
		return
	_rx = {"xid": xid, "sha": sha, "size": size, "got": from, "f": f, "path": part, "head": head,
		"thumb_done": false}
	_hist = [[_time, from]]
	_set_local("get", float(from) / float(size), "")
	if from == size:
		_rx_done()
	else:
		_check_thumb()


## A chunk: the size checked before anything else, then the xid (stale ones are dropped), the
## exact offset and the total; appended to the .part and acked.
func _recv_chunk(sender: int, xid: int, off: int, data: PackedByteArray) -> void:
	if sender != 1 or not _is_client():
		return
	if data.size() > CHUNK:
		if not _rx.is_empty() and xid == int(_rx["xid"]):
			_bad_chunk(str(_rx["sha"]), int(_rx["size"]))
		return
	if _rx.is_empty() or xid != int(_rx["xid"]):
		return
	var got := int(_rx["got"])
	var size := int(_rx["size"])
	if off != got or data.is_empty() or got + data.size() > size or size > LevelIO.MAX_FILE:
		_bad_chunk(str(_rx["sha"]), size)
		return
	var f: FileAccess = _rx["f"]
	if not f.store_buffer(data) or f.get_error() != OK:
		_close_rx()
		_fail_local("disk", TEXT_DISK)
		return
	got += data.size()
	_rx["got"] = got
	var head: PackedByteArray = _rx["head"]
	if head.size() < HEAD_MAX:
		head.append_array(data.slice(0, HEAD_MAX - head.size()))
		_rx["head"] = head
	_ack(xid, got)
	_hist.append([_time, got])
	while _hist.size() > 2 and _time - float(_hist[0][0]) > 3.0:
		_hist.pop_front()
	_set_local("get", float(got) / float(size), "")
	_check_thumb()
	if got == size:
		_rx_done()


func _recv_dl(sender: int, progress: Dictionary) -> void:
	if sender != 1 or not _is_client() or progress.size() > 64:
		return
	for k in progress:
		var v = progress[k]
		if not (k is int) or not _num(v) or not net.players.has(k):
			continue
		var dl := clampf(float(v), 0.0, 1.0)
		net.players[k]["dl"] = dl
		progress_changed.emit(k, str(net.players[k].get("track", "?")), dl)


func _ack(xid: int, upto: int) -> void:
	if ack_hold > 0.0:
		_acks.append([_time + ack_hold, xid, upto])
	else:
		_send(1, &"_c_ack", [xid, upto])


## A bad chunk (or a hash mismatch): the .part is dropped and one fresh need goes out; the second
## time the client stays in the lobby as fail:damaged with RETRY.
func _bad_chunk(sha: String, size: int) -> void:
	_close_rx()
	var part := CustomTracks.cache_part(sha)
	if part != "" and FileAccess.file_exists(part):
		DirAccess.remove_absolute(part)
	_bad[sha] = int(_bad.get(sha, 0)) + 1
	if int(_bad[sha]) >= 2:
		_fail_local("damaged", TEXT_DAMAGED)
	else:
		_need(sha, size)


## The whole package is here: prep; SHA-256, the unpack gate and the compile on a worker.
func _rx_done() -> void:
	var sha := str(_rx["sha"])
	var size := int(_rx["size"])
	var part := str(_rx["path"])
	_close_rx()
	_set_local("prep", 1.0, "")
	_report(sha, "prep", 0, "", 0)
	_work += 1
	var w := _work
	var regs := LevelCompiler.registries()
	var holder := [-1]
	var job := func() -> void:
		var r := TrackShare._verify(part, sha, regs)
		_verified.call_deferred(w, sha, size, part, r, holder)
	holder[0] = WorkerThreadPool.add_task(job, false, "TrackShare.verify")


## Worker side: the part's hash, the gate (LevelIO.unpack), then the compile.
static func _verify(part: String, sha: String, regs: Dictionary) -> Dictionary:
	var b := FileAccess.get_file_as_bytes(part)
	if b.is_empty() or b.size() > LevelIO.MAX_FILE or LevelIO.sha256(b) != sha:
		return {"ok": false, "bad": true}
	var rep := LevelReport.new()
	var doc := LevelIO.unpack(b, rep)
	if doc == null:
		return {"ok": false, "newer": rep.has("newer_format") or rep.has("bad_container"), "why": rep.fatal()}
	compiles += 1
	var build := LevelCompiler.compile(doc, {"id": LevelIO.id_for(sha), "registries": regs})
	if build == null:
		return {"ok": false, "why": "The track could not be built."}
	if not (build.data.get("path") is Dictionary):
		var why := build.report.blocks_drive() if build.report != null else ""
		return {"ok": false, "why": why if why != "" else "The track has no road to race on."}
	return {"ok": true, "build": build, "doc_meta": {"name": str(doc.data.get("name", "")),
		"short": str(doc.data.get("short", "")), "desc": str(doc.data.get("desc", "")),
		"author": str(doc.data.get("author", "")), "guid": str(doc.data.get("guid", "")),
		"rescue": str((doc.data.get("race", {}) as Dictionary).get("rescue", "scanner"))}}


## Main thread: cache_add -> put_memory -> ok; a mismatch is a bad chunk; an invalid package stays
## in the lobby as fail:invalid; only a newer format leaves.
func _verified(w: int, sha: String, size: int, part: String, r: Dictionary, holder: Array) -> void:
	if int(holder[0]) >= 0:
		WorkerThreadPool.wait_for_task_completion(int(holder[0]))
	if w != _work or not _is_client():
		return
	if bool(r.get("bad", false)):
		_bad_chunk(sha, size)
		return
	if not bool(r.get("ok", false)):
		if FileAccess.file_exists(part):
			DirAccess.remove_absolute(part)
		if bool(r.get("newer", false)):
			_set_local("fail", 1.0, TEXT_NEWER)
			_report(sha, "fail:newer", 0, "", 0)
			net.leave_with(TEXT_NEWER)
			return
		_fail_local("invalid", TEXT_INVALID % str(r.get("why", "")))
		return
	var build: LevelBuild = r["build"]
	var facts := CustomTracks.facts_of(build)
	var id := CustomTracks.cache_add(sha, part, facts)
	if id == "":
		_fail_local("invalid", TEXT_INVALID % CustomTracks.last_error)
		return
	var m: Dictionary = (r.get("doc_meta", {}) as Dictionary).duplicate()
	for k in build.meta:
		m[k] = build.meta[k]
	for k in facts:
		m[k] = facts[k]
	CustomTracks.put_memory(id, build, m)
	_local_ready(id, sha)


## As soon as the thumb section is complete (it is first, 2.1): checked, decoded on a worker.
func _check_thumb() -> void:
	if _rx.is_empty() or bool(_rx["thumb_done"]):
		return
	var h: PackedByteArray = _rx["head"]
	if h.size() < 10:
		return
	if h.slice(0, 5).get_string_from_ascii() != LevelIO.MAGIC:
		_rx["thumb_done"] = true
		return
	var ml := h.decode_u32(6)
	if ml > LevelIO.MAX_META:
		_rx["thumb_done"] = true
		return
	if h.size() < 10 + ml:
		return
	var j := JSON.new()
	if j.parse(h.slice(10, 10 + ml).get_string_from_utf8()) != OK or not (j.data is Dictionary):
		_rx["thumb_done"] = true
		return
	var secs = LevelIO.sanitize_meta(j.data).get("sections")
	if not (secs is Array) or secs.is_empty() or not (secs[0] is Dictionary) or str(secs[0].get("id", "")) != "thumb":
		_rx["thumb_done"] = true
		return
	var sz := int(secs[0].get("size", 0))
	if sz <= 0 or sz > LevelIO.MAX_THUMB:
		_rx["thumb_done"] = true
		return
	if h.size() < 10 + ml + sz:
		return
	_rx["thumb_done"] = true
	var png := h.slice(10 + ml, 10 + ml + sz)
	if not LevelIO.png_ok(png):
		return
	var w := _work
	var holder := [-1]
	var job := func() -> void:
		var img := LevelIO.decode_thumb(png)
		_thumb_decoded.call_deferred(w, img, holder)
	holder[0] = WorkerThreadPool.add_task(job, false, "TrackShare.thumb")


func _thumb_decoded(w: int, img: Image, holder: Array) -> void:
	if int(holder[0]) >= 0:
		WorkerThreadPool.wait_for_task_completion(int(holder[0]))
	if w != _work or img == null or img.is_empty():
		return
	_thumb = ImageTexture.create_from_image(img)
	thumb_arrived.emit(_thumb)


## The part opened for writing at `at` (truncated there; a fresh file at 0).
static func _open_at(path: String, at: int) -> FileAccess:
	if at == 0:
		return FileAccess.open(path, FileAccess.WRITE)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var keep := f.get_buffer(at)
	f.close()
	if keep.size() != at:
		return null
	f = FileAccess.open(path, FileAccess.WRITE)
	if f == null or not f.store_buffer(keep):
		return null
	f.seek(at)
	return f


func _close_rx() -> void:
	if not _rx.is_empty() and _rx.get("f") is FileAccess:
		(_rx["f"] as FileAccess).close()
	_rx = {}


# ================================================================ leaving, resetting

## A player left (Net._handle_disconnect).
func drop(peer: int) -> void:
	pump.erase(peer)
	_peer.erase(peer)


## Net._shutdown: every transfer stops; a .part stays for a later resume.
func reset() -> void:
	pump.clear()
	_peer.clear()
	pkg = {}
	_raw = {}
	_own_digest = {}
	pending_track = ""
	_bucket = 0.0
	_close_rx()
	_acks.clear()
	_hist.clear()
	_bad.clear()
	_work += 1
	_thumb = null
	_local = _blank_local()


# ================================================================ rotation (6.8)

## After a race (Net.back_to_lobby): a track rule given during the race, else the next list entry.
func after_race() -> void:
	if not _is_server():
		return
	if pending_track != "":
		var t := pending_track
		pending_track = ""
		net.set_rule("track", t)
		return
	rotate()


## The next usable entry of the track list (mp_rotate, a list of 2+ entries), set with
## Net.set_rule("track"). True when the track changed.
func rotate() -> bool:
	if not _is_server() or not rotate_on:
		return false
	return _rotate_next(2)


## After a build failure (3.10): the next usable entry even with mp_rotate 0 (a list of 1+).
func rotate_after_failure() -> bool:
	if not _is_server():
		return false
	return _rotate_next(1)


## The entry rotate() would pick next ("" when none): a dedicated server's prefetch (6.6).
func next_track() -> String:
	var ids := rotation()
	var cur := str(net.cfg.get("track", "")) if net != null else ""
	var i := ids.find(cur)
	for k in range(1, ids.size() + 1):
		var cand: String = ids[(i + k) % ids.size()]
		if cand != cur and _usable(cand):
			return cand
	return ""


## The track list resolved to ids (built-in ids / names, custom file names / names / c_ ids).
func rotation() -> PackedStringArray:
	var out := PackedStringArray()
	for e in tracklist:
		var id := resolve(e)
		if id != "":
			out.append(id)
	return out


## A track list entry -> its id ("" when it names nothing here).
static func resolve(entry: String) -> String:
	var q := entry.strip_edges()
	if q == "":
		return ""
	for tr in Game.TRACKS:
		if tr["id"] == q or str(tr["name"]).to_lower() == q.to_lower() or str(tr.get("short", "")).to_lower() == q.to_lower():
			return tr["id"]
	return CustomTracks.find(q)


func _rotate_next(min_entries: int) -> bool:
	if rotation().size() < min_entries:
		return false
	var cand := next_track()
	if cand == "":
		return false
	net.set_rule("track", cand)
	return true


func _usable(id: String) -> bool:
	if CustomTracks.is_custom(id):
		return CustomTracks.has(id) and CustomTracks.unusable(id) == ""
	return Game.track_installed(id)


# ================================================================ who has it

func state_of(peer: int) -> String:
	var p = net.players.get(peer) if net != null else null
	return str(p.get("track", "?")) if p is Dictionary else ""


## Every player has the track ("ok"), and a dedicated server has compiled its custom track.
func everyone_has_track() -> bool:
	if net == null or not net.active:
		return true
	for pid in net.players:
		if str(net.players[pid].get("track", "?")) != "ok":
			return false
	if net.is_server and net.dedicated:
		var id := str(net.cfg.get("track", ""))
		if CustomTracks.is_custom(id) and not CustomTracks.is_prepared(id):
			return false
	return true


## [{id, nick, state, dl, why}]
func waiting() -> Array:
	var out := []
	if net == null:
		return out
	var ids: Array = net.players.keys()
	ids.sort()
	for pid in ids:
		var p: Dictionary = net.players[pid]
		var st := str(p.get("track", "?"))
		if st != "ok":
			out.append({"id": pid, "nick": str(p.get("nick", "")), "state": st, "dl": float(p.get("dl", 0.0)),
				"why": str(p.get("why", ""))})
	return out


## "" or the host's blocker line (6.5).
func status_line() -> String:
	if net == null or not net.active:
		return ""
	if net.is_server and not server_ready():
		var id := str(net.cfg.get("track", ""))
		if not CustomTracks.is_custom(id):
			return "This server has not built %s." % str(Game.track(id).get("name", id))
		return "Preparing the track..."
	if everyone_has_track():
		return ""
	var w := waiting()
	for e in w:
		if e["state"] == "fail":
			return "%s has no track (%s): wait, change the track or KICK." % [e["nick"], words(str(e["why"]))]
	if w.is_empty():
		return ""
	var first: Dictionary = w[0]
	var what := "starting"
	if first["state"] == "get":
		what = "%d%%" % int(roundf(float(first["dl"]) * 100.0))
	elif first["state"] == "prep":
		what = "preparing"
	return "Waiting for %d %s to get the track (%s %s)." % [w.size(), "player" if w.size() == 1 else "players",
		first["nick"], what]


## A reason code in plain words.
static func words(code: String) -> String:
	return str(WORDS.get(code, code)) if code != "" else "unknown"


## {state, dl, why, eta_s, name, size}, plus code (the fail code: "downloads off" shows the
## DOWNLOAD IT? box, the others RETRY) and thumb (the decoded thumb section or null).
func local_state() -> Dictionary:
	var eta := -1.0
	if str(_local["state"]) == "get" and _hist.size() >= 2:
		var a: Array = _hist[0]
		var b: Array = _hist[_hist.size() - 1]
		var dt := float(b[0]) - float(a[0])
		var db := float(b[1]) - float(a[1])
		if dt > 0.0 and db > 0.0:
			eta = (float(_local["size"]) - float(b[1])) / (db / dt)
	return {"state": str(_local["state"]), "dl": float(_local["dl"]), "why": str(_local["why"]), "eta_s": eta,
		"name": str(_local["name"]), "size": int(_local["size"]), "code": str(_local.get("code", "")), "thumb": _thumb}


# ================================================================ helpers

func _blank_local() -> Dictionary:
	return {"key": "", "sha": "", "id": "", "state": "", "dl": 0.0, "why": "", "name": "", "size": 0, "t": _time, "code": ""}


func _set_local(state: String, dl: float, why: String) -> void:
	var changed := state != str(_local["state"]) or why != str(_local["why"])
	_local["state"] = state
	_local["dl"] = dl
	_local["why"] = why
	_local["t"] = _time
	if changed or state == "get":
		local_changed.emit(state, dl, why)


## A failure that keeps the client in the lobby (NO TRACK, the reason and RETRY).
func _fail_local(code: String, why: String) -> void:
	_local["code"] = code
	_set_local("fail", float(_local["dl"]), why)
	_report(str(_local["sha"]), "fail:" + code, 0, "", 0)


func _report(sha: String, state: String, have: int, digest: String, missing: int) -> void:
	_send(1, &"_c_track", [sha, state, have, digest, missing])


## The custom block of the current cfg when it is valid, else {}.
func _custom() -> Dictionary:
	var id := str(net.cfg.get("track", ""))
	var c = net.cfg.get("custom")
	if CustomTracks.is_custom(id) and valid_custom(c, id):
		return c
	return {}


## Server side, a player's row: track / why / dl (and missing), broadcast on a state change.
func _set_peer(pid: int, state: String, why: String, dl: float, broadcast: bool) -> void:
	if not net.players.has(pid):
		return
	var p: Dictionary = net.players[pid]
	var changed := str(p.get("track", "")) != state or str(p.get("why", "")) != why
	p["track"] = state
	p["why"] = why
	p["dl"] = clampf(dl, 0.0, 1.0)
	if not p.has("missing"):
		p["missing"] = 0
	if changed:
		var info := _info_of(pid)
		info["t_state"] = _time
		info["t_progress"] = _time
		progress_changed.emit(pid, state, p["dl"])
		if broadcast:
			net.broadcast_roster()


func _info_of(pid: int) -> Dictionary:
	if not _peer.has(pid):
		_peer[pid] = {"t_state": _time, "t_progress": _time, "retries": {}, "t_retry": -INF, "logged": false,
			"digest": "", "kicked": false}
	return _peer[pid]


## The server compares a client's digest with its own build's, part by part (it never blocks).
func _compare_digest(pid: int, digest: String) -> void:
	_info_of(pid)["digest"] = digest
	if digest == "" or _own_digest.is_empty() or not net.players.has(pid):
		return
	var diff := []
	for i in LevelBuild.PARTS.size():
		var k: String = LevelBuild.PARTS[i]
		if digest.substr(i * 8, 8) != str(_own_digest.get(k, "")).left(8):
			diff.append(k)
	_info_of(pid)["digest"] = ""
	var nick := str(net.players[pid].get("nick", "?"))
	if diff.is_empty():
		stats["digest_ok"] += 1
		return
	stats["digest_bad"] += 1
	print("%s built the track differently: %s" % [nick, ", ".join(diff)])
	net._info(TEXT_DIFFERENT % nick)


func _kick(pid: int, reason: String) -> void:
	_info_of(pid)["kicked"] = true
	pump.erase(pid)
	stats["kicks"] += 1
	net.kick(pid, reason)


## A message from a peer that failed the checks of 6.3: dropped, logged once per peer.
func _drop(pid: int, what: String) -> void:
	stats["dropped"] += 1
	var info := _info_of(pid)
	if not bool(info["logged"]):
		info["logged"] = true
		print("TrackShare: dropped %s from #%d (logged once)" % [what, pid])


func _send(peer: int, method: StringName, args: Array) -> void:
	if sink.is_valid():
		sink.call(peer, method, args)
		return
	callv(&"rpc_id", [peer, method] + args)


func _is_server() -> bool:
	return net != null and bool(net.active) and bool(net.is_server)


func _is_client() -> bool:
	return net != null and bool(net.active) and not bool(net.is_server)


func _racing() -> bool:
	return str(net.state) != "lobby"


static func _num(v: Variant) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))


## 1 / 0, true / false, "1" / "on" / "yes" / "true".
static func _flag(v: Variant) -> bool:
	if v is String:
		return v.strip_edges().to_lower() in ["1", "true", "on", "yes"]
	if _num(v):
		return float(v) != 0.0
	return bool(v)


static func _hex(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)):
			return false
	return true


static func _fsize(p: String) -> int:
	var f := FileAccess.open(p, FileAccess.READ)
	return f.get_length() if f != null else 0
