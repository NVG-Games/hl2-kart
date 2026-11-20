class_name LevelDoc
extends RefCounted
## A custom track's source document (2.3): the `data` dict (the JSON doc section) plus the terrain's
## heights and splat and the PNG thumbnail. Every edit is a list of data ops (7.5) applied with
## `apply`, which returns the exact inverse ops, bumps `revision` and emits `changed` once.
## `snapshot` gives a read-only copy for worker threads, copy-on-write per section: only the
## sections changed since the last snapshot are deep-copied, the rest are shared with it.
##
## Ops: ["set", path, value], ["erase", path], ["insert", path, index, value], ["remove", path,
## index], ["heights", [x, z, w, h], PackedFloat32Array], ["splat", [x, z, w, h], PackedByteArray].
## A path is an array of dict keys (String), array indices (int) and "#<uid>" (the element of that
## array whose `uid` is uid). A heights / splat op with a 4th element "all" ([op, [0, 0, r, r],
## values, "all"], from op_heights_all / op_splat_all) replaces the whole array, any size (RESIZE
## WORLD, NO TERRAIN); without it, cells outside the current grid are ignored.
##
## Code that writes `data`, `heights` or `splat` directly (a brush stroke) must call `notify` with
## the sections it touched, or the next snapshot will not see the change. A snapshot is read-only.

signal changed(sections: PackedStringArray, uids: PackedInt32Array, rect: Rect2i)

const FORMAT := 1
const KIND := "hl2kart_track"
const HEIGHT_MIN := -500.0
const HEIGHT_MAX := 1500.0
const SECTIONS := ["road", "branches", "styles", "terrain", "props", "items", "crates", "pads", "barrels",
	"hazards", "crowds", "eggs", "lights", "fires", "lakes", "zones", "screens", "env", "water", "race", "world", "meta"]
## The list sections whose items carry a `uid` (road points live in road.points, branch points in
## each branch's points).
const LISTS := ["branches", "props", "items", "crates", "pads", "barrels", "hazards", "crowds", "eggs",
	"lights", "fires", "lakes", "zones", "screens"]
## Allowed (world size, res) pairs (2.3).
const WORLDS := [[512.0, 257], [1024.0, 513], [2048.0, 513], [2048.0, 1025], [4096.0, 1025]]
## The ground layers' default materials.
const LAYERS := {"base": "nature/grassfloor002a", "dirt": "nature/dirtfloor003a", "rock": "nature/rockfloor006a",
	"pave": "concrete/concretefloor011a", "sand": "nature/blendsandsand008a"}

var data: Dictionary = {}
var heights := PackedFloat32Array()   # res*res natural heights (m, 1 cm steps, NAN = hole), empty with no terrain
var splat := PackedByteArray()        # res*res*4
var thumb := PackedByteArray()        # PNG or empty
var thumb_custom := false             # SET THUMBNAIL FROM CAMERA was used (else every save renders one)
var revision := 0                     # +1 on every apply / notify (bakes and saves compare it)
var report: LevelReport               # what unpack / sanitize dropped (null for a new doc)

var _dirty := {}                      # data key / "#heights" / "#splat" -> true: changed since the last snapshot
var _all_dirty := true                # everything (no snapshot yet, or `data` was replaced)
var _snap: LevelDoc                   # the last snapshot: its unchanged sections are shared by the next one
var _snap_data: Dictionary            # the `data` object that snapshot was taken from
var _index := {}                      # uid -> {section, index, road, path, ...} (find)
var _index_rev := -1


## A valid empty document: no road, flat terrain at 0 m, default sky, light, water and race
## settings. res <= 1 makes a world without terrain (world.terrain false, no heights; world.res
## then holds the allowed res for that size).
static func blank(track_name: String, size := 1024.0, res := 513) -> LevelDoc:
	var d := LevelDoc.new()
	var nm := track_name.strip_edges().left(48)
	if nm == "":
		nm = "MY TRACK"
	var now := int(Time.get_unix_time_from_system())
	var g := _game()
	d.data = {
		"format": FORMAT,
		"kind": KIND,
		"guid": Crypto.new().generate_random_bytes(16).hex_encode(),
		"name": nm,
		"short": nm.to_upper().left(16),
		"author": "",
		"desc": "",
		"created": now,
		"modified": now,
		"content": int(g.get("content_version")) if g != null else 0,
		"app": str(g.get("version")) if g != null else "",
		"next_uid": 1,
		"bake": {"main_n": 0, "branch_n": {}, "rows": {}},
		"theme": "",
		"world": {"size": float(size), "res": res if res > 1 else _res_for(size), "terrain": res > 1},
		"styles": {},
		"road": {"closed": false, "start": {"p": 0, "t": 0.0}, "points": []},
		"branches": [],
		"terrain": {"layers": LAYERS.duplicate(), "flat": 6.0, "blend": 28.0},
		"props": [], "items": [], "crates": [], "pads": [], "barrels": [], "hazards": [],
		"crowds": [], "eggs": [], "lights": [], "fires": [], "lakes": [], "zones": [], "screens": [],
		"env": {"sky": "sky_day01_01", "sun": "sky", "ambient_energy": 1.0, "fog_begin": 180.0,
			"fog_end": 1500.0, "fog_sky": 0.0, "exposure": 1.08, "glow": 0.35, "sdfgi": true},
		"water": {"sea": false, "level": 0.0},
		"race": {"gantry": "combine", "background": "none", "rescue": "scanner", "offtrack": 60.0,
			"laps": 3, "music": []},
	}
	if res > 1:
		var h := PackedFloat32Array()
		h.resize(res * res)
		h.fill(0.0)
		d.heights = h
		var sp := PackedByteArray()
		sp.resize(res * res * 4)
		sp.fill(0)
		d.splat = sp
	return d


## A read-only copy for worker threads (bakes, saves). Sections unchanged since the last snapshot
## are the same objects as in that snapshot; changed ones are deep-copied.
func snapshot() -> LevelDoc:
	var s := LevelDoc.new()
	var prev := _snap
	var reuse := prev != null and not _all_dirty and is_same(data, _snap_data)
	for k in data:
		if reuse and not _dirty.has(k) and prev.data.has(k):
			s.data[k] = prev.data[k]
		else:
			s.data[k] = _copy(data[k])
	if reuse and not _dirty.has("#heights") and prev.heights.size() == heights.size():
		s.heights = prev.heights
	else:
		s.heights = heights.duplicate()
	if reuse and not _dirty.has("#splat") and prev.splat.size() == splat.size():
		s.splat = prev.splat
	else:
		s.splat = splat.duplicate()
	s.thumb = thumb.duplicate()
	s.thumb_custom = thumb_custom
	s.revision = revision
	s.report = report
	_snap = s
	_snap_data = data
	_dirty.clear()
	_all_dirty = false
	return s


## Heightmap samples per side (world.res).
func res() -> int:
	var w = data.get("world", {})
	return int(w.get("res", 513)) if w is Dictionary else 513


## Metres between samples: size / (res - 1).
func cell() -> float:
	return world_size() / float(maxi(res() - 1, 1))


## The world's corner at -x, -z (the world is centred on the origin).
func origin() -> Vector2:
	var h := world_size() * 0.5
	return Vector2(-h, -h)


## A fresh uid (never reused; stored in data.next_uid, outside the undo history).
func new_uid() -> int:
	var top := maxi(int(data.get("next_uid", 1)), 1)
	data["next_uid"] = top + 1
	_dirty["next_uid"] = true
	return top


## {section, index, item, road, path} of the item with this uid, or {}. Road points: section
## "road", road -1; branch points: section "branches", road = the branch uid, index in its points
## (plus "branch": the branch's index); a branch: road = its own uid; list items: road = their
## `road` field or -2. `item` is the live dict: duplicate it before changing it.
func find(uid: int) -> Dictionary:
	if uid <= 0:
		return {}
	for attempt in 2:
		if _index_rev != revision or attempt == 1:
			_rebuild_index()
		var e: Dictionary = _index.get(uid, {})
		if e.is_empty():
			if attempt == 0:
				continue
			return {}
		var it = get_at(e.path)
		if it is Dictionary and int(it.get("uid", 0)) == uid:
			var out := e.duplicate()
			out["item"] = it
			return out
	return {}


## The value at a path (live: do not change it), or null when the path does not exist.
func get_at(path: Array) -> Variant:
	var cur: Variant = data
	for k in path:
		cur = _child(cur, k)
		if cur == null:
			return null
	return cur


## Applies the ops in order; returns the exact inverse ops (in reverse order). Values are
## deep-copied in. Emits `changed` once with the touched sections, uids and terrain rect, and bumps
## `revision`. An op that cannot apply (a missing path) is skipped with push_error; erasing a key
## that is not there is a quiet no-op; when nothing applied there is no signal and no new revision.
func apply(ops: Array) -> Array:
	var inv := []
	var sections := {}
	var uids := {}
	var rect := Rect2i()
	for op in ops:
		if not (op is Array) or op.is_empty():
			push_error("LevelDoc.apply: not an op: %s" % str(op))
			continue
		var r := _apply_one(op, sections, uids)
		if r.is_empty():
			continue
		inv.append(r[0])
		if r.size() > 1 and r[1] is Rect2i and r[1].has_area():
			rect = r[1] if not rect.has_area() else rect.merge(r[1])
	inv.reverse()
	if inv.is_empty():
		return inv  # nothing applied: no signal, same revision
	var secs := PackedStringArray()
	for s in sections:
		secs.append(s)
	var ids := PackedInt32Array()
	for u in uids:
		ids.append(u)
	revision += 1
	changed.emit(secs, ids, rect)
	return inv


## Tells listeners (and the next snapshot) that sections were changed directly (brush strokes).
func notify(sections: PackedStringArray, uids := PackedInt32Array(), rect := Rect2i()) -> void:
	for s in sections:
		_mark(s)
	revision += 1
	changed.emit(sections, uids, rect)


static func op_set(path: Array, value: Variant) -> Array:
	return ["set", path.duplicate(), value]


static func op_erase(path: Array) -> Array:
	return ["erase", path.duplicate()]


## Inserts value into the array at path; index < 0 or past the end appends.
static func op_insert(path: Array, index: int, value: Variant) -> Array:
	return ["insert", path.duplicate(), index, value]


static func op_remove(path: Array, index: int) -> Array:
	return ["remove", path.duplicate(), index]


static func op_heights(rect: Rect2i, values: PackedFloat32Array) -> Array:
	return ["heights", [rect.position.x, rect.position.y, rect.size.x, rect.size.y], values]


static func op_splat(rect: Rect2i, values: PackedByteArray) -> Array:
	return ["splat", [rect.position.x, rect.position.y, rect.size.x, rect.size.y], values]


## Replaces the whole heightmap with r * r values (r = sqrt(size); empty = no terrain).
static func op_heights_all(values: PackedFloat32Array) -> Array:
	var r := int(round(sqrt(values.size())))
	return ["heights", [0, 0, r, r], values, "all"]


## Replaces the whole splat with r * r * 4 bytes.
static func op_splat_all(values: PackedByteArray) -> Array:
	var r := int(round(sqrt(values.size() / 4.0)))
	return ["splat", [0, 0, r, r], values, "all"]


## REVERSE TRACK DIRECTION as ops (2.4), one undo step of whole-section sets: for the main road and
## every branch the point order is reversed, the per-segment fields (SEG_KEYS) move to each
## segment's new owner (the old next point; gap.at -> 1 - at, barrier_l <-> barrier_r), custom
## handles turn round (dir negated, in <-> out) and explicit banks are negated; every anchor {p, t}
## becomes {next(p), 1 - t}; every side, lat and pad turn is negated; zones, hazard zones and
## branch ends (fork <-> merge, side <-> merge_side, respawn before <-> after) swap. Anchor t and
## gap.at are kept on a 1/65536 grid, so reversing twice gives the identical document. [] when the
## main road has fewer than 2 points.
func reverse_ops() -> Array:
	var road = data.get("road")
	if not (road is Dictionary) or not (road.get("points") is Array) or (road.points as Array).size() < 2:
		return []
	var nexts := {-1: _next_map(road.points)}
	var brs = data.get("branches")
	if brs is Array:
		for b in brs:
			if b is Dictionary and b.get("points") is Array:
				nexts[int(b.get("uid", 0))] = _next_map(b.points)
	var main: Dictionary = nexts[-1]
	var ops := []
	var nr: Dictionary = _copy(road)
	nr["points"] = _rev_points(road.points)
	if road.get("start") is Dictionary:
		nr["start"] = _rev_anchor(road.start, main)
	ops.append(op_set(["road"], nr))
	if brs is Array and not brs.is_empty():
		var nb := []
		for b in brs:
			if not (b is Dictionary):
				nb.append(_copy(b))
				continue
			var c: Dictionary = _copy(b)
			if b.get("points") is Array:
				c["points"] = _rev_points(b.points)
			_swap_keys(c, "fork", "merge")
			for k in ["fork", "merge"]:
				if c.get(k) is Dictionary:
					c[k] = _rev_anchor(c[k], main)
			_swap_keys(c, "side", "merge_side")
			for k in ["side", "merge_side"]:
				if _is_num(c.get(k)):
					c[k] = _neg(c[k])
			var rs = c.get("respawn")
			if rs is String and rs == "before":
				c["respawn"] = "after"
			elif rs is String and rs == "after":
				c["respawn"] = "before"
			nb.append(c)
		ops.append(op_set(["branches"], nb))
	for sec in ["items", "pads", "barrels", "crowds", "zones", "hazards"]:
		var list = data.get(sec)
		if not (list is Array) or (list as Array).is_empty():
			continue
		var out := []
		for it in list:
			out.append(_rev_item(sec, it, nexts))
		ops.append(op_set([sec], out))
	return ops


## Removes a road point (main road or branch) and, in the same ops, re-anchors what sat on its two
## segments onto the merged segment (2.4): t rescaled by the chord lengths of the two old segments
## (the document has no compiled arc lengths). At an open end the items move to the remaining end;
## a closed loop left with 2 points opens. Deleting a road's last point removes what is anchored on
## that road (for a branch: the branch itself). [] for a uid that is not a road point.
func delete_point_ops(uid: int) -> Array:
	var f := find(uid)
	if f.is_empty() or not (f.section == "road" or (f.section == "branches" and f.has("branch"))):
		return []
	var road_k := int(f.road)
	var pts: Array
	var pts_path: Array
	var closed := false
	if road_k == -1:
		pts = data.road.points
		pts_path = ["road", "points"]
		closed = bool(data.road.get("closed", false))
	else:
		pts = data.branches[int(f.branch)].points
		pts_path = ["branches", "#%d" % road_k, "points"]
	var n := pts.size()
	var i := int(f.index)
	if n <= 1:
		if road_k != -1:
			return _drop_road_ops(road_k)
		var ops0 := _drop_road_ops(-1)
		ops0.append(["remove", pts_path, "#%d" % uid])
		ops0.append(op_set(["road", "start"], {"p": 0, "t": 0.0}))
		if closed:
			ops0.append(op_set(["road", "closed"], false))
		return ops0
	var m := {"b": uid, "a": 0, "c": 0, "pre_a": 0, "z": 0, "z_prev": 0, "l1": 0.0, "l2": 0.0}
	var pb := _vec(pts[i].get("pos"))
	if i > 0 or closed:
		var ai := (i - 1 + n) % n
		m.a = int(pts[ai].get("uid", 0))
		m.l1 = _vec(pts[ai].get("pos")).distance_to(pb)
		if ai > 0 or closed:
			var pre := (ai - 1 + n) % n
			if pre != i:
				m.pre_a = int(pts[pre].get("uid", 0))
	if i < n - 1 or closed:
		var ci := (i + 1) % n
		m.c = int(pts[ci].get("uid", 0))
		m.l2 = pb.distance_to(_vec(pts[ci].get("pos")))
	if m.a == m.c:
		m.c = 0
	# a closed loop left with fewer than 3 points opens: its new last point loses the closing segment
	var reopen := closed and n - 1 < 3
	if reopen:
		var left := []
		for j in n:
			if j != i:
				left.append(int(pts[j].get("uid", 0)))
		m.z = left[-1]
		m.z_prev = left[-2] if left.size() > 1 else 0
	var ops := []
	if road_k == -1 and data.road.get("start") is Dictionary:
		var sa = _reanchor(data.road.start, m)
		if sa == null:
			sa = {"p": 0, "t": 0.0}
		if sa != data.road.start:
			ops.append(op_set(["road", "start"], sa))
	ops.append_array(_anchor_ops(road_k, m))
	ops.append(["remove", pts_path, "#%d" % uid])
	if reopen:
		ops.append(op_set(["road", "closed"], false))
	return ops


## Older formats -> this one (2.7): the chain _v1_to_v2 ... runs here (none yet: format 1 is the
## only format, returned as is). A format newer than FORMAT is refused by LevelIO.unpack before.
static func migrate(raw: Dictionary) -> Dictionary:
	var d := raw
	# format 1 is current: nothing to do
	return d


## The 2.3 whitelist and the 2.10 caps (6.9): a copy into fresh dicts and arrays, unknown keys
## dropped, every value type-checked and clamped, numbers finite, positions inside the world (far
## props within 3 x size), strings cut with control characters and [ ] { } stripped, ids checked
## against fixed sets, anchors naming an existing point of the right road, uids unique, extra
## items over the caps dropped. What it drops or cleans goes into report (dropped counts per
## section, one warning / info per code). A document this version wrote comes back unchanged and
## with an empty report. P1 (called by LevelIO.unpack and LevelIO.pack).
static func sanitize(raw: Dictionary, report: LevelReport) -> Dictionary:
	var cx := Clean.new()
	cx.report = report if report != null else LevelReport.new()
	var o := _sanitize_into(cx, raw)
	_finish(cx)
	return o


## Cleans items pasted from the OS clipboard (shapes only: the caller gives them new uids and
## re-anchors them; anchors only need the {p >= 1, t} shape, uids may be 0, positions stay inside
## the largest world). `section` is a LISTS name, or "points" for road points. Items over the
## section's cap are dropped. P1.
static func sanitize_items(section: String, items: Array, report: LevelReport) -> Array:
	var cx := Clean.new()
	cx.report = report if report != null else LevelReport.new()
	cx.loose = true
	cx.size = 4096.0
	cx.half = 2048.0
	cx.sea = true
	var out := []
	if not (section in LISTS or section == "points"):
		cx.drop(section, "bad_item", items.size())
		_finish(cx)
		return out
	var cap := int(CAPS.get(section, 400))
	for i in items.size():
		if out.size() >= cap:
			cx.drop(section, "over_cap", items.size() - i)
			break
		var it: Dictionary = _s_point(cx, items[i], section) if section == "points" else _item(cx, section, items[i])
		if not it.is_empty():
			out.append(it)
	_finish(cx)
	return out


# ---------------------------------------------------------------- additions (P0)

## world.size in metres.
func world_size() -> float:
	var w = data.get("world", {})
	return float(w.get("size", 1024.0)) if w is Dictionary else 1024.0


## Whether the world has terrain (world.terrain and a heightmap).
func has_terrain() -> bool:
	var w = data.get("world", {})
	return w is Dictionary and bool(w.get("terrain", false)) and not heights.is_empty()


## The public section (SECTIONS) a top-level data key belongs to: the key itself, or "meta" for
## the scalar fields (name, guid, next_uid, bake...).
static func section_of(key: Variant) -> String:
	var k := str(key)
	return k if k in SECTIONS and k != "meta" else "meta"


## The uid's path for ops (["props", "#12"], ["road", "points", "#3"], ["branches", "#5",
## "points", "#9"]) or [] when there is no such uid.
func path_of(uid: int) -> Array:
	var f := find(uid)
	return (f.path as Array).duplicate() if not f.is_empty() else []


## Every uid in the document (any list item, road point, branch and branch point).
func all_uids() -> PackedInt32Array:
	if _index_rev != revision:
		_rebuild_index()
	var out := PackedInt32Array()
	for u in _index:
		out.append(u)
	return out


## The first allowed res for a world size (WORLDS), 513 when the size is not listed.
static func _res_for(size: float) -> int:
	for w in WORLDS:
		if is_equal_approx(float(w[0]), size):
			return int(w[1])
	return 513


static func _game() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Game")
	return null


static func _copy(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY, TYPE_ARRAY:
			return v.duplicate(true)
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, \
				TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, \
				TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			return v.duplicate()
	return v


## The child of a dict (by key) or an array (by index or "#uid"), or null.
static func _child(cur: Variant, k: Variant) -> Variant:
	if cur is Dictionary:
		return cur.get(k)
	if cur is Array:
		var i := _index_in(cur, k)
		return cur[i] if i >= 0 else null
	return null


## The index of k (an int or "#uid") in arr, or -1.
static func _index_in(arr: Array, k: Variant) -> int:
	if k is int:
		return k if k >= 0 and k < arr.size() else -1
	if k is String or k is StringName:
		var s := str(k)
		if s.begins_with("#") and s.length() > 1:
			var uid := s.substr(1).to_int()
			for i in arr.size():
				var e = arr[i]
				if e is Dictionary and int(e.get("uid", 0)) == uid:
					return i
	return -1


## Marks a public section (or a raw data key) as changed for the next snapshot.
func _mark(section: String) -> void:
	_index_rev = -1
	if section == "terrain":
		_dirty["terrain"] = true
		_dirty["#heights"] = true
		_dirty["#splat"] = true
	elif section == "meta":
		for k in data:
			if section_of(k) == "meta":
				_dirty[k] = true
	else:
		_dirty[section] = true


## Walks path[0 .. n-1]; returns the containers met ([data, c1, ...]) and the resolved keys, or {}.
func _walk(path: Array, n: int) -> Dictionary:
	var conts := [data]
	var keys := []
	var cur: Variant = data
	for i in n:
		var k = path[i]
		var key: Variant = k
		if cur is Array:
			key = _index_in(cur, k)
			if key < 0:
				return {}
		elif cur is Dictionary:
			if not cur.has(k):
				return {}
		else:
			return {}
		keys.append(key)
		cur = cur[key]
		conts.append(cur)
	return {"conts": conts, "keys": keys}


## The path as an inverse should address it after the op: each "#uid" step re-read from the
## element now at that index (a set may have changed its uid).
func _repath(path: Array, keys: Array) -> Array:
	var out := path.duplicate()
	var cur: Variant = data
	for i in mini(keys.size(), path.size()):
		var key = keys[i]
		if cur is Array:
			if not (key is int) or key < 0 or key >= cur.size():
				break
			var e = cur[key]
			var p = path[i]
			if (p is String or p is StringName) and str(p).begins_with("#"):
				out[i] = "#%d" % int(e.get("uid", 0)) if e is Dictionary and e.has("uid") else key
			cur = e
		elif cur is Dictionary:
			if not cur.has(key):
				break
			cur = cur[key]
		else:
			break
	return out


## Collects the uids of the dict elements along a resolved walk.
static func _note_uids(conts: Array, uids: Dictionary) -> void:
	for c in conts:
		if c is Dictionary and c.has("uid"):
			var u := int(c.uid)
			if u > 0:
				uids[u] = true


## The uid of an inserted / removed / replaced value (and of a branch's points inside it).
static func _note_value(v: Variant, uids: Dictionary) -> void:
	if not (v is Dictionary):
		return
	if v.has("uid"):
		var u := int(v.uid)
		if u > 0:
			uids[u] = true
	var pts = v.get("points")
	if pts is Array:
		for p in pts:
			if p is Dictionary and int(p.get("uid", 0)) > 0:
				uids[int(p.uid)] = true


## Applies one op; returns [inverse op] (+ a Rect2i for terrain ops) or [] when it could not apply.
func _apply_one(op: Array, sections: Dictionary, uids: Dictionary) -> Array:
	var kind := str(op[0])
	match kind:
		"heights", "splat":
			return _apply_grid(op, kind == "splat", sections)
		"set", "erase", "insert", "remove":
			pass
		_:
			push_error("LevelDoc.apply: unknown op %s" % kind)
			return []
	if op.size() < 2 or not (op[1] is Array) or (op[1] as Array).is_empty():
		push_error("LevelDoc.apply: bad path in %s" % str(op))
		return []
	var path: Array = op[1]
	var sec := section_of(path[0])
	match kind:
		"set", "erase":
			var w := _walk(path, path.size() - 1)
			if w.is_empty():
				push_error("LevelDoc.apply: no such path %s" % str(path))
				return []
			var c: Variant = w.conts[-1]
			var last = path[-1]
			var keys: Array = w.keys
			if c is Dictionary:
				var had: bool = c.has(last)
				var old = c.get(last)
				if kind == "set":
					if op.size() < 3:
						return []
					c[last] = _copy(op[2])
					_note_value(op[2], uids)
				elif had:
					c.erase(last)
				else:
					return []
				_note_uids(w.conts, uids)
				_note_value(old, uids)
				_touch(sec, path[0], sections)
				keys.append(last)
				var ipath := _repath(path, keys)
				if had:
					return [["set", ipath, old]]
				return [["erase", ipath]]
			if c is Array:
				var i := _index_in(c, last)
				if i < 0:
					push_error("LevelDoc.apply: no such element %s" % str(path))
					return []
				var old2 = c[i]
				_note_value(old2, uids)
				_note_uids(w.conts, uids)
				_touch(sec, path[0], sections)
				if kind == "set":
					if op.size() < 3:
						return []
					c[i] = _copy(op[2])
					_note_value(op[2], uids)
					keys.append(i)
					return [["set", _repath(path, keys), old2]]
				# erase of an array element = remove
				c.remove_at(i)
				var apath := _repath(path.slice(0, path.size() - 1), keys)
				return [["insert", apath, i, old2]]
			push_error("LevelDoc.apply: %s into a non-container %s" % [kind, str(path)])
			return []
		"insert", "remove":
			if op.size() < (4 if kind == "insert" else 3):
				push_error("LevelDoc.apply: short op %s" % str(op))
				return []
			var w2 := _walk(path, path.size())
			if w2.is_empty() or not (w2.conts[-1] is Array):
				push_error("LevelDoc.apply: no array at %s" % str(path))
				return []
			var arr: Array = w2.conts[-1]
			_note_uids(w2.conts, uids)
			_touch(sec, path[0], sections)
			var ipath2 := _repath(path, w2.keys)
			if kind == "insert":
				var at := int(op[2])
				if at < 0 or at > arr.size():
					at = arr.size()
				arr.insert(at, _copy(op[3]))
				_note_value(op[3], uids)
				return [["remove", ipath2, at]]
			var j := _index_in(arr, op[2])
			if j < 0:
				push_error("LevelDoc.apply: no element %s in %s" % [str(op[2]), str(path)])
				return []
			var gone = arr[j]
			arr.remove_at(j)
			_note_value(gone, uids)
			return [["insert", ipath2, j, gone]]
	return []


func _touch(sec: String, key: Variant, sections: Dictionary) -> void:
	sections[sec] = true
	_dirty[key] = true
	_index_rev = -1


## A heights / splat op: a region write, or a whole replace ([0, 0, r, r] with a different size).
func _apply_grid(op: Array, is_splat: bool, sections: Dictionary) -> Array:
	if op.size() < 3 or not (op[1] is Array) or (op[1] as Array).size() < 4:
		push_error("LevelDoc.apply: bad %s op" % op[0])
		return []
	var r: Array = op[1]
	var rx := int(r[0])
	var rz := int(r[1])
	var rw := maxi(int(r[2]), 0)
	var rh := maxi(int(r[3]), 0)
	var per := 4 if is_splat else 1
	var vals = op[2]
	if is_splat and not (vals is PackedByteArray):
		vals = PackedByteArray(vals) if vals is Array else PackedByteArray()
	elif not is_splat and not (vals is PackedFloat32Array):
		vals = PackedFloat32Array(vals) if vals is Array else PackedFloat32Array()
	if vals.size() != rw * rh * per:
		push_error("LevelDoc.apply: %s op with %d values for a %dx%d rect" % [op[0], vals.size(), rw, rh])
		return []
	var cur = splat if is_splat else heights
	var key := "#splat" if is_splat else "#heights"
	sections["terrain"] = true
	_dirty[key] = true
	var rect := Rect2i(rx, rz, rw, rh)
	# a whole replace (any size)
	if op.size() > 3 and str(op[3]) == "all":
		var old_r := int(round(sqrt(cur.size() / float(per))))
		var old = cur.duplicate()
		if is_splat:
			splat = vals.duplicate()
		else:
			heights = vals.duplicate()
		var full := Rect2i(0, 0, maxi(rw, old_r), maxi(rh, old_r))
		return [[op[0], [0, 0, old_r, old_r], old, "all"], full]
	var res_g := int(round(sqrt(cur.size() / float(per))))
	var before = PackedByteArray() if is_splat else PackedFloat32Array()
	before.resize(vals.size())
	for z in rh:
		var gz := rz + z
		for x in rw:
			var gx := rx + x
			var vi := (z * rw + x) * per
			if gx < 0 or gz < 0 or gx >= res_g or gz >= res_g:
				for c in per:
					before[vi + c] = vals[vi + c]
				continue
			var gi := (gz * res_g + gx) * per
			# write the members themselves
			if is_splat:
				for c in 4:
					before[vi + c] = splat[gi + c]
					splat[gi + c] = vals[vi + c]
			else:
				before[vi] = heights[gi]
				heights[gi] = vals[vi]
	return [[op[0], [rx, rz, rw, rh], before], rect]


func _rebuild_index() -> void:
	_index.clear()
	var road = data.get("road", {})
	if road is Dictionary and road.get("points") is Array:
		var pts: Array = road.points
		for i in pts.size():
			var p = pts[i]
			if p is Dictionary and int(p.get("uid", 0)) > 0:
				_index[int(p.uid)] = {"section": "road", "index": i, "road": -1,
					"path": ["road", "points", "#%d" % int(p.uid)]}
	for sec in LISTS:
		var list = data.get(sec)
		if not (list is Array):
			continue
		for i in list.size():
			var it = list[i]
			if not (it is Dictionary) or int(it.get("uid", 0)) <= 0:
				continue
			var u := int(it.uid)
			var road_k := -2
			if sec == "branches":
				road_k = u
			elif it.has("road"):
				road_k = int(it.road)
			_index[u] = {"section": sec, "index": i, "road": road_k, "path": [sec, "#%d" % u]}
			if sec == "branches" and it.get("points") is Array:
				var bp: Array = it.points
				for j in bp.size():
					var p = bp[j]
					if p is Dictionary and int(p.get("uid", 0)) > 0:
						_index[int(p.uid)] = {"section": "branches", "index": j, "road": u, "branch": i,
							"path": ["branches", "#%d" % u, "points", "#%d" % int(p.uid)]}
	_index_rev = revision


# ---------------------------------------------------------------- P1: sanitize, reverse, delete

## The 19 hazard types (4.2); an unknown type drops its hazard. LevelHazards.TYPES has these keys.
const HAZARD_TYPES := ["turret", "vortigaunt", "strider", "apache", "air_strafe", "strike_zone", "field_gate",
	"minefield", "houndeyes", "controller", "bullsquid", "crane", "antlion_guard", "tripmine", "tentacle",
	"antlion", "column", "seesaw", "train"]
## Heavy hazard types (2.10: at most 8 of them).
const HEAVY := ["strider", "column", "seesaw", "antlion", "antlion_guard", "crane"]
const BRANCH_KINDS := ["alt", "jump", "ledge", "high", "trail"]
const EGG_KINDS := ["gman", "birds", "gnome", "zombies", "holo", "lamarr", "nihilanth"]
const SPECIES := ["pigeon", "crow", "seagull", "boid"]
const GANTRIES := ["combine", "blackmesa", "military", "xen"]
const BACKGROUNDS := ["none", "city17", "forest"]
const RESCUES := ["scanner", "crane", "teleport", "xen_portal", "combine_teleport", "vortigaunt"]
const FEELS := ["easy", "normal", "brutal", "custom"]
## The same lists as LevelThemes.IDS and LevelCrowds.ROLES / MOODS (7.3), kept here so the gate
## loads without the compile-side classes.
const THEME_IDS := ["city17", "coast", "blackmesa", "xen", "whiteforest", "novaprospekt", "desert"]
const CROWD_ROLES := ["citizen", "refugee", "rebel", "metrocop", "combine", "scientist", "guard", "vort", "islave",
	"hecu", "zombie", "cameo"]
const CROWD_MOODS := ["fan", "polite", "excited", "loyal", "military", "chant", "scared"]
const PROP_TAGS := ["", "deco", "far", "float"]
## A point's per-segment fields (the segment from this point to the next).
const SEG_KEYS := ["style", "grip", "gap", "tunnel_h", "seesaw", "barrier_l", "barrier_r"]
## Hard caps (2.10) per list ("points": main road, "branch_points": per branch).
const CAPS := {"points": 400, "branch_points": 100, "branches": 8, "props": 3000, "physics": 300, "items": 40,
	"crates": 64, "pads": 64, "barrels": 32, "hazards": 48, "heavy": 8, "crowds": 100, "eggs": 24,
	"lights": 128, "fires": 32, "lakes": 16, "zones": 16, "screens": 16, "styles": 32, "music": 12, "pts": 64,
	"seagulls": 16, "path": 16}
## Anchor t and gap.at live on this grid (1 - t stays exact: reversing twice is the identity).
const T_STEP := 1.0 / 65536.0
const UID_MAX := 2147483646
const DEFAULT_SKY := "sky_day01_01"

const TOP_KEYS := ["format", "kind", "guid", "name", "short", "author", "desc", "remix_of", "created", "modified",
	"content", "app", "next_uid", "bake", "theme", "world", "styles", "road", "branches", "terrain", "props",
	"items", "crates", "pads", "barrels", "hazards", "crowds", "eggs", "lights", "fires", "lakes", "zones",
	"screens", "env", "water", "race"]
## The keys each item kind may have (anything else is dropped and counted).
const KEYS := {
	"point": ["uid", "pos", "width", "bank", "handle", "style", "grip", "gap", "tunnel_h", "seesaw", "barrier_l",
		"barrier_r", "follow"],
	"branches": ["uid", "name", "kind", "fork", "merge", "side", "merge_side", "points", "ai", "risk", "respawn",
		"retry_back", "offtrack"],
	"props": ["uid", "model", "pos", "yaw", "pitch", "roll", "scale", "physics", "tag", "group"],
	"items": ["uid", "road", "at", "count", "inset"],
	"crates": ["uid", "pos"],
	"pads": ["uid", "road", "at", "lat", "turn"],
	"barrels": ["uid", "road", "at"],
	"hazards": ["uid", "type", "at", "side", "setback", "lat", "zone", "mount", "style", "pts", "feel", "p"],
	"crowds": ["uid", "road", "at", "side", "length", "rows", "density", "setback", "role", "mood", "sit", "tags"],
	"eggs": ["uid", "kind", "pos", "yaw", "path", "species", "radius", "count", "chance"],
	"lights": ["uid", "pos", "color", "range", "energy"],
	"fires": ["uid", "pos", "size", "smoke", "light"],
	"lakes": ["uid", "center", "size", "level"],
	"zones": ["uid", "road", "a", "b", "scale", "ease"],
	"screens": ["uid", "pos", "yaw", "w", "h"],
	"road": ["closed", "start", "points"],
	"world": ["size", "res", "terrain"],
	"terrain": ["layers", "flat", "blend"],
	"water": ["sea", "level"],
	"bake": ["main_n", "branch_n", "rows"],
	"env": ["sky", "sun", "sun_color", "sun_energy", "ambient", "ambient_energy", "fog_color", "fog_begin",
		"fog_end", "fog_sky", "exposure", "glow", "sky_energy", "sdfgi"],
	"race": ["gantry", "background", "citadel", "seagulls", "rescue", "offtrack", "laps", "music"],
	"gap": ["len", "at", "lift", "ramp"],
	"handle": ["dir", "in", "out"],
	"ai": ["take", "min_skill", "commit"],
	"barrier": ["kind", "mat", "h", "thick", "off", "col_h", "rep"],
	"remix_of": ["guid", "name", "author"],
}
## Number ranges of an own style's numeric keys.
const STYLE_RANGES := {"road_rep": [0.5, 100.0], "vmax": [5.0, 120.0], "verge_w": [0.0, 40.0],
	"verge_drop": [0.0, 10.0], "curb_h": [0.0, 2.0], "walk": [0.0, 20.0], "skirt_h": [0.0, 20.0],
	"pillar_every": [2.0, 500.0], "pillar_size": [0.1, 20.0], "height": [3.0, 30.0], "wall_gap": [0.0, 10.0],
	"light_every": [2.0, 200.0], "light_energy": [0.0, 16.0]}
## Report texts of what sanitize cleaned ("%d" = how many); WARN_CODES are warnings, the rest info.
const CLEAN_TEXT := {
	"unknown_key": "%d unknown field(s) were left out.",
	"cleaned": "%d value(s) were out of range or of the wrong type and were corrected.",
	"bad_number": "%d number(s) were not finite and were replaced.",
	"bad_text": "%d text(s) had characters that are not allowed or were too long and were shortened.",
	"unknown_style": "%d road segment(s) named a style that does not exist and use ASPHALT now.",
	"bad_guid": "The track's id was damaged and was made again.",
	"bad_key": "%d content name(s) were not valid names and were left out.",
	"bad_anchor": "%d item(s) sat on a road point that does not exist and were removed.",
	"dup_uid": "%d item(s) had the id of another item and were removed.",
	"bad_uid": "%d item(s) had no valid id and were removed.",
	"unknown_hazard": "%d hazard(s) of an unknown type were removed.",
	"over_cap": "%d item(s) over the track limits were removed.",
	"bad_item": "%d broken item(s) were removed.",
	"bad_world": "The world size was not one of the allowed sizes and was reset.",
	"open_road": "A closed road needs at least 3 points: it is open now.",
}
const WARN_CODES := ["unknown_style", "bad_key", "bad_anchor", "dup_uid", "bad_uid", "unknown_hazard", "over_cap",
	"bad_item", "bad_world", "open_road"]


## One sanitize run's state.
class Clean:
	extends RefCounted
	var report: LevelReport
	var loose := false          # sanitize_items: shapes only (no doc to check anchors or uids against)
	var size := 1024.0          # world size (m)
	var half := 512.0
	var sea := false
	var styles := {}            # style ids a point may name
	var roads := {}             # road key (-1 the main road, else a branch uid) -> {point uid: true}
	var uids := {}              # every uid kept so far
	var top := 0                # the largest uid kept
	var physics := 0            # props with physics kept
	var heavy := 0              # heavy hazards kept
	var codes := {}             # report code -> count
	var dropped := {}           # section -> count

	func note(code: String, n := 1) -> void:
		codes[code] = int(codes.get(code, 0)) + n

	func drop(section: String, code: String, n := 1) -> void:
		dropped[section] = int(dropped.get(section, 0)) + n
		note(code, n)


## Text as 2.3 / 2.10 want it: control characters, [ ] { } and invisible format characters
## (_bad_char) stripped, edges trimmed, cut to max_len.
static func clean_text(s: String, max_len: int) -> String:
	var src := s.left(max_len * 4 + 16)
	var bad := false
	for i in src.length():
		if _bad_char(src.unicode_at(i)):
			bad = true
			break
	if bad:
		var keep := PackedStringArray()
		for i in src.length():
			var c := src.unicode_at(i)
			if not _bad_char(c):
				keep.append(char(c))
		src = "".join(keep)
	return src.strip_edges().left(max_len).strip_edges()


## A content key (models, materials, skies, music) or "" when it is not a plain key: never a path
## (no "://", "..", "\", ":", no leading "/", no control characters or spaces), at most 96 chars.
static func clean_key(v: Variant) -> String:
	if not (v is String or v is StringName):
		return ""
	var s := str(v)
	if s.is_empty() or s.length() > 96 or s.begins_with("/"):
		return ""
	if s.contains("://") or s.contains("..") or s.contains("\\") or s.contains(":"):
		return ""
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 33 or c == 127 or (c >= 0x80 and c <= 0x9f):
			return ""
	return s


## An id of the [a-z0-9_] alphabet, 1..24 characters (own style ids, hazard param keys).
static func is_id(s: String) -> bool:
	if s.is_empty() or s.length() > 24:
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
			return false
	return true


## Control characters, [ ] { }, line / paragraph separators, BOM, lone surrogates, and the
## invisible format characters a name can spoof another with: soft hyphen, zero-width space /
## joiners, LRM / RLM, the bidi embeddings and overrides (LRE..RLO) and isolates (WJ..PDI).
static func _bad_char(c: int) -> bool:
	return c < 32 or c == 127 or (c >= 0x80 and c <= 0x9f) or c == 0x5b or c == 0x5d or c == 0x7b or c == 0x7d \
		or c == 0xad or (c >= 0x200b and c <= 0x200f) or (c >= 0x202a and c <= 0x202e) or (c >= 0x2060 and c <= 0x2069) \
		or c == 0x2028 or c == 0x2029 or c == 0xfeff or (c >= 0xd800 and c <= 0xdfff)


static func _is_num(v: Variant) -> bool:
	var t := typeof(v)
	return t == TYPE_FLOAT or t == TYPE_INT


static func _neg(v: Variant) -> Variant:
	if typeof(v) == TYPE_INT:
		return -int(v)
	return -float(v) if float(v) != 0.0 else v


static func _vec(v: Variant) -> Vector3:
	if v is Array and v.size() >= 3 and _is_num(v[0]) and _is_num(v[1]) and _is_num(v[2]):
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	if v is Vector3:
		return v
	return Vector3.ZERO


static func _swap_keys(d: Dictionary, a: String, b: String) -> void:
	var ha := d.has(a)
	var hb := d.has(b)
	var va = d.get(a)
	var vb = d.get(b)
	d.erase(a)
	d.erase(b)
	if hb:
		d[a] = vb
	if ha:
		d[b] = va


# ---------------------------------------------------------------- reverse helpers

## point uid -> the next point's uid along the road (cyclic: an open road's last point -> its first).
static func _next_map(pts: Array) -> Dictionary:
	var m := {}
	var n := pts.size()
	for i in n:
		var p = pts[i]
		var q = pts[(i + 1) % n]
		if p is Dictionary and q is Dictionary:
			m[int(p.get("uid", 0))] = int(q.get("uid", 0))
	return m


static func _rev_anchor(a: Variant, next_map: Dictionary) -> Variant:
	if not (a is Dictionary):
		return _copy(a)
	var o: Dictionary = (a as Dictionary).duplicate(true)
	if _is_num(a.get("p")):
		var p := int(a.p)
		if next_map.has(p):
			o["p"] = next_map[p]
	if _is_num(a.get("t")):
		o["t"] = 1.0 - snappedf(clampf(float(a.t), 0.0, 1.0), T_STEP)
	return o


## The points in reverse order; each takes the segment fields of the point before it (the segment
## it now starts), turned round.
static func _rev_points(pts: Array) -> Array:
	var n := pts.size()
	var out := []
	for j in n:
		var src = pts[n - 1 - j]
		if not (src is Dictionary):
			out.append(_copy(src))
			continue
		var o := {}
		for k in src:
			if not (str(k) in SEG_KEYS):
				o[k] = _copy(src[k])
		var prev = pts[(n - 2 - j + n) % n]
		if prev is Dictionary:
			for k in SEG_KEYS:
				if prev.has(k):
					o[k] = _copy(prev[k])
		var h = o.get("handle")
		if h is Dictionary:
			if h.get("dir") is Array:
				var d: Array = h.dir
				for i in d.size():
					if _is_num(d[i]):
						d[i] = _neg(d[i])
			_swap_keys(h, "in", "out")
		if _is_num(o.get("bank")):
			o["bank"] = _neg(o.bank)
		var g = o.get("gap")
		if g is Dictionary and _is_num(g.get("at")):
			g["at"] = 1.0 - snappedf(float(g.at), T_STEP)
		_swap_keys(o, "barrier_l", "barrier_r")
		out.append(o)
	return out


static func _rev_item(sec: String, it: Variant, nexts: Dictionary) -> Variant:
	if not (it is Dictionary):
		return _copy(it)
	var o: Dictionary = _copy(it)
	var road_k := -1
	if sec != "hazards" and _is_num(o.get("road")):
		road_k = int(o.road)
	var nm: Dictionary = nexts.get(road_k, {})
	if o.get("at") is Dictionary:
		o["at"] = _rev_anchor(o.at, nm)
	match sec:
		"zones":
			_swap_keys(o, "a", "b")
			for k in ["a", "b"]:
				if o.get(k) is Dictionary:
					o[k] = _rev_anchor(o[k], nm)
		"pads":
			for k in ["lat", "turn"]:
				if _is_num(o.get(k)):
					o[k] = _neg(o[k])
		"crowds":
			if _is_num(o.get("side")):
				o["side"] = _neg(o.side)
		"hazards":
			for k in ["side", "lat"]:
				if _is_num(o.get(k)):
					o[k] = _neg(o[k])
			var z = o.get("zone")
			if z is Array and z.size() == 2:
				o["zone"] = [_rev_anchor(z[1], nm), _rev_anchor(z[0], nm)]
			var pts = o.get("pts")
			if pts is Array:
				for i in pts.size():
					var q = pts[i]
					if q is Dictionary:
						if q.get("at") is Dictionary:
							q["at"] = _rev_anchor(q.at, nm)
						for k in ["side", "lat"]:
							if _is_num(q.get(k)):
								q[k] = _neg(q[k])
					elif q is Array and q.size() >= 2 and str(o.get("type", "")) != "strike_zone" and _is_num(q[1]):
						# [s, lat(, h)]: the lateral changes side; strike_zone's core is a world position
						q[1] = _neg(q[1])
	return o


# ---------------------------------------------------------------- delete helpers

## Where an anchor on the deleted point's road goes (m from delete_point_ops); null = nowhere (the
## road has no point left).
static func _reanchor(a: Variant, m: Dictionary) -> Variant:
	if not (a is Dictionary) or not _is_num(a.get("p")):
		return a
	var p := int(a.p)
	var t := clampf(float(a.get("t", 0.0)) if _is_num(a.get("t")) else 0.0, 0.0, 1.0)
	var tot: float = m.l1 + m.l2
	if tot <= 1e-6:
		tot = 1.0
	var res = a
	if p == int(m.b):
		if m.a != 0 and m.c != 0:
			res = {"p": m.a, "t": snappedf((m.l1 + t * m.l2) / tot, T_STEP)}
		elif m.c != 0:
			res = {"p": m.c, "t": 0.0}
		elif m.a != 0:
			p = m.a
			t = 1.0
		else:
			return null
	if p == int(m.a) and m.a != 0:
		if m.c != 0:
			res = {"p": m.a, "t": snappedf(t * m.l1 / tot, T_STEP)}
		elif m.pre_a != 0:
			res = {"p": m.pre_a, "t": 1.0}
		else:
			res = {"p": m.a, "t": 0.0}
	if m.z != 0 and res is Dictionary and int(res.get("p", 0)) == int(m.z):
		res = {"p": m.z_prev, "t": 1.0} if m.z_prev != 0 else {"p": m.z, "t": 0.0}
	return res


## The set / remove ops for everything anchored on road road_k after a point delete.
func _anchor_ops(road_k: int, m: Dictionary) -> Array:
	var ops := []
	for sec in ["items", "pads", "barrels", "crowds", "zones", "hazards", "branches"]:
		var list = data.get(sec)
		if not (list is Array):
			continue
		for it in list:
			if not (it is Dictionary):
				continue
			var uid := int(it.get("uid", 0))
			var path := [sec, "#%d" % uid]
			var on := road_k == -1 if sec == "hazards" or sec == "branches" else \
				(int(it.get("road", -1)) if _is_num(it.get("road")) else -1) == road_k
			if not on:
				continue
			var gone := false
			var sets := []
			var keys: Array = ["fork", "merge"] if sec == "branches" else (["a", "b"] if sec == "zones" else ["at"])
			for k in keys:
				if it.get(k) is Dictionary:
					var na = _reanchor(it[k], m)
					if na == null:
						gone = true
					elif na != it[k]:
						sets.append(op_set(path + [k], na))
			if sec == "hazards":
				var z = it.get("zone")
				if z is Array and z.size() == 2:
					var z0 = _reanchor(z[0], m)
					var z1 = _reanchor(z[1], m)
					if z0 == null or z1 == null:
						gone = true
					elif z0 != z[0] or z1 != z[1]:
						sets.append(op_set(path + ["zone"], [z0, z1]))
				var pts = it.get("pts")
				if pts is Array:
					var np := []
					var moved := false
					for q in pts:
						if q is Dictionary and q.get("at") is Dictionary:
							var qa = _reanchor(q.at, m)
							if qa == null:
								moved = true
								continue
							if qa != q.at:
								var q2: Dictionary = q.duplicate(true)
								q2["at"] = qa
								np.append(q2)
								moved = true
								continue
						np.append(q)
					if moved:
						sets.append(op_set(path + ["pts"], np))
			if gone:
				if sec == "branches":
					ops.append_array(_drop_road_ops(uid))
				else:
					ops.append(["remove", [sec], "#%d" % uid])
			else:
				ops.append_array(sets)
	return ops


## Remove ops for everything anchored on a road (-1: the main road, with every branch and hazard;
## a branch uid: that branch's items and the branch itself).
func _drop_road_ops(road_k: int) -> Array:
	var ops := []
	for sec in ["items", "pads", "barrels", "crowds", "zones"]:
		var list = data.get(sec)
		if list is Array:
			for it in list:
				if it is Dictionary and (int(it.get("road", -1)) if _is_num(it.get("road")) else -1) == road_k:
					ops.append(["remove", [sec], "#%d" % int(it.get("uid", 0))])
	if road_k == -1:
		var hz = data.get("hazards")
		if hz is Array:
			for it in hz:
				if it is Dictionary:
					ops.append(["remove", ["hazards"], "#%d" % int(it.get("uid", 0))])
		var brs = data.get("branches")
		if brs is Array:
			for b in brs:
				if b is Dictionary:
					ops.append_array(_drop_road_ops(int(b.get("uid", 0))))
	else:
		ops.append(["remove", ["branches"], "#%d" % road_k])
	return ops


# ---------------------------------------------------------------- sanitize helpers

static func _finish(cx: Clean) -> void:
	for sec in cx.dropped:
		cx.report.add_dropped(str(sec), int(cx.dropped[sec]))
	for code in cx.codes:
		var n := int(cx.codes[code])
		var text := str(CLEAN_TEXT.get(code, "%d value(s) were cleaned."))
		if text.contains("%d"):
			text = text % n
		if code in WARN_CODES:
			cx.report.warning(code, text, {"count": n})
		else:
			cx.report.info(code, text, {"count": n})


static func _sanitize_into(cx: Clean, raw: Dictionary) -> Dictionary:
	_extra(cx, "meta", raw, TOP_KEYS)
	var o := {}
	o["format"] = FORMAT
	o["kind"] = KIND
	o["guid"] = _guid(cx, raw)
	var nm := _t(cx, raw.get("name"), 48, "MY TRACK")
	o["name"] = nm
	o["short"] = _t(cx, raw.get("short"), 16, nm.to_upper().left(16)).to_upper().left(16)
	o["author"] = _t(cx, raw.get("author"), 24, "")
	o["desc"] = _t(cx, raw.get("desc"), 280, "")
	var rx = raw.get("remix_of")
	if rx is Dictionary:
		_extra(cx, "meta", rx, KEYS.remix_of)
		var rg = rx.get("guid")
		o["remix_of"] = {"guid": str(rg).to_lower() if _is_guid(rg) else "", "name": _t(cx, rx.get("name"), 48, ""),
			"author": _t(cx, rx.get("author"), 24, "")}
	elif rx != null:
		cx.note("cleaned")
	o["created"] = _i(cx, raw.get("created"), 0, 1 << 40, 0)
	o["modified"] = _i(cx, raw.get("modified"), 0, 1 << 40, 0)
	o["content"] = _i(cx, raw.get("content"), 0, 1000000, 0)
	o["app"] = _t(cx, raw.get("app"), 24, "")
	var theme = raw.get("theme")
	o["theme"] = theme if theme is String and theme in THEME_IDS else ""
	if theme != null and not (theme is String and (theme == "" or theme in THEME_IDS)):
		cx.note("cleaned")
	# the world first: positions are checked against it
	var w := _dict(cx, raw.get("world"), "world")
	var size := float(w.get("size", 1024.0)) if _is_num(w.get("size")) else 1024.0
	var wres := int(w.get("res", 513)) if _is_num(w.get("res")) else 513
	var ok := false
	for p in WORLDS:
		if is_equal_approx(float(p[0]), size) and int(p[1]) == wres:
			size = float(p[0])
			ok = true
			break
	if not ok:
		var r2 := 0
		for p in WORLDS:
			if is_equal_approx(float(p[0]), size):
				r2 = int(p[1])
				size = float(p[0])
				break
		if r2 == 0:
			size = 1024.0
			r2 = 513
		wres = r2
		cx.note("bad_world")
	o["world"] = {"size": size, "res": wres, "terrain": _b(cx, w.get("terrain"), true)}
	cx.size = size
	cx.half = size * 0.5
	var wa := _dict(cx, raw.get("water"), "water")
	o["water"] = {"sea": _b(cx, wa.get("sea"), false), "level": _f(cx, wa.get("level"), -200.0, 500.0, 0.0)}
	cx.sea = bool(o.water.sea)
	o["styles"] = _s_styles(cx, raw.get("styles"))
	o["road"] = _s_road(cx, raw.get("road"))
	o["branches"] = _list(cx, raw, "branches")
	var te := _dict(cx, raw.get("terrain"), "terrain")
	var layers := {}
	var ls = te.get("layers")
	if ls is Dictionary:
		_extra(cx, "terrain", ls, LAYERS.keys())
	for k in LAYERS:
		var v = ls.get(k) if ls is Dictionary else null
		var key := clean_key(v)
		if key == "" and v != null:
			cx.note("bad_key")
		layers[k] = key if key != "" else LAYERS[k]
	o["terrain"] = {"layers": layers, "flat": _f(cx, te.get("flat"), 0.0, 20.0, 6.0),
		"blend": _f(cx, te.get("blend"), 4.0, 80.0, 28.0)}
	for sec in ["props", "items", "crates", "pads", "barrels", "hazards", "crowds", "eggs", "lights", "fires",
			"lakes", "zones", "screens"]:
		o[sec] = _list(cx, raw, sec)
	o["env"] = _s_env(cx, raw.get("env"))
	o["race"] = _s_race(cx, raw.get("race"))
	# bake: only counts of what is still there
	var b := _dict(cx, raw.get("bake"), "bake")
	var bake := {"main_n": _i(cx, b.get("main_n"), 0, 10000000, 0), "branch_n": {}, "rows": {}}
	var keep := {"branch_n": {}, "rows": {}}
	for it in o.branches:
		keep.branch_n[int(it.uid)] = true
	for it in o.items:
		keep.rows[int(it.uid)] = true
	for k in ["branch_n", "rows"]:
		var src = b.get(k)
		if src is Dictionary:
			for key in src:
				var u := str(key).to_int()
				if str(u) == str(key) and keep[k].has(u) and _is_num(src[key]):
					bake[k][str(u)] = _i(cx, src[key], 0, 10000000, 0)
				else:
					cx.drop("bake", "unknown_key")
	o["bake"] = bake
	o["next_uid"] = maxi(_i(cx, raw.get("next_uid"), 1, UID_MAX + 1, 1), cx.top + 1)
	return o


## The guid (32 lower hex); a damaged one is replaced by one derived from the document (the same
## on every peer).
static func _guid(cx: Clean, raw: Dictionary) -> String:
	var g = raw.get("guid")
	if _is_guid(g):
		return str(g).to_lower()
	cx.note("bad_guid")
	return JSON.stringify([g, raw.get("name"), raw.get("created")]).sha256_text().left(32)


static func _is_guid(g: Variant) -> bool:
	if not (g is String) or (g as String).length() != 32:
		return false
	var s := (g as String).to_lower()
	for i in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)):
			return false
	return true


## v as a Dictionary ({} when missing or not one), its unknown keys counted under section.
static func _dict(cx: Clean, v: Variant, section: String) -> Dictionary:
	if v is Dictionary:
		if KEYS.has(section):
			_extra(cx, section, v, KEYS[section])
		return v
	if v != null:
		cx.note("cleaned")
	return {}


static func _extra(cx: Clean, section: String, d: Dictionary, allowed: Array) -> void:
	var n := 0
	for k in d:
		if not (str(k) in allowed):
			n += 1
	if n > 0:
		cx.drop(section, "unknown_key", n)


## A float in lo..hi (def when missing; wrong types, non-finite and out-of-range values counted).
static func _f(cx: Clean, v: Variant, lo: float, hi: float, def: float) -> float:
	if v == null:
		return def
	if not _is_num(v):
		cx.note("cleaned")
		return def
	var x := float(v)
	if not is_finite(x):
		cx.note("bad_number")
		return def
	if x < lo or x > hi:
		cx.note("cleaned")
		return clampf(x, lo, hi)
	return x


## An optional float (null when missing or not valid).
static func _fo(cx: Clean, v: Variant, lo: float, hi: float) -> Variant:
	if v == null:
		return null
	if not _is_num(v) or not is_finite(float(v)):
		cx.note("bad_number" if _is_num(v) else "cleaned")
		return null
	return _f(cx, v, lo, hi, 0.0)


static func _i(cx: Clean, v: Variant, lo: int, hi: int, def: int) -> int:
	if v == null:
		return def
	if not _is_num(v):
		cx.note("cleaned")
		return def
	var x := float(v)
	if not is_finite(x):
		cx.note("bad_number")
		return def
	var r := roundi(clampf(x, float(lo), float(hi)))
	if x < lo or x > hi or float(r) != x:
		cx.note("cleaned")
	return clampi(r, lo, hi)


static func _b(cx: Clean, v: Variant, def: bool) -> bool:
	if v == null:
		return def
	if v is bool:
		return v
	cx.note("cleaned")
	if _is_num(v) and is_finite(float(v)):
		return float(v) != 0.0
	return def


## One of choices (def when missing or not one of them).
static func _e(cx: Clean, v: Variant, choices: Array, def: String) -> String:
	if v == null:
		return def
	if (v is String or v is StringName) and str(v) in choices:
		return str(v)
	cx.note("cleaned")
	return def


static func _t(cx: Clean, v: Variant, max_len: int, def: String) -> String:
	if v == null:
		return def
	if not (v is String or v is StringName):
		cx.note("cleaned")
		return def
	var s := str(v)
	var c := clean_text(s, max_len)
	if c != s:
		cx.note("bad_text")
	return c if c != "" else def


## [x, y, z] rounded to 1 mm, x and z within +-lim, y within HEIGHT_MIN..MAX; null when not a
## vector of 3 finite numbers.
static func _v3(cx: Clean, v: Variant, lim: float) -> Variant:
	var src = v
	if v is Vector3:
		src = [v.x, v.y, v.z]
	if not (src is Array) or src.size() != 3:
		if v != null:
			cx.note("cleaned")
		return null
	var o := [0.0, 0.0, 0.0]
	for i in 3:
		var x = src[i]
		if not _is_num(x) or not is_finite(float(x)):
			cx.note("bad_number" if _is_num(x) else "cleaned")
			return null
		var lo := HEIGHT_MIN if i == 1 else -lim
		var hi := HEIGHT_MAX if i == 1 else lim
		var f := snappedf(float(x), 0.001)
		if f < lo or f > hi:
			cx.note("cleaned")
			f = clampf(f, lo, hi)
		o[i] = f
	return o


## [r, g, b] in 0..1 or null.
static func _col(cx: Clean, v: Variant) -> Variant:
	if v == null:
		return null
	if not (v is Array) or v.size() != 3:
		cx.note("cleaned")
		return null
	var o := []
	for x in v:
		if not _is_num(x) or not is_finite(float(x)):
			cx.note("cleaned")
			return null
		o.append(_f(cx, x, 0.0, 1.0, 1.0))
	return o


## An anchor {p, t} naming a point of road road_k (loose: any p >= 1), t on the T_STEP grid; null
## when not valid.
static func _a(cx: Clean, v: Variant, road_k: int) -> Variant:
	if not (v is Dictionary):
		return null
	var p = v.get("p")
	var t = v.get("t")
	if not _is_num(p) or not is_finite(float(p)) or not _is_num(t) or not is_finite(float(t)):
		return null
	var pu := int(p)
	if cx.loose:
		if pu < 1:
			return null
	else:
		var pts = cx.roads.get(road_k)
		if pts == null or not (pts as Dictionary).has(pu):
			return null
	return {"p": pu, "t": clampf(snappedf(float(t), T_STEP), 0.0, 1.0)}


## A road key: -1 (the main road) or a kept branch's uid (loose: any int >= -1); -2 = not valid.
static func _road(cx: Clean, v: Variant) -> int:
	if v == null:
		return -1
	if not _is_num(v) or not is_finite(float(v)):
		return -2
	var r := int(v)
	if cx.loose:
		return r if r >= -1 else -2
	return r if cx.roads.has(r) else -2


## The item's uid, registered; -1 = the item is dropped (counted). Loose: 0 for a missing uid.
static func _uid(cx: Clean, it: Dictionary, sec: String) -> int:
	var u = it.get("uid")
	var ok := _is_num(u) and is_finite(float(u)) and float(u) >= 1.0 and float(u) <= UID_MAX \
		and float(u) == floorf(float(u))
	if cx.loose:
		return int(u) if ok else 0
	if not ok:
		cx.drop(sec, "bad_uid")
		return -1
	var ui := int(u)
	if cx.uids.has(ui):
		cx.drop(sec, "dup_uid")
		return -1
	cx.uids[ui] = true
	cx.top = maxi(cx.top, ui)
	return ui


## A list section of raw, items sanitized one by one, the extra over its cap dropped.
static func _list(cx: Clean, raw: Dictionary, sec: String) -> Array:
	var src = raw.get(sec)
	var out := []
	if src == null:
		return out
	if not (src is Array):
		cx.drop(sec, "bad_item")
		return out
	var cap := int(CAPS[sec])
	for i in src.size():
		if out.size() >= cap:
			cx.drop(sec, "over_cap", src.size() - i)
			break
		var it := _item(cx, sec, src[i])
		if not it.is_empty():
			out.append(it)
	return out


static func _item(cx: Clean, sec: String, it: Variant) -> Dictionary:
	if not (it is Dictionary):
		cx.drop(sec, "bad_item")
		return {}
	match sec:
		"branches":
			return _s_branch(cx, it)
		"props":
			return _s_prop(cx, it)
		"items", "pads", "barrels", "crowds":
			return _s_on_road(cx, sec, it)
		"crates":
			var pos = _v3(cx, it.get("pos"), cx.half)
			if pos == null:
				cx.drop(sec, "bad_item")
				return {}
			var uid := _uid(cx, it, sec)
			if uid < 0:
				return {}
			_extra(cx, sec, it, KEYS[sec])
			return {"uid": uid, "pos": pos}
		"hazards":
			return _s_hazard(cx, it)
		"eggs":
			return _s_egg(cx, it)
		"lights", "fires", "screens":
			return _s_placed(cx, sec, it)
		"lakes":
			return _s_lake(cx, it)
		"zones":
			return _s_zone(cx, it)
	cx.drop(sec, "bad_item")
	return {}


static func _s_point(cx: Clean, p: Variant, sec: String) -> Dictionary:
	if not (p is Dictionary):
		cx.drop(sec, "bad_item")
		return {}
	var pos = _v3(cx, p.get("pos"), cx.half)
	if pos == null:
		cx.drop(sec, "bad_item")
		return {}
	var uid := _uid(cx, p, sec)
	if uid < 0:
		return {}
	_extra(cx, sec, p, KEYS.point)
	var o := {"uid": uid, "pos": pos, "width": _f(cx, p.get("width"), 6.0, 40.0, 14.0)}
	var bank = _fo(cx, p.get("bank"), -25.0, 25.0)
	if bank != null:
		o["bank"] = bank
	var h = p.get("handle")
	if h is Dictionary:
		_extra(cx, sec, h, KEYS.handle)
		var d = h.get("dir")
		var dv := _vec(d) if d is Array and d.size() == 3 else Vector3.ZERO
		if d is Array and d.size() == 3 and is_finite(dv.x) and is_finite(dv.y) and is_finite(dv.z) and dv.length() > 1e-6:
			var dir := [float(d[0]), float(d[1]), float(d[2])]
			if absf(dv.length() - 1.0) > 1e-6:
				dv = dv.normalized()
				dir = [dv.x, dv.y, dv.z]
			o["handle"] = {"dir": dir, "in": _f(cx, h.get("in"), 0.0, 200.0, 0.0),
				"out": _f(cx, h.get("out"), 0.0, 200.0, 0.0)}
		else:
			cx.note("cleaned")
	elif h != null:
		cx.note("cleaned")
	var st = p.get("style")
	var sid := "asphalt"
	if st is String or st is StringName:
		if (cx.loose and is_id(str(st))) or cx.styles.has(str(st)):
			sid = str(st)
		else:
			cx.note("unknown_style")
	elif st != null:
		cx.note("unknown_style")
	o["style"] = sid
	var grip = p.get("grip")
	if grip != null:
		if grip is String and (grip == "road" or grip == "offroad"):
			o["grip"] = grip
		else:
			cx.note("cleaned")
	var g = p.get("gap")
	if g is Dictionary:
		_extra(cx, sec, g, KEYS.gap)
		o["gap"] = {"len": _f(cx, g.get("len"), 4.0, 40.0, 12.0),
			"at": snappedf(_f(cx, g.get("at"), 0.1, 0.9, 0.5), T_STEP),
			"lift": _f(cx, g.get("lift"), 0.0, 4.0, 1.8), "ramp": _f(cx, g.get("ramp"), 6.0, 40.0, 16.0)}
	elif g != null:
		cx.note("cleaned")
	var th = _fo(cx, p.get("tunnel_h"), 5.0, 20.0)
	if th != null:
		o["tunnel_h"] = th
	o["seesaw"] = _b(cx, p.get("seesaw"), false)
	for k in ["barrier_l", "barrier_r"]:
		var bar = _barrier(cx, p.get(k), sec)
		if bar != null:
			o[k] = bar
	o["follow"] = _b(cx, p.get("follow"), false)
	return o


## A barrier dict (2.5): null, {kind: "none"} or a full dict of a known kind.
static func _barrier(cx: Clean, v: Variant, sec: String) -> Variant:
	if v == null:
		return null
	if not (v is Dictionary):
		cx.note("cleaned")
		return null
	var kind = v.get("kind")
	if kind is String and kind == "none":
		if v.size() > 1:
			cx.drop(sec, "unknown_key", v.size() - 1)
		return {"kind": "none"}
	_extra(cx, sec, v, KEYS.barrier)
	var k := _e(cx, kind, LevelStyles.BARRIER_KINDS, "wall")
	var base: Dictionary = LevelStyles.BARRIERS.get(k, LevelStyles.BARRIER_BASE)
	var mat := clean_key(v.get("mat"))
	if mat == "":
		if v.get("mat") != null:
			cx.note("bad_key")
		mat = str(base.mat)
	return {"kind": k, "mat": mat, "h": _f(cx, v.get("h"), 0.1, 6.0, float(base.h)),
		"thick": _f(cx, v.get("thick"), 0.01, 3.0, float(base.thick)),
		"off": _f(cx, v.get("off"), 0.0, 5.0, float(base.off)),
		"col_h": _f(cx, v.get("col_h"), 0.0, 10.0, float(base.col_h)),
		"rep": _f(cx, v.get("rep"), 0.5, 50.0, float(base.rep))}


static func _s_styles(cx: Clean, v: Variant) -> Dictionary:
	var out := {}
	cx.styles = {}
	for id in LevelStyles.PRESETS:
		cx.styles[id] = true
	if v == null:
		return out
	if not (v is Dictionary):
		cx.drop("styles", "bad_item")
		return out
	var n := 0
	for id in v:
		n += 1
		if out.size() >= int(CAPS.styles):
			cx.drop("styles", "over_cap", (v as Dictionary).size() - n + 1)
			break
		var sid := str(id)
		var st = v[id]
		if not is_id(sid) or not (st is Dictionary):
			cx.drop("styles", "bad_item")
			continue
		out[sid] = _s_style(cx, sid, st)
		cx.styles[sid] = true
	return out


## An own style: its name and kind, plus the BASE / kind keys it has (sanitized).
static func _s_style(cx: Clean, id: String, st: Dictionary) -> Dictionary:
	var kind := _e(cx, st.get("kind"), LevelStyles.KINDS, "open")
	var kk: Dictionary = LevelStyles.KIND_KEYS[kind]
	var allowed: Array = LevelStyles.BASE.keys() + kk.keys()
	_extra(cx, "styles", st, allowed)
	var o := {"name": _t(cx, st.get("name"), 32, id.to_upper()), "kind": kind}
	for k in allowed:
		if k == "name" or k == "kind" or not st.has(k):
			continue
		var v = st[k]
		if k == "barrier_l" or k == "barrier_r":
			var bar = _barrier(cx, v, "styles")
			if bar != null:
				o[k] = bar
		elif k in LevelStyles.MAT_KEYS:
			var key := clean_key(v)
			if key != "" or (v is String and v == "" and (k == "pillar" or k == "light")):
				o[k] = key
			else:
				cx.note("bad_key")
		elif k == "road_u":
			o[k] = _e(cx, v, ["rep", "full"], "rep")
		elif k == "grip":
			o[k] = _e(cx, v, ["road", "offroad"], "road")
		elif k == "bank" or k == "lines":
			o[k] = _b(cx, v, false)
		elif k == "light_color":
			var c = _col(cx, v)
			if c != null:
				o[k] = c
		elif STYLE_RANGES.has(k):
			var r: Array = STYLE_RANGES[k]
			var dv = kk.get(k, LevelStyles.BASE.get(k, r[0]))
			var x = _fo(cx, v, float(r[0]), float(r[1]))
			o[k] = x if x != null else float(dv)
	return o


static func _s_road(cx: Clean, v: Variant) -> Dictionary:
	var r := _dict(cx, v, "road")
	var pts := []
	var idx := {}
	var src = r.get("points")
	if src is Array:
		for i in src.size():
			if pts.size() >= int(CAPS.points):
				cx.drop("road", "over_cap", src.size() - i)
				break
			var p := _s_point(cx, src[i], "road")
			if not p.is_empty():
				pts.append(p)
				idx[int(p.uid)] = true
	elif src != null:
		cx.drop("road", "bad_item")
	cx.roads[-1] = idx
	var closed := _b(cx, r.get("closed"), false)
	if closed and pts.size() < 3:
		closed = false
		cx.note("open_road")
	var start = _a(cx, r.get("start"), -1)
	if start == null:
		var given = r.get("start")
		var unset: bool = given == null or (given is Dictionary and _is_num(given.get("p")) and int(given.p) == 0)
		if not unset:
			cx.note("cleaned")
		start = {"p": int(pts[0].uid) if not pts.is_empty() else 0, "t": 0.0}
	return {"closed": closed, "start": start, "points": pts}


static func _s_branch(cx: Clean, it: Dictionary) -> Dictionary:
	var fork = _a(cx, it.get("fork"), -1)
	var merge = _a(cx, it.get("merge"), -1)
	if fork == null or merge == null:
		cx.drop("branches", "bad_anchor")
		return {}
	var uid := _uid(cx, it, "branches")
	if uid < 0:
		return {}
	_extra(cx, "branches", it, KEYS.branches)
	var pts := []
	var idx := {}
	var src = it.get("points")
	if src is Array:
		for i in src.size():
			if pts.size() >= int(CAPS.branch_points):
				cx.drop("branches", "over_cap", src.size() - i)
				break
			var p := _s_point(cx, src[i], "branches")
			if not p.is_empty():
				pts.append(p)
				idx[int(p.uid)] = true
	if pts.is_empty():
		cx.drop("branches", "bad_item")
		return {}
	if not cx.loose:
		cx.roads[uid] = idx
	var ai = it.get("ai")
	var a: Dictionary = ai if ai is Dictionary else {}
	if ai is Dictionary:
		_extra(cx, "branches", ai, KEYS.ai)
	elif ai != null:
		cx.note("cleaned")
	var off := _f(cx, it.get("offtrack"), -1.0, 200.0, -1.0)
	if off < 0.0:
		off = -1.0
	elif off < 20.0:
		cx.note("cleaned")
		off = 20.0
	return {"uid": uid, "name": _t(cx, it.get("name"), 24, "BRANCH"), "kind": _e(cx, it.get("kind"), BRANCH_KINDS, "alt"),
		"fork": fork, "merge": merge, "side": _i(cx, it.get("side"), -1, 1, 0),
		"merge_side": _i(cx, it.get("merge_side"), -1, 1, 0), "points": pts,
		"ai": {"take": _f(cx, a.get("take"), 0.0, 1.0, 0.5), "min_skill": _f(cx, a.get("min_skill"), 0.0, 1.0, 0.0),
			"commit": _f(cx, a.get("commit"), 10.0, 80.0, 40.0)},
		"risk": _f(cx, it.get("risk"), 0.0, 1.0, 0.0), "respawn": _e(cx, it.get("respawn"), ["before", "after", "main"], "before"),
		"retry_back": _f(cx, it.get("retry_back"), 10.0, 120.0, 45.0), "offtrack": off}


static func _s_prop(cx: Clean, it: Dictionary) -> Dictionary:
	var tag := _e(cx, it.get("tag"), PROP_TAGS, "")
	var model := clean_key(it.get("model"))
	if model == "":
		cx.drop("props", "bad_key" if it.get("model") != null else "bad_item")
		return {}
	var far := tag == "far"
	var pos = _v3(cx, it.get("pos"), cx.size * 3.0 if far else cx.half)
	if pos == null:
		cx.drop("props", "bad_item")
		return {}
	var uid := _uid(cx, it, "props")
	if uid < 0:
		return {}
	_extra(cx, "props", it, KEYS.props)
	if tag == "float" and not cx.sea:
		tag = ""
		cx.note("cleaned")
	var lo := 0.1 if far else 0.25
	var hi := 150.0 if far else 4.0
	var sc := clampf(snappedf(_f(cx, it.get("scale"), lo, hi, 1.0), 0.05), lo, hi)
	var phys := _b(cx, it.get("physics"), false)
	if phys and not cx.loose:
		if cx.physics >= int(CAPS.physics):
			phys = false
			cx.note("over_cap")
		else:
			cx.physics += 1
	var o := {"uid": uid, "model": model, "pos": pos, "yaw": _f(cx, it.get("yaw"), -360.0, 360.0, 0.0),
		"pitch": _f(cx, it.get("pitch"), -90.0, 90.0, 0.0), "roll": _f(cx, it.get("roll"), -90.0, 90.0, 0.0),
		"scale": sc, "physics": phys, "tag": tag}
	var grp = it.get("group")
	if grp != null:
		if _is_num(grp) and is_finite(float(grp)) and float(grp) >= 1.0 and float(grp) <= UID_MAX:
			o["group"] = int(grp)
		else:
			cx.note("cleaned")
	return o


## Crate rows, pads, barrels and crowd groups: a road and an anchor on it.
static func _s_on_road(cx: Clean, sec: String, it: Dictionary) -> Dictionary:
	var road_k := _road(cx, it.get("road"))
	var at = _a(cx, it.get("at"), road_k) if road_k != -2 else null
	if at == null:
		cx.drop(sec, "bad_anchor")
		return {}
	var uid := _uid(cx, it, sec)
	if uid < 0:
		return {}
	_extra(cx, sec, it, KEYS[sec])
	var o := {"uid": uid, "road": road_k, "at": at}
	match sec:
		"items":
			o["count"] = _i(cx, it.get("count"), 0, 5, 0)
			o["inset"] = _f(cx, it.get("inset"), 1.5, 5.0, 2.5)
		"pads":
			var lat = _fo(cx, it.get("lat"), -20.0, 20.0)
			if lat != null:
				o["lat"] = lat
			o["turn"] = _f(cx, it.get("turn"), -30.0, 30.0, 0.0)
		"crowds":
			o["side"] = -1 if _i(cx, it.get("side"), -1, 1, 1) < 0 else 1
			o["length"] = _f(cx, it.get("length"), 6.0, 120.0, 20.0)
			o["rows"] = _i(cx, it.get("rows"), 1, 4, 2)
			o["density"] = _f(cx, it.get("density"), 0.5, 2.0, 1.0)
			o["setback"] = _f(cx, it.get("setback"), 0.5, 20.0, 2.5)
			o["role"] = _e(cx, it.get("role"), CROWD_ROLES, "citizen")
			o["mood"] = _e(cx, it.get("mood"), CROWD_MOODS, "fan")
			o["sit"] = _f(cx, it.get("sit"), 0.0, 1.0, 0.0)
			var tags := []
			var tg = it.get("tags")
			if tg is Array:
				for k in ["start", "jump"]:
					if k in tg:
						tags.append(k)
				if tags.size() != tg.size():
					cx.note("cleaned")
			elif tg != null:
				cx.note("cleaned")
			o["tags"] = tags
	return o


static func _s_hazard(cx: Clean, it: Dictionary) -> Dictionary:
	var ty = it.get("type")
	if not (ty is String and ty in HAZARD_TYPES):
		cx.drop("hazards", "unknown_hazard")
		return {}
	var at = null
	if it.get("at") != null:
		at = _a(cx, it.get("at"), -1)
		if at == null:
			cx.drop("hazards", "bad_anchor")
			return {}
	var zone = null
	var zs = it.get("zone")
	if zs != null:
		if not (zs is Array) or zs.size() != 2:
			cx.drop("hazards", "bad_anchor")
			return {}
		var z0 = _a(cx, zs[0], -1)
		var z1 = _a(cx, zs[1], -1)
		if z0 == null or z1 == null:
			cx.drop("hazards", "bad_anchor")
			return {}
		zone = [z0, z1]
	if at == null and zone == null:
		cx.drop("hazards", "bad_anchor")
		return {}
	if ty in HEAVY and not cx.loose:
		if cx.heavy >= int(CAPS.heavy):
			cx.drop("hazards", "over_cap")
			return {}
	var uid := _uid(cx, it, "hazards")
	if uid < 0:
		return {}
	if ty in HEAVY and not cx.loose:
		cx.heavy += 1
	_extra(cx, "hazards", it, KEYS.hazards)
	var o := {"uid": uid, "type": ty, "at": at, "side": _i(cx, it.get("side"), -1, 1, 0), "zone": zone,
		"feel": _e(cx, it.get("feel"), FEELS, "normal")}
	var sb = _fo(cx, it.get("setback"), -20.0, 60.0)
	if sb != null:
		o["setback"] = sb
	var lat = _fo(cx, it.get("lat"), -60.0, 60.0)
	if lat != null:
		o["lat"] = lat
	if ty == "turret":
		o["mount"] = _e(cx, it.get("mount"), ["floor", "ceiling"], "floor")
	if ty == "strike_zone":
		o["style"] = _e(cx, it.get("style"), ["mortar", "arc"], "mortar")
	var pts := []
	var ps = it.get("pts")
	if ps is Array:
		for i in ps.size():
			if pts.size() >= int(CAPS.pts):
				cx.drop("hazards", "over_cap", ps.size() - i)
				break
			var q = _hz_point(cx, ps[i])
			if q != null:
				pts.append(q)
	elif ps != null:
		cx.note("cleaned")
	o["pts"] = pts
	o["p"] = _hz_params(cx, it.get("p"))
	return o


## A hazard point: [2..4 numbers] or {at, side, setback, lat, h, pos}; null when not valid.
static func _hz_point(cx: Clean, q: Variant) -> Variant:
	if q is Array:
		if q.size() < 2 or q.size() > 4:
			cx.drop("hazards", "bad_item")
			return null
		var o := []
		for x in q:
			if not _is_num(x) or not is_finite(float(x)):
				cx.drop("hazards", "bad_item")
				return null
			o.append(_f(cx, x, -100000.0, 100000.0, 0.0))
		return o
	if q is Dictionary:
		_extra(cx, "hazards", q, ["at", "side", "setback", "lat", "h", "pos"])
		var o2 := {}
		if q.get("at") != null:
			var a = _a(cx, q.at, -1)
			if a == null:
				cx.drop("hazards", "bad_anchor")
				return null
			o2["at"] = a
		if q.get("side") != null:
			o2["side"] = _i(cx, q.side, -1, 1, 0)
		for k in ["setback", "lat", "h"]:
			var x = _fo(cx, q.get(k), -1000.0, 1000.0)
			if x != null:
				o2[k] = x
		if q.get("pos") != null:
			var p = _v3(cx, q.pos, cx.size * 3.0)
			if p != null:
				o2["pos"] = p
		return o2
	cx.drop("hazards", "bad_item")
	return null


## A hazard's p: [a-z0-9_] keys (<= 32) to numbers, bools, plain strings or small arrays of numbers
## (the field gate's pattern rows, [min, max] pairs).
static func _hz_params(cx: Clean, v: Variant) -> Dictionary:
	var o := {}
	if v == null:
		return o
	if not (v is Dictionary):
		cx.note("cleaned")
		return o
	for k in v:
		var key := str(k)
		if o.size() >= 32 or not is_id(key):
			cx.drop("hazards", "unknown_key")
			continue
		var x = _hz_value(cx, v[k], 0)
		if x == null:
			cx.drop("hazards", "unknown_key")
			continue
		o[key] = x
	return o


static func _hz_value(cx: Clean, v: Variant, depth: int) -> Variant:
	if v is bool:
		return v
	if _is_num(v):
		if not is_finite(float(v)):
			cx.note("bad_number")
			return null
		return _f(cx, v, -1000000.0, 1000000.0, 0.0)
	if v is String:
		if v == "":
			return v
		var s := clean_key(v)
		if s == "" or clean_text(s, 64) != s:
			return null
		return s
	if v is Array and depth < 2 and v.size() <= 64:
		var o := []
		for x in v:
			var e = _hz_value(cx, x, depth + 1)
			if e == null or e is String:
				return null
			o.append(e)
		return o
	return null


static func _s_egg(cx: Clean, it: Dictionary) -> Dictionary:
	var kind = it.get("kind")
	if not (kind is String and kind in EGG_KINDS):
		cx.drop("eggs", "bad_item")
		return {}
	var pos = _v3(cx, it.get("pos"), cx.half)
	if pos == null:
		cx.drop("eggs", "bad_item")
		return {}
	var uid := _uid(cx, it, "eggs")
	if uid < 0:
		return {}
	_extra(cx, "eggs", it, KEYS.eggs)
	var o := {"uid": uid, "kind": kind, "pos": pos, "yaw": _f(cx, it.get("yaw"), -360.0, 360.0, 0.0)}
	if kind == "zombies" or kind == "lamarr":
		var path := []
		var src = it.get("path")
		if src is Array:
			for q in src:
				if path.size() >= int(CAPS.path):
					cx.drop("eggs", "over_cap")
					break
				var p = _v3(cx, q, cx.half)
				if p != null:
					path.append(p)
		o["path"] = path
	if kind == "birds":
		o["species"] = _e(cx, it.get("species"), SPECIES, "pigeon")
		var r = _fo(cx, it.get("radius"), 4.0, 60.0)
		if r != null:
			o["radius"] = r
	if kind == "birds" or kind == "zombies":
		if it.get("count") != null:
			o["count"] = _i(cx, it.get("count"), 1, 40, 8)
	if kind == "gman":
		o["chance"] = _f(cx, it.get("chance"), 0.0, 1.0, 0.5)
	return o


## Lights, fires and screens: a position plus a few numbers.
static func _s_placed(cx: Clean, sec: String, it: Dictionary) -> Dictionary:
	var pos = _v3(cx, it.get("pos"), cx.half)
	if pos == null:
		cx.drop(sec, "bad_item")
		return {}
	var uid := _uid(cx, it, sec)
	if uid < 0:
		return {}
	_extra(cx, sec, it, KEYS[sec])
	var o := {"uid": uid, "pos": pos}
	match sec:
		"lights":
			var c = _col(cx, it.get("color"))
			o["color"] = c if c != null else [1.0, 1.0, 1.0]
			o["range"] = _f(cx, it.get("range"), 1.0, 60.0, 16.0)
			o["energy"] = _f(cx, it.get("energy"), 0.0, 8.0, 1.2)
		"fires":
			o["size"] = _f(cx, it.get("size"), 0.0, 3.0, 1.0)
			o["smoke"] = _f(cx, it.get("smoke"), 0.0, 3.0, 1.0)
			o["light"] = _b(cx, it.get("light"), true)
		"screens":
			o["yaw"] = _f(cx, it.get("yaw"), -360.0, 360.0, 0.0)
			o["w"] = _f(cx, it.get("w"), 2.0, 20.0, 8.0)
			o["h"] = _f(cx, it.get("h"), 1.0, 12.0, 4.5)
	return o


static func _s_lake(cx: Clean, it: Dictionary) -> Dictionary:
	var c = it.get("center")
	var s = it.get("size")
	if not (c is Array) or c.size() != 2 or not (s is Array) or s.size() != 2:
		cx.drop("lakes", "bad_item")
		return {}
	for x in c + s:
		if not _is_num(x) or not is_finite(float(x)):
			cx.drop("lakes", "bad_item")
			return {}
	var uid := _uid(cx, it, "lakes")
	if uid < 0:
		return {}
	_extra(cx, "lakes", it, KEYS.lakes)
	return {"uid": uid,
		"center": [snappedf(_f(cx, c[0], -cx.half, cx.half, 0.0), 0.001), snappedf(_f(cx, c[1], -cx.half, cx.half, 0.0), 0.001)],
		"size": [_f(cx, s[0], 4.0, 2000.0, 40.0), _f(cx, s[1], 4.0, 2000.0, 40.0)],
		"level": _f(cx, it.get("level"), HEIGHT_MIN, HEIGHT_MAX, 0.0)}


static func _s_zone(cx: Clean, it: Dictionary) -> Dictionary:
	var road_k := _road(cx, it.get("road"))
	var a = _a(cx, it.get("a"), road_k) if road_k != -2 else null
	var b = _a(cx, it.get("b"), road_k) if road_k != -2 else null
	if a == null or b == null:
		cx.drop("zones", "bad_anchor")
		return {}
	var uid := _uid(cx, it, "zones")
	if uid < 0:
		return {}
	_extra(cx, "zones", it, KEYS.zones)
	return {"uid": uid, "road": road_k, "a": a, "b": b, "scale": _f(cx, it.get("scale"), 0.2, 0.9, 0.4),
		"ease": _f(cx, it.get("ease"), 5.0, 40.0, 15.0)}


static func _s_env(cx: Clean, v: Variant) -> Dictionary:
	var e := _dict(cx, v, "env")
	var sky := clean_key(e.get("sky"))
	if sky == "":
		if e.get("sky") != null:
			cx.note("bad_key")
		sky = DEFAULT_SKY
	var o := {"sky": sky}
	var sun = e.get("sun")
	if sun is Dictionary:
		_extra(cx, "env", sun, ["az", "el"])
		o["sun"] = {"az": _f(cx, sun.get("az"), 0.0, 360.0, 135.0), "el": _f(cx, sun.get("el"), 5.0, 90.0, 45.0)}
	else:
		if sun != null and not (sun is String and sun == "sky"):
			cx.note("cleaned")
		o["sun"] = "sky"
	for k in ["sun_color", "ambient", "fog_color"]:
		var c = _col(cx, e.get(k))
		if c != null:
			o[k] = c
	var se = _fo(cx, e.get("sun_energy"), 0.0, 3.0)
	if se != null:
		o["sun_energy"] = se
	var ke = _fo(cx, e.get("sky_energy"), 0.1, 2.0)
	if ke != null:
		o["sky_energy"] = ke
	o["ambient_energy"] = _f(cx, e.get("ambient_energy"), 0.0, 4.0, 1.0)
	o["fog_begin"] = _f(cx, e.get("fog_begin"), 20.0, 2000.0, 180.0)
	o["fog_end"] = _f(cx, e.get("fog_end"), 100.0, 6000.0, 1500.0)
	o["fog_sky"] = _f(cx, e.get("fog_sky"), 0.0, 1.0, 0.0)
	o["exposure"] = _f(cx, e.get("exposure"), 0.4, 2.0, 1.08)
	o["glow"] = _f(cx, e.get("glow"), 0.0, 1.5, 0.35)
	o["sdfgi"] = _b(cx, e.get("sdfgi"), true)
	return o


static func _s_race(cx: Clean, v: Variant) -> Dictionary:
	var r := _dict(cx, v, "race")
	var far := cx.size * 3.0
	var o := {"gantry": _e(cx, r.get("gantry"), GANTRIES, "combine"),
		"background": _e(cx, r.get("background"), BACKGROUNDS, "none"),
		"rescue": _e(cx, r.get("rescue"), RESCUES, "scanner"),
		"offtrack": _f(cx, r.get("offtrack"), 30.0, 200.0, 60.0), "laps": _i(cx, r.get("laps"), 1, 9, 3)}
	var cit = r.get("citadel")
	if cit != null:
		var c := _nums(cit, 4)
		if c.is_empty():
			cx.note("cleaned")
		else:
			o["citadel"] = [_f(cx, c[0], -far, far, 0.0), _f(cx, c[1], -far, far, 0.0), _f(cx, c[2], -far, far, 0.0),
				_f(cx, c[3], 0.1, 10.0, 1.0)]
	var sg = r.get("seagulls")
	if sg != null:
		var gulls := []
		if sg is Array:
			for q in sg:
				if gulls.size() >= int(CAPS.seagulls):
					cx.drop("race", "over_cap")
					break
				var g := _nums(q, 4)
				if g.is_empty():
					cx.drop("race", "bad_item")
					continue
				gulls.append([_f(cx, g[0], -far, far, 0.0), _f(cx, g[1], -far, far, 0.0), _f(cx, g[2], -far, far, 0.0),
					_f(cx, g[3], 1.0, 500.0, 20.0)])
		else:
			cx.note("cleaned")
		o["seagulls"] = gulls
	var music := []
	var ms = r.get("music")
	if ms is Array:
		for m in ms:
			var key := clean_key(m)
			if key == "":
				cx.drop("race", "bad_key")
			elif not key in music:
				if music.size() >= int(CAPS.music):
					cx.drop("race", "over_cap")
				else:
					music.append(key)
	elif ms != null:
		cx.note("cleaned")
	o["music"] = music
	return o


## v as n finite numbers, or [] when it is not that.
static func _nums(v: Variant, n: int) -> Array:
	if not (v is Array) or v.size() != n:
		return []
	for x in v:
		if not _is_num(x) or not is_finite(float(x)):
			return []
	return v
