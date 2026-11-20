class_name CustomTracks
## The custom-track registry (5.1, 6.6): own tracks, downloads, the download cache with its parts
## and LRU, server folders, imports, builds kept in memory (bounded), prepare on a worker, thumbs
## and history copies.
##
## Where files live (2.8): mine_dir() (user://tracks, user://tracks_test in test runs) holds MY
## TRACKS, downloaded/ (kept downloads and imports, never evicted), .autosave/, .history/<guid>/,
## .trash/ and cache/ (or --track-cache <dir>) with <sha>.hl2kt files and <sha>.part downloads.
## Extra scan folders (--tracks <dir>, add_folder, <exe dir>/tracks, res://tracks) hold a server's
## tracks. Two index files keep what a scan learnt (mine_dir()/index.json: path -> {sha, size, mtime,
## guid, facts, meta}; cache/index.json: sha -> {name, author, size, last_used, facts, meta}), so a
## file is re-hashed only when its size or mtime changed.
##
## Facts (raceable, errors, warnings, length, branches, props, hazards) come only from a compile on
## this computer (the editor's save, prepare, build_for or the background check); a header's own
## claims only label a card (C1 S17). Until a file has been compiled here it is not raceable.

const EDIT_ID := "c_edit"
## What an index's facts hold (LevelBuild.facts()).
const FACT_KEYS := ["raceable", "errors", "warnings", "length", "branches", "props", "hazards"]
## Folders a scan never descends into (C1 N13).
const SKIP_DIRS := [".autosave", ".trash", ".history", "cache"]
## An entry's kind: own files, kept downloads / imports, a server folder's files, the cache.
const KINDS := ["mine", "kept", "server", "cache"]
const MAX_PARTS := 2
const HISTORY_KEEP := 5
## In-memory builds besides the current track and c_edit (the prefetch, C1 S16).
const MEMORY_OTHERS := 1
const THUMB_CACHE := 64
const SCAN_DEPTH := 3

static var last_error := ""
## The cache's LRU limits (6.6); tests make them small.
static var cache_max_bytes := 512 << 20
static var cache_max_files := 200
## A .part older than this (s) is deleted at refresh / evict.
static var part_max_age := 24 * 3600
## Added to the clock (tests: make everything look older).
static var time_offset := 0
## Compile files that have no local facts yet in the background (one at a time).
static var auto_check := true

static var _scanned := false
static var _indexes_loaded := false
static var _own_index := {}      # path -> {sha, size, mtime, guid, facts, meta} or {size, mtime, bad}
static var _cache_index := {}    # sha -> {name, author, size, last_used, facts, meta}
static var _files := {}          # path -> kind: the non-cache files of the last scan
static var _entries := {}        # id -> entry (meta())
static var _guids := {}          # guid -> id (own first)
static var _extra_folders := PackedStringArray()
static var _mem := {}            # id -> {build, meta, t}
static var _mem_t := 0
static var _current := ""
static var _unusable := {}       # id -> reason
static var _thumbs := {}         # id -> {tex, t}
static var _thumb_t := 0
static var _thumb_jobs := {}     # id -> true while a worker decodes it
static var _prep := {}           # id -> {cbs: [Callable]}
static var _check_q: Array[String] = []
static var _checking := ""


# ---------------------------------------------------------------- ids and folders

## Begins with "c_".
static func is_custom(id: String) -> bool:
	return id.begins_with("c_")


## ^c_[0-9a-f]{16}$ (never c_edit).
static func valid_id(id: String) -> bool:
	if id.length() != 18 or not id.begins_with("c_"):
		return false
	for i in range(2, 18):
		var c := id.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)):
			return false
	return true


## "c_" + sha.left(16); "" (and push_error) unless sha is a sha.
static func id_for(sha: String) -> String:
	return LevelIO.id_for(sha)


## user://tracks or user://tracks_test
static func mine_dir() -> String:
	return "user://tracks_test" if test_mode() else "user://tracks"


## The download cache: --track-cache <dir>, else mine_dir()/cache.
static func cache_dir() -> String:
	var a := _user_arg("--track-cache")
	if a != "":
		return a.trim_suffix("/").trim_suffix("\\")
	return mine_dir() + "/cache"


## mine_dir()/downloaded: kept downloads and imports.
static func kept_dir() -> String:
	return mine_dir() + "/downloaded"


static func autosave_dir() -> String:
	return mine_dir() + "/.autosave"


static func trash_dir() -> String:
	return mine_dir() + "/.trash"


static func history_dir(guid: String) -> String:
	return mine_dir() + "/.history/" + guid


## A test run (any res://tests/... argument, like Game.settings_path()).
static func test_mode() -> bool:
	for a in OS.get_cmdline_args():
		if a.begins_with("res://tests/"):
			return true
	return false


## The scan folders in search order (6.8): --tracks <dir> and add_folder() ones first, then
## <exe dir>/tracks and res://tracks (not in test runs), then mine_dir().
static func folders() -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	var cands := PackedStringArray()
	var a := _user_arg("--tracks")
	if a != "":
		cands.append(a)
	cands.append_array(_extra_folders)
	if not test_mode():
		cands.append(OS.get_executable_path().get_base_dir().path_join("tracks"))
		cands.append("res://tracks")
	cands.append(mine_dir())
	for d in cands:
		var dd := d.trim_suffix("/").trim_suffix("\\")
		var k := _norm(dd)
		if dd == "" or seen.has(k):
			continue
		seen[k] = true
		out.append(dd)
	return out


## An extra scan folder (a dedicated server's sv_tracks); the next refresh scans it.
static func add_folder(dir: String) -> void:
	var d := dir.strip_edges().trim_suffix("/").trim_suffix("\\")
	if d == "":
		return
	for f in _extra_folders:
		if _norm(f) == _norm(d):
			return
	_extra_folders.append(d)
	_scanned = false


# ---------------------------------------------------------------- the scan

## Builds the id -> file map from the folders and both index files, re-hashing a file only when
## its size or mtime changed (force: re-read the index files and re-check every file). Recovers a
## <file>.tmp whose <file> is missing, deletes .part files older than 24 h and all but the two
## newest, and never descends into .autosave/, .trash/, .history/ or cache/.
static func refresh(force := false) -> void:
	_load_indexes(force)
	var own_changed := false
	var files := {}
	var cache_k := _norm(cache_dir())
	for dir in folders():
		for p in _scan(dir, 0, cache_k):
			if files.has(p):
				continue
			var kind := _kind_of(p)
			var size := _fsize(p)
			var mtime := FileAccess.get_modified_time(p)
			var rec = _own_index.get(p)
			if force or not (rec is Dictionary) or int(rec.get("size", -1)) != size or int(rec.get("mtime", -1)) != mtime:
				rec = _index_file(p, kind, size, mtime, rec if rec is Dictionary else {})
				_own_index[p] = rec
				own_changed = true
			if rec.has("bad"):
				continue
			files[p] = kind
	for p in _own_index.keys():
		if not files.has(p) and not (_own_index[p] is Dictionary and _own_index[p].has("bad") and FileAccess.file_exists(p)):
			_own_index.erase(p)
			own_changed = true
	_files = files
	var cache_changed := _scan_cache()
	_scanned = true
	_rebuild()
	if own_changed:
		_save_own_index()
	if cache_changed:
		_save_cache_index()
	evict()
	_queue_unchecked()


static func _ensure() -> void:
	if not _scanned:
		refresh()


## "mine" | "kept" | "downloaded" (kept + cache) | "server" | "all"; newest first.
static func list(which := "all") -> Array[Dictionary]:
	_ensure()
	var out: Array[Dictionary] = []
	for id in _entries:
		var e: Dictionary = _entries[id]
		var k := str(e.kind)
		var take := false
		match which:
			"mine":
				take = k == "mine"
			"kept":
				take = k == "kept"
			"downloaded":
				take = k == "kept" or k == "cache"
			"server":
				take = k == "server"
			_:
				take = true
		if take:
			out.append(meta(str(id)))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.time) != int(b.time):
			return int(a.time) > int(b.time)
		return str(a.id) < str(b.id))
	return out


## Header labels + local facts (S17): {id, name, short, desc, rescue, custom: true, author, sha,
## size, path, guid, length, raceable, errors, warnings, downloaded, kept, kind, checked,
## branches, props, hazards, created, modified, time, thumb, thumb_custom, outline, remix_of,
## unusable}; {} for an unknown id. c_edit (in memory only) gives its build's meta.
static func meta(id: String) -> Dictionary:
	if id == EDIT_ID:
		if not _mem.has(id):
			return {}
		var m: Dictionary = (_mem[id].meta as Dictionary).duplicate(true)
		m["id"] = EDIT_ID
		m["custom"] = true
		m["kind"] = "edit"
		m["unusable"] = ""
		for k in ["name", "short", "desc", "author", "rescue"]:
			if not m.has(k):
				m[k] = "TEST DRIVE" if k == "name" or k == "short" else ("scanner" if k == "rescue" else "")
		return m
	if not valid_id(id):
		return {}
	_ensure()
	if not _entries.has(id):
		return {}
	var e: Dictionary = (_entries[id] as Dictionary).duplicate(true)
	e["unusable"] = str(_unusable.get(id, ""))
	return e


static func has(id: String) -> bool:
	if id == EDIT_ID:
		return _mem.has(id)
	if not valid_id(id):
		return false
	_ensure()
	return _entries.has(id)


static func path(id: String) -> String:
	if not valid_id(id):
		if id != EDIT_ID:
			push_error("CustomTracks.path: not a track id: %s" % id.left(40).c_escape())
		return ""
	_ensure()
	return str(_entries[id].path) if _entries.has(id) else ""


## The own (else kept, else server) track with this guid: follows a track across saves.
static func id_for_guid(guid: String) -> String:
	if guid == "":
		return ""
	_ensure()
	return str(_guids.get(guid.to_lower(), ""))


## Cached or null (worker decode, then Game.track_thumb_ready).
static func thumb(id: String) -> Texture2D:
	if _thumbs.has(id):
		_thumb_t += 1
		_thumbs[id]["t"] = _thumb_t
		return _thumbs[id].tex
	if not valid_id(id) or _thumb_jobs.has(id):
		return null
	_ensure()
	if not _entries.has(id) or not bool(_entries[id].get("thumb", false)):
		return null
	var p := str(_entries[id].path)
	_thumb_jobs[id] = true
	var holder := [-1]
	var job := func() -> void:
		var img := LevelIO.decode_thumb(CustomTracks._thumb_png(p))
		CustomTracks._thumb_done.call_deferred(id, img, holder)
	holder[0] = WorkerThreadPool.add_task(job, false, "CustomTracks.thumb")
	return null


## The saved file's bytes.
static func bytes(id: String) -> PackedByteArray:
	var p := path(id)
	if p == "" or _fsize(p) > LevelIO.MAX_FILE:
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(p)


# ---------------------------------------------------------------- builds in memory

## Memory; compiles synchronously only headless / in tests, else null.
static func build_for(id: String) -> LevelBuild:
	if _mem.has(id):
		_mem_t += 1
		_mem[id]["t"] = _mem_t
		return _mem[id].build
	if not valid_id(id) or not (_headless() or test_mode()):
		return null
	_ensure()
	if not _entries.has(id) or str(_unusable.get(id, "")) != "":
		return null
	var e: Dictionary = _entries[id]
	var r := _compile_file(id, str(e.path), str(e.sha), LevelCompiler.registries())
	if _accept_build(id, r) != "":
		return null
	return _mem[id].build if _mem.has(id) else null


## done(ok: bool, reason: String), deferred; compiles from bytes() on a worker.
static func prepare(id: String, done: Callable) -> void:
	if is_prepared(id):
		if done.is_valid():
			done.call_deferred(true, "")
		return
	var fail := ""
	if not valid_id(id):
		fail = "This is not a custom track."
	else:
		_ensure()
		if not _entries.has(id):
			fail = "The track is not on this computer."
		elif str(_unusable.get(id, "")) != "":
			fail = str(_unusable[id])
	if fail != "":
		if done.is_valid():
			done.call_deferred(false, fail)
		return
	if _prep.has(id):
		(_prep[id].cbs as Array).append(done)
		return
	_prep[id] = {"cbs": [done]}
	var e: Dictionary = _entries[id]
	var p := str(e.path)
	var sha := str(e.sha)
	var regs := LevelCompiler.registries()
	var holder := [-1]
	var job := func() -> void:
		var r := CustomTracks._compile_file(id, p, sha, regs)
		CustomTracks._prepared.call_deferred(id, r, holder)
	holder[0] = WorkerThreadPool.add_task(job, false, "CustomTracks.prepare")


static func is_prepared(id: String) -> bool:
	return _mem.has(id)


## Bounded: current + c_edit + 1.
static func put_memory(id: String, build: LevelBuild, meta_d: Dictionary) -> void:
	if build == null or id == "":
		return
	_mem_t += 1
	_mem[id] = {"build": build, "meta": meta_d.duplicate(true) if meta_d != null else {}, "t": _mem_t}
	_bound_memory()


## The track being raced or served: kept in memory and never evicted from the cache.
static func set_current(id: String) -> void:
	_current = id
	_bound_memory()


static func current() -> String:
	return _current


static func forget(id: String) -> void:
	_mem.erase(id)


static func mark_unusable(id: String, reason: String) -> void:
	if id == "":
		return
	_unusable[id] = reason if reason != "" else "The track cannot be used."
	_mem.erase(id)


## "" or the reason.
static func unusable(id: String) -> String:
	return str(_unusable.get(id, ""))


## The ids held in memory (tests, the console).
static func memory_ids() -> PackedStringArray:
	return PackedStringArray(_mem.keys())


# ---------------------------------------------------------------- the cache

## Where a download of sha is written ("" unless LevelIO.is_sha). The other parts are pruned first
## (prune_parts), so a server that keeps announcing new tracks never leaves more than MAX_PARTS.
static func cache_part(sha: String) -> String:
	if not LevelIO.is_sha(sha):
		push_error("CustomTracks.cache_part: not a sha: %s" % sha.left(80).c_escape())
		return ""
	_make_dir(cache_dir())
	prune_parts(sha)
	return cache_dir().path_join(sha + ".part")


## The .part files within bounds (6.6): parts older than part_max_age go, then all but keep_sha's
## own part and the MAX_PARTS - 1 newest others. keep_sha's part always stays (a resume).
static func prune_parts(keep_sha := "") -> void:
	_prune_parts(keep_sha)


## A finished download: the part's bytes must hash to sha; it becomes cache/<sha>.hl2kt with the
## local facts given (or none yet). Returns the id ("" with last_error).
static func cache_add(sha: String, part_path: String, facts: Dictionary) -> String:
	last_error = ""
	if not LevelIO.is_sha(sha):
		push_error("CustomTracks.cache_add: not a sha")
		last_error = "The download has no valid id."
		return ""
	if not FileAccess.file_exists(part_path):
		last_error = "The download is missing."
		return ""
	if _fsize(part_path) > LevelIO.MAX_FILE or LevelIO.file_sha256(part_path) != sha:
		DirAccess.remove_absolute(part_path)
		last_error = "The download did not match the track."
		return ""
	var m := LevelIO.read_meta(part_path)
	if m.is_empty():
		DirAccess.remove_absolute(part_path)
		last_error = "This is not a track file."
		return ""
	_ensure()
	var dst := cache_dir().path_join(sha + LevelIO.EXT)
	_make_dir(cache_dir())
	if _norm(dst) != _norm(part_path):
		if FileAccess.file_exists(dst):
			DirAccess.remove_absolute(part_path)
		elif DirAccess.rename_absolute(part_path, dst) != OK:
			if DirAccess.copy_absolute(part_path, dst) != OK:
				last_error = "The download could not be stored."
				return ""
			DirAccess.remove_absolute(part_path)
	var f := _clean_facts(facts)
	var old = _cache_index.get(sha)
	if f.is_empty() and old is Dictionary:
		f = _clean_facts(old.get("facts"))
	_cache_index[sha] = {"name": str(m.get("name", "")), "author": str(m.get("author", "")), "size": _fsize(dst),
		"last_used": _now(), "facts": f, "meta": _strip_meta(m)}
	_rebuild()
	evict(sha)
	_save_cache_index()
	var id := LevelIO.id_for(sha)
	if f.is_empty():
		_queue_check(id)
	return id


static func cache_touch(sha: String) -> void:
	if not LevelIO.is_sha(sha):
		return
	_ensure()
	if _cache_index.has(sha):
		_cache_index[sha]["last_used"] = _now()
		_rebuild()
		_save_cache_index()


## Files and .part files (6.6): parts older than 24 h and all but the two newest go, then the least
## recently used files until the cache is within its bytes (parts counted) and file count; never
## keep_sha or the current track.
static func evict(keep_sha := "") -> void:
	_ensure()
	var parts := _prune_parts()
	var protect := {}
	if keep_sha != "":
		protect[keep_sha] = true
	if _entries.has(_current):
		protect[str(_entries[_current].sha)] = true
	var total := 0
	for q in parts:
		total += int(q[2])
	var files := []
	for sha in _cache_index:
		var sz := int(_cache_index[sha].get("size", 0))
		total += sz
		files.append([int(_cache_index[sha].get("last_used", 0)), str(sha), sz])
	files.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] or (a[0] == b[0] and str(a[1]) < str(b[1])))
	var count := files.size()
	var changed := false
	for f in files:
		if total <= cache_max_bytes and count <= cache_max_files:
			break
		if protect.has(f[1]):
			continue
		_drop_cache(str(f[1]), true)
		total -= int(f[2])
		count -= 1
		changed = true
	if changed:
		_rebuild()
		_save_cache_index()


# ---------------------------------------------------------------- own files

## A name, file name (no extension), c_ id or sha prefix (>= 6 hex) -> the id, "" when none (the
## dedicated config's mp_track / mp_tracklist, the console's `track`). Server folders first.
static func find(name_or_id: String) -> String:
	var q := name_or_id.strip_edges()
	if q == "":
		return ""
	_ensure()
	if valid_id(q):
		return q if _entries.has(q) else ""
	var ql := q.to_lower().trim_suffix(LevelIO.EXT)
	var order := _ordered()
	for e in order:
		if str(e.path).get_file().get_basename().to_lower() == ql:
			return str(e.id)
	var named: Array = []
	for e in order:
		if str(e.name).to_lower() == ql or str(e.short).to_lower() == ql:
			named.append(e)
	if not named.is_empty():
		if named.size() > 1:
			# say which one won, so a server operator is not surprised (the console shows it)
			print("CustomTracks: %d tracks are named \"%s\": using %s (give its file name to pick another)."
				% [named.size(), q, str(named[0].path).get_file()])
		return str(named[0].id)
	if ql.length() >= 6 and _hex(ql):
		var hit := ""
		for e in order:
			if str(e.sha).begins_with(ql):
				if hit != "" and hit != str(e.id):
					return ""
				hit = str(e.id)
		return hit
	return ""


## KEEP: a cached download is copied into downloaded/ (never evicted) and leaves the cache.
static func keep(id: String) -> Error:
	last_error = ""
	_ensure()
	if not _entries.has(id):
		return ERR_DOES_NOT_EXIST
	var e: Dictionary = _entries[id]
	if str(e.kind) != "cache" and str(e.kind) != "server":
		return OK
	_make_dir(kept_dir())
	var dst := LevelIO.free_path(kept_dir(), str(e.name))
	var err := DirAccess.copy_absolute(str(e.path), dst)
	if err != OK:
		last_error = "The track could not be copied."
		return err
	var facts := {}
	if str(e.kind) == "cache":
		facts = _clean_facts(_cache_index.get(str(e.sha), {}).get("facts"))
	else:
		facts = _clean_facts(_own_index.get(str(e.path), {}).get("facts"))
	var m := LevelIO.read_meta(dst)
	_own_index[dst] = {"sha": str(e.sha), "size": _fsize(dst), "mtime": FileAccess.get_modified_time(dst),
		"guid": str(m.get("guid", "")), "facts": facts, "meta": _strip_meta(m)}
	_files[dst] = "kept"
	if str(e.kind) == "cache":
		_drop_cache(str(e.sha), false)
		_save_cache_index()
	_rebuild()
	_save_own_index()
	return OK


## Own: to .trash; download: from the cache.
static func remove(id: String) -> Error:
	last_error = ""
	_ensure()
	if not _entries.has(id):
		return ERR_DOES_NOT_EXIST
	var e: Dictionary = _entries[id]
	var p := str(e.path)
	match str(e.kind):
		"mine", "kept":
			_make_dir(trash_dir())
			var dst := LevelIO.free_path(trash_dir(), p.get_file().get_basename())
			var err := DirAccess.rename_absolute(p, dst)
			if err != OK:
				last_error = "The track could not be moved to the trash."
				return err
			_own_index.erase(p)
			_files.erase(p)
			_save_own_index()
		"cache":
			_drop_cache(str(e.sha), true)
			_save_cache_index()
		_:
			last_error = "A server folder's track is not removed from here."
			return ERR_UNAVAILABLE
	forget(id)
	_thumbs.erase(id)
	_rebuild()
	return OK


## A dropped file -> downloaded/: the id, or "" with last_error. The one gate (LevelIO.unpack)
## checks it first; the exact bytes are kept (they are the id). Its facts come from a local
## compile later (the background check), never from its header.
static func import_file(src_path: String) -> String:
	last_error = ""
	var fa := FileAccess.open(src_path, FileAccess.READ)
	if fa == null:
		last_error = str(LevelIO.FATAL.no_file)
		return ""
	if fa.get_length() > LevelIO.MAX_FILE:
		last_error = str(LevelIO.FATAL.too_big)
		return ""
	var b := fa.get_buffer(fa.get_length())
	fa.close()
	var rep := LevelReport.new()
	var d := LevelIO.unpack(b, rep)
	if d == null:
		last_error = rep.fatal() if rep.fatal() != "" else str(LevelIO.FATAL.bad_doc)
		return ""
	var sha := LevelIO.sha256(b)
	var id := LevelIO.id_for(sha)
	_ensure()
	if _entries.has(id):
		if str(_entries[id].kind) == "cache":
			keep(id)
		return id
	_make_dir(kept_dir())
	var dst := LevelIO.free_path(kept_dir(), str(d.data.get("name", "track")))
	var err := LevelIO.write_atomic(dst, b)
	if err != OK:
		last_error = "The track could not be stored."
		return ""
	var m := LevelIO.read_meta(dst)
	_own_index[dst] = {"sha": sha, "size": _fsize(dst), "mtime": FileAccess.get_modified_time(dst),
		"guid": str(d.data.get("guid", "")), "facts": {}, "meta": _strip_meta(m)}
	_files[dst] = "kept"
	_rebuild()
	_save_own_index()
	_queue_check(id)
	return id


## The editor saved a file: re-index it, returns its id.
static func note_saved(path: String, facts: Dictionary) -> String:
	if not FileAccess.file_exists(path):
		return ""
	_ensure()
	var sha := LevelIO.file_sha256(path)
	var m := LevelIO.read_meta(path)
	if sha == "" or m.is_empty():
		return ""
	_own_index[path] = {"sha": sha, "size": _fsize(path), "mtime": FileAccess.get_modified_time(path),
		"guid": str(m.get("guid", "")), "facts": _clean_facts(facts), "meta": _strip_meta(m)}
	_files[path] = _kind_of(path)
	_rebuild()
	_save_own_index()
	return LevelIO.id_for(sha)


## [{path, modified}] newest first (<= 5).
static func history(guid: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _is_guid(guid):
		return out
	var dir := history_dir(guid)
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(LevelIO.EXT):
			var p := dir.path_join(f)
			out.append({"path": p, "modified": _stamp_of(f, p)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.modified) != int(b.modified):
			return int(a.modified) > int(b.modified)
		return str(a.path) > str(b.path))
	if out.size() > HISTORY_KEEP:
		out.resize(HISTORY_KEEP)
	return out


## Before a save overwrites path: copies the file into .history/<guid>/<modified>.hl2kt and keeps
## the newest five.
static func keep_history(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var m := LevelIO.read_meta(path)
	var g := str(m.get("guid", ""))
	if not _is_guid(g):
		return
	var dir := history_dir(g)
	_make_dir(dir)
	var stamp := int(m.get("modified", FileAccess.get_modified_time(path)))
	var dst := dir.path_join("%d%s" % [stamp, LevelIO.EXT])
	var n := 2
	while FileAccess.file_exists(dst):
		dst = dir.path_join("%d_%d%s" % [stamp, n, LevelIO.EXT])
		n += 1
	if DirAccess.copy_absolute(path, dst) != OK:
		return
	var all := []
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(LevelIO.EXT):
			var p := dir.path_join(f)
			all.append([_stamp_of(f, p), FileAccess.get_modified_time(p), p])
	all.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] > b[0]
		if a[1] != b[1]:
			return a[1] > b[1]
		return str(a[2]) > str(b[2]))
	for i in range(HISTORY_KEEP, all.size()):
		DirAccess.remove_absolute(str(all[i][2]))


## Forgets everything learnt (tests): the next call scans again.
static func reset() -> void:
	_scanned = false
	_indexes_loaded = false
	_own_index = {}
	_cache_index = {}
	_files = {}
	_entries = {}
	_guids = {}
	_mem = {}
	_current = ""
	_unusable = {}
	_thumbs = {}
	_check_q.clear()


# ---------------------------------------------------------------- internals

static func _game() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Game")
	return null


static func _net() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Net")
	return null


static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func _now() -> int:
	return int(Time.get_unix_time_from_system()) + time_offset


static func _user_arg(flag: String) -> String:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == flag and i + 1 < a.size():
			return a[i + 1]
		if a[i].begins_with(flag + "="):
			return a[i].substr(flag.length() + 1)
	return ""


static func _norm(p: String) -> String:
	var g := p
	if p.begins_with("user://") or p.begins_with("res://"):
		g = ProjectSettings.globalize_path(p)
	g = g.replace("\\", "/").simplify_path().trim_suffix("/")
	return g.to_lower() if OS.get_name() == "Windows" else g


static func _hex(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)):
			return false
	return true


static func _is_guid(g: String) -> bool:
	return g.length() == 32 and _hex(g)


static func _fsize(p: String) -> int:
	var fa := FileAccess.open(p, FileAccess.READ)
	return int(fa.get_length()) if fa != null else -1


static func _make_dir(d: String) -> void:
	if not DirAccess.dir_exists_absolute(d):
		DirAccess.make_dir_recursive_absolute(d)


static func _stamp_of(file_name: String, p: String) -> int:
	var head := file_name.get_basename().split("_")[0]
	if head.is_valid_int():
		return head.to_int()
	return FileAccess.get_modified_time(p)


static func _kind_of(p: String) -> String:
	var n := _norm(p)
	if n.begins_with(_norm(kept_dir()) + "/"):
		return "kept"
	if n.begins_with(_norm(mine_dir()) + "/"):
		return "mine"
	return "server"


## .hl2kt files under dir (depth-limited), recovering a lone <file>.tmp first.
static func _scan(dir: String, depth: int, cache_k: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	var names := d.get_files()
	for f in names:
		if f.ends_with(LevelIO.EXT + ".tmp"):
			var target := dir.path_join(f.trim_suffix(".tmp"))
			if not FileAccess.file_exists(target):
				LevelIO.load_file(target, LevelReport.new())
	d = DirAccess.open(dir)
	for f in d.get_files():
		if f.ends_with(LevelIO.EXT) and not f.begins_with("."):
			out.append(dir.path_join(f))
	if depth >= SCAN_DEPTH:
		return out
	for sub in d.get_directories():
		if sub in SKIP_DIRS or sub.begins_with("."):
			continue
		var sp := dir.path_join(sub)
		if _norm(sp) == cache_k:
			continue
		out.append_array(_scan(sp, depth + 1, cache_k))
	return out


## A new or changed file: its sha and header (mine), or the full gate (kept / server files).
static func _index_file(p: String, kind: String, size: int, mtime: int, old: Dictionary) -> Dictionary:
	if size <= 0 or size > LevelIO.MAX_FILE:
		return {"size": size, "mtime": mtime, "bad": str(LevelIO.FATAL.too_big)}
	var sha := ""
	if kind == "mine":
		sha = LevelIO.file_sha256(p)
	else:
		var b := FileAccess.get_file_as_bytes(p)
		var rep := LevelReport.new()
		if LevelIO.unpack(b, rep) == null:
			var why := rep.fatal()
			print("%s skipped: %s" % [p.get_file(), why])
			return {"size": size, "mtime": mtime, "bad": why}
		sha = LevelIO.sha256(b)
	var m := LevelIO.read_meta(p)
	if sha == "" or m.is_empty() or not m.has("guid"):
		return {"size": size, "mtime": mtime, "bad": str(LevelIO.FATAL.bad_magic)}
	var facts := {}
	if str(old.get("sha", "")) == sha:
		facts = _clean_facts(old.get("facts"))
	return {"sha": sha, "size": size, "mtime": mtime, "guid": str(m.get("guid", "")), "facts": facts,
		"meta": _strip_meta(m)}


## The cache folder against its index; returns whether the index changed.
static func _scan_cache() -> bool:
	var cd := cache_dir()
	var changed := false
	var found := {}
	var d := DirAccess.open(cd)
	if d != null:
		for f in d.get_files():
			if not f.ends_with(LevelIO.EXT):
				continue
			var sha := f.get_basename()
			if not LevelIO.is_sha(sha):
				continue
			var p := cd.path_join(f)
			var size := _fsize(p)
			var rec = _cache_index.get(sha)
			if not (rec is Dictionary) or int(rec.get("size", -1)) != size:
				var m := LevelIO.read_meta(p)
				if size > LevelIO.MAX_FILE or m.is_empty() or LevelIO.file_sha256(p) != sha:
					DirAccess.remove_absolute(p)
					changed = true
					continue
				_cache_index[sha] = {"name": str(m.get("name", "")), "author": str(m.get("author", "")), "size": size,
					"last_used": FileAccess.get_modified_time(p), "facts": {}, "meta": _strip_meta(m)}
				changed = true
			found[sha] = true
	for sha in _cache_index.keys():
		if not found.has(sha):
			_cache_index.erase(sha)
			changed = true
	return changed


## Deletes .part files older than part_max_age and all but the MAX_PARTS newest (with keep_sha:
## its own part, whatever its age, and the MAX_PARTS - 1 newest others); returns the rest as
## [mtime, path, size].
static func _prune_parts(keep_sha := "") -> Array:
	var cd := cache_dir()
	var parts := []
	var kept := []
	var d := DirAccess.open(cd)
	if d == null:
		return parts
	var now := _now()
	for f in d.get_files():
		if not f.ends_with(".part"):
			continue
		var p := cd.path_join(f)
		var mt := FileAccess.get_modified_time(p)
		if keep_sha != "" and f == keep_sha + ".part":
			kept.append([mt, p, _fsize(p)])
			continue
		if now - mt > part_max_age:
			DirAccess.remove_absolute(p)
			continue
		parts.append([mt, p, _fsize(p)])
	parts.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] > b[0] or (a[0] == b[0] and str(a[1]) > str(b[1])))
	while parts.size() > MAX_PARTS - (1 if keep_sha != "" else 0):
		DirAccess.remove_absolute(str(parts.pop_back()[1]))
	return kept + parts


## The cache's copy of sha leaves (file and index); forget_build also drops its build and thumb
## (eviction, DELETE), not when the same bytes stay elsewhere (KEEP).
static func _drop_cache(sha: String, forget_build: bool) -> void:
	DirAccess.remove_absolute(cache_dir().path_join(sha + LevelIO.EXT))
	_cache_index.erase(sha)
	var id := LevelIO.id_for(sha)
	if forget_build and _entries.has(id) and str(_entries[id].kind) == "cache":
		_mem.erase(id)
		_thumbs.erase(id)


## The entries from the scanned files and the cache index (mine > kept > server > cache for the
## same bytes) and the guid map.
static func _rebuild() -> void:
	var ents := {}
	var rank := {"mine": 0, "kept": 1, "server": 2, "cache": 3}
	for p in _files:
		var rec = _own_index.get(p)
		if not (rec is Dictionary) or rec.has("bad") or not LevelIO.is_sha(str(rec.get("sha", ""))):
			continue
		var e := _entry(str(_files[p]), str(p), rec)
		var id := str(e.id)
		if ents.has(id) and int(rank[ents[id].kind]) <= int(rank[e.kind]):
			continue
		ents[id] = e
	for sha in _cache_index:
		var id := LevelIO.id_for(str(sha))
		if id == "" or ents.has(id):
			continue
		var rec: Dictionary = _cache_index[sha]
		var r2 := {"sha": str(sha), "size": int(rec.get("size", 0)), "mtime": int(rec.get("last_used", 0)),
			"facts": rec.get("facts", {}), "meta": rec.get("meta", {})}
		ents[id] = _entry("cache", cache_dir().path_join(str(sha) + LevelIO.EXT), r2)
		ents[id]["time"] = int(rec.get("last_used", 0))
	_entries = ents
	var g := {}
	var gt := {}
	for id in ents:
		var e: Dictionary = ents[id]
		if str(e.kind) == "cache" or str(e.guid) == "":
			continue
		var key := str(e.guid)
		var score := (3 - int(rank[e.kind])) * 10000000000 + int(e.modified)
		if not g.has(key) or score > int(gt[key]):
			g[key] = id
			gt[key] = score
	_guids = g


static func _entry(kind: String, p: String, rec: Dictionary) -> Dictionary:
	var m: Dictionary = rec.get("meta", {}) if rec.get("meta") is Dictionary else {}
	var facts := _clean_facts(rec.get("facts"))
	var sha := str(rec.sha)
	var nm := str(m.get("name", ""))
	if nm == "":
		nm = p.get_file().get_basename().to_upper()
	var secs: Array = m.get("sections", []) if m.get("sections") is Array else []
	var has_thumb := false
	for s in secs:
		if s is Dictionary and s.get("id") == "thumb":
			has_thumb = true
	var modified := int(m.get("modified", int(rec.get("mtime", 0))))
	var e := {"id": LevelIO.id_for(sha), "name": nm, "short": str(m.get("short", nm.to_upper().left(16))),
		"desc": str(m.get("desc", "")), "author": str(m.get("author", "")), "rescue": str(m.get("rescue", "scanner")),
		"custom": true, "sha": sha, "size": int(rec.get("size", 0)), "path": p, "guid": str(m.get("guid", rec.get("guid", ""))),
		"kind": kind, "downloaded": kind == "kept" or kind == "cache", "kept": kind == "kept",
		"created": int(m.get("created", 0)), "modified": modified, "time": modified,
		"checked": not facts.is_empty(), "raceable": false, "errors": 0, "warnings": 0,
		"length": float(m.get("length", 0.0)), "branches": int(m.get("branches", 0)), "props": int(m.get("props", 0)),
		"hazards": int(m.get("hazards", 0)), "thumb": has_thumb, "thumb_custom": bool(m.get("thumb_custom", false)),
		"outline": m.get("outline", []), "remix_of": m.get("remix_of", {})}
	if not facts.is_empty():
		for k in FACT_KEYS:
			e[k] = facts[k]
	return e


## Entries in find() order: server folders, mine, kept, cache.
static func _ordered() -> Array:
	var rank := {"server": 0, "mine": 1, "kept": 2, "cache": 3}
	var out := _entries.values()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(rank[a.kind]) != int(rank[b.kind]):
			return int(rank[a.kind]) < int(rank[b.kind])
		return str(a.path) < str(b.path))
	return out


## The facts of a build: LevelBuild.facts() (else its report and meta); a build without a road to
## race on is never raceable.
static func facts_of(b: LevelBuild) -> Dictionary:
	if b == null:
		return {}
	var f: Dictionary = b.facts()
	if f.is_empty():
		var rep := b.report if b.report != null else LevelReport.new()
		f = {"raceable": rep.raceable(), "errors": rep.errors(), "warnings": rep.warnings(),
			"length": float(b.meta.get("length", 0.0)), "branches": int(b.meta.get("branches", 0)),
			"props": int(b.meta.get("props", 0)), "hazards": int(b.meta.get("hazards", 0))}
	f = _clean_facts(f)
	if not (b.data.get("path") is Dictionary):
		f["raceable"] = false
	return f


static func _clean_facts(v: Variant) -> Dictionary:
	if not (v is Dictionary) or not (v.get("raceable") is bool):
		return {}
	var o := {"raceable": bool(v.raceable)}
	for k in ["errors", "warnings", "branches", "props", "hazards"]:
		var x = v.get(k, 0)
		o[k] = clampi(int(x), 0, 1000000) if (x is int or x is float) and is_finite(float(x)) else 0
	var ln = v.get("length", 0.0)
	o["length"] = clampf(float(ln), 0.0, 100000.0) if (ln is int or ln is float) and is_finite(float(ln)) else 0.0
	if int(o.errors) > 0:
		o["raceable"] = false
	return o


## A header kept in an index: without the section list's sizes (they are re-read with the file).
static func _strip_meta(m: Dictionary) -> Dictionary:
	var o := m.duplicate(true)
	if o.get("sections") is Array:
		var ids := []
		for s in o.sections:
			if s is Dictionary:
				ids.append({"id": s.get("id", "")})
		o["sections"] = ids
	return o


## Worker side: the file's bytes (checked against the id's sha), the gate, the compile.
static func _compile_file(id: String, p: String, sha: String, regs: Dictionary) -> Dictionary:
	var b := FileAccess.get_file_as_bytes(p)
	if b.is_empty():
		return {"build": null, "reason": str(LevelIO.FATAL.no_file)}
	if b.size() > LevelIO.MAX_FILE:
		return {"build": null, "reason": str(LevelIO.FATAL.too_big)}
	if LevelIO.sha256(b) != sha:
		return {"build": null, "reason": "The track file changed on disk."}
	var rep := LevelReport.new()
	var doc := LevelIO.unpack(b, rep)
	if doc == null:
		return {"build": null, "reason": rep.fatal()}
	var build := LevelCompiler.compile(doc, {"id": id, "registries": regs})
	if build == null:
		return {"build": null, "reason": "The track could not be built."}
	if build.id == "":
		build.id = id
	return {"build": build, "reason": "", "doc_meta": {"name": str(doc.data.get("name", "")),
		"short": str(doc.data.get("short", "")), "desc": str(doc.data.get("desc", "")),
		"author": str(doc.data.get("author", "")), "guid": str(doc.data.get("guid", "")),
		"rescue": str((doc.data.get("race", {}) as Dictionary).get("rescue", "scanner"))}}


## Main thread: records the local facts and keeps a raceable build in memory; "" = fine, else why not.
static func _accept_build(id: String, r: Dictionary) -> String:
	var b: LevelBuild = r.get("build")
	if b == null:
		mark_unusable(id, str(r.get("reason", "The track could not be built.")))
		return unusable(id)
	var facts := facts_of(b)
	_record_facts(id, facts)
	if not (b.data.get("path") is Dictionary):
		var why := b.report.blocks_drive() if b.report != null else ""
		if why == "":
			why = "The track has no road to race on."
		mark_unusable(id, why)
		return why
	var m: Dictionary = (r.get("doc_meta", {}) as Dictionary).duplicate()
	for k in b.meta:
		m[k] = b.meta[k]
	for k in facts:
		m[k] = facts[k]
	put_memory(id, b, m)
	return ""


static func _record_facts(id: String, facts: Dictionary) -> void:
	if not _entries.has(id) or facts.is_empty():
		return
	var e: Dictionary = _entries[id]
	if str(e.kind) == "cache":
		var rec = _cache_index.get(str(e.sha))
		if rec is Dictionary:
			rec["facts"] = facts
			_save_cache_index()
	else:
		var rec = _own_index.get(str(e.path))
		if rec is Dictionary:
			rec["facts"] = facts
			_save_own_index()
	_rebuild()


static func _prepared(id: String, r: Dictionary, holder: Array) -> void:
	if int(holder[0]) >= 0:
		WorkerThreadPool.wait_for_task_completion(int(holder[0]))
	var cbs: Array = _prep[id].cbs if _prep.has(id) else []
	_prep.erase(id)
	var why := _accept_build(id, r)
	for cb in cbs:
		if (cb as Callable).is_valid():
			(cb as Callable).call(why == "", why)


static func _bound_memory() -> void:
	var others := []
	for k in _mem:
		if k != _current and k != EDIT_ID:
			others.append([int(_mem[k].t), k])
	others.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	while others.size() > MEMORY_OTHERS:
		_mem.erase(others.pop_front()[1])


# ---------------------------------------------------------------- thumbs

## Worker side: the PNG section of a track file, checked (png_ok); empty when there is none.
static func _thumb_png(p: String) -> PackedByteArray:
	var fa := FileAccess.open(p, FileAccess.READ)
	if fa == null or fa.get_length() < 10:
		return PackedByteArray()
	var head := fa.get_buffer(10)
	if head.slice(0, 5).get_string_from_ascii() != LevelIO.MAGIC:
		return PackedByteArray()
	var meta_len := head.decode_u32(6)
	if meta_len > LevelIO.MAX_META:
		return PackedByteArray()
	var j := JSON.new()
	if j.parse(fa.get_buffer(meta_len).get_string_from_utf8()) != OK or not (j.data is Dictionary):
		return PackedByteArray()
	var m := LevelIO.sanitize_meta(j.data)
	var off := 10 + meta_len
	for s in m.get("sections", []):
		if s.id == "thumb":
			if int(s.size) > LevelIO.MAX_THUMB or off + int(s.size) > fa.get_length():
				return PackedByteArray()
			fa.seek(off)
			var png := fa.get_buffer(int(s.size))
			return png if LevelIO.png_ok(png) else PackedByteArray()
		off += int(s.size)
	return PackedByteArray()


static func _thumb_done(id: String, img: Image, holder: Array) -> void:
	if int(holder[0]) >= 0:
		WorkerThreadPool.wait_for_task_completion(int(holder[0]))
	_thumb_jobs.erase(id)
	if img == null or img.is_empty():
		return
	_thumb_t += 1
	_thumbs[id] = {"tex": ImageTexture.create_from_image(img), "t": _thumb_t}
	if _thumbs.size() > THUMB_CACHE:
		var oldest := ""
		var ot := 1 << 62
		for k in _thumbs:
			if int(_thumbs[k].t) < ot:
				ot = int(_thumbs[k].t)
				oldest = k
		_thumbs.erase(oldest)
	var g := _game()
	if g != null and g.has_signal("track_thumb_ready"):
		g.emit_signal("track_thumb_ready", id)


# ---------------------------------------------------------------- background checks

## Files without local facts get compiled one at a time on a worker (not on a dedicated server,
## which compiles only its current and next track).
static func _queue_unchecked() -> void:
	for id in _entries:
		if not bool(_entries[id].checked):
			_queue_check(str(id))


static func _queue_check(id: String) -> void:
	if not auto_check or id == "" or id == _checking or id in _check_q:
		return
	var n := _net()
	if n != null and bool(n.get("dedicated")):
		return
	_check_q.append(id)
	_next_check()


static func _next_check() -> void:
	while _checking == "" and not _check_q.is_empty():
		var id: String = _check_q.pop_front()
		if not _entries.has(id) or bool(_entries[id].checked) or str(_unusable.get(id, "")) != "":
			continue
		_checking = id
		var e: Dictionary = _entries[id]
		var p := str(e.path)
		var sha := str(e.sha)
		var regs := LevelCompiler.registries()
		var holder := [-1]
		var job := func() -> void:
			var r := CustomTracks._compile_file(id, p, sha, regs)
			CustomTracks._checked.call_deferred(id, r, holder)
		holder[0] = WorkerThreadPool.add_task(job, false, "CustomTracks.check")


static func _checked(id: String, r: Dictionary, holder: Array) -> void:
	if int(holder[0]) >= 0:
		WorkerThreadPool.wait_for_task_completion(int(holder[0]))
	_checking = ""
	var b: LevelBuild = r.get("build")
	if b == null:
		mark_unusable(id, str(r.get("reason", "")))
	else:
		_record_facts(id, facts_of(b))
	var g := _game()
	if g != null and g.has_signal("custom_tracks_changed"):
		g.emit_signal("custom_tracks_changed")
	_next_check()


## True while a background check runs or waits (tests wait for it).
static func checking() -> bool:
	return _checking != "" or not _check_q.is_empty()


# ---------------------------------------------------------------- index files

static func _own_index_path() -> String:
	return mine_dir() + "/index.json"


static func _cache_index_path() -> String:
	return cache_dir() + "/index.json"


static func _load_indexes(force: bool) -> void:
	if _indexes_loaded and not force:
		return
	_indexes_loaded = true
	_own_index = {}
	var raw = _read_json(_own_index_path())
	if raw is Dictionary:
		for p in raw:
			var r = raw[p]
			if r is Dictionary and (r.has("bad") or LevelIO.is_sha(str(r.get("sha", "")))):
				var rec := {"size": int(r.get("size", -1)) if _num(r.get("size")) else -1,
					"mtime": int(r.get("mtime", -1)) if _num(r.get("mtime")) else -1}
				if r.has("bad"):
					rec["bad"] = str(r.bad)
				else:
					rec["sha"] = str(r.sha)
					rec["guid"] = str(r.get("guid", "")).to_lower() if _is_guid(str(r.get("guid", "")).to_lower()) else ""
					rec["facts"] = _clean_facts(r.get("facts"))
					rec["meta"] = _strip_meta(LevelIO.sanitize_meta(r.meta)) if r.get("meta") is Dictionary else {}
				_own_index[str(p)] = rec
	_cache_index = {}
	raw = _read_json(_cache_index_path())
	if raw is Dictionary:
		for sha in raw:
			var r = raw[sha]
			if LevelIO.is_sha(str(sha)) and r is Dictionary:
				var m: Dictionary = _strip_meta(LevelIO.sanitize_meta(r.meta)) if r.get("meta") is Dictionary else {}
				_cache_index[str(sha)] = {"name": LevelDoc.clean_text(str(r.get("name", "")), 48),
					"author": LevelDoc.clean_text(str(r.get("author", "")), 24),
					"size": int(r.get("size", -1)) if _num(r.get("size")) else -1,
					"last_used": int(r.get("last_used", 0)) if _num(r.get("last_used")) else 0,
					"facts": _clean_facts(r.get("facts")), "meta": m}


static func _num(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))


static func _read_json(p: String) -> Variant:
	if not FileAccess.file_exists(p):
		return null
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(p)) != OK:
		return null
	return j.data


static func _save_own_index() -> void:
	_make_dir(mine_dir())
	LevelIO.write_atomic(_own_index_path(), JSON.stringify(_own_index).to_utf8_buffer())


static func _save_cache_index() -> void:
	_make_dir(cache_dir())
	LevelIO.write_atomic(_cache_index_path(), JSON.stringify(_cache_index).to_utf8_buffer())
