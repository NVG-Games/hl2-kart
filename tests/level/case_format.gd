extends RefCounted
## P1: the .hl2kt container and the one gate (2.1, 2.2, 2.3, 2.8, 2.9, 2.10, 6.9). Blank and
## hand-made documents round-trip byte-identical (pack -> unpack -> pack); the header-only read;
## sha / ids; the thumb is written first; every hostile case is refused or cleaned with its report
## code; a 20-1000 m field with a 350 m cliff and holes round-trips exactly through the int32 deltas;
## slugs; .tmp recovery; save_async; migrate is a no-op on format 1 and format 2 is refused.

const NEEDS_CONTENT := false

var t: Node


func run(t_: Node) -> void:
	t = t_
	_round_trips()
	_header_and_ids()
	_hostile_container()
	_hostile_doc()
	_heights()
	_thumbs()
	_slugs()
	await _files()
	_paste()


# ---------------------------------------------------------------- helpers

## A doc in the canonical form sanitize gives: something in every section.
func _hand_doc() -> LevelDoc:
	var d := LevelDoc.blank("Canal Run", 1024.0, 513)
	var x: Dictionary = d.data
	x.guid = "0123456789abcdef0123456789abcdef"
	x.author = "Tester"
	x.desc = "A canal, a bridge and a shortcut."
	x.created = 1763500000
	x.modified = 1763590000
	x.content = 4
	x.app = "0.3.0"
	x.theme = "coast"
	x.remix_of = {"guid": "fedcba9876543210fedcba9876543210", "name": "Old Canal", "author": "Someone"}
	x.styles = {"my_road": {"name": "MY ROAD", "kind": "street", "road": "concrete/concretefloor006a", "lines": true,
		"curb_h": 0.2, "barrier_r": {"kind": "wall", "mat": "concrete/concretewall008a", "h": 1.5, "thick": 0.5,
		"off": 0.2, "col_h": 2.5, "rep": 3.0}}}
	var pts := []
	for i in 6:
		var a := TAU * i / 6.0
		var p := {"uid": i + 1, "pos": [snappedf(cos(a) * 200.0, 0.001), 2.5 * i, snappedf(sin(a) * 200.0, 0.001)],
			"width": 14.0, "style": "asphalt", "seesaw": false, "follow": i % 2 == 0}
		pts.append(p)
	pts[1]["bank"] = 8.0
	pts[1]["handle"] = {"dir": [1.0, 0.0, 0.0], "in": 20.0, "out": 35.0}
	pts[2]["style"] = "my_road"
	pts[2]["grip"] = "offroad"
	pts[2]["barrier_l"] = {"kind": "none"}
	pts[3]["gap"] = {"len": 12.0, "at": 0.25, "lift": 1.8, "ramp": 16.0}
	pts[4]["style"] = "tunnel"
	pts[4]["tunnel_h"] = 8.0
	pts[5]["barrier_r"] = {"kind": "rail", "mat": "metal/metalrail013a", "h": 1.0, "thick": 0.05, "off": 0.2,
		"col_h": 2.5, "rep": 3.0}
	x.road = {"closed": true, "start": {"p": 1, "t": 0.5}, "points": pts}
	x.branches = [{"uid": 10, "name": "SHORTCUT", "kind": "alt", "fork": {"p": 2, "t": 0.25}, "merge": {"p": 4, "t": 0.75},
		"side": 1, "merge_side": -1, "points": [{"uid": 11, "pos": [10.0, 3.0, 20.0], "width": 10.0, "style": "dirt",
		"seesaw": false, "follow": true}, {"uid": 12, "pos": [-10.0, 4.0, 30.0], "width": 10.0, "style": "dirt",
		"seesaw": false, "follow": false}], "ai": {"take": 0.7, "min_skill": 0.2, "commit": 40.0}, "risk": 0.1,
		"respawn": "before", "retry_back": 45.0, "offtrack": -1.0}]
	x.water = {"sea": true, "level": -2.0}
	x.props = [
		{"uid": 20, "model": "props_c17/oildrum001a", "pos": [1.5, 0.0, 2.25], "yaw": 90.0, "pitch": 0.0, "roll": 0.0,
			"scale": 1.0, "physics": true, "tag": ""},
		{"uid": 21, "model": "combine_citadel", "pos": [2500.0, 10.0, -900.0], "yaw": 10.0, "pitch": 0.0, "roll": 0.0,
			"scale": 40.0, "physics": false, "tag": "far", "group": 7},
		{"uid": 22, "model": "props_junk/wood_crate001a", "pos": [5.0, 0.0, 5.0], "yaw": -45.5, "pitch": 5.0, "roll": -5.0,
			"scale": 1.25, "physics": false, "tag": "float"}]
	x.items = [{"uid": 30, "road": -1, "at": {"p": 3, "t": 0.5}, "count": 0, "inset": 2.5},
		{"uid": 31, "road": 10, "at": {"p": 11, "t": 0.5}, "count": 3, "inset": 2.0}]
	x.crates = [{"uid": 32, "pos": [0.0, 1.0, 0.0]}]
	x.pads = [{"uid": 33, "road": -1, "at": {"p": 5, "t": 0.125}, "lat": 2.0, "turn": 10.0},
		{"uid": 34, "road": -1, "at": {"p": 6, "t": 0.0}, "turn": 0.0}]
	x.barrels = [{"uid": 35, "road": 10, "at": {"p": 12, "t": 0.5}}]
	x.hazards = [
		{"uid": 40, "type": "turret", "at": {"p": 1, "t": 0.75}, "side": 1, "zone": null, "feel": "normal",
			"setback": 1.6, "mount": "floor", "pts": [], "p": {"model": "hl1/sentry", "range": 40.0, "cone": 60.0}},
		{"uid": 41, "type": "strike_zone", "at": null, "side": 0, "zone": [{"p": 2, "t": 0.0}, {"p": 3, "t": 0.5}],
			"feel": "brutal", "style": "arc", "pts": [[120.0, 5.0, -40.0]], "p": {"every": 2.2}},
		{"uid": 42, "type": "minefield", "at": {"p": 4, "t": 0.5}, "side": 0, "zone": null, "feel": "custom",
			"pts": [[10.0, -2.0], [14.0, 3.0], [18.0, 0.0], [22.0, -4.0]], "p": {"range": 3.5}},
		{"uid": 43, "type": "antlion", "at": {"p": 5, "t": 0.5}, "side": -1, "zone": [{"p": 5, "t": 0.0}, {"p": 6, "t": 0.5}],
			"feel": "easy", "pts": [{"at": {"p": 5, "t": 0.25}, "side": 1, "setback": 6.0}], "p": {"count": [1.0, 3.0]}},
		{"uid": 44, "type": "field_gate", "at": {"p": 6, "t": 0.5}, "side": 0, "zone": null, "feel": "normal", "lat": 1.5,
			"pts": [], "p": {"pattern": [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0]], "step": 2.0, "on": true}}]
	x.crowds = [{"uid": 50, "road": -1, "at": {"p": 2, "t": 0.5}, "side": -1, "length": 20.0, "rows": 2, "density": 1.0,
		"setback": 2.5, "role": "rebel", "mood": "excited", "sit": 0.0, "tags": ["start"]}]
	x.eggs = [{"uid": 51, "kind": "birds", "pos": [3.0, 2.0, 1.0], "yaw": 0.0, "species": "crow", "radius": 12.0, "count": 9},
		{"uid": 52, "kind": "zombies", "pos": [4.0, 0.0, 1.0], "yaw": 30.0, "path": [[4.0, 0.0, 1.0], [8.0, 0.0, 2.0]], "count": 4},
		{"uid": 53, "kind": "gman", "pos": [6.0, 0.0, 1.0], "yaw": 0.0, "chance": 0.5}]
	x.lights = [{"uid": 54, "pos": [0.0, 5.0, 0.0], "color": [1.0, 0.5, 0.25], "range": 16.0, "energy": 1.2}]
	x.fires = [{"uid": 55, "pos": [1.0, 0.0, 9.0], "size": 2.0, "smoke": 1.0, "light": true}]
	x.lakes = [{"uid": 56, "center": [50.0, -60.0], "size": [40.0, 80.0], "level": 1.5}]
	x.zones = [{"uid": 57, "road": -1, "a": {"p": 1, "t": 0.0}, "b": {"p": 2, "t": 0.5}, "scale": 0.4, "ease": 15.0}]
	x.screens = [{"uid": 58, "pos": [9.0, 3.0, 9.0], "yaw": 180.0, "w": 8.0, "h": 4.5}]
	x.env = {"sky": "sky_day01_01", "sun": {"az": 120.0, "el": 40.0}, "sun_color": [1.0, 0.9, 0.74], "sun_energy": 1.5,
		"ambient": [0.5, 0.42, 0.62], "ambient_energy": 1.0, "fog_color": [0.6, 0.66, 0.72], "fog_begin": 180.0,
		"fog_end": 1500.0, "fog_sky": 0.2, "exposure": 1.08, "glow": 0.35, "sky_energy": 1.2, "sdfgi": false}
	x.race = {"gantry": "xen", "background": "city17", "citadel": [100.0, 0.0, -300.0, 1.5],
		"seagulls": [[10.0, 30.0, 10.0, 25.0]], "rescue": "crane", "offtrack": 60.0, "laps": 4, "music": ["hl2_song12", "hl1_song3"]}
	x.bake = {"main_n": 600, "branch_n": {"10": 30}, "rows": {"30": 4}}
	x.next_uid = 59
	# a hill on the terrain, 1 cm steps
	var r := d.res()
	for z in range(100, 140):
		for xx in range(200, 260):
			d.heights[z * r + xx] = snappedf(5.0 + 0.01 * (xx - 200) * (z - 100), 0.01)
	d.splat[(120 * r + 220) * 4 + 1] = 200
	return d


func _part(id: String, codec: String, raw: int, body: PackedByteArray) -> Array:
	return [id, codec, raw, body]


func _zdoc(d: Variant) -> Array:
	var raw := JSON.stringify(d).to_utf8_buffer()
	return _part("doc", "zstd", raw.size(), raw.compress(FileAccess.COMPRESSION_ZSTD))


## A container from a meta dict (sections filled in from parts) and its parts.
func _container(meta: Dictionary, parts: Array, version := 1, magic := "HL2KT") -> PackedByteArray:
	var secs := []
	for p in parts:
		secs.append({"id": p[0], "codec": p[1], "raw": p[2], "size": (p[3] as PackedByteArray).size()})
	var m := meta.duplicate(true)
	m["sections"] = secs
	return _raw(JSON.stringify(m).to_utf8_buffer(), parts, version, magic)


func _raw(meta_bytes: PackedByteArray, parts: Array, version := 1, magic := "HL2KT", meta_len := -1) -> PackedByteArray:
	var out := magic.to_ascii_buffer()
	out.append(version)
	var ml := PackedByteArray()
	ml.resize(4)
	ml.encode_u32(0, meta_bytes.size() if meta_len < 0 else meta_len)
	out.append_array(ml)
	out.append_array(meta_bytes)
	for p in parts:
		out.append_array(p[3])
	return out


func _meta() -> Dictionary:
	return {"format": 1, "kind": "hl2kart_track", "name": "H"}


## A blank doc without terrain (no height / splat sections needed).
func _flat() -> Dictionary:
	return LevelDoc.blank("Hostile", 1024.0, 1).data


func _refused(bytes: PackedByteArray, code: String, what: String) -> void:
	var rep := LevelReport.new()
	var d := LevelIO.unpack(bytes, rep)
	t.check(d == null and rep.has(code) and rep.fatal() != "", "%s: refused with %s (got %s)" % [what, code,
		str(rep.items[0].code) if not rep.items.is_empty() else "nothing"])


## sanitize of a raw dict; returns [clean, report].
func _san(raw: Dictionary) -> Array:
	var rep := LevelReport.new()
	return [LevelDoc.sanitize(raw, rep), rep]


func _png(w: int, h: int, depth := 8, colour := 2) -> PackedByteArray:
	var out := PackedByteArray([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
	var ihdr := PackedByteArray([0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52])
	ihdr.append_array(_be(w))
	ihdr.append_array(_be(h))
	ihdr.append_array(PackedByteArray([depth, colour, 0, 0, 0, 0, 0, 0, 0]))
	out.append_array(ihdr)
	# a zlib stream of zeros as the IDAT (the probe file: a small PNG with a huge declared size)
	var zeros := PackedByteArray()
	zeros.resize(4096)
	zeros.fill(0)
	var idat := zeros.compress(FileAccess.COMPRESSION_DEFLATE)
	out.append_array(_be(idat.size()))
	out.append_array("IDAT".to_ascii_buffer())
	out.append_array(idat)
	out.append_array(PackedByteArray([0, 0, 0, 0]))
	out.append_array(PackedByteArray([0, 0, 0, 0, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82]))
	return out


func _be(v: int) -> PackedByteArray:
	return PackedByteArray([(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255])


func _same_heights(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if is_nan(a[i]) != is_nan(b[i]) or (not is_nan(a[i]) and a[i] != b[i]):
			return false
	return true


func _meta_of(bytes: PackedByteArray) -> Dictionary:
	var ml := bytes.decode_u32(6)
	var j := JSON.new()
	if j.parse(bytes.slice(10, 10 + ml).get_string_from_utf8()) != OK or not (j.data is Dictionary):
		return {}
	return j.data


# ---------------------------------------------------------------- cases

func _round_trips() -> void:
	for spec in [["blank 1024/513", LevelDoc.blank("Blank", 1024.0, 513)], ["blank, no terrain", LevelDoc.blank("Open", 2048.0, 1)],
			["hand-made", _hand_doc()]]:
		var nm: String = spec[0]
		var d: LevelDoc = spec[1]
		# canonical: sanitize gives the same dict back with an empty report
		var s := _san(d.data)
		var srep: LevelReport = s[1]
		t.check(s[0] == d.data, "%s: sanitize returns the document unchanged" % nm)
		t.check(srep.items.is_empty() and srep.dropped.is_empty(), "%s: sanitize reports nothing (%s)" % [nm, str(srep.to_dict().items)])
		var a := LevelIO.pack(d, {"length": 1256.5, "raceable": true, "errors": 0, "warnings": 2})
		t.check(a.size() > 10 and a.slice(0, 5).get_string_from_ascii() == "HL2KT", "%s: packed" % nm)
		var rep := LevelReport.new()
		var u := LevelIO.unpack(a, rep)
		t.check(u != null, "%s: unpacked (%s)" % [nm, rep.fatal()])
		if u == null:
			continue
		t.check(rep.items.is_empty() and rep.dropped.is_empty(), "%s: unpack reports nothing" % nm)
		t.check(u.data == d.data and JSON.stringify(u.data) == JSON.stringify(d.data), "%s: the document comes back identical" % nm)
		t.check(_same_heights(u.heights, d.heights) and u.splat == d.splat, "%s: heights and splat come back identical" % nm)
		t.check(u.report == rep and u.revision == 0, "%s: the doc carries the unpack report" % nm)
		var b := LevelIO.pack(u, {"length": 1256.5, "raceable": true, "errors": 0, "warnings": 2})
		t.check(a == b, "%s: pack -> unpack -> pack is byte-identical (%d / %d bytes)" % [nm, a.size(), b.size()])
		var m := _meta_of(a)
		var ids := []
		for sec in m.get("sections", []):
			ids.append(sec.id)
		var want := ["doc", "height", "splat"] if bool(d.data.world.terrain) else ["doc"]
		t.check(ids == want, "%s: sections %s" % [nm, str(ids)])
	# the hand-made doc: a few facts of the header
	var h := _hand_doc()
	var hb := LevelIO.pack(h, {"outline": [[0.1, 0.2], [0.5, 0.9]], "view": [1.0, 2.0, 3.0, 45.0, -30.0], "bogus": 1})
	var hm := _meta_of(hb)
	t.check(hm.name == "Canal Run" and hm.short == "CANAL RUN" and hm.guid == h.data.guid and int(hm.props) == 3
		and int(hm.hazards) == 5 and int(hm.branches) == 1 and hm.rescue == "crane", "header: name, guid, counts, rescue")
	t.check(hm.has("outline") and hm.has("view") and not hm.has("bogus"), "header: outline and view kept, unknown extra dropped")
	t.check(hm.remix_of.name == "Old Canal", "header: remix_of")
	# a doc written with non-canonical values comes back canonical, and then stays put
	var nc := LevelDoc.blank("Loose", 1024.0, 513)
	nc.data.road.points = [{"uid": 1, "pos": [1.00049, 0, 2], "width": 14, "style": "asphalt"},
		{"uid": 2, "pos": Vector3(30, 0, 0), "width": 14.0}, {"uid": 3, "pos": [0, 0, 30], "bank": null}]
	nc.data.road.closed = true
	nc.data.race.laps = 3.0
	var p1 := LevelIO.pack(nc)
	var u1 := LevelIO.unpack(p1, LevelReport.new())
	t.check(u1 != null and u1.data.road.points[0].pos == [1.0, 0.0, 2.0] and u1.data.road.points[1].pos == [30.0, 0.0, 0.0]
		and typeof(u1.data.race.laps) == TYPE_INT and not u1.data.road.points[2].has("bank")
		and u1.data.road.start == {"p": 1, "t": 0.0}, "non-canonical values are written canonical (1 mm, ints, no nulls, start set)")
	t.check(u1 != null and LevelIO.pack(u1) == p1, "a canonicalised doc packs to the same bytes again")
	t.check(LevelDoc.migrate(h.data) == h.data and is_same(LevelDoc.migrate(h.data), h.data), "migrate is a no-op on format 1")


func _header_and_ids() -> void:
	var d := _hand_doc()
	var png := Image.create(480, 320, false, Image.FORMAT_RGB8)
	png.fill(Color(0.2, 0.4, 0.6))
	d.thumb = png.save_png_to_buffer()
	d.thumb_custom = true
	var bytes := LevelIO.pack(d, {"length": 999.0, "raceable": false, "errors": 2})
	var m := _meta_of(bytes)
	var ml := bytes.decode_u32(6)
	t.check(not m.is_empty() and m.sections[0].id == "thumb" and m.sections[0].codec == "png", "thumb is the first section")
	t.check(bytes.slice(10 + ml, 10 + ml + 8) == PackedByteArray([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
		"the PNG starts right after the header")
	var u := LevelIO.unpack(bytes, LevelReport.new())
	t.check(u != null and u.thumb == d.thumb and u.thumb_custom, "thumb and thumb_custom come back")
	var path: String = t.tmp("format/canal.hl2kt")
	t.check(LevelIO.save(d, path, {"length": 999.0, "raceable": false, "errors": 2}) == OK, "save")
	t.check(not FileAccess.file_exists(path + ".tmp"), "save leaves no .tmp")
	var rm := LevelIO.read_meta(path)
	t.check(rm.get("name") == "Canal Run" and rm.get("guid") == d.data.guid and is_equal_approx(float(rm.get("length", 0)), 999.0)
		and rm.get("raceable") == false and int(rm.get("errors", -1)) == 2 and (rm.get("sections", []) as Array).size() == 4,
		"read_meta: the header only, sanitized")
	t.check(LevelIO.read_meta(t.tmp("format/none.hl2kt")).is_empty(), "read_meta of a missing file is {}")
	var sha := LevelIO.sha256(bytes)
	var fsha := LevelIO.file_sha256(path)
	t.check(LevelIO.is_sha(sha) and sha == fsha, "sha256 of the bytes = file_sha256 of the file")
	t.check(LevelIO.id_for(sha) == "c_" + sha.left(16) and CustomTracksShape.ok(LevelIO.id_for(sha)), "id_for: c_ + 16 hex")
	t.check(LevelIO.id_for("c_edit") == "" and LevelIO.id_for("../../x") == "" and LevelIO.id_for(sha.to_upper()) == ""
		and LevelIO.id_for(sha + "0") == "", "id_for refuses other shapes")
	t.check(not LevelIO.is_sha("") and not LevelIO.is_sha(sha.left(63)) and not LevelIO.is_sha(sha.left(63) + "g")
		and not LevelIO.is_sha(sha.to_upper()), "is_sha: exactly 64 lower hex")


## The custom id shape (2.9) as CustomTracks.valid_id checks it.
class CustomTracksShape:
	static func ok(id: String) -> bool:
		if id.length() != 18 or not id.begins_with("c_"):
			return false
		for i in range(2, 18):
			var c := id.unicode_at(i)
			if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)):
				return false
		return true


func _hostile_container() -> void:
	var good := _container(_meta(), [_zdoc(_flat())])
	t.check(LevelIO.unpack(good, LevelReport.new()) != null, "hostile base: the hand-built container unpacks")
	var bm := good.duplicate()
	bm[4] = 0x58
	_refused(bm, "bad_magic", "bad magic")
	_refused(PackedByteArray([0x48, 0x4c]), "bad_magic", "2 bytes")
	_refused(_container(_meta(), [_zdoc(_flat())], 2), "bad_container", "container version 2")
	var mb := JSON.stringify(_meta()).to_utf8_buffer()
	_refused(_raw(mb, [_zdoc(_flat())], 1, "HL2KT", 9000), "bad_meta", "meta_len 9000")
	var big_meta := _meta()
	big_meta["desc"] = "x".repeat(9000)
	_refused(_container(big_meta, [_zdoc(_flat())]), "bad_meta", "a 9 KB header")
	_refused(_raw("[1, 2, 3]".to_utf8_buffer(), [_zdoc(_flat())]), "bad_meta", "meta not a dict")
	_refused(_raw("{\"name\": ".to_utf8_buffer(), [_zdoc(_flat())]), "bad_meta", "meta not JSON")
	# section sizes off by one
	var zd := _zdoc(_flat())
	var m1 := _meta()
	m1["sections"] = [{"id": "doc", "codec": "zstd", "raw": zd[2], "size": (zd[3] as PackedByteArray).size() + 1}]
	_refused(_raw(JSON.stringify(m1).to_utf8_buffer(), [zd]), "bad_sections", "a section 1 byte longer than the file")
	m1["sections"] = [{"id": "doc", "codec": "zstd", "raw": zd[2], "size": (zd[3] as PackedByteArray).size() - 1}]
	_refused(_raw(JSON.stringify(m1).to_utf8_buffer(), [zd]), "bad_sections", "a section 1 byte short of the file")
	var extra := good.duplicate()
	extra.append(0)
	_refused(extra, "bad_sections", "a trailing byte")
	m1["sections"] = [{"id": "doc", "codec": "png", "raw": zd[2], "size": (zd[3] as PackedByteArray).size()}]
	_refused(_raw(JSON.stringify(m1).to_utf8_buffer(), [zd]), "bad_sections", "the wrong codec")
	m1["sections"] = [{"id": "doc", "codec": "zstd", "raw": zd[2], "size": (zd[3] as PackedByteArray).size()},
		{"id": "doc", "codec": "zstd", "raw": zd[2], "size": (zd[3] as PackedByteArray).size()}]
	_refused(_raw(JSON.stringify(m1).to_utf8_buffer(), [zd, zd]), "bad_sections", "a section twice")
	m1["sections"] = "doc"
	_refused(_raw(JSON.stringify(m1).to_utf8_buffer(), [zd]), "bad_sections", "sections not a list")
	m1["sections"] = [{"id": "doc", "codec": "zstd", "raw": -5, "size": (zd[3] as PackedByteArray).size()}]
	_refused(_raw(JSON.stringify(m1).to_utf8_buffer(), [zd]), "bad_sections", "a negative raw size")
	var sp := PackedByteArray()
	sp.resize(257 * 257 * 4)
	_refused(_container(_meta(), [_part("splat", "zstd", sp.size(), sp.compress(FileAccess.COMPRESSION_ZSTD))]), "no_doc", "no doc section")
	# doc raw 5 MiB declared (C1 S2), raw declared too small, a zstd bomb
	var dbody: PackedByteArray = zd[3]
	_refused(_container(_meta(), [_part("doc", "zstd", 5 << 20, dbody)]), "doc_too_big", "doc raw 5 MiB declared")
	_refused(_container(_meta(), [_part("doc", "zstd", int(zd[2]) - 10, dbody)]), "bad_doc", "doc raw declared too small")
	_refused(_container(_meta(), [_part("doc", "zstd", int(zd[2]) + 10, dbody)]), "bad_doc", "doc raw declared too big")
	var zeros := PackedByteArray()
	zeros.resize(8 << 20)
	zeros.fill(0)
	var bomb := zeros.compress(FileAccess.COMPRESSION_ZSTD)
	_refused(_container(_meta(), [_part("doc", "zstd", 1024, bomb)]), "bad_doc", "a zstd bomb (8 MiB of zeros declared as 1 KiB)")
	_refused(_container(_meta(), [_part("doc", "zstd", 1024, PackedByteArray([1, 2, 3, 4, 5]))]), "bad_doc", "garbage zstd")
	# a real 5 MiB document (C1 S2)
	var fat := _flat()
	fat["padding"] = "x".repeat(5 << 20)
	_refused(_container(_meta(), [_zdoc(fat)]), "doc_too_big", "a 5 MiB doc")
	# 16 MiB + 1
	var huge := good.duplicate()
	huge.resize(LevelIO.MAX_FILE + 1)
	_refused(huge, "too_big", "a file over 16 MiB")
	# format 2 in the header, then in the doc
	var m2 := _meta()
	m2["format"] = 2
	_refused(_container(m2, [_zdoc(_flat())]), "newer_format", "header format 2")
	var f2 := _flat()
	f2["format"] = 2
	var rep := LevelReport.new()
	t.check(LevelIO.unpack(_container(_meta(), [_zdoc(f2)]), rep) == null and rep.fatal().contains("newer version"),
		"doc format 2: \"%s\"" % rep.fatal())
	var k2 := _flat()
	k2["kind"] = "zip"
	_refused(_container(_meta(), [_zdoc(k2)]), "not_a_track", "kind is not hl2kart_track")
	var nf := _flat()
	nf.erase("format")
	_refused(_container(_meta(), [_zdoc(nf)]), "bad_doc", "no format")
	_refused(_container(_meta(), [_zdoc([1, 2])]), "bad_doc", "doc not a dict")
	# nesting 2000 deep: the parser refuses it
	var deep := "{\"format\": 1, \"kind\": \"hl2kart_track\", \"x\": " + "[".repeat(2000) + "]".repeat(2000) + "}"
	var draw := deep.to_utf8_buffer()
	_refused(_container(_meta(), [_part("doc", "zstd", draw.size(), draw.compress(FileAccess.COMPRESSION_ZSTD))]), "bad_doc", "2000-deep nesting")
	# terrain sections: wrong raw for res, missing, not a grid size
	var td := LevelDoc.blank("T", 1024.0, 513)
	var hr := PackedByteArray()
	hr.resize(257 * 257 * 4)
	var spl := PackedByteArray()
	spl.resize(513 * 513 * 4)
	var hz := hr.compress(FileAccess.COMPRESSION_ZSTD)
	var sz := spl.compress(FileAccess.COMPRESSION_ZSTD)
	_refused(_container(_meta(), [_zdoc(td.data), _part("height", "i32d+zstd", hr.size(), hz), _part("splat", "zstd", spl.size(), sz)]),
		"bad_height", "height raw for res 257 in a res 513 world")
	_refused(_container(_meta(), [_zdoc(td.data), _part("splat", "zstd", spl.size(), sz)]), "bad_height", "terrain without a height section")
	_refused(_container(_meta(), [_zdoc(td.data), _part("height", "i32d+zstd", 1000, hz), _part("splat", "zstd", spl.size(), sz)]),
		"bad_height", "a height raw that fits no world")
	var h5 := PackedByteArray()
	h5.resize(513 * 513 * 4)
	_refused(_container(_meta(), [_zdoc(td.data), _part("height", "i32d+zstd", h5.size(), h5.compress(FileAccess.COMPRESSION_ZSTD)),
		_part("splat", "zstd", hr.size(), hz)]), "bad_splat", "splat raw for res 257 in a res 513 world")
	# a PNG declaring 8192 x 8192: dropped before any decode, the track kept (C1 M3)
	var bad_png := _png(8192, 8192)
	t.check(bad_png.size() < 1024 and not LevelIO.png_ok(bad_png), "a %d-byte PNG declaring 8192 x 8192 fails png_ok" % bad_png.size())
	var rep2 := LevelReport.new()
	var kept := LevelIO.unpack(_container(_meta(), [_part("thumb", "png", bad_png.size(), bad_png), _zdoc(_flat())]), rep2)
	t.check(kept != null and kept.thumb.is_empty() and int(rep2.dropped.get("thumb", 0)) == 1 and rep2.has("thumb_refused")
		and rep2.raceable(), "the 8192 x 8192 thumb is dropped, the track kept")
	var box := {}
	var task := WorkerThreadPool.add_task(func() -> void:
		var t0 := Time.get_ticks_usec()
		box["img"] = LevelIO.decode_thumb(bad_png)
		box["us"] = Time.get_ticks_usec() - t0)
	WorkerThreadPool.wait_for_task_completion(task)
	t.check(box.get("img") == null and int(box.get("us", 99999999)) < 20000, "decode_thumb refuses it without decoding (%d us)" % int(box.get("us", -1)))


func _hostile_doc() -> void:
	# NaN / INF numbers (INF also through JSON: 1e999)
	var d := _flat()
	d.road.points = [{"uid": 1, "pos": [NAN, 0.0, 0.0], "width": 14.0}, {"uid": 2, "pos": [0.0, 0.0, 5.0], "width": INF},
		{"uid": 3, "pos": [5.0, 0.0, 0.0], "width": 14.0, "bank": -INF}]
	d.env.glow = NAN
	var s := _san(d)
	var c: Dictionary = s[0]
	var rep: LevelReport = s[1]
	t.check(c.road.points.size() == 2 and c.road.points[0].width == 14.0 and not c.road.points[1].has("bank")
		and c.env.glow == 0.35 and rep.has("bad_number"), "NaN / INF: replaced or the item dropped (bad_number)")
	var txt := JSON.stringify(_flat()).replace("\"fog_sky\":0.0", "\"fog_sky\":1e999")
	var raw := txt.to_utf8_buffer()
	var rep_j := LevelReport.new()
	var uj := LevelIO.unpack(_container(_meta(), [_part("doc", "zstd", raw.size(), raw.compress(FileAccess.COMPRESSION_ZSTD))]), rep_j)
	t.check(txt.contains("1e999") and uj != null and uj.data.env.fog_sky == 0.0 and rep_j.has("bad_number"), "1e999 in the JSON is cleaned")
	# 10 000 props (cap 3000; physics cap 300)
	var many := _flat()
	var props := []
	for i in 10000:
		props.append({"uid": 100 + i, "model": "props_c17/oildrum001a", "pos": [float(i % 100), 0.0, floorf(i / 100.0)],
			"yaw": 0.0, "pitch": 0.0, "roll": 0.0, "scale": 1.0, "physics": true, "tag": ""})
	many.props = props
	var rep_m := LevelReport.new()
	var many_bytes := _container(_meta(), [_zdoc(many)])
	var box := {}
	var ms_many: float = t.ms(func() -> void: box["doc"] = LevelIO.unpack(many_bytes, rep_m))
	var um: LevelDoc = box.doc
	t.log("10 000 props: unpack %.0f ms (%d bytes)" % [ms_many, many_bytes.size()])
	var phys := 0
	if um != null:
		for p in um.data.props:
			phys += 1 if p.physics else 0
	t.check(um != null and um.data.props.size() == 3000 and int(rep_m.dropped.get("props", 0)) == 7000 and rep_m.has("over_cap")
		and phys == 300, "10 000 props: 3000 kept (300 with physics), 7000 dropped (over_cap)")
	t.check(um != null and um.data.next_uid == 100 + 2999 + 1, "next_uid follows the largest kept uid")
	# paths in content keys
	var keys := _flat()
	keys.props = [{"uid": 1, "model": "../../x", "pos": [0.0, 0.0, 0.0]}, {"uid": 2, "model": "res://scenes/main.tscn", "pos": [0.0, 0.0, 0.0]},
		{"uid": 3, "model": "C:\\x", "pos": [0.0, 0.0, 0.0]}, {"uid": 4, "model": "props_c17/oildrum001a", "pos": [0.0, 0.0, 0.0]}]
	keys.env.sky = "user://evil"
	keys.race.music = ["res://a.ogg", "hl1_song3", "hl1_song3", "..\\b"]
	keys.terrain.layers.rock = "file:///etc/passwd"
	keys.styles = {"own": {"name": "OWN", "kind": "open", "road": "../secret", "verge": "nature/grassfloor002a"}}
	var sk := _san(keys)
	var ck: Dictionary = sk[0]
	var rk: LevelReport = sk[1]
	t.check(ck.props.size() == 1 and ck.props[0].uid == 4 and ck.env.sky == LevelDoc.DEFAULT_SKY and ck.race.music == ["hl1_song3"]
		and ck.terrain.layers.rock == LevelDoc.LAYERS.rock and not ck.styles.own.has("road") and rk.has("bad_key"),
		"\"../../x\", res://, user://, file:// and \\ keys are refused (bad_key)")
	# unknown hazard type, unknown keys, duplicate uids, anchors to missing points
	var mix := _flat()
	mix.road.points = [{"uid": 1, "pos": [0.0, 0.0, 0.0]}, {"uid": 2, "pos": [50.0, 0.0, 0.0]}, {"uid": 3, "pos": [0.0, 0.0, 50.0]},
		{"uid": 3, "pos": [9.0, 0.0, 9.0]}]
	mix.road.closed = true
	mix.hazards = [{"uid": 10, "type": "nuke", "at": {"p": 1, "t": 0.5}}, {"uid": 11, "type": "turret", "at": {"p": 99, "t": 0.5}},
		{"uid": 12, "type": "turret", "at": {"p": 2, "t": 0.5}, "mode": "walk", "evil": true},
		{"uid": 13, "type": "crane", "zone": [{"p": 1, "t": 0.0}, {"p": 77, "t": 0.0}]}]
	mix.items = [{"uid": 2, "road": -1, "at": {"p": 1, "t": 0.5}}, {"uid": 14, "road": 555, "at": {"p": 1, "t": 0.5}},
		{"uid": 15, "road": -1, "at": {"p": 2, "t": 2.0}}]
	mix.branches = [{"uid": 20, "fork": {"p": 1, "t": 0.0}, "merge": {"p": 404, "t": 0.0}, "points": [{"uid": 21, "pos": [1.0, 0.0, 1.0]}]}]
	mix["evil_key"] = {"x": 1}
	mix.env["shader"] = "res://evil.gdshader"
	var sm := _san(mix)
	var cm: Dictionary = sm[0]
	var rm: LevelReport = sm[1]
	t.check(cm.hazards.size() == 1 and cm.hazards[0].uid == 12 and not cm.hazards[0].has("mode") and rm.has("unknown_hazard"),
		"an unknown hazard type drops that hazard; no mode key (unknown_hazard)")
	t.check(rm.has("unknown_key") and not cm.has("evil_key") and not cm.env.has("shader") and int(rm.dropped.get("meta", 0)) >= 1
		and int(rm.dropped.get("env", 0)) == 1, "unknown keys dropped and counted (unknown_key)")
	t.check(cm.road.points.size() == 3 and cm.items.size() == 1 and cm.items[0].uid == 15 and rm.has("dup_uid"),
		"duplicate uids: the later item dropped (dup_uid)")
	t.check(cm.items[0].at.t == 1.0, "an anchor t over 1 is clamped")
	t.check(cm.branches.is_empty() and rm.has("bad_anchor") and int(rm.dropped.get("hazards", 0)) == 5,
		"anchors to missing points (a hazard, a zone end, a branch end, another road) drop the item (bad_anchor)")
	# long names with control characters and [ ] { }
	var names := _flat()
	names.name = "\u0001[b]{boost}" + "Long \u0007name\n".repeat(400)
	names.author = "{auth}\t" + "a".repeat(5000)
	names.desc = "[img]x[/img] " + "d".repeat(5000)
	var sn := _san(names)
	var cn: Dictionary = sn[0]
	var bad := false
	for k in ["name", "short", "author", "desc"]:
		var v: String = cn[k]
		for ch in ["[", "]", "{", "}", "\u0001", "\u0007", "\n", "\t"]:
			if v.contains(ch):
				bad = true
	t.check(not bad and cn.name.length() <= 48 and cn.short.length() <= 16 and cn.author.length() == 24 and cn.desc.length() == 280
		and cn.name.begins_with("bboost") and (sn[1] as LevelReport).has("bad_text"), "5000-char names: cut, control chars and [ ] { } stripped (bad_text)")
	# positions outside the world, far props, float without a sea, the world itself
	var pos := _flat()
	pos.world = {"size": 1000.0, "res": 7, "terrain": false}
	pos.props = [{"uid": 1, "model": "m", "pos": [9000.0, 5000.0, -9000.0]}, {"uid": 2, "model": "m", "tag": "far", "pos": [2900.0, 0.0, -2900.0], "scale": 100.0},
		{"uid": 3, "model": "m", "tag": "far", "pos": [99999.0, 0.0, 0.0]}, {"uid": 4, "model": "m", "tag": "float", "pos": [0.0, 0.0, 0.0], "scale": 9.0}]
	var spo := _san(pos)
	var cp: Dictionary = spo[0]
	t.check(cp.world == {"size": 1024.0, "res": 513, "terrain": false} and (spo[1] as LevelReport).has("bad_world"), "a world size that is not allowed is reset (bad_world)")
	t.check(cp.props[0].pos == [512.0, 1500.0, -512.0] and cp.props[1].pos == [2900.0, 0.0, -2900.0] and cp.props[1].scale == 100.0
		and cp.props[2].pos[0] == 3072.0 and cp.props[3].tag == "" and cp.props[3].scale == 4.0,
		"positions clamped into the world, far props within 3 x size, float cleared without a sea, scale capped")
	# hazards: heavy cap 8, mount / style only where they belong, params
	var hz := _flat()
	hz.road.points = [{"uid": 1, "pos": [0.0, 0.0, 0.0]}, {"uid": 2, "pos": [50.0, 0.0, 0.0]}, {"uid": 3, "pos": [0.0, 0.0, 50.0]}]
	var list := []
	for i in 10:
		list.append({"uid": 10 + i, "type": "crane", "at": {"p": 1, "t": 0.1 * i}})
	list.append({"uid": 30, "type": "bullsquid", "at": {"p": 2, "t": 0.5}, "mount": "ceiling", "style": "arc",
		"p": {"range": 1e9, "Bad Key": 1, "model": "../x", "nested": [[[1]]], "ok": [16.0, 30.0], "feel": "x"}})
	hz.hazards = list
	var sh := _san(hz)
	var ch: Dictionary = sh[0]
	var last: Dictionary = ch.hazards[-1]
	t.check(ch.hazards.size() == 9 and last.uid == 30, "heavy hazards over 8 are dropped")
	t.check(not last.has("mount") and not last.has("style") and last.p.range == 1000000.0 and not last.p.has("Bad Key")
		and not last.p.has("model") and not last.p.has("nested") and last.p.ok == [16.0, 30.0] and last.p.feel == "x",
		"hazard params: keys checked, numbers clamped, path-like strings and deep arrays dropped")
	# a closed road of 2 points opens; the start anchor follows the road
	var cl := _flat()
	cl.road = {"closed": true, "start": {"p": 9, "t": 0.5}, "points": [{"uid": 1, "pos": [0.0, 0.0, 0.0]}, {"uid": 2, "pos": [9.0, 0.0, 0.0]}]}
	var sc := _san(cl)
	t.check(sc[0].road.closed == false and sc[0].road.start == {"p": 1, "t": 0.0} and (sc[1] as LevelReport).has("open_road"),
		"a closed road of 2 points opens; a start on a missing point moves to the first point")
	# a style that does not exist falls back to asphalt
	var st := _flat()
	st.road.points = [{"uid": 1, "pos": [0.0, 0.0, 0.0], "style": "lava"}, {"uid": 2, "pos": [1.0, 0.0, 0.0], "style": "bridge"}]
	var ss := _san(st)
	t.check(ss[0].road.points[0].style == "asphalt" and ss[0].road.points[1].style == "bridge" and (ss[1] as LevelReport).has("unknown_style"),
		"an unknown style falls back to asphalt (unknown_style)")
	# the report of a dirty file is warnings / info only: the track stays raceable
	t.check(rm.errors() == 0 and rm.warnings() > 0, "sanitize reports warnings, never errors")
	# not even a dict where one is expected
	var junk := _flat()
	junk.road = "x"
	junk.props = {"a": 1}
	junk.env = 5
	junk.race = [1]
	var sj := _san(junk)
	t.check(sj[0].road.points.is_empty() and sj[0].props.is_empty() and sj[0].env.sky == LevelDoc.DEFAULT_SKY and sj[0].race.laps == 3,
		"sections of the wrong type become their defaults")


func _heights() -> void:
	# a 20-1000 m field with a 350 m cliff and holes (C1 M2), 1 cm steps
	var d := LevelDoc.blank("Cliff", 1024.0, 513)
	var r := 513
	var h := d.heights
	for z in r:
		for x in r:
			var v := 510.0 + 490.0 * sin(x * 0.031) * cos(z * 0.027)
			if x >= 300:
				v = minf(v + 350.0, 1500.0)
			h[z * r + x] = snappedf(clampf(v, 20.0, 1000.0 if x < 300 else 1350.0), 0.01)
	for i in range(0, r * r, 977):
		h[i] = NAN
	h[5] = 1600.0
	h[6] = -900.0
	h[7] = INF
	var want := h.duplicate()
	want[5] = 1500.0
	want[6] = -500.0
	want[7] = 1500.0
	var box := {}
	var ms_pack: float = t.ms(func() -> void: box["bytes"] = LevelIO.pack(d))
	var bytes: PackedByteArray = box.bytes
	var ms_unpack: float = t.ms(func() -> void: box["doc"] = LevelIO.unpack(bytes, LevelReport.new()))
	var u: LevelDoc = box.doc
	t.check(u != null and _same_heights(u.heights, want), "a 20-1000 m field with a 350 m cliff and holes round-trips exactly (clamped to -500..1500)")
	var holes := 0
	if u != null:
		for v in u.heights:
			holes += 1 if is_nan(v) else 0
	t.check(holes == ceili(r * r / 977.0), "holes survive (%d)" % holes)
	var deltas := LevelIO.encode_heights(want)
	t.check(LevelIO.decode_heights(deltas).size() == r * r and deltas[1] - 0 != LevelIO.HEIGHT_HOLE, "encode / decode")
	t.check(u != null and LevelIO.pack(u) == bytes, "the field packs to the same bytes again")
	t.log("heights 513^2: pack %.0f ms, unpack %.0f ms, %d bytes" % [ms_pack, ms_unpack, bytes.size()])


func _thumbs() -> void:
	var img := Image.create(480, 320, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0.5, 0, 1))
	var png := img.save_png_to_buffer()
	t.check(LevelIO.png_ok(png), "png_ok: a 480 x 320 RGBA PNG")
	t.check(not LevelIO.png_ok(_png(1025, 10)) and not LevelIO.png_ok(_png(0, 10)) and not LevelIO.png_ok(_png(64, 64, 16))
		and not LevelIO.png_ok(_png(64, 64, 8, 3)) and LevelIO.png_ok(_png(1024, 1024, 8, 6)), "png_ok: size, depth and colour type rules")
	var notpng := png.duplicate()
	notpng[1] = 0x51
	var big := png.duplicate()
	big.resize(LevelIO.MAX_THUMB + 1)
	t.check(not LevelIO.png_ok(notpng) and not LevelIO.png_ok(big) and not LevelIO.png_ok(PackedByteArray()), "png_ok: signature and MAX_THUMB")
	var box := {}
	var task := WorkerThreadPool.add_task(func() -> void: box["img"] = LevelIO.decode_thumb(png))
	WorkerThreadPool.wait_for_task_completion(task)
	var dec: Image = box.get("img")
	t.check(dec != null and dec.get_width() == 480 and dec.get_height() == 320, "decode_thumb on a worker")
	t.check(LevelIO.decode_thumb(png) == null, "decode_thumb refuses the main thread")


func _slugs() -> void:
	var cases := [["Моя трасса", "moya_trassa"], ["🙂🙂🙂", "track"], ["", "track"], ["  Hello, World!  ", "hello_world"],
		["Щука Ёж", "shchuka_ezh"], ["ПОДЪЕЗД", "podezd"], ["Їжак і Ґава є", "yizhak_i_gava_ye"], [".hidden", "hidden"],
		["con", "con_track"], ["a__b--c", "a_b_c"], ["Canal Run 2", "canal_run_2"], ["_x_", "x"]]
	for c in cases:
		t.check(LevelIO.slug(c[0]) == c[1], "slug \"%s\" -> %s (got %s)" % [c[0], c[1], LevelIO.slug(c[0])])
	var long := LevelIO.slug("A very long track name ".repeat(9))
	t.check(long.length() <= 32 and long.length() >= 30 and not long.ends_with("_"), "a 200-char name -> %d chars (%s)" % [long.length(), long])
	var dir: String = t.tmp("format/slugs")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	var p1 := LevelIO.free_path(dir, "Моя трасса")
	t.check(p1.get_file() == "moya_trassa.hl2kt", "free_path: %s" % p1.get_file())
	LevelIO.write_atomic(p1, PackedByteArray([1]))
	var p2 := LevelIO.free_path(dir, "Моя трасса")
	t.check(p2.get_file() == "moya_trassa_2.hl2kt", "free_path on a clash: %s" % p2.get_file())


func _files() -> void:
	var d := _hand_doc()
	var path: String = t.tmp("format/recover.hl2kt")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")
	t.check(LevelIO.save(d, path) == OK, "save")
	var rep := LevelReport.new()
	var back := LevelIO.load_file(path, rep)
	t.check(back != null and back.data == d.data and rep.items.is_empty(), "load_file")
	# a save that stopped between the write and the rename: only <path>.tmp is there
	DirAccess.rename_absolute(path, path + ".tmp")
	var rep2 := LevelReport.new()
	var rec := LevelIO.load_file(path, rep2)
	t.check(rec != null and rec.data == d.data and FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".tmp")
		and rep2.has("recovered"), ".tmp recovery: loaded and renamed into place")
	# a broken .tmp next to a missing file is refused, not renamed
	var broken: String = t.tmp("format/broken.hl2kt")
	DirAccess.remove_absolute(broken)
	LevelIO.write_atomic(broken + ".tmp", PackedByteArray([1, 2, 3]))
	var rep3 := LevelReport.new()
	t.check(LevelIO.load_file(broken, rep3) == null and rep3.has("bad_magic") and not FileAccess.file_exists(broken),
		"a damaged .tmp is not recovered")
	var rep4 := LevelReport.new()
	t.check(LevelIO.load_file(t.tmp("format/missing.hl2kt"), rep4) == null and rep4.has("no_file"), "load_file of a missing file")
	# save_async: snapshot now, pack + write on a worker, done(err) on the main thread
	var apath: String = t.tmp("format/async.hl2kt")
	DirAccess.remove_absolute(apath)
	var box := {"done": false, "err": -1, "main": false}
	var d2 := _hand_doc()
	LevelIO.save_async(d2, apath, {"length": 5.0}, func(err: Error) -> void:
		box.done = true
		box.err = err
		box.main = OS.get_thread_caller_id() == OS.get_main_thread_id())
	d2.apply([LevelDoc.op_set(["name"], "Changed after the snapshot")])
	var n := 0
	while not box.done and n < 600:
		await t.frames(1)
		n += 1
	t.check(box.done and box.err == OK and box.main, "save_async: done(OK) on the main thread")
	var ab := LevelIO.load_file(apath, LevelReport.new())
	t.check(ab != null and ab.data.name == "Canal Run", "save_async wrote the snapshot taken at the call")
	var bad := LevelDoc.blank("Bad", 1024.0, 513)
	bad.heights.resize(10)
	t.check(LevelIO.pack(bad).is_empty() and LevelIO.save(bad, t.tmp("format/bad.hl2kt")) != OK, "pack refuses heights of the wrong size")


func _paste() -> void:
	var rep := LevelReport.new()
	var items := LevelDoc.sanitize_items("props", [{"uid": 0, "model": "props_c17/oildrum001a", "pos": [5000.0, 0.0, 0.0]},
		{"model": "../x", "pos": [0.0, 0.0, 0.0]}, "junk", {"uid": 7, "model": "m", "pos": [1.0, 2.0, 3.0], "hack": 1}], rep)
	t.check(items.size() == 2 and items[0].uid == 0 and items[0].pos[0] == 2048.0 and items[1].uid == 7 and not items[1].has("hack"),
		"sanitize_items: shapes cleaned, uids kept for the paste to replace")
	t.check(rep.has("bad_key") and rep.has("bad_item") and rep.has("unknown_key"), "sanitize_items reports what it dropped")
	var hz := LevelDoc.sanitize_items("hazards", [{"uid": 3, "type": "turret", "at": {"p": 12, "t": 0.5}}, {"uid": 4, "type": "x", "at": {"p": 1, "t": 0.0}}], LevelReport.new())
	t.check(hz.size() == 1 and hz[0].at == {"p": 12, "t": 0.5}, "sanitize_items keeps anchors of any point (re-anchored by the paste)")
	t.check(LevelDoc.sanitize_items("nonsense", [{"uid": 1}], LevelReport.new()).is_empty(), "sanitize_items of an unknown section is empty")
	var pts := LevelDoc.sanitize_items("points", [{"uid": 1, "pos": [0.0, 0.0, 0.0], "style": "own_style"}], LevelReport.new())
	t.check(pts.size() == 1 and pts[0].style == "own_style" and pts[0].width == 14.0, "sanitize_items of road points")
