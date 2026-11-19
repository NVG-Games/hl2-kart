extends RefCounted
## net/case_transfer (P9, `-- unit`, CI): TrackShare without sockets. A server TrackShare and a
## client TrackShare, each on a fake Net, exchange their RPCs through queues: chunk reassembly,
## offsets, oversize, resume, xid change and stale chunks, AIMD, the race buckets, stalls and
## restarts, the RETRY limit, deadlines, the server-side argument checks, the validators against
## hostile cfg / rules, hostile packages refused before any compile (the client stays), and the
## can_start table on the real Net with a fake roster.

const NEEDS_CONTENT := false
const TIMEOUT := 180.0
const CHUNK := TrackShare.CHUNK
const CPEER := 2


## The Net fields and calls TrackShare uses; records what it was asked to do.
class FakeNet:
	extends Node
	var active := true
	var is_server := true
	var dedicated := false
	var state := "lobby"
	var players := {}
	var cfg := {}
	var server_addr := "127.0.0.1:27300"
	var me := 1
	var peer_net: FakeNet
	var kicks: Array = []
	var infos: Array = []
	var left: Array = []
	var local: Array = []
	var rules: Array = []
	var failed: Array = []
	var rosters := 0

	func my_id() -> int:
		return me

	func kick(id: int, reason: String) -> void:
		kicks.append([id, reason])

	func _info(text: String) -> void:
		infos.append(text)

	func broadcast_roster() -> void:
		rosters += 1
		if peer_net != null:
			peer_net.players = players.duplicate(true)

	func set_rule(key: String, value: Variant) -> void:
		rules.append([key, value])
		if key == "track":
			cfg["track"] = value

	func track_failed(reason: String) -> void:
		failed.append(reason)

	func leave_with(reason: String) -> void:
		left.append(reason)

	func local_info(text: String) -> void:
		local.append(text)

	func _clients() -> Array[int]:
		var o: Array[int] = []
		for id in players:
			if id != 1:
				o.append(id)
		return o


var t: Node
var A: FakeNet    # the server's Net
var B: FakeNet    # the client's Net
var S: TrackShare
var C: TrackShare
var to_c: Array = []
var to_s: Array = []
## (method, args) -> args to deliver, or null to drop (tests tamper with what the client gets)
var filter_c := Callable()
var local_states: Array = []
var thumb_state := ""
var ids_made: Array = []


func run(tt: Node) -> void:
	t = tt
	_validators()
	_can_start_table()
	var good := _good_package()
	t.check(good.size() > 6 * CHUNK, "the test package spans several chunks (%d bytes)" % good.size())
	await _full_transfer(good)
	await _cache_hit(good)
	await _resume(good)
	await _bad_chunks(good)
	await _xid_change(good)
	_aimd()
	_race_buckets(good)
	_stalls(good)
	_retry_limit(good)
	_deadlines()
	_arg_checks(good)
	_downloads_off(good)
	await _hostile(good)
	_rotation()
	_cleanup()


# ---------------------------------------------------------------- the rig

func _rig(dedicated := false) -> void:
	if S != null:
		# reset first: an open .part is closed before the next rig deletes it
		S.reset()
		C.reset()
		for x in [S, C, A, B]:
			x.queue_free()
	A = FakeNet.new()
	B = FakeNet.new()
	A.dedicated = dedicated
	B.is_server = false
	B.me = CPEER
	A.peer_net = B
	A.players = {CPEER: {"nick": "Vance", "ready": false, "ping": 20, "host": false, "track": "?", "why": "", "dl": 0.0, "missing": 0}}
	if not dedicated:
		A.players[1] = {"nick": "Gordon", "ready": false, "ping": 0, "host": true, "track": "?", "why": "", "dl": 0.0, "missing": 0}
	B.players = A.players.duplicate(true)
	S = TrackShare.new()
	C = TrackShare.new()
	S.net = A
	C.net = B
	S.sink = func(peer: int, method: StringName, args: Array) -> void:
		if peer == CPEER:
			to_c.append([method, args])
	C.sink = func(peer: int, method: StringName, args: Array) -> void:
		to_s.append([method, args])
	t.add_child(A)
	t.add_child(B)
	t.add_child(S)
	t.add_child(C)
	to_c.clear()
	to_s.clear()
	filter_c = Callable()
	local_states.clear()
	thumb_state = ""
	C.local_changed.connect(func(st: String, _dl: float, _why: String) -> void:
		if local_states.is_empty() or local_states[-1] != st:
			local_states.append(st))
	C.thumb_arrived.connect(func(_tex: Texture2D) -> void:
		thumb_state = str(C.local_state()["state"]))


## The server serves `bytes` as its track; the client gets the roster and cfg and checks.
func _serve(bytes: PackedByteArray, label := "NET TEST") -> String:
	var id := S.serve_raw(bytes, label)
	var sha := LevelIO.sha256(bytes)
	if not ids_made.has([id, sha]):
		ids_made.append([id, sha])
	_forget(id, sha)
	A.cfg = {"name": "test", "track": id, "laps": 3}
	S.on_track_rule(id)
	B.cfg = TrackShare.clean_cfg(A.cfg)
	B.players = A.players.duplicate(true)
	return id


## Messages both ways until both queues are empty.
func _deliver() -> void:
	var n := 0
	while (not to_c.is_empty() or not to_s.is_empty()) and n < 100000:
		n += 1
		if not to_s.is_empty():
			var m: Array = to_s.pop_front()
			match m[0]:
				&"_c_track":
					S.callv("_recv_track", [CPEER] + m[1])
				&"_c_ack":
					S.callv("_recv_ack", [CPEER] + m[1])
		if not to_c.is_empty():
			var m: Array = to_c.pop_front()
			var args = m[1]
			if filter_c.is_valid():
				args = filter_c.call(m[0], m[1])
				if args == null:
					continue
			match m[0]:
				&"_s_xfer":
					C.callv("_recv_xfer", [1] + args)
				&"_s_chunk":
					C.callv("_recv_chunk", [1] + args)
				&"_s_dl":
					C.callv("_recv_dl", [1] + args)


## Ticks and deliveries until the client is ok / fail (or the limit).
func _drive(limit := 600) -> void:
	for i in limit:
		S.tick(0.05)
		C.tick(0.05)
		_deliver()
		var st := str(C.local_state()["state"])
		if st == "ok" or st == "fail":
			return
		await t.frames(1)


func _part(sha: String) -> String:
	return CustomTracks.cache_part(sha)


## The track out of the registry, memory and cache, and its .part gone (a fresh client).
func _forget(id: String, sha: String) -> void:
	if CustomTracks.has(id):
		CustomTracks.remove(id)
	CustomTracks.forget(id)
	var p := _part(sha)
	if p != "" and FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)


func _cleanup() -> void:
	if S != null:
		S.reset()
		C.reset()
		for x in [S, C, A, B]:
			x.queue_free()
	S = null
	for e in ids_made:
		_forget(e[0], e[1])
	CustomTracks.set_current("")


# ---------------------------------------------------------------- packages

## The oval with a thumb and random ground paint (about 1 MB: many chunks).
func _good_package() -> PackedByteArray:
	var doc := LevelTemplates.make("oval", "NET TEST OVAL")
	var img := Image.create(48, 32, false, Image.FORMAT_RGB8)
	img.fill(Color(0.8, 0.4, 0.1))
	doc.thumb = img.save_png_to_buffer()
	if bool(doc.data.world.terrain) and doc.splat.size() > 0:
		doc.splat = Crypto.new().generate_random_bytes(doc.splat.size())
	return LevelIO.pack(doc)


static func _u32(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, n)
	return b


## A container by hand: magic, version, meta, bodies.
static func _container(meta: Variant, bodies: Array, version := 1) -> PackedByteArray:
	var mb := JSON.stringify(meta).to_utf8_buffer()
	var out := "HL2KT".to_ascii_buffer()
	out.append(version)
	out.append_array(_u32(mb.size()))
	out.append_array(mb)
	for b in bodies:
		out.append_array(b)
	return out


static func _doc_only(doc_text: String, raw_claim := -1) -> PackedByteArray:
	var raw := doc_text.to_utf8_buffer()
	var z := raw.compress(FileAccess.COMPRESSION_ZSTD)
	return _container({"format": 1, "kind": "hl2kart_track", "sections": [{"id": "doc", "codec": "zstd",
		"raw": raw.size() if raw_claim < 0 else raw_claim, "size": z.size()}]}, [z])


## The format cases' refused set (name -> [bytes, leaves]): only a newer format makes a client leave.
func _hostile_set(good: PackedByteArray) -> Dictionary:
	var out := {}
	var b := good.duplicate()
	b[0] = 0x58
	out["bad magic"] = [b, false]
	b = good.duplicate()
	b.encode_u32(6, 9000)
	out["meta_len 9000"] = [b, false]
	out["meta not a dict"] = [_container([1, 2, 3], []), false]
	b = good.duplicate()
	b.append(0)
	out["section sizes off by one"] = [b, false]
	var png := Image.create(8, 8, false, Image.FORMAT_RGB8).save_png_to_buffer()
	out["missing doc"] = [_container({"format": 1, "kind": "hl2kart_track", "sections": [{"id": "thumb",
		"codec": "png", "raw": png.size(), "size": png.size()}]}, [png]), false]
	out["doc raw 5 MiB declared"] = [_doc_only('{"format":1,"kind":"hl2kart_track"}', 5 << 20), false]
	out["raw declared too small"] = [_doc_only('{"format":1,"kind":"hl2kart_track","name":"xxxxxxxxxxxxxxxxxxxxxxxx"}', 10), false]
	var zeros := PackedByteArray()
	zeros.resize(8 << 20)
	var bomb := zeros.compress(FileAccess.COMPRESSION_ZSTD)
	out["zstd bomb"] = [_container({"format": 1, "kind": "hl2kart_track", "sections": [{"id": "doc", "codec": "zstd",
		"raw": 1024, "size": bomb.size()}]}, [bomb]), false]
	out["doc not json"] = [_doc_only("this is not json {"), false]
	out["not a track"] = [_doc_only('{"format":1,"kind":"something_else"}'), false]
	out["2000-deep nesting"] = [_doc_only("[".repeat(2000) + "]".repeat(2000)), false]
	out["format 2"] = [_doc_only('{"format":2,"kind":"hl2kart_track"}'), true]
	b = good.duplicate()
	b[5] = 2
	out["container 2"] = [b, true]
	return out


# ---------------------------------------------------------------- validators

func _validators() -> void:
	var sha := "0123456789abcdef".repeat(4)
	var id := "c_" + sha.left(16)
	var good := {"track": id, "custom": {"sha": sha, "size": 1000, "name": "Canal Run", "author": "Sasha"}}
	t.check(TrackShare.valid_cfg({"track": "city17_circuit"}), "valid_cfg: a built-in")
	t.check(TrackShare.valid_cfg(good), "valid_cfg: a custom track with its block")
	t.check(TrackShare.valid_cfg({"track": id}), "valid_cfg: a custom id without a block (the client waits)")
	t.check(not TrackShare.valid_cfg({"track": "../.."}), "valid_cfg refuses track '../..'")
	t.check(not TrackShare.valid_cfg({"track": "c_edit"}), "valid_cfg refuses c_edit")
	t.check(not TrackShare.valid_cfg({"track": 5}), "valid_cfg refuses a number")
	t.check(not TrackShare.valid_cfg({}), "valid_cfg refuses no track")
	t.check(not TrackShare.valid_cfg({"track": "c_0123456789ABCDEF"}), "valid_cfg refuses upper-case hex")
	var bad := good.duplicate(true)
	bad.custom.sha = "../../x"
	t.check(not TrackShare.valid_cfg(bad), "valid_cfg refuses sha '../../x'")
	bad = good.duplicate(true)
	bad.custom.sha = "f".repeat(64)
	t.check(not TrackShare.valid_cfg(bad), "valid_cfg refuses a sha that is not the id's")
	for s in [0, LevelIO.MAX_FILE + 1, -5, 1.5, "100"]:
		bad = good.duplicate(true)
		bad.custom.size = s
		t.check(not TrackShare.valid_cfg(bad), "valid_cfg refuses size %s" % str(s))
	bad = good.duplicate(true)
	bad.custom.name = 7
	t.check(not TrackShare.valid_cfg(bad), "valid_cfg refuses a name that is not a string")
	t.check(not TrackShare.valid_cfg({"track": "city17_circuit", "custom": good.custom}), "valid_cfg refuses a custom block on a built-in")
	# clean_cfg: what a client stores
	t.check(TrackShare.clean_cfg({"track": "../.."}).is_empty(), "clean_cfg refuses a bad track")
	t.check(TrackShare.clean_cfg({"track": "c_edit"}).is_empty(), "clean_cfg refuses c_edit")
	var long := good.duplicate(true)
	long.custom.name = "\u0001[b]{x}" + "N".repeat(5000)
	long.custom.author = "  \tA}{uthor  "
	var cc := TrackShare.clean_cfg(long)
	t.check(cc.custom.name == "bxN" + "N".repeat(45), "clean_cfg cuts the name to 48 and strips [ ] { } and controls (%s)" % str(cc.custom.name).left(20))
	t.check(cc.custom.author == "Author", "clean_cfg strips the author (%s)" % cc.custom.author)
	bad = good.duplicate(true)
	bad.custom.sha = "../../x"
	cc = TrackShare.clean_cfg(bad)
	t.check(cc.get("track") == id and not cc.has("custom"), "clean_cfg drops a broken custom block, keeps the id (waits in ?)")
	# rules
	t.check(TrackShare.valid_rules({"track": "xen", "track_sha": "", "laps": 3, "epoch": 1.5}), "valid_rules: a built-in")
	t.check(TrackShare.valid_rules({"track": id, "track_sha": sha, "laps": 3}), "valid_rules: a custom track")
	t.check(not TrackShare.valid_rules({"track": "xen", "track_sha": sha}), "valid_rules refuses a sha on a built-in")
	t.check(not TrackShare.valid_rules({"track": id, "track_sha": "../../x"}), "valid_rules refuses sha '../../x'")
	t.check(not TrackShare.valid_rules({"track": id, "track_sha": "f".repeat(64)}), "valid_rules refuses another track's sha")
	t.check(not TrackShare.valid_rules({"track": "../..", "track_sha": ""}), "valid_rules refuses track '../..'")
	t.check(not TrackShare.valid_rules({"track": "c_edit", "track_sha": ""}), "valid_rules refuses c_edit")
	t.check(not TrackShare.valid_rules({"track": "xen", "track_sha": "", "laps": "3"}), "valid_rules refuses laps as text")
	t.check(not TrackShare.valid_rules({"track": "xen", "track_sha": 5}), "valid_rules refuses a numeric sha")
	t.check(TrackShare.clean_text("a\nb[c]{d}\u007f", 80) == "abcd", "clean_text strips")
	t.check(TrackShare.words("stalled") == "download stalled", "reason words")


# ---------------------------------------------------------------- can_start on the real Net

func _can_start_table() -> void:
	var net := t.get_node_or_null("/root/Net")
	if net == null or net.get("share") == null:
		t.fail("Net has no TrackShare child")
		return
	t.check(net.get_node_or_null("TrackShare") == net.share, "TrackShare lives at /root/Net/TrackShare")
	t.check(net.PROTOCOL == 5, "PROTOCOL 5")
	if net.active:
		t.fail("Net is active: the table needs it offline")
		return
	var sha := "abcdef0123456789".repeat(4)
	var id := "c_" + sha.left(16)
	var saved := {"active": net.active, "is_server": net.is_server, "dedicated": net.dedicated, "state": net.state,
		"players": net.players, "cfg": net.cfg}
	# all of this runs in one frame: Net._process never sees the fake state
	net.active = true
	net.is_server = true
	net.dedicated = true
	net.cfg = {"name": "t", "track": id, "laps": 3, "difficulty": 1, "hazards": 1,
		"custom": {"sha": sha, "size": 1500000, "name": "Canal Run", "author": "Sasha"}}
	var vance := {"nick": "Vance", "ready": true, "host": false, "track": "ok", "why": "", "dl": 1.0, "missing": 0, "ping": 30}
	var rows := []
	net.players = {}
	net.state = "race"
	rows.append(["in a race", net.can_start(), "Not in the lobby."])
	net.state = "lobby"
	net.players = {2: vance.duplicate()}
	rows.append(["dedicated, not prepared", net.can_start(), "Preparing the track..."])
	rows.append(["dedicated, not prepared, force_ready", net.can_start(true), "Preparing the track..."])
	t.check(not net.everyone_has_track(), "everyone_has_track: false while the dedicated server's build is not ready")
	CustomTracks.put_memory(id, LevelBuild.new(), {})
	t.check(net.everyone_has_track(), "everyone_has_track once the dedicated server's build is ready")
	rows.append(["all ok and READY", net.can_start(), ""])
	net.players[2].track = "get"
	net.players[2].dl = 0.42
	rows.append(["downloading", net.can_start(), "Waiting for 1 player to get the track (Vance 42%)."])
	rows.append(["downloading, force_ready", net.can_start(true), "Waiting for 1 player to get the track (Vance 42%)."])
	net.players[3] = {"nick": "Barney", "ready": false, "host": false, "track": "prep", "why": "", "dl": 1.0}
	rows.append(["two waiting", net.can_start(), "Waiting for 2 players to get the track (Vance 42%)."])
	net.players[2].track = "fail"
	net.players[2].why = "stalled"
	rows.append(["a failure", net.can_start(), "Vance has no track (download stalled): wait, change the track or KICK."])
	net.players[2].track = "ok"
	net.players[3].track = "ok"
	rows.append(["Barney not READY", net.can_start(), "Waiting for Barney to be READY."])
	rows.append(["Barney not READY, force_ready", net.can_start(true), ""])
	net.players[2].ready = false
	rows.append(["two not READY", net.can_start(), "Waiting for 2 players to be READY."])
	net.players[3].track = "?"
	t.check(not net.everyone_has_track(), "everyone_has_track: false with a player in ?")
	rows.append(["a joiner in ?", net.can_start(true), "Waiting for 1 player to get the track (Barney starting)."])
	# a listen host: its own row
	net.dedicated = false
	CustomTracks.forget(id)
	net.players = {1: {"nick": "Gordon", "ready": false, "host": true, "track": "prep", "why": "", "dl": 0.0},
		2: vance.duplicate()}
	rows.append(["listen host preparing", net.can_start(), "Preparing the track..."])
	CustomTracks.put_memory(id, LevelBuild.new(), {})
	net.players[1].track = "ok"
	rows.append(["listen host ready, the host not READY", net.can_start(), ""])
	# server_info (6.7)
	var info: Dictionary = net.server_info()
	t.check(info.get("cu") == 1 and info.get("msha") == sha.left(16) and info.get("mkb") == 1465 and info.get("map") == "Canal Run",
		"server_info: cu, msha, mkb, map (%s)" % str([info.get("cu"), info.get("msha"), info.get("mkb"), info.get("map")]))
	t.check(JSON.stringify(info).to_utf8_buffer().size() < 1200, "server_info stays one datagram")
	# set_rule: server keys stay on the server, a track during a race waits
	var rate0: int = net.share.download_rate
	net.set_rule("download_rate", 100)
	t.check(net.share.download_rate == 100 and not net.cfg.has("download_rate"), "set_rule(download_rate) stays on the server")
	net.share.download_rate = rate0
	net.state = "race"
	var other := "c_" + "1".repeat(16)
	net.set_rule("track", other)
	t.check(net.cfg.track == id and net.share.pending_track == other, "a track rule during a race waits for the lobby")
	net.share.pending_track = ""
	net.set_rule("track", "../..")
	t.check(net.cfg.track == id, "set_rule refuses a bad track id")
	# track_failed in the lobby: the reason in the chat, unusable, the first installed circuit
	var broken := "c_" + "2".repeat(16)
	net.state = "lobby"
	net.cfg.track = broken
	net.cfg.erase("custom")
	var said := []
	var on_chat := func(_n: String, text: String, _k: String) -> void: said.append(text)
	net.chat_received.connect(on_chat)
	net.track_failed("The track could not be built here.")
	net.chat_received.disconnect(on_chat)
	t.check(said.has("The track could not be built here."), "track_failed: the reason in the chat")
	t.check(CustomTracks.unusable(broken) == "The track could not be built here.", "track_failed marks the track unusable")
	if Game.track_installed("city17_circuit"):
		t.check(net.cfg.track == "city17_circuit", "track_failed falls back to the first installed circuit (%s)" % net.cfg.track)
	else:
		t.check(net.cfg.track == broken, "track_failed: no circuit installed, the track stays")
	for r in rows:
		t.check(r[1] == r[2], "can_start %s: '%s' (want '%s')" % r)
	CustomTracks.forget(id)
	for k in saved:
		net.set(k, saved[k])
	net.share.reset()


# ---------------------------------------------------------------- transfers

func _full_transfer(good: PackedByteArray) -> void:
	_rig(true)
	var id := _serve(good)
	var sha := LevelIO.sha256(good)
	t.check(A.cfg.custom.sha == sha and A.cfg.custom.size == good.size() and A.cfg.custom.name == "NET TEST",
		"on_track_rule fills cfg.custom")
	t.check(A.players[CPEER].track == "?", "on_track_rule resets the client to ?")
	t.check(TrackShare.valid_cfg(A.cfg), "the server's cfg passes valid_cfg")
	var progress := []
	S.progress_changed.connect(func(p: int, st: String, dl: float) -> void: progress.append([p, st, dl]))
	C.check()
	t.check(to_s.size() == 1 and to_s[0][1][1] == "need" and to_s[0][1][2] == 0, "a fresh client asks: need, have 0")
	_deliver()
	t.check(A.players[CPEER].track == "get", "the server opens a transfer: get")
	t.check(S.pump.has(CPEER) and S.stats.xfers == 1, "one pump state, one _s_xfer")
	t.check(str(C.local_state().state) == "get", "the client: get")
	S.tick(0.05)
	t.check(int(S.pump[CPEER].sent) == TrackShare.WIN_LOBBY * CHUNK, "lobby window: 4 chunks in flight (%d)" % int(S.pump[CPEER].sent))
	S.tick(0.05)
	t.check(int(S.pump[CPEER].sent) == TrackShare.WIN_LOBBY * CHUNK, "no more until an ack")
	await _drive()
	await t.frames(3)
	var ls: Dictionary = C.local_state()
	t.check(ls.state == "ok", "the download ends ok (%s, %s)" % [ls.state, ls.why])
	t.check(local_states.slice(0, 4) == ["need", "get", "prep", "ok"], "client states need -> get -> prep -> ok (%s)" % str(local_states))
	t.check(A.players[CPEER].track == "ok", "the server's roster says ok")
	var seen := []
	for e in progress:
		if int(e[0]) == CPEER and (seen.is_empty() or seen[-1] != e[1]):
			seen.append(e[1])
	t.check(seen.has("get") and seen.has("prep") and seen[-1] == "ok", "progress_changed on the server (%s)" % str(seen))
	t.check(CustomTracks.has(id) and str(CustomTracks.meta(id).get("kind", "")) == "cache", "the track is in the cache")
	var cached := FileAccess.get_file_as_bytes(CustomTracks.path(id))
	t.check(cached == good, "chunk reassembly: the cached file is the server's bytes")
	t.check(not FileAccess.file_exists(_part(sha)), "the .part became the cache file")
	t.check(CustomTracks.is_prepared(id) and CustomTracks.current() == id, "the build is in memory and current")
	t.check(S.stats.dl_sent > 0, "_s_dl went out while downloading (%d)" % S.stats.dl_sent)
	t.check(thumb_state == "get", "the thumb arrived during the download (%s)" % thumb_state)
	t.check(B.left.is_empty(), "the client stayed")
	# the digest compare, part by part
	var b := CustomTracks.build_for(id)
	S._own_digest = b.digest_parts()
	S._recv_track(CPEER, sha, "ok", 0, b.digest(), 0)
	t.check(S.stats.digest_ok == 1 and A.infos.is_empty(), "a matching digest")
	var d2 := b.digest()
	d2 = d2.left(40) + ("0" if d2[40] != "0" else "1") + d2.substr(41)
	S._recv_track(CPEER, sha, "ok", 0, d2, 0)
	t.check(S.stats.digest_bad == 1 and A.infos.size() == 1 and str(A.infos[0]).contains("built the track differently"),
		"a different part: one info line (%s)" % str(A.infos))
	t.check(S.status_line() == "", "status line empty when everyone has it")


func _cache_hit(good: PackedByteArray) -> void:
	# the same client again (a new session): the registry has it
	var id := LevelIO.id_for(LevelIO.sha256(good))
	B.players[CPEER].track = "?"
	C.reset()
	var x0: int = S.stats.xfers
	C.check()
	var states := []
	for m in to_s:
		states.append(m[1][1])
	t.check(states.slice(0, 2) == ["prep", "ok"], "a cache hit: prep -> ok without need (%s)" % str(states))
	_deliver()
	t.check(S.stats.xfers == x0 and A.players[CPEER].track == "ok", "a cache hit sends no _s_xfer")
	# a laps change re-sends nothing
	C.check()
	t.check(to_s.is_empty(), "the same track in hand: check() does nothing")
	t.check(CustomTracks.has(id), "still cached")


func _resume(good: PackedByteArray) -> void:
	_rig(true)
	var id := _serve(good)
	var sha := LevelIO.sha256(good)
	var p := _part(sha)
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_buffer(good.slice(0, 5 * CHUNK + 100))
	f.close()
	C.check()
	t.check(to_s.size() == 1 and to_s[0][1][1] == "need" and int(to_s[0][1][2]) == 5 * CHUNK,
		"resume: need with have = the .part rounded down to 32 KiB (%s)" % str(to_s[0][1][2]))
	_deliver()
	t.check(int(S.pump[CPEER].acked) == 5 * CHUNK, "the server starts at the offset")
	t.check(float(C.local_state().dl) > 0.1, "the client's progress starts there")
	await _drive()
	await t.frames(3)
	t.check(str(C.local_state().state) == "ok", "the resumed download ends ok (%s)" % str(C.local_state().why))
	t.check(FileAccess.get_file_as_bytes(CustomTracks.path(id)) == good, "the resumed file is exact")
	t.check(int(S.stats.chunks) == ceili((good.size() - 5 * CHUNK) / float(CHUNK)), "only the missing chunks were sent (%d)" % int(S.stats.chunks))


func _bad_chunks(good: PackedByteArray) -> void:
	_rig(true)
	var sha := LevelIO.sha256(good)
	_serve(good)
	# 1: a chunk at the wrong offset
	var tampered := {"n": 0}
	filter_c = func(method: StringName, args: Array) -> Variant:
		if method == &"_s_chunk" and int(args[1]) == 2 * CHUNK and tampered.n == 0:
			tampered.n = 1
			return [args[0], int(args[1]) + 1, args[2]]
		return args
	C.check()
	for i in 10:
		S.tick(0.05)
		_deliver()
		if S.stats.xfers >= 2:
			break
	t.check(tampered.n == 1, "a chunk was tampered with")
	t.check(S.stats.xfers == 2 and int(S.pump[CPEER].restarts) == 1, "a bad offset: one fresh need, a new transfer (%d)" % S.stats.xfers)
	t.check(str(C.local_state().state) == "get" and B.left.is_empty(), "the client downloads again, connected")
	# 2: an oversize chunk on the new xid: damaged twice
	filter_c = func(method: StringName, args: Array) -> Variant:
		if method == &"_s_chunk":
			var big := PackedByteArray()
			big.resize(CHUNK + 1)
			return [args[0], args[1], big]
		return args
	for i in 3:
		S.tick(0.05)
		_deliver()
	var ls: Dictionary = C.local_state()
	t.check(ls.state == "fail" and ls.why == TrackShare.TEXT_DAMAGED, "a second bad chunk: fail:damaged (%s)" % ls.why)
	t.check(A.players[CPEER].track == "fail" and A.players[CPEER].why == "damaged", "the server's roster: fail, damaged")
	t.check(not FileAccess.file_exists(_part(sha)), "the damaged .part is gone")
	t.check(B.left.is_empty(), "damaged: the client stays in the lobby")
	CustomTracks.put_memory(LevelIO.id_for(sha), LevelBuild.new(), {})
	t.check(S.status_line() == "Vance has no track (download damaged): wait, change the track or KICK.", "status line: %s" % S.status_line())
	# RETRY: a fresh need, accepted once
	filter_c = Callable()
	C.retry()
	_deliver()
	t.check(A.players[CPEER].track == "get" and S.stats.xfers == 3, "RETRY starts a new transfer")
	await _drive()
	await t.frames(3)
	t.check(str(C.local_state().state) == "ok", "after RETRY the download ends ok")


func _xid_change(good: PackedByteArray) -> void:
	_rig(true)
	var id := _serve(good)
	C.check()
	_deliver()
	S.tick(0.05)
	var stale := []
	for m in to_c:
		if m[0] == &"_s_chunk":
			stale.append(m)
	to_c.clear()
	var old_xid := int(S.pump[CPEER].xid)
	# the host picks the track again: every transfer stops, every client back to ?
	S.on_track_rule(id)
	t.check(S.pump.is_empty() and A.players[CPEER].track == "?" and B.players[CPEER].track == "?", "a track rule resets the transfers and the roster")
	B.cfg = TrackShare.clean_cfg(A.cfg)
	C.check()
	_deliver()
	var new_xid := int(S.pump[CPEER].xid)
	t.check(new_xid != old_xid, "the new transfer has a new xid")
	var got0 := int(C._rx.got)
	for m in stale:
		C.callv("_recv_chunk", [1] + m[1])
	t.check(int(C._rx.got) == got0 and str(C.local_state().state) == "get" and not C._bad.has(LevelIO.sha256(good)),
		"stale chunks (old xid) are dropped quietly")
	var d0: int = S.stats.dropped
	S._recv_ack(CPEER, old_xid, CHUNK)
	t.check(S.stats.dropped == d0 + 1 and int(S.pump[CPEER].acked) == 0, "a stale ack is dropped")
	# a chunk from someone who is not the server
	S.tick(0.05)
	var m0: Array = to_c[0] if not to_c.is_empty() else []
	if not m0.is_empty() and m0[0] == &"_s_chunk":
		C.callv("_recv_chunk", [5] + m0[1])
		t.check(int(C._rx.got) == got0, "a chunk from another peer is ignored")
	to_c.clear()


func _aimd() -> void:
	_rig(false)
	var st := {"win": 4, "srtt": -1.0, "base_rtt": INF, "acks": 0, "good": 0, "since": TrackShare.BASE_ACKS}
	for i in 8:
		S._aimd(st, 0.02)
	t.near(float(st.base_rtt), 0.02, 0.0001, "base RTT from the first 8 acks")
	t.check(int(st.win) == 4, "no change while measuring")
	var halved_at := -1
	for i in 6:
		S._aimd(st, 0.4)
		if int(st.win) == 2 and halved_at < 0:
			halved_at = i
	t.check(int(st.win) == 2 and halved_at >= 0, "a fake RTT rise halves the window (4 -> %d after %d acks)" % [int(st.win), halved_at + 1])
	for i in 10:
		S._aimd(st, 0.4)
	t.check(int(st.win) == 1, "it keeps halving, at least 1 (%d)" % int(st.win))
	for i in 40:
		S._aimd(st, 0.02)
	t.check(int(st.win) > 1, "the window grows back once the RTT falls (%d)" % int(st.win))
	for i in 200:
		S._aimd(st, 0.02)
	t.check(int(st.win) == TrackShare.WIN_LOBBY_MAX, "up to 8 in the lobby (%d)" % int(st.win))
	A.state = "race"
	st.win = 1
	for i in 100:
		S._aimd(st, 0.02)
	t.check(int(st.win) == TrackShare.WIN_RACE, "up to 2 during a race (%d)" % int(st.win))
	# the RTT is measured from the chunk the ack covers
	A.state = "lobby"
	var good := PackedByteArray()
	good.resize(20 * CHUNK)
	_serve(good)
	C.check()
	_deliver()
	S.tick(0.05)
	to_c.clear()
	S._time += 0.3
	S._recv_ack(CPEER, int(S.pump[CPEER].xid), CHUNK)
	t.near(float(S.pump[CPEER].srtt), 0.3, 0.001, "the ack RTT")


func _race_buckets(good: PackedByteArray) -> void:
	for dedicated in [false, true]:
		_rig(dedicated)
		_serve(good)
		A.state = "race"
		C.check()
		_deliver()
		var chunks0: int = S.stats.chunks
		var max_flight := 0
		var secs := 4.0
		var steps := int(secs / 0.05)
		for i in steps:
			S.tick(0.05)
			if S.pump.has(CPEER):
				max_flight = maxi(max_flight, int(S.pump[CPEER].sent) - int(S.pump[CPEER].acked))
			_deliver()
		var sent := (int(S.stats.chunks) - chunks0) * CHUNK
		var rate := TrackShare.RATE_LISTEN if not dedicated else TrackShare.RATE_DEDICATED
		var want := rate * 1024.0 * secs
		t.check(absf(sent - want) <= 2 * CHUNK, "%s race bucket %d KB/s: %d KB in %.0f s (want about %d)" % [
			"dedicated" if dedicated else "listen", rate, sent / 1024, secs, int(want / 1024)])
		t.check(max_flight <= TrackShare.WIN_RACE * CHUNK, "at most 2 chunks in flight during a race (%d)" % (max_flight / CHUNK))
	_rig(true)
	S.rate_cap = 256
	_serve(good)
	C.check()
	_deliver()
	var c0: int = S.stats.chunks
	for i in 40:
		S.tick(0.05)
		_deliver()
	var kb := (int(S.stats.chunks) - c0) * CHUNK / 1024
	t.check(kb >= 448 and kb <= 640, "the test rate cap (--rate 256) holds in the lobby: %d KB in 2 s" % kb)


func _stalls(good: PackedByteArray) -> void:
	_rig(false)
	var id := _serve(good)
	C.check()
	_deliver()
	S.tick(0.05)
	to_c.clear()
	var xid := int(S.pump[CPEER].xid)
	var acked0 := int(S.pump[CPEER].acked)
	for i in TrackShare.RESTARTS:
		S.tick(TrackShare.STALL + 0.5)
		var re := to_c.filter(func(m: Array) -> bool: return m[0] == &"_s_xfer")
		t.check(re.size() == 1 and int(re[0][1][0]) == xid and int(re[0][1][3]) == acked0, "stall %d: a restart from the last ack, same xid" % (i + 1))
		to_c.clear()
	t.check(S.pump.has(CPEER), "still sending after 3 restarts")
	S.tick(TrackShare.STALL + 0.5)
	t.check(not S.pump.has(CPEER) and A.players[CPEER].track == "fail" and A.players[CPEER].why == "stalled",
		"the 4th stall: fail:stalled, nothing more sent")
	t.check(S.stats.restarts == TrackShare.RESTARTS + 1, "restarts counted")
	t.check(S.status_line() == "Preparing the track...", "the host's own build first: %s" % S.status_line())
	CustomTracks.put_memory(id, LevelBuild.new(), {})
	A.players[1].track = "ok"
	t.check(S.status_line() == "Vance has no track (download stalled): wait, change the track or KICK.", "status line: %s" % S.status_line())
	var w := S.waiting()
	t.check(w.size() == 1 and int(w[0].id) == CPEER and w[0].why == "stalled", "waiting() lists Vance (%s)" % str(w))
	CustomTracks.forget(id)
	t.check(A.kicks.is_empty(), "a listen host never auto-kicks")
	# the client's own watchdog
	to_c.clear()
	C.tick(TrackShare.CLIENT_STALL + 1.0)
	t.check(str(C.local_state().state) == "fail" and str(C.local_state().why) == TrackShare.TEXT_STALLED, "the client gives up a silent download itself")
	t.check(B.left.is_empty(), "stalled: the client stays")


func _retry_limit(good: PackedByteArray) -> void:
	_rig(true)
	var sha := LevelIO.sha256(good)
	_serve(good)
	var x0: int = S.stats.xfers
	var accepted := 0
	for i in 8:
		A.players[CPEER].track = "fail"
		S.pump.erase(CPEER)
		S._recv_track(CPEER, sha, "need", 0, "", 0)
		if A.players[CPEER].track == "get":
			accepted += 1
		A.players[CPEER].track = "fail"
		S._recv_track(CPEER, sha, "need", 0, "", 0)
		t.check(A.players[CPEER].track == "fail", "retry %d: a second need within 30 s is dropped" % (i + 1))
		S._time += TrackShare.RETRY_GAP + 1.0
	t.check(accepted == TrackShare.RETRY_MAX and S.stats.xfers == x0 + TrackShare.RETRY_MAX,
		"at most 5 retries per sha (%d accepted)" % accepted)
	# sv_downloads 0
	A.players[CPEER].track = "?"
	S.downloads = false
	S._recv_track(CPEER, sha, "need", 0, "", 0)
	t.check(A.kicks.size() == 1 and A.kicks[0][1] == TrackShare.TEXT_NO_SEND, "sv_downloads 0: a need is answered with a kick")
	S.downloads = true


func _deadlines() -> void:
	for dedicated in [false, true]:
		_rig(dedicated)
		var p: Dictionary = A.players[CPEER]
		p.track = "prep"
		S._info_of(CPEER)
		S._time += TrackShare.PREP_TIMEOUT + 1.0
		S._deadlines()
		if dedicated:
			t.check(A.kicks.size() == 1 and A.kicks[0][1] == TrackShare.TEXT_PREP_KICK, "dedicated: prep over 60 s is kicked")
		else:
			t.check(A.kicks.is_empty() and p.track == "fail" and p.why == "preparation timed out", "listen host: prep over 60 s fails, no kick")
		_rig(dedicated)
		p = A.players[CPEER]
		p.track = "need"
		S._info_of(CPEER)
		S._time += TrackShare.IDLE_KICK - 5.0
		S._deadlines()
		t.check(A.kicks.is_empty(), "no kick before 120 s")
		S._time += 10.0
		S._deadlines()
		if dedicated:
			t.check(A.kicks.size() == 1 and A.kicks[0][1] == "Could not get the track: no progress.", "dedicated: 120 s without progress is kicked (%s)" % str(A.kicks))
			S._deadlines()
			t.check(A.kicks.size() == 1, "kicked once")
		else:
			t.check(A.kicks.is_empty(), "listen host: no idle kick")


func _arg_checks(good: PackedByteArray) -> void:
	_rig(true)
	var sha := LevelIO.sha256(good)
	_serve(good)
	var p: Dictionary = A.players[CPEER]
	var bad := [["another sha", "f".repeat(64), "ok", 0, "", 0], ["no sha", "", "ok", 0, "", 0],
		["a bad state", sha, "done", 0, "", 0], ["have off the grid", sha, "need", 100, "", 0],
		["have past the size", sha, "need", good.size() + CHUNK, "", 0], ["have negative", sha, "need", -CHUNK, "", 0],
		["a short digest", sha, "ok", 0, "abc", 0], ["an upper-case digest", sha, "ok", 0, "A".repeat(72), 0],
		["missing -1", sha, "ok", 0, "", -1], ["missing 100001", sha, "ok", 0, "", 100001]]
	for b in bad:
		S._recv_track(CPEER, b[1], b[2], b[3], b[4], b[5])
		t.check(p.track == "?", "_c_track with %s is dropped" % b[0])
	S._recv_track(99, sha, "ok", 0, "", 0)
	t.check(not A.players.has(99), "_c_track from a peer not in players is ignored")
	S._recv_track(CPEER, sha, "fail:\u0001" + "[x]".repeat(100), 0, "", 0)
	t.check(p.track == "fail" and str(p.why).length() <= TrackShare.REASON_MAX and not str(p.why).contains("[") and not str(p.why).contains("\u0001"),
		"a fail reason is cut and stripped (%d chars)" % str(p.why).length())
	S._recv_track(CPEER, sha, "ok", 0, "", 7)
	t.check(p.track == "ok" and int(p.missing) == 7, "an ok report with its missing count")
	# acks
	_rig(true)
	_serve(good)
	C.check()
	_deliver()
	S.tick(0.05)
	to_c.clear()
	var st: Dictionary = S.pump[CPEER]
	var d0: int = S.stats.dropped
	S._recv_ack(CPEER, int(st.xid), int(st.sent) + CHUNK)
	S._recv_ack(CPEER, int(st.xid), 100)
	S._recv_ack(CPEER, int(st.xid) + 1, CHUNK)
	t.check(S.stats.dropped == d0 + 3 and int(st.acked) == 0, "acks past what was sent, off the grid or of another xid are dropped")
	S._recv_ack(CPEER, int(st.xid), 2 * CHUNK)
	S._recv_ack(CPEER, int(st.xid), CHUNK)
	t.check(int(st.acked) == 2 * CHUNK, "acks are monotone")
	# a client: messages not from the server, a transfer it did not ask for
	_rig(true)
	_serve(good)
	C._recv_xfer(1, 1, sha, good.size(), 0)
	t.check(C._rx.is_empty(), "a transfer the client did not ask for is ignored")
	C.check()
	to_s.clear()
	C._recv_xfer(3, 1, sha, good.size(), 0)
	t.check(C._rx.is_empty(), "_s_xfer from another peer is ignored")
	C._recv_xfer(1, 1, "f".repeat(64), good.size(), 0)
	C._recv_xfer(1, 1, sha, good.size() + 1, 0)
	t.check(C._rx.is_empty(), "_s_xfer with another sha or size is ignored")


func _downloads_off(good: PackedByteArray) -> void:
	_rig(true)
	var sha := LevelIO.sha256(good)
	var id := _serve(good)
	var g := t.get_node("/root/Game")
	g.settings["allow_downloads"] = false
	C.check()
	t.check(str(C.local_state().state) == "fail" and str(C.local_state().code) == "downloads off" and to_s.size() == 1
		and to_s[0][1][1] == "fail:downloads off", "allow_downloads off: fail:downloads off until DOWNLOAD")
	to_s.clear()
	C.consent()
	t.check(to_s.size() == 1 and to_s[0][1][1] == "need", "DOWNLOAD (consent) for this server: need")
	g.settings["allow_downloads"] = true
	# a custom id without a valid block: wait in ?
	_rig(true)
	_serve(good)
	B.cfg = {"track": id}
	C.check()
	t.check(to_s.is_empty() and str(C.local_state().state) == "?" and B.left.is_empty(), "a custom id without a valid custom block waits in ?")
	B.cfg = TrackShare.clean_cfg({"track": id, "custom": {"sha": sha, "size": LevelIO.MAX_FILE + 1}})
	C.check()
	t.check(to_s.is_empty() and str(C.local_state().state) == "?", "an oversize custom block is not valid: ? and nothing sent")
	# a built-in this computer has not built: the one other case that leaves
	_rig(true)
	B.cfg = {"track": "no_such_circuit_here"}
	B.players[CPEER].track = "?"
	if not Game.track_installed("xen"):
		B.cfg = {"track": "xen"}
		C.check()
		t.check(B.left.size() == 1 and str(B.left[0]).contains("has not built"), "a built-in it lacks: fail:not built and leave")
	else:
		B.cfg = {"track": "xen"}
		C.check()
		t.check(to_s.size() == 1 and to_s[0][1][1] == "ok" and B.left.is_empty(), "a built-in it has: ok")


func _hostile(good: PackedByteArray) -> void:
	var set := _hostile_set(good)
	for name in set:
		var bytes: PackedByteArray = set[name][0]
		var leaves: bool = set[name][1]
		_rig(true)
		_serve(bytes, "HOSTILE")
		var c0 := TrackShare.compiles
		C.check()
		await _drive(200)
		for i in 30:
			if not B.left.is_empty() or str(C.local_state().state) == "fail":
				break
			await t.frames(1)
		var ls: Dictionary = C.local_state()
		t.check(TrackShare.compiles == c0, "%s: refused before any compile" % name)
		if leaves:
			t.check(B.left.size() == 1 and B.left[0] == TrackShare.TEXT_NEWER, "%s: the client leaves (newer format) (%s)" % [name, str(B.left)])
		else:
			t.check(ls.state == "fail" and str(ls.why).begins_with("This server's track could not be used:") and B.left.is_empty(),
				"%s: fail:invalid, the client stays in the lobby (%s / %s)" % [name, ls.state, ls.why])
			t.check(A.players[CPEER].track == "fail" and A.players[CPEER].why == "invalid", "%s: the server's roster says invalid" % name)
		var id := LevelIO.id_for(LevelIO.sha256(bytes))
		t.check(not CustomTracks.has(id), "%s: nothing cached" % name)
		t.check(not FileAccess.file_exists(_part(LevelIO.sha256(bytes))), "%s: no .part left" % name)


func _rotation() -> void:
	_rig(true)
	A.cfg = {"track": "city17_circuit"}
	S.tracklist = PackedStringArray(["city17_circuit", "xen", "nowhere"])
	t.check(S.rotation() == PackedStringArray(["city17_circuit", "xen"]), "the track list resolves ids, drops unknown entries")
	S.rotate_on = false
	t.check(not S.rotate(), "mp_rotate 0: no rotation")
	S.rotate_on = true
	if Game.track_installed("xen"):
		t.check(S.rotate() and A.rules[-1] == ["track", "xen"], "rotate: the next entry")
	else:
		t.check(not S.rotate(), "rotate skips tracks this computer lacks")
	S.pending_track = "xen"
	S.after_race()
	t.check(A.rules[-1] == ["track", "xen"] and S.pending_track == "", "after_race applies a rule given during the race")
