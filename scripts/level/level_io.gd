class_name LevelIO
## The .hl2kt container (2.1): pack (thumb first), unpack (the one gate for foreign bytes), the
## header-only read, atomic saves with .tmp recovery, the PNG check and worker decode, sha / ids and
## file name slugs.
##
## Layout (little-endian): "HL2KT", container version (u8), meta_len (u32), the header meta (UTF-8
## JSON, 2.2) and the section bodies back to back in the order of meta.sections:
## thumb (png), doc (zstd JSON), height (i32d+zstd: int32 cm deltas, INT32_MIN = a hole), splat
## (zstd RGBA8). Nothing but `unpack` turns foreign bytes into a LevelDoc.

const MAGIC := "HL2KT"
const CONTAINER := 1
const MAX_FILE := 16 << 20
const MAX_DOC_RAW := 4 << 20
const MAX_META := 8192
const MAX_THUMB := 1 << 20
const THUMB_SIZE := Vector2i(480, 320)
const HEIGHT_HOLE := -2147483648

## The extension of a track file.
const EXT := ".hl2kt"
## Each section id and its codec.
const CODECS := {"thumb": "png", "doc": "zstd", "height": "i32d+zstd", "splat": "zstd"}
## The writer's section order (readers accept any order).
const ORDER := ["thumb", "doc", "height", "splat"]
## Heights in cm are kept within these (LevelDoc.HEIGHT_MIN / MAX).
const CM_MIN := -50000
const CM_MAX := 150000
## Header keys (2.2) sanitize_meta keeps.
const META_KEYS := ["format", "kind", "guid", "name", "short", "author", "desc", "created", "modified", "content",
	"app", "length", "branches", "props", "hazards", "raceable", "errors", "warnings", "rescue", "outline", "view",
	"remix_of", "sections", "thumb_custom"]
## Texts of the hard failures (report error codes).
const FATAL := {
	"no_file": "The track file could not be read.",
	"too_big": "The track file is larger than 16 MB.",
	"bad_magic": "This is not a track file.",
	"bad_container": "This track file needs a newer version of the game.",
	"bad_meta": "The track file's header is damaged.",
	"bad_sections": "The track file is damaged.",
	"doc_too_big": "The track's document is larger than 4 MB.",
	"no_doc": "The track file has no document.",
	"bad_doc": "The track's document is damaged.",
	"newer_format": "This track was made with a newer version of the game.",
	"not_a_track": "This file is not a Half-Life 2: Kart track.",
	"bad_height": "The track's terrain is damaged.",
	"bad_splat": "The track's ground paint is damaged.",
	"pack": "The track could not be written.",
}
## 2.8: Cyrillic letters (lower case; upper case is lowered first).
const TRANSLIT := {"а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh", "з": "z",
	"и": "i", "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t",
	"у": "u", "ф": "f", "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch", "ъ": "", "ы": "y", "ь": "",
	"э": "e", "ю": "yu", "я": "ya", "і": "i", "ї": "yi", "є": "ye", "ґ": "g"}
## File names Windows will not create.
const RESERVED := ["con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8",
	"com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9"]


## The file bytes; the thumb section first. The document is written as LevelDoc.sanitize gives it
## (so the file holds exactly what every reader will get back), heights as int32 centimetre deltas
## (clamped to -500..1500 m, NAN = a hole). header_extra adds the compile's facts to the header
## (length, raceable, errors, warnings, outline, view...); the document's own fields win. Empty
## bytes (and push_error) when the document cannot be written: heights of the wrong size, a doc
## over MAX_DOC_RAW or a file over MAX_FILE.
static func pack(doc: LevelDoc, header_extra := {}) -> PackedByteArray:
	if doc == null:
		return PackedByteArray()
	var d := LevelDoc.sanitize(doc.data, LevelReport.new())
	var doc_raw := JSON.stringify(d).to_utf8_buffer()
	if doc_raw.size() > MAX_DOC_RAW:
		push_error("LevelIO.pack: the document is %d bytes (max %d)" % [doc_raw.size(), MAX_DOC_RAW])
		return PackedByteArray()
	var sections := []
	var bodies := []
	if not doc.thumb.is_empty():
		if png_ok(doc.thumb):
			sections.append({"id": "thumb", "codec": "png", "raw": doc.thumb.size(), "size": doc.thumb.size()})
			bodies.append(doc.thumb)
		else:
			push_warning("LevelIO.pack: the thumbnail is not a PNG this game reads; left out")
	var dz := doc_raw.compress(FileAccess.COMPRESSION_ZSTD)
	sections.append({"id": "doc", "codec": "zstd", "raw": doc_raw.size(), "size": dz.size()})
	bodies.append(dz)
	if bool(d.world.terrain):
		var r := int(d.world.res)
		if doc.heights.size() != r * r or doc.splat.size() != r * r * 4:
			push_error("LevelIO.pack: heights %d / splat %d do not fit res %d" % [doc.heights.size(), doc.splat.size(), r])
			return PackedByteArray()
		var hraw := encode_heights(doc.heights).to_byte_array()
		var hz := hraw.compress(FileAccess.COMPRESSION_ZSTD)
		sections.append({"id": "height", "codec": "i32d+zstd", "raw": hraw.size(), "size": hz.size()})
		bodies.append(hz)
		var sz := doc.splat.compress(FileAccess.COMPRESSION_ZSTD)
		sections.append({"id": "splat", "codec": "zstd", "raw": doc.splat.size(), "size": sz.size()})
		bodies.append(sz)
	var meta := {"format": LevelDoc.FORMAT, "kind": LevelDoc.KIND, "guid": d.guid, "name": d.name, "short": d.short,
		"author": d.author, "desc": d.desc, "created": d.created, "modified": d.modified, "content": d.content,
		"app": d.app, "branches": d.branches.size(), "props": d.props.size(), "hazards": d.hazards.size(),
		"rescue": d.race.rescue}
	if d.has("remix_of"):
		meta["remix_of"] = d.remix_of
	if doc.thumb_custom:
		meta["thumb_custom"] = true
	if header_extra is Dictionary:
		for k in header_extra:
			if not meta.has(str(k)):
				meta[str(k)] = header_extra[k]
	meta = sanitize_meta(meta)
	meta["sections"] = sections
	var mb := JSON.stringify(meta).to_utf8_buffer()
	if mb.size() > MAX_META:
		meta.erase("outline")
		mb = JSON.stringify(meta).to_utf8_buffer()
	if mb.size() > MAX_META:
		push_error("LevelIO.pack: the header is %d bytes" % mb.size())
		return PackedByteArray()
	var out := MAGIC.to_ascii_buffer()
	out.append(CONTAINER)
	var ml := PackedByteArray()
	ml.resize(4)
	ml.encode_u32(0, mb.size())
	out.append_array(ml)
	out.append_array(mb)
	for b in bodies:
		out.append_array(b)
	if out.size() > MAX_FILE:
		push_error("LevelIO.pack: the file is %d bytes (max %d)" % [out.size(), MAX_FILE])
		return PackedByteArray()
	return out


## THE gate (2.1, 6.9): container checks (magic, version, meta_len, meta a Dictionary, section list
## shape, exact sizes, the caps), sanitize_meta, section decodes, the doc's JSON parse with its error
## checked, LevelDoc.migrate, LevelDoc.sanitize, the height clamp, the thumb check. null on a hard
## failure (report.fatal() says why); else a sanitized LevelDoc whose `report` (this report) lists
## what was dropped. The thumb is checked (png_ok), never decoded here.
static func unpack(bytes: PackedByteArray, report: LevelReport) -> LevelDoc:
	if report == null:
		report = LevelReport.new()
	var total := bytes.size()
	if total > MAX_FILE:
		return _fail(report, "too_big")
	if total < 10 or bytes.slice(0, 5).get_string_from_ascii() != MAGIC:
		return _fail(report, "bad_magic")
	if bytes[5] != CONTAINER:
		return _fail(report, "bad_container")
	var meta_len := bytes.decode_u32(6)
	if meta_len > MAX_META or 10 + meta_len > total:
		return _fail(report, "bad_meta")
	var meta = _parse(bytes.slice(10, 10 + meta_len))
	if not (meta is Dictionary):
		return _fail(report, "bad_meta")
	var mf = meta.get("format")
	if _is_num(mf) and float(mf) > LevelDoc.FORMAT:
		return _fail(report, "newer_format")
	# the section list: shape, codecs, exact sizes, caps
	var secs = meta.get("sections")
	if not (secs is Array) or secs.is_empty() or secs.size() > CODECS.size():
		return _fail(report, "bad_sections")
	var at := 10 + meta_len
	var parts := {}
	for s in secs:
		if not (s is Dictionary):
			return _fail(report, "bad_sections")
		var id = s.get("id")
		if not (id is String) or not CODECS.has(id) or parts.has(id) or s.get("codec") != CODECS[id]:
			return _fail(report, "bad_sections")
		if not _count(s.get("raw")) or not _count(s.get("size")):
			return _fail(report, "bad_sections")
		var size := int(s.size)
		if at + size > total:
			return _fail(report, "bad_sections")
		parts[id] = {"raw": int(s.raw), "at": at, "size": size}
		at += size
	if at != total:
		return _fail(report, "bad_sections")
	if not parts.has("doc"):
		return _fail(report, "no_doc")
	if int(parts.doc.raw) > MAX_DOC_RAW:
		return _fail(report, "doc_too_big")
	for id in ["height", "splat"]:
		if parts.has(id) and not _grid_raw(int(parts[id].raw)):
			return _fail(report, "bad_height" if id == "height" else "bad_splat")
	sanitize_meta(meta)
	# the document
	var raw_doc := _inflate(bytes, parts.doc)
	if raw_doc.is_empty():
		return _fail(report, "bad_doc")
	var j := JSON.new()
	if j.parse(raw_doc.get_string_from_utf8()) != OK or not (j.data is Dictionary):
		return _fail(report, "bad_doc")
	var src: Dictionary = j.data
	var f = src.get("format")
	if not _is_num(f) or not is_finite(float(f)) or float(f) < 1.0:
		return _fail(report, "bad_doc")
	if float(f) > LevelDoc.FORMAT:
		return _fail(report, "newer_format")
	if src.get("kind") != LevelDoc.KIND:
		return _fail(report, "not_a_track")
	src = LevelDoc.migrate(src)
	var doc := LevelDoc.new()
	doc.data = LevelDoc.sanitize(src, report)
	# terrain
	var w: Dictionary = doc.data.world
	if bool(w.terrain):
		var r := int(w.res)
		if not parts.has("height") or int(parts.height.raw) != r * r * 4:
			return _fail(report, "bad_height")
		if not parts.has("splat") or int(parts.splat.raw) != r * r * 4:
			return _fail(report, "bad_splat")
		var hraw := _inflate(bytes, parts.height)
		if hraw.is_empty():
			return _fail(report, "bad_height")
		doc.heights = decode_heights(hraw.to_int32_array())
		var sp := _inflate(bytes, parts.splat)
		if sp.is_empty():
			return _fail(report, "bad_splat")
		doc.splat = sp
	else:
		for id in ["height", "splat"]:
			if parts.has(id):
				report.add_dropped("terrain", 1)
	# the thumbnail: checked, never decoded here
	if parts.has("thumb"):
		var tp: Dictionary = parts.thumb
		var png := bytes.slice(int(tp.at), int(tp.at) + int(tp.size))
		if int(tp.raw) == png.size() and png_ok(png):
			doc.thumb = png
			doc.thumb_custom = meta.get("thumb_custom") == true
		else:
			report.add_dropped("thumb", 1)
			report.warning("thumb_refused", "The track's picture was not a PNG this game reads and was left out.")
	doc.report = report
	return doc


## The header only (2.2), sanitized; {} on failure. Reads at most 10 + MAX_META bytes.
static func read_meta(path: String) -> Dictionary:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return {}
	var total := fa.get_length()
	if total < 10 or total > MAX_FILE:
		return {}
	var head := fa.get_buffer(10)
	if head.size() != 10 or head.slice(0, 5).get_string_from_ascii() != MAGIC or head[5] != CONTAINER:
		return {}
	var meta_len := head.decode_u32(6)
	if meta_len > MAX_META or 10 + meta_len > total:
		return {}
	var meta = _parse(fa.get_buffer(meta_len))
	if not (meta is Dictionary):
		return {}
	return sanitize_meta(meta)


## The header's whitelist (2.2): the 2.3 string rules, numbers clamped, outline <= 64 pairs in 0..1,
## view 5 finite numbers, sections of the known ids. Never trusted beyond labelling a card.
static func sanitize_meta(meta: Dictionary) -> Dictionary:
	var o := {}
	var f = meta.get("format")
	if _is_num(f) and is_finite(float(f)):
		o["format"] = clampi(int(f), 0, 1000000)
	if meta.get("kind") == LevelDoc.KIND:
		o["kind"] = LevelDoc.KIND
	var g = meta.get("guid")
	if g is String and g.length() == 32 and _hex(g.to_lower()):
		o["guid"] = g.to_lower()
	for k in [["name", 48], ["short", 16], ["author", 24], ["desc", 280], ["app", 24]]:
		var v = meta.get(k[0])
		if v is String:
			o[k[0]] = LevelDoc.clean_text(v, k[1])
	for k in [["created", 1 << 40], ["modified", 1 << 40], ["content", 1000000], ["branches", 8], ["props", 3000],
			["hazards", 48], ["errors", 100000], ["warnings", 100000]]:
		var v = meta.get(k[0])
		if _is_num(v) and is_finite(float(v)):
			o[k[0]] = clampi(int(v), 0, int(k[1]))
	var ln = meta.get("length")
	if _is_num(ln) and is_finite(float(ln)):
		o["length"] = clampf(float(ln), 0.0, 100000.0)
	for k in ["raceable", "thumb_custom"]:
		if meta.get(k) is bool:
			o[k] = meta[k]
	var rs = meta.get("rescue")
	if rs is String and rs in LevelDoc.RESCUES:
		o["rescue"] = rs
	var ol = meta.get("outline")
	if ol is Array:
		var pts := []
		for q in ol:
			if pts.size() >= 64:
				break
			if q is Array and q.size() == 2 and _is_num(q[0]) and _is_num(q[1]) and is_finite(float(q[0])) \
					and is_finite(float(q[1])):
				pts.append([snappedf(clampf(float(q[0]), 0.0, 1.0), 0.0001), snappedf(clampf(float(q[1]), 0.0, 1.0), 0.0001)])
		o["outline"] = pts
	var vw = meta.get("view")
	if vw is Array and vw.size() == 5:
		var ok := true
		var v5 := []
		for x in vw:
			if not _is_num(x) or not is_finite(float(x)):
				ok = false
				break
			v5.append(clampf(float(x), -100000.0, 100000.0))
		if ok:
			o["view"] = v5
	var rx = meta.get("remix_of")
	if rx is Dictionary:
		var r := {}
		var rg = rx.get("guid")
		r["guid"] = rg.to_lower() if rg is String and rg.length() == 32 and _hex(rg.to_lower()) else ""
		r["name"] = LevelDoc.clean_text(rx.get("name"), 48) if rx.get("name") is String else ""
		r["author"] = LevelDoc.clean_text(rx.get("author"), 24) if rx.get("author") is String else ""
		o["remix_of"] = r
	var secs = meta.get("sections")
	if secs is Array:
		var out := []
		for s in secs:
			if out.size() >= CODECS.size():
				break
			if s is Dictionary and s.get("id") is String and CODECS.has(s.id) and _count(s.get("raw")) and _count(s.get("size")):
				out.append({"id": s.id, "codec": CODECS[s.id], "raw": int(s.raw), "size": int(s.size)})
		o["sections"] = out
	return o


## Writes <path>.tmp then renames it over <path> (sync: tests, servers). The folder is made.
static func save(doc: LevelDoc, path: String, header_extra := {}) -> Error:
	var bytes := pack(doc, header_extra)
	if bytes.is_empty():
		return ERR_INVALID_DATA
	return write_atomic(path, bytes)


## Snapshot here, pack + write on a worker; done(err) deferred on the main thread.
static func save_async(doc: LevelDoc, path: String, header_extra: Dictionary, done: Callable) -> void:
	if doc == null:
		if done.is_valid():
			done.call_deferred(ERR_INVALID_PARAMETER)
		return
	var snap := doc.snapshot()
	var extra: Dictionary = header_extra.duplicate(true) if header_extra != null else {}
	var holder := [-1]
	var job := func() -> void:
		var bytes := pack(snap, extra)
		var err: Error = ERR_INVALID_DATA if bytes.is_empty() else write_atomic(path, bytes)
		LevelIO._saved.call_deferred(holder, err, done)
	holder[0] = WorkerThreadPool.add_task(job, false, "LevelIO.save_async")


## Recovers <path>.tmp when <path> is missing (a save that stopped between the write and the
## rename): the .tmp is unpacked and, when it is a good track, renamed into place.
static func load_file(path: String, report: LevelReport) -> LevelDoc:
	if report == null:
		report = LevelReport.new()
	var tmp := path + ".tmp"
	if not FileAccess.file_exists(path) and FileAccess.file_exists(tmp):
		var rec := unpack(_read(tmp, report), report)
		if rec == null:
			return null
		if DirAccess.rename_absolute(tmp, path) == OK:
			report.info("recovered", "The track was recovered from an unfinished save.")
		return rec
	if not FileAccess.file_exists(path):
		return _fail(report, "no_file")
	var bytes := _read(path, report)
	if bytes.is_empty():
		return null
	return unpack(bytes, report)


## Signature + IHDR check (2.1), no decode: at most MAX_THUMB bytes, the PNG signature, an IHDR chunk
## (length 13) first, width and height 1..1024, bit depth 8, colour type 2 (RGB) or 6 (RGBA).
static func png_ok(png: PackedByteArray) -> bool:
	if png.size() < 33 or png.size() > MAX_THUMB:
		return false
	var sig := [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
	for i in 8:
		if png[i] != sig[i]:
			return false
	if _u32be(png, 8) != 13 or png.slice(12, 16).get_string_from_ascii() != "IHDR":
		return false
	var w := _u32be(png, 16)
	var h := _u32be(png, 20)
	if w < 1 or w > 1024 or h < 1 or h > 1024:
		return false
	return png[24] == 8 and (png[25] == 2 or png[25] == 6)


## Worker threads only (C1 M3: never decode a received PNG on the main thread); null unless png_ok
## or when called on the main thread.
static func decode_thumb(png: PackedByteArray) -> Image:
	if OS.get_thread_caller_id() == OS.get_main_thread_id():
		push_error("LevelIO.decode_thumb: called on the main thread")
		return null
	if not png_ok(png):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(png) != OK or img.is_empty():
		return null
	return img


static func sha256(bytes: PackedByteArray) -> String:
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(bytes)
	return hc.finish().hex_encode()


## SHA-256 of a file's bytes, read in 1 MiB pieces; "" when it cannot be read.
static func file_sha256(path: String) -> String:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return ""
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	var left := fa.get_length()
	while left > 0:
		var piece := fa.get_buffer(mini(left, 1 << 20))
		if piece.is_empty():
			return ""
		hc.update(piece)
		left -= piece.size()
	return hc.finish().hex_encode()


## "c_" + sha.left(16); "" (and push_error) unless is_sha.
static func id_for(sha: String) -> String:
	if not is_sha(sha):
		push_error("LevelIO.id_for: not a sha: %s" % sha.left(80).c_escape())
		return ""
	return "c_" + sha.left(16)


## ^[0-9a-f]{64}$
static func is_sha(s: String) -> bool:
	return s.length() == 64 and _hex(s)


## 2.8: Cyrillic transliterated, lower case, anything outside [a-z0-9] -> "_", runs collapsed, "_"
## stripped at both ends, cut to 32, "track" when empty (never a hidden or reserved file name).
static func slug(track_name: String) -> String:
	var src := track_name.left(512).to_lower()
	var out := PackedStringArray()
	var last_us := true
	for i in src.length():
		var c := src.unicode_at(i)
		var piece := ""
		if (c >= 97 and c <= 122) or (c >= 48 and c <= 57):
			piece = char(c)
		else:
			var ch := char(c)
			if TRANSLIT.has(ch):
				piece = TRANSLIT[ch]
				if piece == "":
					continue
			else:
				piece = "_"
		if piece == "_":
			if last_us:
				continue
			last_us = true
		else:
			last_us = false
		out.append(piece)
	var s := "".join(out).left(32)
	while s.begins_with("_"):
		s = s.substr(1)
	while s.ends_with("_"):
		s = s.left(s.length() - 1)
	if s == "":
		s = "track"
	if s in RESERVED:
		s += "_track"
	return s


# ---------------------------------------------------------------- additions (P1)

## A free file path for a track name in dir: <slug>.hl2kt, else <slug>_2.hl2kt, _3... (2.8).
static func free_path(dir: String, track_name: String) -> String:
	var base := slug(track_name)
	var d := dir.trim_suffix("/")
	var p := "%s/%s%s" % [d, base, EXT]
	var n := 2
	while FileAccess.file_exists(p) or FileAccess.file_exists(p + ".tmp"):
		p = "%s/%s_%d%s" % [d, base, n, EXT]
		n += 1
	return p


## Writes bytes to <path>.tmp, then renames it over <path> (the folder is made).
static func write_atomic(path: String, bytes: PackedByteArray) -> Error:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		var e := DirAccess.make_dir_recursive_absolute(dir)
		if e != OK:
			return e
	var tmp := path + ".tmp"
	var fa := FileAccess.open(tmp, FileAccess.WRITE)
	if fa == null:
		return FileAccess.get_open_error()
	fa.store_buffer(bytes)
	var err := fa.get_error()
	fa.close()
	if err != OK:
		DirAccess.remove_absolute(tmp)
		return err
	return DirAccess.rename_absolute(tmp, path)


## Heights (m, NAN = hole) -> int32 centimetre deltas from the previous non-hole value (the first
## from 0), clamped to -500..1500 m; HEIGHT_HOLE for a hole.
static func encode_heights(h: PackedFloat32Array) -> PackedInt32Array:
	var n := h.size()
	var out := PackedInt32Array()
	out.resize(n)
	var prev := 0
	for i in n:
		var v := h[i]
		if is_nan(v):
			out[i] = HEIGHT_HOLE
			continue
		var cm := CM_MAX if v > 1500.0 else (CM_MIN if v < -500.0 else roundi(v * 100.0))
		out[i] = cm - prev
		prev = cm
	return out


## The inverse of encode_heights: a running sum skipping holes, clamped to -500..1500 m.
static func decode_heights(d: PackedInt32Array) -> PackedFloat32Array:
	var n := d.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var acc := 0
	for i in n:
		var v := d[i]
		if v == HEIGHT_HOLE:
			out[i] = NAN
			continue
		acc += v
		out[i] = clampi(acc, CM_MIN, CM_MAX) / 100.0
	return out


static func _saved(holder: Array, err: Error, done: Callable) -> void:
	if int(holder[0]) >= 0:
		WorkerThreadPool.wait_for_task_completion(int(holder[0]))
	if done.is_valid():
		done.call(err)


static func _fail(report: LevelReport, code: String) -> LevelDoc:
	report.error(code, str(FATAL.get(code, code)))
	return null


static func _read(path: String, report: LevelReport) -> PackedByteArray:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		_fail(report, "no_file")
		return PackedByteArray()
	if fa.get_length() > MAX_FILE:
		_fail(report, "too_big")
		return PackedByteArray()
	return fa.get_buffer(fa.get_length())


## A JSON value or null.
static func _parse(buf: PackedByteArray) -> Variant:
	var j := JSON.new()
	if j.parse(buf.get_string_from_utf8()) != OK:
		return null
	return j.data


## A section's body decompressed to exactly its raw size; empty on any mismatch.
static func _inflate(bytes: PackedByteArray, part: Dictionary) -> PackedByteArray:
	var raw := int(part.raw)
	var body := bytes.slice(int(part.at), int(part.at) + int(part.size))
	if raw == 0 or body.is_empty():
		return PackedByteArray()
	var out := body.decompress(raw, FileAccess.COMPRESSION_ZSTD)
	if out.size() != raw:
		return PackedByteArray()
	return out


## A raw size a heights / splat section may have: res * res * 4 for an allowed res.
static func _grid_raw(n: int) -> bool:
	for w in LevelDoc.WORLDS:
		var r := int(w[1])
		if n == r * r * 4:
			return true
	return false


## A non-negative integral number within MAX_FILE.
static func _count(v: Variant) -> bool:
	return _is_num(v) and is_finite(float(v)) and float(v) >= 0.0 and float(v) <= MAX_FILE and float(v) == floorf(float(v))


static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT


static func _hex(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)):
			return false
	return true


static func _u32be(b: PackedByteArray, at: int) -> int:
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]
