extends RefCounted
## P5: CustomTracks (2.8, 2.9, 5.1, 6.6, C1 S13 / S16 / S17 / S18 / S19) in user://tracks_test/, no
## content: id / sha shapes refused ('../x', 63 hex, c_edit); own files, the index surviving a
## restart (no re-hash), skipped folders, .tmp recovery, trash; KEEP; the cache's LRU in bytes and
## count (parts counted), touch, the current track kept; at most two .part files and the 24 h rule;
## import of a good and of hostile files; header claims never trusted (a file claiming raceable
## with an error is not raceable); the memory bound (a fourth build evicts the oldest
## non-current); prepare (deferred, shared callbacks); worker thumbs and track_thumb_ready;
## history copies (last 5); find; Game.track / track_installed / all_tracks / track_pick with a
## re-saved guid; race_setting ignoring test_drive while Net.active.

const NEEDS_CONTENT := false

var t: Node
var _real := false      # the compiler is real (a blank doc reports no_road)


func run(t_: Node) -> void:
	t = t_
	var saved := [CustomTracks.auto_check, CustomTracks.cache_max_bytes, CustomTracks.cache_max_files,
		CustomTracks.part_max_age, CustomTracks.time_offset]
	CustomTracks.auto_check = false
	_wipe(CustomTracks.mine_dir())
	CustomTracks.reset()
	_real = LevelCompiler.compile(LevelDoc.blank("x", 512.0, 257)).report.errors() > 0
	t.log("compiler: %s" % ("real" if _real else "stub (facts checks limited)"))
	_shapes()
	_own_files()
	_cache()
	_parts()
	_imports()
	_claims()
	_memory()
	await _prepare()
	await _thumbs()
	_history()
	_find()
	_game_wiring()
	CustomTracks.auto_check = saved[0]
	CustomTracks.cache_max_bytes = saved[1]
	CustomTracks.cache_max_files = saved[2]
	CustomTracks.part_max_age = saved[3]
	CustomTracks.time_offset = saved[4]
	_wipe(CustomTracks.mine_dir())
	CustomTracks.reset()


# ---------------------------------------------------------------- helpers

## A small closed loop (512 m world) named nm.
func _doc(nm: String, closed := true, points := 4) -> LevelDoc:
	var d := LevelDoc.blank(nm, 512.0, 257)
	var pts := []
	for i in points:
		var a := TAU * i / maxf(points, 1)
		pts.append({"uid": d.new_uid(), "pos": [120.0 * cos(a), 0.0, 120.0 * sin(a)], "width": 14.0,
			"style": "asphalt", "seesaw": false, "follow": false})
	d.data["road"] = {"closed": closed and points >= 3, "start": {"p": int(pts[0].uid) if points > 0 else 0, "t": 0.0},
		"points": pts}
	d.data["author"] = "Tester"
	return d


func _save(d: LevelDoc, p: String, extra := {}) -> String:
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var err := LevelIO.save(d, p, extra)
	t.check(err == OK, "saved %s" % p.get_file())
	return p


func _facts(raceable := true, errors := 0) -> Dictionary:
	return {"raceable": raceable, "errors": errors, "warnings": 1, "length": 754.0, "branches": 0, "props": 0,
		"hazards": 0}


func _sha_like(seed_s: String) -> String:
	return seed_s.sha256_text()


func _wipe(dir: String) -> void:
	if not dir.begins_with("user://tracks_test"):
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.include_hidden = true
	for f in d.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in d.get_directories():
		_wipe(dir.path_join(sub))
		DirAccess.remove_absolute(dir.path_join(sub))


func _until(cond: Callable, seconds: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > int(seconds * 1000.0):
			return false
		await t.frames(1)
	return true


# ---------------------------------------------------------------- shapes (2.9, 6.9)

func _shapes() -> void:
	var hex16 := "0123456789abcdef"
	t.check(CustomTracks.valid_id("c_" + hex16), "valid_id: c_ + 16 hex")
	for bad in ["c_edit", "c_" + hex16.to_upper(), "c_" + hex16.left(15), "c_" + hex16 + "0", "../x", "c_../../x",
			"d_" + hex16, "", "c_0123456789abcdeg", "c_" + hex16.left(14) + "/x"]:
		t.check(not CustomTracks.valid_id(bad), "valid_id refuses %s" % bad.c_escape())
	t.check(CustomTracks.is_custom("c_edit") and CustomTracks.is_custom("c_" + hex16) and not CustomTracks.is_custom("ct17"),
		"is_custom: begins with c_")
	var sha := _sha_like("a")
	t.check(CustomTracks.cache_part("../x") == "", "cache_part refuses ../x")
	t.check(CustomTracks.cache_part(sha.left(63)) == "", "cache_part refuses 63 hex")
	t.check(CustomTracks.cache_part(sha.to_upper()) == "", "cache_part refuses upper-case hex")
	t.check(CustomTracks.cache_part("../" + sha.left(61)) == "", "cache_part refuses a path of 64 chars")
	var cp := CustomTracks.cache_part(sha)
	t.check(cp == CustomTracks.cache_dir().path_join(sha + ".part"), "cache_part: cache/<sha>.part")
	t.check(CustomTracks.path("../x") == "" and CustomTracks.path("c_" + sha.left(15)) == "", "path refuses other shapes")
	t.check(CustomTracks.path(CustomTracks.EDIT_ID) == "", "path: c_edit has no file")
	t.check(CustomTracks.id_for(sha.left(63)) == "" and CustomTracks.id_for(sha) == "c_" + sha.left(16), "id_for: shapes")
	t.check(CustomTracks.meta("../x").is_empty() and not CustomTracks.has("../x"), "meta / has refuse other shapes")
	t.check(CustomTracks.mine_dir() == "user://tracks_test", "test runs use user://tracks_test")
	t.check(CustomTracks.cache_dir() == "user://tracks_test/cache", "the cache lives in the tracks folder")
	t.check(CustomTracks.folders()[-1] == CustomTracks.mine_dir(), "folders: mine last")


# ---------------------------------------------------------------- own files, index, skips, trash

func _own_files() -> void:
	var md := CustomTracks.mine_dir()
	var a := _doc("Canal Run")
	var b := _doc("Old Docks")
	var pa := _save(a, md + "/canal_run.hl2kt")
	var pb := _save(b, md + "/old_docks.hl2kt")
	# copies in the folders a scan skips
	for sub in [".autosave", ".trash", ".history/" + str(a.data.guid), "cache"]:
		_save(_doc("Skip " + sub.get_file()), md + "/" + sub + "/skip_me.hl2kt")
	var ida := CustomTracks.note_saved(pa, _facts())
	t.check(CustomTracks.valid_id(ida) and ida == LevelIO.id_for(LevelIO.file_sha256(pa)), "note_saved: the id of the file's bytes")
	CustomTracks.refresh()
	var mine := CustomTracks.list("mine")
	t.check(mine.size() == 2, "list mine: the two own files only (skipped folders), got %d" % mine.size())
	var ma := CustomTracks.meta(ida)
	t.check(str(ma.get("name")) == "Canal Run" and str(ma.get("author")) == "Tester" and bool(ma.get("custom")),
		"meta: name, author, custom")
	t.check(str(ma.get("kind")) == "mine" and not bool(ma.get("downloaded")) and str(ma.get("path")) == pa, "meta: kind mine, path")
	t.check(bool(ma.get("raceable")) and bool(ma.get("checked")) and int(ma.get("warnings")) == 1, "meta: the local facts")
	t.check(str(ma.get("guid")) == str(a.data.guid) and CustomTracks.id_for_guid(str(a.data.guid)) == ida, "id_for_guid")
	var idb := LevelIO.id_for(LevelIO.file_sha256(pb))
	var mb := CustomTracks.meta(idb)
	t.check(not mb.is_empty() and not bool(mb.get("checked")) and not bool(mb.get("raceable")),
		"a file never compiled here is not raceable")
	t.check(CustomTracks.has(ida) and CustomTracks.path(ida) == pa, "has / path")
	t.check(CustomTracks.bytes(ida) == FileAccess.get_file_as_bytes(pa), "bytes: the saved file's bytes")
	# a restart: the index keeps the facts (no re-hash, no recompile)
	CustomTracks.reset()
	CustomTracks.refresh()
	t.check(bool(CustomTracks.meta(ida).get("raceable")), "index.json: facts survive a restart")
	t.check(FileAccess.file_exists(md + "/index.json"), "the own index is written")
	# .tmp recovery: a save that stopped between the write and the rename
	var c := _doc("Half Saved")
	var cbytes := LevelIO.pack(c)
	var fa := FileAccess.open(md + "/half_saved.hl2kt.tmp", FileAccess.WRITE)
	fa.store_buffer(cbytes)
	fa.close()
	CustomTracks.refresh()
	var idc := LevelIO.id_for(LevelIO.sha256(cbytes))
	t.check(FileAccess.file_exists(md + "/half_saved.hl2kt") and CustomTracks.has(idc), "refresh recovers a lone .tmp")
	# remove: own tracks go to the trash
	t.check(CustomTracks.remove(idc) == OK, "remove own")
	t.check(not FileAccess.file_exists(md + "/half_saved.hl2kt") and not CustomTracks.has(idc), "removed from mine")
	t.check(FileAccess.file_exists(md + "/.trash/half_saved.hl2kt"), "moved to .trash")
	t.check(CustomTracks.remove("c_" + "f".repeat(16)) == ERR_DOES_NOT_EXIST, "remove: unknown id")


# ---------------------------------------------------------------- the cache (6.6)

## Writes a track's bytes as a download part and adds it to the cache; returns [id, sha, size].
func _download(nm: String, facts := {}) -> Array:
	var b := LevelIO.pack(_doc(nm))
	var sha := LevelIO.sha256(b)
	var part := CustomTracks.cache_part(sha)
	var fa := FileAccess.open(part, FileAccess.WRITE)
	fa.store_buffer(b)
	fa.close()
	var id := CustomTracks.cache_add(sha, part, facts)
	return [id, sha, b.size()]


func _cache() -> void:
	CustomTracks.cache_max_files = 3
	CustomTracks.cache_max_bytes = 512 << 20
	var dls := []
	for i in 3:
		CustomTracks.time_offset = i * 10
		dls.append(_download("Download %d" % i, _facts()))
	t.check(CustomTracks.valid_id(str(dls[0][0])) and not FileAccess.file_exists(CustomTracks.cache_part(str(dls[0][1]))),
		"cache_add: the id, the part renamed")
	t.check(FileAccess.file_exists(CustomTracks.cache_dir().path_join(str(dls[0][1]) + ".hl2kt")), "cache/<sha>.hl2kt")
	var m0 := CustomTracks.meta(str(dls[0][0]))
	t.check(str(m0.get("kind")) == "cache" and bool(m0.get("downloaded")) and not bool(m0.get("kept")), "meta: a cached download")
	t.check(bool(m0.get("raceable")), "cache_add keeps the local facts given")
	t.check(CustomTracks.list("downloaded").size() == 3, "list downloaded: the cache")
	# touch the oldest: the next add evicts the second instead
	CustomTracks.time_offset = 30
	CustomTracks.cache_touch(str(dls[0][1]))
	CustomTracks.time_offset = 40
	dls.append(_download("Download 3"))
	t.check(CustomTracks.has(str(dls[0][0])) and not CustomTracks.has(str(dls[1][0])), "LRU by count: the touched one stays, the oldest goes")
	t.check(not FileAccess.file_exists(CustomTracks.cache_dir().path_join(str(dls[1][1]) + ".hl2kt")), "the evicted file is deleted")
	t.check(CustomTracks.has(str(dls[3][0])), "the new one is in")
	# the current track is never evicted
	CustomTracks.set_current(str(dls[2][0]))
	CustomTracks.time_offset = 50
	CustomTracks.cache_touch(str(dls[0][1]))
	CustomTracks.time_offset = 55
	CustomTracks.cache_touch(str(dls[3][1]))
	CustomTracks.time_offset = 60
	dls.append(_download("Download 4", _facts()))
	t.check(CustomTracks.has(str(dls[2][0])), "the current track is kept although it is the least recently used")
	t.check(not CustomTracks.has(str(dls[0][0])) and CustomTracks.has(str(dls[3][0])) and CustomTracks.has(str(dls[4][0])),
		"the next least recently used goes instead")
	CustomTracks.set_current("")
	# bytes: parts count too
	CustomTracks.cache_max_files = 200
	var sz := int(dls[4][2])
	CustomTracks.cache_max_bytes = sz * 3 + 40
	var part := CustomTracks.cache_part(_sha_like("big part"))
	var fa := FileAccess.open(part, FileAccess.WRITE)
	var pad := PackedByteArray()
	pad.resize(sz + 20)
	fa.store_buffer(pad)
	fa.close()
	CustomTracks.evict()
	t.check(CustomTracks.list("downloaded").size() == 2, "LRU by bytes: a part's bytes push one file out (%d left)" % CustomTracks.list("downloaded").size())
	t.check(FileAccess.file_exists(part), "the part itself stays")
	DirAccess.remove_absolute(part)
	CustomTracks.cache_max_bytes = 512 << 20
	# a part that does not hash to its sha is refused and deleted
	var wrong := _sha_like("wrong")
	var wp := CustomTracks.cache_part(wrong)
	fa = FileAccess.open(wp, FileAccess.WRITE)
	fa.store_buffer(LevelIO.pack(_doc("Not This")))
	fa.close()
	t.check(CustomTracks.cache_add(wrong, wp, {}) == "" and CustomTracks.last_error != "", "cache_add refuses bytes of another sha")
	t.check(not FileAccess.file_exists(wp), "the bad part is deleted")
	t.check(CustomTracks.cache_add("../" + wrong.left(61), wp, {}) == "", "cache_add refuses a bad sha shape")
	# KEEP: into downloaded/, out of the cache, never evicted
	var kid := str(dls[4][0])
	t.check(CustomTracks.keep(kid) == OK, "keep")
	var mk := CustomTracks.meta(kid)
	t.check(str(mk.get("kind")) == "kept" and bool(mk.get("kept")) and str(mk.get("path")).begins_with(CustomTracks.kept_dir() + "/"),
		"kept: in downloaded/ with KEPT")
	t.check(bool(mk.get("raceable")), "kept: the cache's local facts carried over")
	t.check(not FileAccess.file_exists(CustomTracks.cache_dir().path_join(str(dls[4][1]) + ".hl2kt")), "kept: left the cache")
	t.check(CustomTracks.list("kept").size() == 1, "list kept")
	CustomTracks.cache_max_files = 0
	CustomTracks.evict()
	t.check(CustomTracks.has(kid) and CustomTracks.list("downloaded").size() == 1, "evict never touches kept tracks")
	CustomTracks.cache_max_files = 200
	CustomTracks.time_offset = 0
	# the cache index survives a restart
	var d5 := _download("Download 5", _facts())
	CustomTracks.reset()
	CustomTracks.refresh()
	t.check(bool(CustomTracks.meta(str(d5[0])).get("raceable")), "cache/index.json keeps the facts")
	t.check(CustomTracks.remove(str(d5[0])) == OK and not CustomTracks.has(str(d5[0])), "remove: a download leaves the cache")


func _parts() -> void:
	var parts := []
	for i in 3:
		var p := CustomTracks.cache_part(_sha_like("part %d" % i))
		var fa := FileAccess.open(p, FileAccess.WRITE)
		fa.store_buffer(PackedByteArray([1, 2, 3]))
		fa.close()
		parts.append(p)
	CustomTracks.evict()
	var left := 0
	for p in parts:
		if FileAccess.file_exists(p):
			left += 1
	t.check(left == 2, "at most two .part files are kept (%d)" % left)
	CustomTracks.time_offset = 25 * 3600
	CustomTracks.refresh()
	left = 0
	for p in parts:
		if FileAccess.file_exists(p):
			left += 1
	t.check(left == 0, "refresh deletes .part files older than 24 h")
	CustomTracks.time_offset = 0


# ---------------------------------------------------------------- imports (the one gate)

func _imports() -> void:
	var good := _doc("Imported Run")
	var src: String = t.tmp("import_good.hl2kt")
	DirAccess.remove_absolute(src)
	LevelIO.save(good, src)
	var id := CustomTracks.import_file(src)
	t.check(CustomTracks.valid_id(id) and CustomTracks.last_error == "", "import: a good file gives its id")
	var m := CustomTracks.meta(id)
	t.check(str(m.get("kind")) == "kept" and str(m.get("path")).begins_with(CustomTracks.kept_dir() + "/"), "import: into downloaded/")
	t.check(FileAccess.get_file_as_bytes(str(m.get("path"))) == FileAccess.get_file_as_bytes(src), "import: the exact bytes")
	t.check(not bool(m.get("checked")) and not bool(m.get("raceable")), "import: not raceable before a local compile")
	var n0 := CustomTracks.list("kept").size()
	t.check(CustomTracks.import_file(src) == id and CustomTracks.list("kept").size() == n0, "import twice: the same id, no copy")
	# hostile files
	var bad: String = t.tmp("import_bad.hl2kt")
	var cases := {"garbage": "not a track at all".to_utf8_buffer(), "two bytes": PackedByteArray([72, 76])}
	var real := LevelIO.pack(good)
	cases["truncated"] = real.slice(0, real.size() - 7)
	var magic := real.duplicate()
	magic[0] = 88
	cases["bad magic"] = magic
	var long := real.duplicate()
	long.append(0)
	cases["trailing byte"] = long
	for k in cases:
		var fa := FileAccess.open(bad, FileAccess.WRITE)
		fa.store_buffer(cases[k])
		fa.close()
		t.check(CustomTracks.import_file(bad) == "" and CustomTracks.last_error != "", "import refuses %s: %s" % [k, CustomTracks.last_error])
	t.check(CustomTracks.import_file(t.tmp("no_such_file.hl2kt")) == "" and CustomTracks.last_error != "", "import: a missing file")
	t.check(CustomTracks.list("kept").size() == n0, "nothing hostile was stored")


# ---------------------------------------------------------------- header claims (C1 S17)

func _claims() -> void:
	# no road: an error ("no_road") for the real compiler, nothing to race for any
	var liar := _doc("Liar", false, 0)
	var src: String = t.tmp("liar.hl2kt")
	DirAccess.remove_absolute(src)
	LevelIO.save(liar, src, {"raceable": true, "errors": 0, "warnings": 0, "length": 3000.0})
	t.check(bool(LevelIO.read_meta(src).get("raceable")), "the header claims raceable")
	var id := CustomTracks.import_file(src)
	t.check(id != "", "the liar imports")
	t.check(not bool(CustomTracks.meta(id).get("raceable")), "a header's raceable claim is not believed")
	t.check(not Game.track_installed(id), "track_installed: not before a local compile")
	t.check(CustomTracks.build_for(id) == null, "build_for: no road, no build")
	var m := CustomTracks.meta(id)
	t.check(bool(m.get("checked")) and not bool(m.get("raceable")), "the local compile says not raceable")
	if _real:
		t.check(int(m.get("errors")) >= 1, "the local compile counted the error")
	t.check(CustomTracks.unusable(id) != "" and not Game.track_installed(id), "marked unusable")
	# a server folder's file: the same
	var sd: String = t.tmp("server_folder")
	DirAccess.make_dir_recursive_absolute(sd)
	LevelIO.save(_doc("Server Liar", false, 0), sd + "/server_liar.hl2kt", {"raceable": true, "errors": 0})
	CustomTracks.add_folder(sd)
	CustomTracks.refresh()
	var sl := CustomTracks.list("server")
	t.check(sl.size() == 1 and str(sl[0].kind) == "server", "add_folder: a server folder's track is listed")
	t.check(sl.size() == 1 and not bool(sl[0].raceable), "a server file's claims are not believed either")
	t.check(CustomTracks.folders()[0] == sd, "folders: the added folder first")


# ---------------------------------------------------------------- memory (C1 S16)

func _memory() -> void:
	for k in CustomTracks.memory_ids():
		CustomTracks.forget(k)
	CustomTracks.set_current("")
	var ids := []
	for i in 6:
		ids.append("c_%016x" % (0xa0 + i))
	var bs := []
	for i in 6:
		var b := LevelBuild.new()
		b.id = ids[i]
		bs.append(b)
	CustomTracks.set_current(ids[0])
	CustomTracks.put_memory(ids[0], bs[0], {})
	CustomTracks.put_memory(CustomTracks.EDIT_ID, LevelBuild.new(), {"name": "MY TRACK"})
	CustomTracks.put_memory(ids[1], bs[1], {})
	t.check(CustomTracks.memory_ids().size() == 3, "current + c_edit + one")
	CustomTracks.put_memory(ids[2], bs[2], {})
	var mem := CustomTracks.memory_ids()
	t.check(mem.size() == 3 and ids[0] in mem and CustomTracks.EDIT_ID in mem and ids[2] in mem and not ids[1] in mem,
		"a fourth build evicts the oldest non-current")
	t.check(CustomTracks.build_for(ids[2]) == bs[2] and CustomTracks.is_prepared(ids[2]), "build_for: from memory")
	t.check(CustomTracks.has(CustomTracks.EDIT_ID) and str(CustomTracks.meta(CustomTracks.EDIT_ID).get("name")) == "MY TRACK",
		"c_edit: in memory, its meta")
	t.check(Game.track_installed(CustomTracks.EDIT_ID) and str(Game.track(CustomTracks.EDIT_ID).name) == "MY TRACK",
		"Game: c_edit from memory")
	# a track change: the old current is one of the others now; the least recently used goes
	CustomTracks.set_current(ids[3])
	CustomTracks.put_memory(ids[3], bs[3], {})
	mem = CustomTracks.memory_ids()
	t.check(mem.size() == 3 and ids[3] in mem and ids[2] in mem and not ids[0] in mem and CustomTracks.EDIT_ID in mem,
		"set_current: the old current (least recently used) is dropped")
	CustomTracks.put_memory(ids[4], bs[4], {})
	mem = CustomTracks.memory_ids()
	t.check(mem.size() == 3 and ids[4] in mem and not ids[2] in mem and ids[3] in mem, "the bound holds: current + c_edit + 1")
	CustomTracks.mark_unusable(ids[4], "broken")
	t.check(not CustomTracks.is_prepared(ids[4]) and CustomTracks.unusable(ids[4]) == "broken", "mark_unusable drops the build")
	CustomTracks.forget(CustomTracks.EDIT_ID)
	t.check(not CustomTracks.has(CustomTracks.EDIT_ID), "forget")
	t.check(CustomTracks.build_for(CustomTracks.EDIT_ID) == null, "build_for: c_edit only from memory")
	for k in CustomTracks.memory_ids():
		CustomTracks.forget(k)
	CustomTracks.set_current("")


# ---------------------------------------------------------------- prepare

func _prepare() -> void:
	var calls := []
	CustomTracks.prepare("c_" + "e".repeat(16), func(ok: bool, why: String) -> void: calls.append([ok, why]))
	t.check(calls.is_empty(), "prepare: done is deferred")
	await t.frames(2)
	t.check(calls.size() == 1 and not calls[0][0] and str(calls[0][1]) != "", "prepare: an unknown track fails with a reason")
	var p := _save(_doc("Prepared Loop", true, 6), CustomTracks.mine_dir() + "/prepared_loop.hl2kt")
	var id := CustomTracks.note_saved(p, _facts())
	var got := []
	CustomTracks.prepare(id, func(ok: bool, why: String) -> void: got.append([ok, why]))
	CustomTracks.prepare(id, func(ok: bool, why: String) -> void: got.append([ok, why]))
	t.check(got.is_empty(), "prepare: never synchronous")
	var done: bool = await _until(func() -> bool: return got.size() >= 2, 10.0)
	t.check(done and got.size() == 2, "prepare: both callbacks of a shared job are called")
	if got.size() == 2:
		t.check(bool(got[0][0]) == bool(got[1][0]), "prepare: the same answer to both")
		if _real:
			t.check(bool(got[0][0]) and CustomTracks.is_prepared(id), "prepare: a closed loop is in memory (%s)" % str(got[0][1]))
			t.check(bool(CustomTracks.meta(id).get("checked")), "prepare: the local facts are recorded")
		else:
			t.check(not bool(got[0][0]) and str(got[0][1]) != "", "prepare: the stub compiler gives no road: refused with a reason")
	for k in CustomTracks.memory_ids():
		CustomTracks.forget(k)


# ---------------------------------------------------------------- thumbs

func _thumbs() -> void:
	var d := _doc("Pictured")
	var img := Image.create(48, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.8, 0.3, 0.1))
	d.thumb = img.save_png_to_buffer()
	var p := _save(d, CustomTracks.mine_dir() + "/pictured.hl2kt")
	var id := CustomTracks.note_saved(p, _facts())
	var fired := []
	var cb := func(tid: String) -> void: fired.append(tid)
	Game.track_thumb_ready.connect(cb)
	t.check(Game.track_thumb(id) == null, "track_thumb: null while the worker decodes")
	var ok: bool = await _until(func() -> bool: return id in fired, 5.0)
	Game.track_thumb_ready.disconnect(cb)
	t.check(ok, "Game.track_thumb_ready fires")
	var tex := Game.track_thumb(id)
	t.check(tex != null and tex.get_width() == 48 and tex.get_height() == 32, "track_thumb: the decoded picture")
	var nopic := CustomTracks.note_saved(_save(_doc("No Picture"), CustomTracks.mine_dir() + "/no_picture.hl2kt"), _facts())
	t.check(CustomTracks.thumb(nopic) == null and not bool(CustomTracks.meta(nopic).get("thumb")), "no thumb section: null")
	t.check(Game.track_thumb("c_" + "d".repeat(16)) == null, "track_thumb: unknown id")


# ---------------------------------------------------------------- history copies

func _history() -> void:
	var d := _doc("Versions")
	var p := CustomTracks.mine_dir() + "/versions.hl2kt"
	for i in 7:
		d.data["modified"] = 1763500000 + i * 60
		_save(d, p)
		if i < 6:
			CustomTracks.keep_history(p)
	var h := CustomTracks.history(str(d.data.guid))
	t.check(h.size() == 5, "history: the last five (%d)" % h.size())
	if h.size() == 5:
		t.check(int(h[0].modified) == 1763500000 + 5 * 60 and int(h[4].modified) == 1763500000 + 60, "history: newest first")
		t.check(str(LevelIO.read_meta(str(h[0].path)).get("guid")) == str(d.data.guid), "history: copies of the track")
	t.check(CustomTracks.history("../x").is_empty(), "history refuses a bad guid")
	CustomTracks.refresh()
	t.check(CustomTracks.find("versions") != "", "history copies are not listed, the track is")
	var listed := 0
	for e in CustomTracks.list("mine"):
		if str(e.name) == "Versions":
			listed += 1
	t.check(listed == 1, "only the track itself is listed")


# ---------------------------------------------------------------- find

func _find() -> void:
	CustomTracks.refresh()
	var id := CustomTracks.find("canal_run")
	t.check(id != "" and str(CustomTracks.meta(id).get("name")) == "Canal Run", "find: a file name")
	t.check(CustomTracks.find("canal run") == id and CustomTracks.find("CANAL RUN") == id, "find: a display name")
	t.check(CustomTracks.find(id) == id, "find: a c_ id")
	t.check(CustomTracks.find(str(CustomTracks.meta(id).get("sha")).left(10)) == id, "find: a sha prefix")
	t.check(CustomTracks.find("canal_run.hl2kt") == id, "find: a file name with its extension")
	t.check(CustomTracks.find("no such track") == "" and CustomTracks.find("") == "" and CustomTracks.find("abc") == "",
		"find: nothing")


# ---------------------------------------------------------------- Game (5.1)

func _game_wiring() -> void:
	var unknown := "c_" + "9".repeat(16)
	var u := Game.track(unknown)
	t.check(bool(u.get("unknown")) and str(u.name) == "Unknown track" and str(u.rescue) == "scanner",
		"Game.track: an unknown custom id is not Highway 17")
	t.check(str(Game.track("ct17").name) == "CT17", "Game.track: built-ins unchanged")
	t.check(Game.track_installed("ct17") == FileAccess.file_exists("res://assets/track/ct17.json"), "track_installed: built-ins unchanged")
	var all := Game.all_tracks()
	t.check(all.size() == Game.TRACKS.size() + CustomTracks.list("mine").size() + CustomTracks.list("kept").size(),
		"all_tracks: circuits + mine + kept")
	t.check(Game.all_tracks(false).size() == Game.TRACKS.size(), "all_tracks(false): the circuits")
	# track_pick follows a re-saved track by its guid (C1 S18)
	var d := _doc("Picked Track")
	var p := _save(d, CustomTracks.mine_dir() + "/picked_track.hl2kt")
	var id1 := CustomTracks.note_saved(p, _facts())
	t.check(str(Game.track(id1).name) == "Picked Track" and bool(Game.track(id1).custom), "Game.track: a custom track")
	t.check(Game.track_installed(id1), "track_installed: own, raceable")
	Game.settings["track"] = id1
	Game.settings["track_guid"] = str(d.data.guid)
	t.check(Game.track_pick() == id1, "track_pick: the installed pick")
	d.data["desc"] = "saved again"
	_save(d, p)
	var id2 := CustomTracks.note_saved(p, _facts())
	t.check(id2 != id1 and not CustomTracks.has(id1), "a re-save changes the id")
	t.check(Game.track_pick() == id2, "track_pick: follows the guid to the re-saved track")
	Game.settings["track_guid"] = ""
	var first := ""
	for tr in Game.TRACKS:
		if Game.track_installed(tr.id):
			first = tr.id
			break
	t.check(Game.track_pick() == (first if first != "" else Game.TRACKS[0].id), "track_pick: else the first installed circuit")
	var unr := CustomTracks.note_saved(_save(_doc("Has Errors"), CustomTracks.mine_dir() + "/has_errors.hl2kt"), _facts(false, 2))
	Game.settings["track"] = unr
	t.check(not Game.track_installed(unr) and Game.track_pick() != unr, "track_pick: never a track with errors")
	# race_setting reads test_drive only offline (C1 S19)
	var net := t.get_node("/root/Net")
	var was_active: bool = net.active
	Game.settings["laps"] = 3
	Game.test_drive = {"track": CustomTracks.EDIT_ID, "laps": 1, "bots": 2}
	t.check(int(Game.race_setting("laps")) == 1 and str(Game.race_setting("track")) == CustomTracks.EDIT_ID,
		"race_setting: the test drive's first, offline")
	t.check(int(Game.race_setting("difficulty")) == int(Game.settings.difficulty), "race_setting: keys the test drive lacks")
	net.active = true
	t.check(int(Game.race_setting("laps")) == 3 and str(Game.race_setting("track")) != CustomTracks.EDIT_ID,
		"race_setting ignores test_drive while Net.active")
	net.active = was_active
	Game.test_drive = {}
	t.check(int(Game.race_setting("laps")) == 3, "race_setting: settings without a test drive")
	for k in ["track_guid", "allow_downloads", "editor_hints", "editor_cam_speed", "editor_snap", "editor_recent",
			"editor_fav_props", "editor_recent_props", "editor_test", "editor_autosave"]:
		t.check(Game.settings.has(k), "settings default: %s" % k)
