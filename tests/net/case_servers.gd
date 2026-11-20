extends RefCounted
## net/case_servers (P11, `-- unit`, CI): the dedicated server's side of custom tracks (6.8) and the
## UI helpers of the lobby, CREATE SERVER and the browser (6.5, 6.7), without content:
## - the scan of a server folder through the gate: .autosave/ .trash/ .history/ cache/ skipped, a
##   damaged file and a junk file skipped (logged), a sub folder taken; a damaged own file marked
##   unusable (the registry only hashes own files);
## - mp_track by file name, display name, c_ id and sha prefix; finish(o) after the scan (a
##   mp_track line before its sv_tracks line still resolves), flags over the file, the five cvars,
##   the console's set_option, a track list with unknown and unusable entries left out;
## - rotation from the resolved list on TrackShare: unusable entries skipped, mp_rotate 0;
## - a real dedicated host (UDP 27306): the server compiles its current track and the next
##   rotation entry (the prefetch) and nothing else; the console's next / track / set / tracks /
##   status;
## - Lobby.fill_track_cell, CreateServer's combined dropdown by id (and HOST's track), ServerBrowser's
##   TRACK cell and CUSTOM TRACK line against hostile replies;
## - the host's lobby on a custom track (UDP 27308): START disabled with the reason until its own
##   build is ready; a friend's lobby (no socket): the sub line, the TRACK column in place, the own
##   download row (size, percent, time left), PREPARING TRACK..., RETRY, DOWNLOAD IT? once.

const NEEDS_CONTENT := false
const TIMEOUT := 120.0
const PORT := 27306


## The Net fields TrackShare's rotation reads; records set_rule.
class FakeNet:
	extends Node
	var active := true
	var is_server := true
	var dedicated := true
	var state := "lobby"
	var players := {}
	var cfg := {}
	var rules: Array = []

	func set_rule(key: String, value: Variant) -> void:
		rules.append([key, value])
		if key == "track":
			cfg["track"] = value


var t: Node
var dir := ""                 # the server folder (sv_tracks)
var ids := {}                 # label -> id
var shas := {}                # label -> sha
var made: Array[String] = []  # files to delete at the end
var _saved := {}


func run(t_: Node) -> void:
	t = t_
	_saved = {"auto_check": CustomTracks.auto_check, "extra": CustomTracks._extra_folders.duplicate(),
		"allow": Game.settings.get("allow_downloads", true), "track": Game.settings.get("track", ""),
		"guid": Game.settings.get("track_guid", "")}
	CustomTracks.auto_check = false
	_make_files()
	_scan()
	_resolve()
	_finish_order()
	_load_options()
	_set_option()
	_rotation()
	await _dedicated()
	await _ui_helpers()
	await _lobby_host()
	_lobby_client()
	await _lobby_layout()
	await _lobby_rules()
	# (the sounds the lobby played end before the runner quits)
	await t.get_tree().create_timer(0.6).timeout
	_cleanup()


# ---------------------------------------------------------------- files

func _doc(nm: String) -> LevelDoc:
	var d := LevelTemplates.make("oval", nm)
	d.data["author"] = "Tester"
	return d


func _write(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	made.append(path)


func _make_files() -> void:
	dir = str(t.tmp("servers"))
	# a clean folder each run
	for sub in ["", "/.autosave", "/.trash", "/.history/x", "/cache", "/sub"]:
		var d := DirAccess.open(dir + sub)
		if d:
			for f in d.get_files():
				d.remove(f)
	CustomTracks._extra_folders = PackedStringArray()
	CustomTracks.reset()
	for e in [["canal", "canal_run", "Canal Run"], ["docks", "old_docks", "Old Docks"], ["deeper", "sub/deeper", "Deep Cut"]]:
		var b := LevelIO.pack(_doc(e[2]))
		_write("%s/%s.hl2kt" % [dir, e[1]], b)
		shas[e[0]] = LevelIO.sha256(b)
		ids[e[0]] = LevelIO.id_for(shas[e[0]])
	# the hidden folders: never scanned
	var hid := 0
	for sub in [".autosave", ".trash", ".history/x", "cache"]:
		hid += 1
		_write("%s/%s/hidden_%d.hl2kt" % [dir, sub, hid], LevelIO.pack(_doc("Hidden %d" % hid)))
	# a damaged file (its header fine, its sections cut short) and junk
	var good := LevelIO.pack(_doc("Broken Run"))
	_write(dir + "/broken.hl2kt", good.slice(0, good.size() - 7))
	_write(dir + "/junk.hl2kt", "not a track at all".to_utf8_buffer())
	# an own file damaged the same way: the registry only hashes own files, the scan's gate refuses it
	var mine := LevelIO.pack(_doc("P11 Mine Broken"))
	var mp := CustomTracks.mine_dir().path_join("p11_mine_broken.hl2kt")
	_write(mp, mine.slice(0, mine.size() - 7))
	ids["mine_broken"] = LevelIO.id_for(LevelIO.sha256(mine.slice(0, mine.size() - 7)))
	var ok_mine := LevelIO.pack(_doc("P11 Mine Good"))
	_write(CustomTracks.mine_dir().path_join("p11_mine_good.hl2kt"), ok_mine)
	ids["mine_good"] = LevelIO.id_for(LevelIO.sha256(ok_mine))


# ---------------------------------------------------------------- the scan

func _scan() -> void:
	t.check(DedicatedConfig.resolve_track("canal_run") == "", "before the scan the folder's tracks are unknown")
	DedicatedConfig.scan(dir)
	t.check(CustomTracks.folders()[0] == dir, "scan: sv_tracks is the first folder")
	var names := []
	for m in CustomTracks.list("server"):
		names.append(str(m.get("name", "")))
	names.sort()
	t.check(names == ["Canal Run", "Deep Cut", "Old Docks"], "scan: the folder's three tracks, the sub folder too (%s)" % [names])
	t.check(not names.has("Broken Run"), "scan: the damaged file is skipped")
	for i in range(1, 5):
		t.check(CustomTracks.find("Hidden %d" % i) == "", "scan: .autosave / .trash / .history / cache are not scanned (%d)" % i)
	t.check(CustomTracks.has(ids["canal"]) and CustomTracks.has(ids["docks"]) and CustomTracks.has(ids["deeper"]), "scan: ids are the files' hashes")
	t.check(CustomTracks.has(ids["mine_broken"]) and CustomTracks.unusable(ids["mine_broken"]) != "",
		"scan: a damaged own file goes through the gate and is marked unusable (%s)" % CustomTracks.unusable(ids["mine_broken"]))
	t.check(CustomTracks.has(ids["mine_good"]) and CustomTracks.unusable(ids["mine_good"]) == "", "scan: a good own file stays usable")
	var compiled := 0
	for k in ["canal", "docks", "deeper", "mine_good"]:
		if CustomTracks.is_prepared(ids[k]):
			compiled += 1
	t.check(compiled == 0 and not CustomTracks.checking(), "scan: nothing compiled (the server builds only its current and next track)")


# ---------------------------------------------------------------- resolution

func _resolve() -> void:
	var r := DedicatedConfig.resolve_track
	t.check(r.call("canal_run") == ids["canal"], "mp_track by file name")
	t.check(r.call("CANAL_RUN.hl2kt") == ids["canal"], "by file name with the extension, any case")
	t.check(r.call("Old Docks") == ids["docks"] and r.call("old docks") == ids["docks"], "by display name")
	t.check(r.call(ids["deeper"]) == ids["deeper"], "by c_ id")
	t.check(r.call(str(shas["docks"]).left(8)) == ids["docks"], "by sha prefix (8 hex)")
	t.check(r.call(str(shas["docks"]).left(5)) == "", "a sha prefix under 6 hex names nothing")
	t.check(r.call("c_0123456789abcdef") == "", "an unknown c_ id")
	t.check(r.call("nosuch") == "" and r.call("") == "" and r.call("../../x") == "", "unknown names")
	t.check(r.call("broken") == "" and r.call("P11 Mine Broken") == "", "the damaged files name nothing")
	t.check(r.call("c_edit") == "", "c_edit never")
	for tr in Game.TRACKS:
		var want := str(tr["id"]) if Game.track_installed(tr["id"]) else ""
		t.check(r.call(str(tr["id"])) == want and r.call(str(tr["name"]).to_upper()) == want,
			"a circuit by id / name: %s when %s" % [want if want != "" else "refused", "built" if want != "" else "not built"])


## finish(o): the raw track and list resolve after the scan of o.tracks_dir.
func _finish_order() -> void:
	CustomTracks._extra_folders = PackedStringArray()
	CustomTracks.reset()
	t.check(DedicatedConfig.resolve_track("Old Docks") == "", "finish: unknown while the folder is not scanned")
	var o := DedicatedConfig.defaults()
	o["track"] = "Old Docks"
	o["tracks_dir"] = dir
	o["tracklist"] = "canal_run, nosuch, P11 Mine Broken, Old Docks, canal_run"
	DedicatedConfig.finish(o)
	t.check(str(o["track"]) == ids["docks"], "finish: the track resolves after the scan")
	t.check(o["tracklist"] is PackedStringArray and Array(o["tracklist"]) == ["canal_run", "nosuch", "P11 Mine Broken", "Old Docks", "canal_run"],
		"finish: the list kept as written (%s)" % [o["tracklist"]])
	t.check(Array(DedicatedConfig.resolve_list(o["tracklist"])) == [ids["canal"], ids["docks"]],
		"finish: the list resolves with unknown / unusable / repeated entries left out (%s)" % [DedicatedConfig.resolve_list(o["tracklist"])])
	var o2 := DedicatedConfig.defaults()
	o2["track"] = "nosuch"
	DedicatedConfig.finish(o2)
	var fallback := str(DedicatedConfig.defaults()["track"])
	if not Game.track_installed(fallback):
		for tr in Game.TRACKS:
			if Game.track_installed(tr["id"]):
				fallback = tr["id"]
				break
	t.check(str(o2["track"]) == fallback, "finish: a track that names nothing keeps the default (%s)" % o2["track"])
	var o3 := DedicatedConfig.defaults()
	o3["track"] = ids["deeper"]
	DedicatedConfig.finish(o3)
	DedicatedConfig.finish(o3)
	t.check(str(o3["track"]) == ids["deeper"] and (o3["tracklist"] as PackedStringArray).is_empty(), "finish: an id stays, twice is the same")
	# C2 N6: a list and no mp_track / --track: the list's first usable entry, never Highway 17
	var o4 := DedicatedConfig.defaults()
	o4["tracklist"] = "nosuch, P11 Mine Broken, Deep Cut, canal_run"
	DedicatedConfig.finish(o4)
	t.check(str(o4["track"]) == ids["deeper"], "finish: a list without a track starts on its first usable entry (%s)" % o4["track"])
	var o5 := DedicatedConfig.load_options(PackedStringArray(["--tracks", ProjectSettings.globalize_path(dir), "--tracklist", "Old Docks, canal_run"]))
	t.check(str(o5["track"]) == ids["docks"], "flags: --tracklist without --track starts on the list's first entry (%s)" % o5["track"])
	var o6 := DedicatedConfig.load_options(PackedStringArray(["--tracks", ProjectSettings.globalize_path(dir), "--tracklist", "Old Docks, canal_run",
		"--track", str(DedicatedConfig.defaults()["track"])]))
	t.check(str(o6["track"]) != ids["docks"], "flags: a --track given (even the default) wins over the list (%s)" % o6["track"])


## A server.cfg whose mp_track names a custom file above its sv_tracks line; flags win.
func _load_options() -> void:
	CustomTracks._extra_folders = PackedStringArray()
	CustomTracks.reset()
	var cfg: String = t.tmp("p11_server.cfg")
	var f := FileAccess.open(cfg, FileAccess.WRITE)
	f.store_string("\n".join(PackedStringArray([
		"// test",
		"hostname \"P11 test\"",
		"mp_track canal_run      // a custom file, named before its folder",
		"mp_tracklist \"Old Docks, canal_run, nosuch\"",
		"mp_rotate 0",
		"sv_downloads 0          // turned away",
		"sv_download_rate 64",
		"sv_tracks \"%s\"" % ProjectSettings.globalize_path(dir),
		"mp_laps 4",
	])))
	f.close()
	made.append(cfg)
	var o := DedicatedConfig.load_options(PackedStringArray(["--config", cfg]))
	t.check(str(o["track"]) == ids["canal"], "server.cfg: mp_track before sv_tracks resolves (%s)" % o["track"])
	t.check(Array(DedicatedConfig.resolve_list(o["tracklist"])) == [ids["docks"], ids["canal"]], "server.cfg: mp_tracklist (%s)" % [o["tracklist"]])
	t.check(int(o["rotate"]) == 0 and int(o["downloads"]) == 0 and int(o["download_rate"]) == 64, "server.cfg: mp_rotate, sv_downloads, sv_download_rate")
	t.check(str(o["tracks_dir"]) == ProjectSettings.globalize_path(dir) and str(o["name"]) == "P11 test" and int(o["laps"]) == 4, "server.cfg: sv_tracks, hostname, mp_laps")
	var o2 := DedicatedConfig.load_options(PackedStringArray(["--config", cfg, "--track", str(shas["deeper"]).left(10),
		"--tracklist", "Deep Cut,Old Docks", "--tracks", ProjectSettings.globalize_path(dir)]))
	t.check(str(o2["track"]) == ids["deeper"], "flags: --track by sha prefix wins over the file")
	t.check(Array(DedicatedConfig.resolve_list(o2["tracklist"])) == [ids["deeper"], ids["docks"]], "flags: --tracklist")
	var d := DedicatedConfig.defaults()
	t.check(str(d["tracks_dir"]) == "" and int(d["downloads"]) == 1 and int(d["download_rate"]) == 192 and int(d["rotate"]) == 1
		and (d["tracklist"] as PackedStringArray).is_empty(), "defaults: the five keys (6.8)")
	for cv in ["sv_tracks", "sv_downloads", "sv_download_rate", "mp_tracklist", "mp_rotate"]:
		t.check(DedicatedConfig.CVARS.has(cv) and str(DedicatedConfig.CVARS[cv]) in TrackShare.SERVER_KEYS, "cvar %s maps to a server key" % cv)
	t.check(DedicatedConfig.FLAGS.get("--tracks") == "tracks_dir" and DedicatedConfig.FLAGS.get("--tracklist") == "tracklist", "flags --tracks / --tracklist")


func _set_option() -> void:
	var o := {"track": ids["docks"]}
	t.check(DedicatedConfig.set_option(o, "track", "canal run") and str(o["track"]) == ids["canal"], "set mp_track: a display name at once")
	t.check(not DedicatedConfig.set_option(o, "track", "nosuch") and str(o["track"]) == ids["canal"], "set mp_track: unknown refused, kept")
	t.check(DedicatedConfig.set_option(o, "tracklist", "deep cut, canal_run") and Array(o["tracklist"]) == ["deep cut", "canal_run"]
		and Array(DedicatedConfig.resolve_list(o["tracklist"])) == [ids["deeper"], ids["canal"]], "set mp_tracklist: kept as written, resolves")
	t.check(DedicatedConfig.set_option(o, "downloads", "off") and int(o["downloads"]) == 0, "set sv_downloads off")
	t.check(not DedicatedConfig.set_option(o, "downloads", "maybe"), "sv_downloads: a bad value")
	t.check(not DedicatedConfig.set_option(o, "download_rate", "fast") and not DedicatedConfig.set_option(o, "download_rate", "0"), "sv_download_rate: bad values")
	t.check(DedicatedConfig.set_option(o, "rotate", "on") and int(o["rotate"]) == 1, "set mp_rotate on")


# ---------------------------------------------------------------- rotation

func _rotation() -> void:
	var n := FakeNet.new()
	var s := TrackShare.new()
	s.net = n
	var o := DedicatedConfig.defaults()
	o["tracklist"] = "Old Docks, canal_run, Deep Cut"
	o["tracks_dir"] = dir
	DedicatedConfig.finish(o)
	s.configure(o)
	n.cfg["track"] = ids["docks"]
	t.check(s.next_track() == ids["canal"], "rotation: the next entry")
	CustomTracks.mark_unusable(ids["canal"], "test: unusable")
	t.check(s.next_track() == ids["deeper"], "rotation: an unusable entry is skipped")
	t.check(s.rotate() and str(n.cfg["track"]) == ids["deeper"], "rotate(): set_rule with the next usable entry")
	t.check(s.next_track() == ids["docks"], "rotation: round to the first")
	s.set_option("rotate", 0)
	t.check(not s.rotate() and str(n.cfg["track"]) == ids["deeper"], "mp_rotate 0: no rotation after a race")
	t.check(s.rotate_after_failure() and str(n.cfg["track"]) == ids["docks"], "after a build failure: rotates even with mp_rotate 0")
	CustomTracks.mark_unusable(ids["deeper"], "test: unusable")
	t.check(s.next_track() == "", "rotation: nothing usable left but the current one")
	s.free()
	n.free()
	# the scan's state again (unusable marks undone)
	CustomTracks._extra_folders = PackedStringArray()
	CustomTracks.reset()
	DedicatedConfig.scan(dir)


# ---------------------------------------------------------------- a real dedicated host

func _wait_for(cond: Callable, secs: float) -> bool:
	var until := Time.get_ticks_msec() + int(secs * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < until:
		await t.get_tree().process_frame
	return cond.call()


func _dedicated() -> void:
	for k in CustomTracks.memory_ids():
		CustomTracks.forget(k)
	var o := DedicatedConfig.defaults()
	o["port"] = PORT
	o["lan_only"] = true
	o["tracks_dir"] = dir
	o["track"] = "Old Docks"
	o["tracklist"] = "Old Docks, canal_run, Deep Cut"
	DedicatedConfig.finish(o)
	if Net.host(o, true) != OK:
		t.fail("dedicated: could not host on UDP %d (%s)" % [PORT, Net.last_error])
		return
	var con := DedicatedConsole.new()
	var cur_ok: bool = await _wait_for(func() -> bool: return CustomTracks.is_prepared(ids["docks"]) or CustomTracks.unusable(ids["docks"]) != "", 30.0)
	t.check(cur_ok and CustomTracks.is_prepared(ids["docks"]), "dedicated: the current track compiled (%s)" % CustomTracks.unusable(ids["docks"]))
	t.check(not CustomTracks.is_prepared(ids["canal"]) and not CustomTracks.is_prepared(ids["deeper"]), "dedicated: nothing else before the prefetch")
	con._prefetch()
	var nxt_ok: bool = await _wait_for(func() -> bool: return CustomTracks.is_prepared(ids["canal"]) or CustomTracks.unusable(ids["canal"]) != "", 30.0)
	t.check(nxt_ok and CustomTracks.is_prepared(ids["canal"]), "dedicated: the next rotation entry prefetched")
	await t.frames(3)
	con._prefetch()
	t.check(not CustomTracks.is_prepared(ids["deeper"]) and con._prefetching == "", "dedicated: the third entry is not compiled")
	t.check(CustomTracks.memory_ids().size() <= 3, "dedicated: the memory bound holds (%s)" % [CustomTracks.memory_ids()])
	var lines := DedicatedConsole.tracks_lines()
	var joined := "\n".join(lines)
	t.check(joined.contains(ids["docks"]) and joined.contains("Old Docks") and joined.contains("not compiled yet") and joined.contains("folders:"),
		"console tracks: ids, names, raceable")
	var st := "\n".join(DedicatedConsole.status_lines())
	t.check(st.contains("Old Docks") and st.contains("next") and st.contains("Canal Run"), "console status: the track and the next one")
	t.check(DedicatedConsole.track_state({"track": "get", "dl": 0.42}) == "track 42%"
		and DedicatedConsole.track_state({"track": "fail", "why": "stalled"}) == "track NO (download stalled)"
		and DedicatedConsole.track_state({"track": "fail", "why": "a\u0007b[c]"}) == "track NO (abc)"
		and DedicatedConsole.track_state({"track": "ok"}) == "track ok", "console status: track states (reasons cut and stripped)")
	con._command("next")
	t.check(str(Net.cfg.get("track")) == ids["canal"], "console next: the next entry")
	con._command("track Deep Cut")
	t.check(str(Net.cfg.get("track")) == ids["deeper"], "console track <name>")
	con._command("set mp_track nosuch")
	t.check(str(Net.cfg.get("track")) == ids["deeper"], "console set mp_track: unknown refused")
	con._command("set mp_track old_docks")
	t.check(str(Net.cfg.get("track")) == ids["docks"], "console set mp_track: a file name")
	con._command("set mp_rotate 0")
	t.check(not Net.share.rotate_on and not Net.cfg.has("rotate"), "console set mp_rotate: a server setting, not a rule")
	con._command("set sv_downloads 0")
	t.check(not Net.share.downloads, "console set sv_downloads 0")
	Net.share.downloads = true
	# C2 N8: the query reply names a custom track's author, and stays one datagram
	var info := Net.server_info()
	t.check(int(info.get("cu", 0)) == 1 and str(info.get("mau", "")) == "Tester" and str(info.get("map", "")) == "Old Docks",
		"server_info: a custom track's name and author (%s / %s)" % [info.get("map"), info.get("mau")])
	t.check(("I" + JSON.stringify(info)).to_utf8_buffer().size() < 1200, "server_info: the reply fits one datagram")
	await _rescan(con)
	# during a race a track waits for the lobby
	Net.state = "race"
	con._command("track canal_run")
	t.check(str(Net.cfg.get("track")) == ids["docks"] and Net.share.pending_track == ids["canal"], "console track during a race: after it")
	Net.state = "lobby"
	Net.share.pending_track = ""
	con.free()
	# the track changes started the server's own compiles: let them land before leaving
	await _wait_for(func() -> bool: return CustomTracks._prep.is_empty(), 30.0)
	Net.leave()
	for k in CustomTracks.memory_ids():
		CustomTracks.forget(k)
	t.check(not Net.active and not Net.dedicated, "dedicated: left")


## C2 N7: files added or replaced while the dedicated server runs: `rescan`, `track` and the
## rotation find them, and a track rule on a replaced file's old id follows it to the new one.
func _rescan(con: DedicatedConsole) -> void:
	var p := dir + "/swap_me.hl2kt"
	var a := LevelIO.pack(_doc("Swap Me"))
	var old_id := LevelIO.id_for(LevelIO.sha256(a))
	_write(p, a)
	t.check(DedicatedConfig.resolve_track("swap_me") == "", "rescan: a new file is unknown before a rescan")
	con._command("rescan")
	t.check(DedicatedConfig.resolve_track("swap_me") == old_id, "console rescan: the new file is found")
	DirAccess.remove_absolute(p)
	var p2 := dir + "/brand_new.hl2kt"
	var bn := LevelIO.pack(_doc("Brand New"))
	_write(p2, bn)
	con._command("track brand_new")
	t.check(str(Net.cfg.get("track")) == LevelIO.id_for(LevelIO.sha256(bn)), "console track: a file added while it runs (%s)" % Net.cfg.get("track"))
	# swap_me back, raced, then replaced on disk
	_write(p, a)
	con._command("track swap_me")
	t.check(str(Net.cfg.get("track")) == old_id and not Net.share.pkg.is_empty(), "console track: the file before the swap")
	var d := _doc("Swap Me")
	d.data["author"] = "Someone Else"
	var b := LevelIO.pack(d)
	var new_id := LevelIO.id_for(LevelIO.sha256(b))
	if b.size() == a.size():
		await t.get_tree().create_timer(1.1).timeout   # (the scan re-reads a file whose size or second changed)
	_write(p, b)
	t.check(new_id != old_id, "rescan: the replaced file has a new id")
	Net.set_rule("track", old_id)
	t.check(str(Net.cfg.get("track")) == new_id and str(Net.share.pkg.get("id", "")) == new_id and Net.cfg.get("custom") is Dictionary
		and str(Net.cfg["custom"].get("sha", "")) == LevelIO.sha256(b), "track rule on a replaced file: followed to its new id (%s)" % Net.cfg.get("track"))
	# the rotation follows the entry as written
	var was_list := Net.share.tracklist
	Net.share.tracklist = PackedStringArray(["Old Docks", "swap_me"])
	Net.set_rule("track", ids["docks"])
	var c := LevelIO.pack(_doc("Swap Me Again"))
	if c.size() == b.size():
		await t.get_tree().create_timer(1.1).timeout
	_write(p, c)
	t.check(Net.share.rotate_after_failure() and str(Net.cfg.get("track")) == LevelIO.id_for(LevelIO.sha256(c)),
		"rotation: a list entry follows its file to the new id (%s)" % Net.cfg.get("track"))
	await _wait_for(func() -> bool: return CustomTracks._prep.is_empty(), 30.0)
	DirAccess.remove_absolute(p)
	DirAccess.remove_absolute(p2)
	con._command("rescan")
	t.check(DedicatedConfig.resolve_track("swap_me") == "" and DedicatedConfig.resolve_track("brand_new") == "", "console rescan: removed files are gone")
	Net.share.tracklist = was_list
	Net.set_rule("track", ids["docks"])


# ---------------------------------------------------------------- UI helpers

func _ui_helpers() -> void:
	var tc := Label.new()
	Lobby.fill_track_cell(tc, {"track": "get", "dl": 0.42})
	t.check(tc.text == "42%", "lobby TRACK: 42%")
	Lobby.fill_track_cell(tc, {"track": "prep"})
	t.check(tc.text == "PREP", "lobby TRACK: PREP")
	Lobby.fill_track_cell(tc, {"track": "ok"})
	t.check(tc.text.ends_with("OK"), "lobby TRACK: OK")
	Lobby.fill_track_cell(tc, {"track": "fail", "why": "stalled"})
	t.check(tc.text == "NO TRACK" and tc.tooltip_text == "No track: download stalled", "lobby TRACK: NO TRACK with the reason")
	Lobby.fill_track_cell(tc, {})
	t.check(tc.text == "...", "lobby TRACK: no report yet")
	tc.free()
	# CREATE SERVER / the lobby's dropdown: by id, MY TRACKS after a separator, unusable disabled
	var got := []
	var o := CreateServer.track_dropdown(ids["mine_good"], func(id: String): got.append(id))
	t.check(CreateServer.picked(o) == ids["mine_good"], "dropdown: a custom pick selected by id (never Highway 17)")
	var sep := -1
	var broken := -1
	for i in o.item_count:
		if o.is_item_separator(i):
			sep = i
		if o.get_item_metadata(i) is String and str(o.get_item_metadata(i)) == ids["mine_broken"]:
			broken = i
	t.check(sep == Game.TRACKS.size() and o.get_item_text(sep) == CreateServer.SEPARATOR, "dropdown: the circuits, then MY TRACKS")
	t.check(broken > sep and o.is_item_disabled(broken), "dropdown: an unusable own track is disabled")
	for i in Game.TRACKS.size():
		if o.is_item_disabled(i) == Game.track_installed(Game.TRACKS[i]["id"]):
			t.check(false, "dropdown: %s disabled only when not built" % Game.TRACKS[i]["id"])
	o.item_selected.emit(0)
	t.check(got == [Game.TRACKS[0]["id"]], "dropdown: a pick gives its id")
	# (the pick's click sound ends before the runner quits)
	await t.get_tree().create_timer(0.5).timeout
	CreateServer.select_track(o, ids["docks"])
	t.check(CreateServer.picked(o) == ids["docks"], "dropdown: a custom track missing from the lists is added for it")
	o.free()
	# CREATE SERVER through HOST: EditorSession.host_track, used once
	var ses := EditorSession.current()
	var was_host := ses.host_track
	ses.host_track = ids["mine_good"]
	var cs := CreateServer.new()
	t.add_child(cs)
	t.check(cs.track_id == ids["mine_good"] and CreateServer.picked(cs.track_pick) == ids["mine_good"], "CREATE SERVER: HOST's track picked")
	t.check(ses.host_track == "", "CREATE SERVER: host_track cleared after use")
	cs.free()
	ses.host_track = was_host
	# the browser: the TRACK cell and the CUSTOM TRACK line, against hostile replies
	var have := {"cu": 1, "map": "Canal Run", "mau": "Sasha", "msha": str(shas["canal"]).left(16), "mkb": 1434}
	t.check(ServerBrowser.custom_line(have) == "CUSTOM TRACK: Canal Run  by Sasha  ·  you have it", "browser: you have it (%s)" % ServerBrowser.custom_line(have))
	var need := {"cu": 1, "map": "Far Away", "msha": "0123456789abcdef", "mkb": 1434}
	t.check(ServerBrowser.custom_line(need) == "CUSTOM TRACK: Far Away  ·  1.4 MB download", "browser: the download size (%s)" % ServerBrowser.custom_line(need))
	t.check(ServerBrowser.custom_line({"map": "Highway 17"}) == "" and ServerBrowser.track_cell({"map": "Highway 17"}) == "Highway 17", "browser: a circuit")
	t.check(ServerBrowser.track_cell({"cu": 1, "map": "Canal\u0007 [b]Run[/b]"}) == "Canal bRun/b  (custom)", "browser: names cut and stripped (%s)" % ServerBrowser.track_cell({"cu": 1, "map": "Canal\u0007 [b]Run[/b]"}))
	t.check(ServerBrowser.custom_line({"cu": "1", "map": "x"}) == "" and ServerBrowser.custom_line({"cu": [1]}) == "", "browser: a non-number cu is no custom track")
	t.check(not ServerBrowser.have_track({"msha": "../../etc/passwd"}) and not ServerBrowser.have_track({"msha": ["x"]}), "browser: a hostile msha")
	t.check(ServerBrowser.custom_line({"cu": 1, "map": "x", "msha": "zz", "mkb": [5]}).ends_with("1 KB download"), "browser: a hostile mkb")
	t.check(ServerBrowser.custom_line({"cu": 1, "map": "x", "mkb": 1e12}).ends_with("16.0 MB download"), "browser: a huge mkb is capped")
	# C2 N9: a track to download is orange, but never on the selected (orange) row
	t.check(ServerBrowser.track_color(need, false) == UiKit.ORANGE and ServerBrowser.track_color(need, true) == UiKit.TEXT
		and ServerBrowser.track_color(have, false) == UiKit.TEXT and ServerBrowser.track_color({"map": "Highway 17"}, false) == UiKit.TEXT,
		"browser: the TRACK colour (orange only for a download, never on the selected row)")


## The host's lobby on a custom track (a listen server, UDP 27308): the track picked by id in the
## rules, START RACE disabled with the reason while the host's own build is prepared, then enabled.
func _lobby_host() -> void:
	for k in CustomTracks.memory_ids():
		CustomTracks.forget(k)
	if Net.host({"port": 27308, "lan_only": true, "upnp": false, "bots": true, "track": ids["docks"]}) != OK:
		t.fail("lobby host: could not host on UDP 27308 (%s)" % Net.last_error)
		return
	var lobby := Lobby.new()
	t.add_child(lobby)
	lobby._update_status()
	var prepared := CustomTracks.is_prepared(ids["docks"])
	t.check(prepared or (lobby.start_button.disabled and lobby.start_button.tooltip_text == "Preparing the track..."
		and lobby.status_label.text == "Preparing the track..."), "lobby host: START disabled while the track is prepared (%s)" % lobby.start_button.tooltip_text)
	t.check(lobby.track_dd != null and CreateServer.picked(lobby.track_dd) == ids["docks"], "lobby host: the rules' dropdown shows the custom track")
	t.check(lobby.sub_label.text.begins_with("Old Docks  by Tester  ·  CUSTOM"), "lobby host: the sub line (%s)" % lobby.sub_label.text)
	await _wait_for(func() -> bool: return CustomTracks.is_prepared(ids["docks"]) and str(Net.players[1].get("track")) == "ok", 30.0)
	lobby._update_status()
	t.check(not lobby.start_button.disabled and lobby.start_button.tooltip_text == "", "lobby host: START enabled once the host has it (%s)" % lobby.start_button.tooltip_text)
	t.check(lobby._track_cells.has(1) and (lobby._track_cells[1] as Label).text.ends_with("OK"), "lobby host: the host's own row OK")
	t.check(lobby.status_label.text == "Everyone is ready: press START RACE.", "lobby host: the host is not counted as waiting (%s)" % lobby.status_label.text)
	lobby.free()
	Net.leave()
	for k in CustomTracks.memory_ids():
		CustomTracks.forget(k)


## A friend's lobby on a custom track, without a socket: Net looks like a client for the length of
## the (synchronous) checks; the own download row is driven through TrackShare's local state.
func _lobby_client() -> void:
	var was := {"cfg": Net.cfg, "players": Net.players, "active": Net.active, "server": Net.is_server, "state": Net.state}
	var cid: String = ids["canal"]
	var ch: String = Game.CHARACTERS[0]["id"]
	var vh: String = Game.VEHICLES[0]["id"]
	Net.cfg = {"name": "P11 lobby", "track": cid, "laps": 3, "difficulty": 1, "bots": false, "grid": 8, "max_players": 8,
		"custom": {"sha": shas["canal"], "size": 1468006, "name": "Canal Run", "author": "Sasha"}}
	Net.players = {
		1: {"nick": "Me", "character": ch, "vehicle": vh, "ready": false, "ping": 30, "track": "get", "why": "", "dl": 0.42, "missing": 0},
		7: {"nick": "Host", "character": ch, "vehicle": vh, "ready": false, "ping": 0, "host": true, "track": "ok", "why": "", "dl": 1.0, "missing": 0},
		9: {"nick": "Vance", "character": ch, "vehicle": vh, "ready": true, "ping": 40, "track": "fail", "why": "stalled", "dl": 0.3, "missing": 0},
	}
	var lobby := Lobby.new()
	t.add_child(lobby)
	Net.active = true
	Net.is_server = false
	Net.state = "lobby"
	Net.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()   # my_id() 1
	var sh: TrackShare = Net.share
	sh._local = sh._blank_local()
	var loc := {"key": "c:" + str(shas["canal"]), "sha": shas["canal"], "id": cid, "state": "get", "dl": 0.42, "name": "Canal Run", "size": 1468006}
	for k in loc:
		sh._local[k] = loc[k]
	sh._hist = [[0.0, 0], [3.0, 600000]]
	lobby._on_cfg()
	t.check(lobby.sub_label.text.begins_with("Canal Run  by Sasha  ·  CUSTOM  ·  3 laps"), "lobby: the custom sub line (%s)" % lobby.sub_label.text)
	t.check(lobby.dl_row.visible and lobby.dl_label.text == "DOWNLOADING CANAL RUN  ·  1.4 MB" and lobby.dl_pct.visible
		and lobby.dl_pct.text == "42%  ·  5 s LEFT" and is_equal_approx(lobby.dl_bar.value, 0.42)
		and lobby.dl_label.tooltip_text == "DOWNLOADING CANAL RUN  ·  1.4 MB  ·  42%  ·  5 s LEFT",
		"lobby: the own download with size, percent and time left (%s | %s)" % [lobby.dl_label.text, lobby.dl_pct.text])
	var c9: Label = lobby._track_cells.get(9)
	var c7: Label = lobby._track_cells.get(7)
	t.check(c9 != null and c9.text == "NO TRACK" and c9.tooltip_text.contains("download stalled") and c7 != null and c7.text.ends_with("OK"),
		"lobby: the TRACK column of every row")
	t.check(lobby.track_line() == "Waiting for 1 player to get the track.", "lobby: a friend's status line (%s)" % lobby.track_line())
	Net.players[9]["track"] = "get"
	Net.players[9]["dl"] = 0.8
	lobby._on_progress(9, "get", 0.8)
	t.check(lobby._track_cells.get(9) == c9 and c9.text == "80%", "lobby: progress updates the cell in place")
	sh._local["state"] = "prep"
	lobby._show_local()
	t.check(lobby.dl_row.visible and lobby.dl_label.text == "PREPARING TRACK..." and not lobby.dl_pct.visible, "lobby: PREPARING TRACK...")
	sh._local["state"] = "fail"
	sh._local["code"] = "stalled"
	sh._local["why"] = TrackShare.TEXT_STALLED
	lobby._show_local()
	t.check(lobby.dl_row.visible and lobby.dl_label.text == TrackShare.TEXT_STALLED and lobby.retry_button.visible and lobby.retry_button.text == "RETRY",
		"lobby: a failure gives the reason and RETRY")
	lobby.retry_button.grab_focus()
	lobby._show_local()
	lobby._show_local()
	t.check(lobby.get_viewport().gui_get_focus_owner() == lobby.retry_button, "lobby: RETRY keeps the focus across refreshes")
	# C2 N5: past the RETRY limit the reason says to ask the host and RETRY goes
	sh._retries[str(shas["canal"])] = {"n": TrackShare.RETRY_MAX, "t": -INF, "code": "", "why": ""}
	lobby._show_local()
	t.check(lobby.dl_label.text == TrackShare.TEXT_RETRY_MAX % TrackShare.RETRY_MAX and not lobby.retry_button.visible,
		"lobby: past the RETRY limit, no RETRY (%s)" % lobby.dl_label.text)
	sh._retries.clear()
	sh._local["code"] = "downloads off"
	sh._local["why"] = TrackShare.TEXT_OFF
	lobby._show_local()
	t.check(lobby.retry_button.text == "DOWNLOAD" and lobby._ask_box != null and is_instance_valid(lobby._ask_box)
		and lobby._ask_box.text_label.text.contains("CANAL RUN by Sasha") and lobby._ask_box.text_label.text.contains("1.4 MB"),
		"lobby: downloads off asks DOWNLOAD IT?")
	var box := lobby._ask_box
	lobby._show_local()
	t.check(lobby._ask_box == box, "lobby: DOWNLOAD IT? once per track")
	sh._local["state"] = "ok"
	sh._local["code"] = ""
	lobby._show_local()
	t.check(not lobby.dl_row.visible and not lobby._fetching, "lobby: the row goes when the track is ready")
	t.check(not lobby.keep_button.visible, "lobby: KEEP TRACK only for a cached download (this one is a server folder's)")
	Net.multiplayer.multiplayer_peer = null
	Net.active = was["active"]
	Net.is_server = was["server"]
	Net.state = was["state"]
	Net.cfg = was["cfg"]
	Net.players = was["players"]
	sh._local = sh._blank_local()
	sh._hist = []
	lobby.free()


## ui_fit's rule on a friend's lobby that ui_fit never shows: a full roster with TRACK columns
## (KICK too, as the host sees it) and the download row with RETRY, the thumbnail and KEEP TRACK, at
## a 1600 x 900 canvas: nothing outside the window, nothing squeezed.
func _lobby_layout() -> void:
	var root: Window = t.get_tree().root
	var was_size := root.size
	var was_players := Net.players
	root.size = Vector2i(1280, 720)
	await t.frames(2)
	var ch: String = Game.CHARACTERS[0]["id"]
	var vh: String = Game.VEHICLES[0]["id"]
	var ps := {}
	for i in 8:
		ps[i + 1] = {"nick": "Player With A Long Name %d" % i, "character": ch, "vehicle": vh, "ready": i % 2 == 0, "ping": 999,
			"host": i == 0, "track": ["get", "prep", "ok", "fail", "?", "need", "ok", "get"][i], "why": "stalled", "dl": 0.42, "missing": 3}
	Net.players = ps
	var lobby := Lobby.new()
	t.add_child(lobby)
	lobby.set_process(false)
	lobby.sub_label.text = "A Track Name That Is Forty-Eight Characters Long  by Twenty-Four Character Nm  ·  CUSTOM  ·  9 laps  ·  Hard  ·  bots fill the grid to 8"
	lobby.dl_row.visible = true
	lobby.dl_bar.visible = true
	lobby.retry_button.visible = true
	lobby.keep_button.visible = true
	var img := Image.create(64, 40, false, Image.FORMAT_RGB8)
	lobby.dl_thumb.texture = ImageTexture.create_from_image(img)
	lobby.dl_thumb.visible = true
	lobby.dl_label.text = "DOWNLOADING A TRACK NAME THAT IS FORTY-EIGHT CHARACTERS LONG  ·  16.0 MB  ·  99%  ·  120 s LEFT"
	# the host's view of the rows: a KICK on each
	Net.is_server = true
	lobby._rebuild_players()
	Net.is_server = false
	await t.frames(4)
	var vr := lobby.get_viewport().get_visible_rect()
	var bad := []
	var seen := 0
	for c in lobby.find_children("*", "Control", true, false):
		var ctl := c as Control
		if not ctl.is_visible_in_tree() or ctl is ScrollBar or _in_scroll(ctl):
			continue
		seen += 1
		var r := ctl.get_global_rect()
		if r.size.x < 1 or r.size.y < 1:
			continue
		if not vr.grow(1.0).encloses(r) and r.intersects(vr):
			bad.append("OUTSIDE %s %s" % [ctl.name, r])
		var m := ctl.get_combined_minimum_size()
		if ctl is Label and (ctl as Label).clip_text:
			m.x = 0
		if ctl.size.x + 1 < m.x or ctl.size.y + 1 < m.y:
			bad.append("SQUEEZED %s %s < %s" % [ctl.name, ctl.size, m])
	t.check(vr.size == Vector2(1600, 900), "lobby layout: a 1600 x 900 canvas (%s)" % vr.size)
	t.check(bad.is_empty() and seen > 60 and lobby._track_cells.size() == 8,
		"lobby layout: a full lobby with a download fits (%d controls; %s)" % [seen, bad.slice(0, 6)])
	lobby.free()
	Net.players = was_players
	root.size = was_size
	await t.frames(2)


## C2 N2 / N3 / N11 at a 1600 x 900 canvas, a full roster: the Track rule first and every rule
## inside the RULES box (host and friend, the friend with the download row), its scroll bar wider
## than 0 px, the friend's percent and time left never clipped, and the ping / READY / TRACK / KICK
## cells in the same columns on every row (the host's own row has no KICK).
func _lobby_rules() -> void:
	var root: Window = t.get_tree().root
	var was := {"size": root.size, "players": Net.players, "cfg": Net.cfg, "server": Net.is_server}
	root.size = Vector2i(1280, 720)
	await t.frames(2)
	var ch: String = Game.CHARACTERS[0]["id"]
	var vh: String = Game.VEHICLES[0]["id"]
	var ps := {}
	for i in 8:
		ps[i + 1] = {"nick": "Player %d" % i, "character": ch, "vehicle": vh, "ready": i % 2 == 0, "ping": 999,
			"host": i == 0, "track": ["ok", "get", "fail", "prep", "?", "need", "ok", "get"][i], "why": "stalled", "dl": 0.42, "missing": 0}
	Net.players = ps
	Net.cfg = {"name": "P11 rules", "track": ids["canal"], "laps": 3, "difficulty": 1, "bots": true, "grid": 8, "max_players": 8,
		"custom": {"sha": shas["canal"], "size": 1468006, "name": "Canal Run", "author": "Sasha"}}
	for host in [true, false]:
		Net.is_server = host
		var lobby := Lobby.new()
		t.add_child(lobby)
		lobby.set_process(false)
		var who := "host" if host else "friend"
		if not host:
			lobby.dl_row.visible = true
			lobby.dl_bar.visible = true
			lobby.dl_pct.visible = true
			lobby.dl_label.text = "DOWNLOADING A TRACK NAME THAT IS FORTY-EIGHT CHARACTERS LONG  ·  16.0 MB"
			lobby.dl_pct.text = "42%  ·  120 s LEFT"
		await t.frames(4)
		var view := lobby.rscroll.get_global_rect()
		var rows := lobby.rules_box.get_children()
		t.check((rows[0].get_child(0) as Label).text == "Track", "lobby %s: the Track rule comes first" % who)
		var out := []
		for r in rows:
			if not view.grow(0.5).encloses((r as Control).get_global_rect()):
				out.append((r.get_child(0) as Label).text)
		t.check(out.is_empty() and view.size.y > 100, "lobby %s: every rule inside the RULES box at 1600 x 900 (%s outside; box %d px)" % [who, out, int(view.size.y)])
		t.check(lobby.rscroll.get_v_scroll_bar().get_combined_minimum_size().x >= 4, "lobby %s: the rules' scroll bar has a width" % who)
		var xs := {}
		for row in lobby.players_box.get_children():
			if row is HBoxContainer:
				var cells: Array = row.get_children()
				for k in [3, 4, 5, 6]:
					if k < cells.size():
						if not xs.has(k):
							xs[k] = {}
						xs[k][int((cells[k] as Control).global_position.x)] = true
		var cols := []
		for k in xs:
			cols.append((xs[k] as Dictionary).size())
		t.check(xs.size() == (4 if host else 3) and cols.max() == 1, "lobby %s: ping / READY / TRACK%s in the same columns on every row (%s)" % [
			who, " / KICK" if host else "", xs])
		if not host:
			var pr := lobby.dl_pct.get_global_rect()
			t.check(lobby.dl_pct.size.x + 0.5 >= lobby.dl_pct.get_combined_minimum_size().x and lobby.dl_row.get_global_rect().grow(0.5).encloses(pr)
				and absf(pr.end.x - lobby.dl_bar.get_global_rect().end.x) < 1.0, "lobby friend: the percent and time left whole, at the bar's end (%s)" % pr)
		lobby.free()
	Net.players = was["players"]
	Net.cfg = was["cfg"]
	Net.is_server = was["server"]
	root.size = was["size"]
	await t.frames(2)


func _in_scroll(c: Node) -> bool:
	var p := c.get_parent()
	while p:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _cleanup() -> void:
	for p in made:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	CustomTracks._extra_folders = _saved["extra"]
	CustomTracks.auto_check = _saved["auto_check"]
	CustomTracks.set_current("")
	CustomTracks.reset()
	Game.settings["allow_downloads"] = _saved["allow"]
	Game.settings["track"] = _saved["track"]
	Game.settings["track_guid"] = _saved["guid"]
