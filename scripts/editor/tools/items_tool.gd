class_name ItemsTool
extends EditorTool
## 1.6 ITEMS: crate rows, single crates, boost pads, barrels and LOW GRAVITY zones. A click on a
## road places the mode's item at that spot (anchored, 2.3); a single crate goes 1.2 m over any
## surface. Markers are diamonds over the rows, squares on crates, triangles on pads, dots on
## barrels and end bars + a blue strip for zones; a marker turns red for a pad within 12 m of a grid
## slot or 10 m of a crate and for anything over a jump or within 16 m of one. Anchored markers
## slide along their road (zone end bars move one end). Tool options: AUTO ITEMS (crate rows only,
## LevelDress.items_ops, one undo step) and AUTO DRESS... (4.4). The road-spot helpers here are
## shared with CrowdsTool and ObjectsTool. P17.

const MODES := ["row", "crate", "pad", "barrels", "zone"]
const MODE_NAMES := ["CRATE ROW", "SINGLE CRATE", "BOOST PAD", "BARRELS", "LOW GRAVITY"]
## The kinds' icons and tips (EditorKit.icon names; {ed_*} written as keys).
const MODE_ICONS := ["crate_row", "crate", "boost", "barrels", "gravity"]
const MODE_TIPS := ["Click a road: a row of item crates across it.", "Click anywhere: one item crate.",
	"Click a road: a boost pad on the racing line; {ed_mod_shift} + click: in that lane.", "Click a road: a group of barrels on it.",
	"Click a road: a low-gravity stretch; drag its ends to size it."]
const SECTION := {"item_row": "items", "crate": "crates", "pad": "pads", "barrels": "barrels", "zone": "zones"}
const NOUN := {"item_row": "CRATE ROW", "crate": "CRATE", "pad": "BOOST PAD", "barrels": "BARRELS", "zone": "LOW GRAVITY ZONE"}
## Hard caps per list (2.10).
const CAP := {"items": 40, "crates": 64, "pads": 64, "barrels": 32, "zones": 16}
const T_STEP := 1.0 / 65536.0
const CRATE_UP := 1.2
const BARREL_UP := 0.6
const ZONE_LEN := 60.0
const PAD_GRID := 12.0          # a pad this close to a grid slot is flagged
const PAD_CRATE := 10.0         # ... or to a crate
const JUMP_NEAR := 16.0         # anything this close to a jump is flagged
const ROW_COLOR := Color(1.0, 0.78, 0.25)
const CRATE_COLOR := Color(0.95, 0.65, 0.2)
const PAD_COLOR := Color(0.3, 0.85, 1.0)
const BARREL_COLOR := Color(0.95, 0.3, 0.2)
const ZONE_COLOR := Color(0.35, 0.55, 1.0)
const WARN_COLOR := Color(0.92, 0.2, 0.16)

var mode := "row"
var _drag := {}                 # a marker drag of this tool: {uid, kind, how: "slide" | "free", name}
var _slide := {}                # slide state: {uid, sub, s0, sa, sb}
var _counts_label: Label


func _init(ed: TrackEditor) -> void:
	super(ed)
	id = "items"
	title = "ITEMS"
	purpose = "Crate rows, crates, boost pads, barrels and low-gravity zones"


func kinds() -> PackedStringArray:
	return PackedStringArray(["item_row", "crate", "pad", "barrels", "zone"])


func deactivate() -> void:
	_end_drag()


# ---------------------------------------------------------------- shared road helpers

## The full bake's road of a key (never a preview), null when there is none.
func full_road(key: int) -> LevelRoad:
	if editor == null:
		return null
	return LevelFixes.road_of(editor.build, key)


## {key, i, s, lat, off, pos} of the road spot under a hit: on the road itself, or (reach > 0) on
## the ground within `reach` metres past an edge of the nearest road; {} when there is none.
## `off` is the distance past the edge (negative on the road).
func road_spot(hit: EditorHit, reach := 0.0) -> Dictionary:
	if hit == null or not hit.hit or editor == null or editor.build == null:
		return {}
	var on_road := hit.what == "road" and hit.road != -2
	var best := {}
	var best_off := INF
	for r in editor.build.roads:
		if r == null or r.partial or r.n < 2:
			continue
		if on_road and r.key != hit.road:
			continue
		var i := -1
		if on_road and hit.sample >= 0 and hit.sample < r.n:
			i = r.closest(hit.pos, hit.sample, 4)
		else:
			i = r.closest(hit.pos)
		var lat := r.lateral(hit.pos, i)
		var off := absf(lat) - r.width[i] * 0.5
		if not on_road and off > reach:
			continue
		if off >= best_off:
			continue
		best_off = off
		best = {"key": r.key, "i": i, "s": s_near(r, hit.pos, i), "lat": lat, "off": off, "pos": hit.pos}
	return best


## Metres along r of the spot nearest p (sample i nearest, else found).
static func s_near(r: LevelRoad, p: Vector3, i := -1) -> float:
	if r == null or r.n <= 0:
		return 0.0
	if i < 0 or i >= r.n:
		i = r.closest(p)
	var s := r.s[i] + clampf((p - r.pos[i]).dot(r.fwd[i]), -r.step, r.step)
	return wrap_s(r, s)


## s kept on the road: wrapped round a loop, clamped on an open road.
static func wrap_s(r: LevelRoad, s: float) -> float:
	if r == null or r.length <= 0.0:
		return s
	if r.closed:
		return fposmod(s, r.length)
	return clampf(s, 0.0, r.length)


## The signed shortest way from a to b along r (a loop wraps).
static func delta_s(r: LevelRoad, a: float, b: float) -> float:
	var d := b - a
	if r != null and r.closed and r.length > 0.0:
		d = fposmod(d + r.length * 0.5, r.length) - r.length * 0.5
	return d


## The anchor {p, t} of a spot s metres along r, t on the T_STEP grid.
static func anchor_of(r: LevelRoad, s: float) -> Dictionary:
	var a := r.s_to_anchor(wrap_s(r, s))
	if a.is_empty():
		return {}
	a["t"] = clampf(snappedf(float(a.t), T_STEP), 0.0, 1.0)
	return a


## The world spot of an anchor on road key, `lat` across and `h` over the surface (NAN x when the
## road or the anchor is unknown).
func anchor_pos(key: int, at: Variant, lat := 0.0, h := 0.0) -> Vector3:
	var r := full_road(key)
	if r == null or not (at is Dictionary) or r.n <= 0:
		return Vector3(NAN, NAN, NAN)
	var i := r.anchor_i(at)
	return r.surface(i, lat, h)


## Metres along road key of an anchor (NAN when unknown).
func anchor_s(key: int, at: Variant) -> float:
	var r := full_road(key)
	if r == null or not (at is Dictionary):
		return NAN
	return r.anchor_s(at)


static func op_add(section: String, item: Dictionary) -> Array:
	return LevelDoc.op_insert([section], -1, item)


static func op_del(section: String, uid: int) -> Array:
	return ["remove", [section], "#%d" % uid]


static func op_field(section: String, uid: int, field: String, value: Variant) -> Array:
	if value == null:
		return LevelDoc.op_erase([section, "#%d" % uid, field])
	return LevelDoc.op_set([section, "#%d" % uid, field], value)


## The live list of a document section ([] when it is missing).
func list_of(section: String) -> Array:
	if editor == null or editor.doc == null:
		return []
	var l = editor.doc.data.get(section)
	return l if l is Array else []


## The live item of a uid in one section ({} when it is not there).
func item_of(section: String, uid: int) -> Dictionary:
	if editor == null or editor.doc == null:
		return {}
	var f := editor.doc.find(uid)
	if f.is_empty() or str(f.get("section", "")) != section or not (f.get("item") is Dictionary):
		return {}
	return f.item


## Whether a list has room under its hard cap (else a status line says so).
func has_room(section: String, more := 1) -> bool:
	var cap := int(CAP.get(section, LevelDoc.CAPS.get(section, 1 << 30)))
	if list_of(section).size() + more > cap:
		editor.status("At most %d %s on a track." % [cap, section.to_upper()])
		editor.toast("Limit reached (%d %s)" % [cap, section])
		return false
	return true


static func _v3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


static func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


# ---------------------------------------------------------------- placing

func click(hit: EditorHit, mods: int) -> bool:
	if editor == null or editor.doc == null or hit == null:
		return false
	if hit.what == "marker" or hit.what == "gizmo":
		return false   # the common rule: select
	if not hit.hit:
		return false
	if mode == "crate":
		if hit.what == "water":
			editor.status("Crates go on a surface, not on the water.")
			return true
		return place_crate(hit.pos) > 0
	if hit.what == "prop":
		return false
	var sp := road_spot(hit)
	if sp.is_empty():
		editor.status("Click on a road." if editor.build != null else "Wait for the track to bake.")
		return true
	match mode:
		"row":
			return place_row(sp) > 0
		"pad":
			return place_pad(sp, has_mod(mods, MOD_SHIFT)) > 0
		"barrels":
			return place_barrels(sp) > 0
		"zone":
			return place_zone(sp) > 0
	return false


## A crate row across the road at the spot (count AUTO, inset 2.5). Returns its uid (0 refused).
func place_row(sp: Dictionary) -> int:
	if not has_room("items"):
		return 0
	var r := full_road(int(sp.key))
	if r == null:
		return 0
	var u := editor.doc.new_uid()
	_add("ADD CRATE ROW", "items", {"uid": u, "road": int(sp.key), "at": anchor_of(r, float(sp.s)), "count": 0, "inset": 2.5})
	return u


## A single crate 1.2 m over a surface spot.
func place_crate(p: Vector3) -> int:
	if not has_room("crates"):
		return 0
	var u := editor.doc.new_uid()
	_add("ADD CRATE", "crates", {"uid": u, "pos": _arr(p + Vector3.UP * CRATE_UP)})
	return u


## A boost pad on the racing line, or (lane) at the clicked lateral.
func place_pad(sp: Dictionary, lane: bool) -> int:
	if not has_room("pads"):
		return 0
	var r := full_road(int(sp.key))
	if r == null:
		return 0
	var u := editor.doc.new_uid()
	var lat: Variant = null
	if lane:
		lat = snappedf(clampf(float(sp.lat), -20.0, 20.0), 0.01)
	_add("ADD BOOST PAD", "pads", {"uid": u, "road": int(sp.key), "at": anchor_of(r, float(sp.s)), "lat": lat, "turn": 0.0})
	return u


## Three explosive drums across the road's middle third (the compiler places them).
func place_barrels(sp: Dictionary) -> int:
	if not has_room("barrels"):
		return 0
	var r := full_road(int(sp.key))
	if r == null:
		return 0
	var u := editor.doc.new_uid()
	_add("ADD BARRELS", "barrels", {"uid": u, "road": int(sp.key), "at": anchor_of(r, float(sp.s))})
	return u


## A 60 m LOW GRAVITY zone centred on the spot (kept on an open road).
func place_zone(sp: Dictionary) -> int:
	if not has_room("zones"):
		return 0
	var r := full_road(int(sp.key))
	if r == null:
		return 0
	var s := float(sp.s)
	var s0 := s - ZONE_LEN * 0.5
	var s1 := s + ZONE_LEN * 0.5
	if not r.closed:
		s0 = maxf(s0, 0.0)
		s1 = minf(s1, r.length)
		if s1 - s0 < 10.0:
			editor.status("Too close to the end of the road for a zone.")
			return 0
	var u := editor.doc.new_uid()
	_add("ADD LOW GRAVITY ZONE", "zones", {"uid": u, "road": int(sp.key), "a": anchor_of(r, s0), "b": anchor_of(r, s1),
		"scale": 0.4, "ease": 15.0})
	return u


func _add(step_name: String, section: String, item: Dictionary) -> void:
	editor.commit(step_name, [op_add(section, item)])
	editor.select(PackedInt32Array([int(item.uid)]))
	succeeded()


## AUTO ITEMS (S1): crate rows only (LevelDress.items_ops on a current bake), one undo step.
func auto_items() -> void:
	if editor == null or editor.doc == null:
		return
	editor.bake_now(func(b: LevelBuild) -> void:
		if b == null:
			return
		var ops := LevelDress.items_ops(editor.doc, b)
		if ops.is_empty():
			editor.toast("No crate rows to add.")
			return
		editor.commit("AUTO ITEMS", ops)
		editor.toast("Added %d crate row%s" % [ops.size(), "" if ops.size() == 1 else "s"]))


# ---------------------------------------------------------------- hover

func hints(hit: EditorHit) -> Array:
	if hit == null or not hit.hit:
		return [["CLICK A ROAD: %s" % _mode_name()]]
	if hit.what == "marker":
		if hit.kind == "issue":
			return [["CLICK SHOW THE PROBLEM"]]
		if owns(hit.kind):
			if hit.kind == "zone" and hit.sub in [3, 4]:
				return [["DRAG MOVE THIS END"], ["CLICK SELECT"]]
			if hit.kind == "crate":
				return [["CLICK SELECT"], ["DRAG MOVE"], ["{ed_delete} DELETE"]]
			return [["CLICK SELECT"], ["DRAG SLIDE ALONG THE ROAD"], ["{ed_delete} DELETE"]]
		return [["CLICK SELECT"]]
	if mode == "crate":
		return [["CLICK ADD A CRATE"]]
	if hit.what == "road":
		match mode:
			"row":
				return [["CLICK ADD A CRATE ROW"]]
			"pad":
				return [["CLICK ADD A BOOST PAD ON THE RACING LINE"], ["{ed_mod_shift} CLICK ADD ONE IN THIS LANE"]]
			"barrels":
				return [["CLICK ADD BARRELS"]]
			"zone":
				return [["CLICK ADD A LOW GRAVITY ZONE"]]
	return [["CLICK A ROAD: %s" % _mode_name()]]


func status_step() -> String:
	match mode:
		"crate":
			return "Click anywhere to put a crate there"
		"pad":
			return "Click a road for a boost pad on the racing line ({ed_mod_shift} + click: in that lane)"
		"zone":
			return "Click a road for a 60 m low-gravity zone; drag its end bars along the road"
		"row":
			return "Click a road to add a crate row"
		"barrels":
			return "Click a road to add a group of barrels"
	return "Click a road to add %s" % _mode_name().to_lower()


func _mode_name() -> String:
	var k := MODES.find(mode)
	return MODE_NAMES[k] if k >= 0 else "ITEMS"


# ---------------------------------------------------------------- markers and overlay

func markers(m: EditorMarkers) -> void:
	if editor == null or editor.doc == null:
		return
	var warn := warning_map()
	for it in list_of("items"):
		if it is Dictionary:
			var p := anchor_pos(int(it.get("road", -1)), it.get("at"), 0.0, CRATE_UP)
			if not is_nan(p.x):
				m.add("item_row", int(it.uid), p, EditorMarkers.Shape.DIAMOND, WARN_COLOR if warn.has(int(it.uid)) else ROW_COLOR, 2.0)
	for c in list_of("crates"):
		if c is Dictionary:
			m.add("crate", int(c.uid), _v3(c.get("pos")), EditorMarkers.Shape.SQUARE, WARN_COLOR if warn.has(int(c.uid)) else CRATE_COLOR, 1.2)
	for pd in list_of("pads"):
		if pd is Dictionary:
			var p := pad_pos(pd)
			if not is_nan(p.x):
				m.add("pad", int(pd.uid), p, EditorMarkers.Shape.TRIANGLE, WARN_COLOR if warn.has(int(pd.uid)) else PAD_COLOR, 2.0)
	for b in list_of("barrels"):
		if b is Dictionary:
			var p := anchor_pos(int(b.get("road", -1)), b.get("at"), 0.0, BARREL_UP)
			if not is_nan(p.x):
				m.add("barrels", int(b.uid), p, EditorMarkers.Shape.DOT, WARN_COLOR if warn.has(int(b.uid)) else BARREL_COLOR, 1.6)
	for z in list_of("zones"):
		if not (z is Dictionary):
			continue
		var key := int(z.get("road", -1))
		var u := int(z.uid)
		var col := WARN_COLOR if warn.has(u) else ZONE_COLOR
		var pa := anchor_pos(key, z.get("a"), 0.0, 0.5)
		var pb := anchor_pos(key, z.get("b"), 0.0, 0.5)
		if is_nan(pa.x) or is_nan(pb.x):
			continue
		m.add("zone", u, pa, EditorMarkers.Shape.BAR, col, 3.0, 3)
		m.add("zone", u, pb, EditorMarkers.Shape.BAR, col, 3.0, 4)
		var r := full_road(key)
		var sa := r.anchor_s(z.a)
		var mid := wrap_s(r, sa + delta_s(r, sa, r.anchor_s(z.b)) * 0.5) if r.closed else (sa + r.anchor_s(z.b)) * 0.5
		m.add("zone", u, r.surface(r.idx(mid), 0.0, 0.8), EditorMarkers.Shape.DIAMOND, col, 2.0, 0)


## Where a pad sits: its lane, or the racing line at its anchor.
func pad_pos(pd: Dictionary) -> Vector3:
	var key := int(pd.get("road", -1))
	var r := full_road(key)
	if r == null or not (pd.get("at") is Dictionary):
		return Vector3(NAN, NAN, NAN)
	var i := r.anchor_i(pd.at)
	var lat := 0.0
	var l = pd.get("lat")
	if l is float or l is int:
		lat = float(l)
	elif r.line.size() == r.n:
		lat = (r.line[i] - r.pos[i]).dot(r.right[i])
	return r.surface(i, lat, 0.3)


func overlay(d: EditorDraw) -> void:
	draw_zones(d)


## The LOW GRAVITY zones as blue strips on their roads (the selected one brighter); VIEW > ZONES
## can draw them in the other tools too.
func draw_zones(d: EditorDraw) -> void:
	if editor == null or editor.doc == null or d == null:
		return
	for z in list_of("zones"):
		if not (z is Dictionary):
			continue
		var r := full_road(int(z.get("road", -1)))
		if r == null or not (z.get("a") is Dictionary) or not (z.get("b") is Dictionary):
			continue
		var sa := r.anchor_s(z.a)
		var sb := r.anchor_s(z.b)
		var sel := editor.selection != null and editor.selection.has(int(z.uid))
		var col := Color(ZONE_COLOR, 0.38 if sel else 0.22)
		var w := r.width[r.idx(sa)] * 0.5
		if r.closed and sb < sa:
			d.strip_on_road(r, sa, r.length, -w, w, col)
			d.strip_on_road(r, 0.0, sb, -w, w, col)
		else:
			d.strip_on_road(r, minf(sa, sb), maxf(sa, sb), -w, w, col)


## uid -> [reasons] for the red markers (1.6 ITEMS): a pad within 12 m of a grid slot or 10 m of a
## crate; anything over a jump or within 16 m of one.
func warning_map() -> Dictionary:
	var out := {}
	if editor == null or editor.build == null:
		return out
	var grid := PackedVector3Array()
	for g in editor.build.data.get("grid", []):
		if g is Dictionary:
			grid.append(_v3(g.get("pos")))
	var boxes := PackedVector3Array()
	for b in editor.build.data.get("item_boxes", []):
		boxes.append(_v3(b))
	for sec in ["items", "pads", "barrels"]:
		for it in list_of(sec):
			if not (it is Dictionary):
				continue
			var key := int(it.get("road", -1))
			var r := full_road(key)
			if r == null or not (it.get("at") is Dictionary):
				continue
			var i := r.anchor_i(it.at)
			var why := []
			if near_jump(r, i):
				why.append("Over a jump or within 16 m of one")
			if sec == "pads":
				var p := pad_pos(it)
				if _near(grid, p, PAD_GRID):
					why.append("Within 12 m of a grid slot")
				if _near(boxes, p, PAD_CRATE):
					why.append("Within 10 m of a crate")
			if not why.is_empty():
				out[int(it.uid)] = why
	for z in list_of("zones"):
		if not (z is Dictionary):
			continue
		var r := full_road(int(z.get("road", -1)))
		if r == null or not (z.get("a") is Dictionary) or not (z.get("b") is Dictionary):
			continue
		if near_jump(r, r.anchor_i(z.a)) or near_jump(r, r.anchor_i(z.b)):
			out[int(z.uid)] = ["An end over a jump or within 16 m of one"]
	var main := full_road(-1)
	if main != null:
		for c in list_of("crates"):
			if not (c is Dictionary):
				continue
			var p := _v3(c.get("pos"))
			var i := main.closest(p)
			if absf(main.lateral(p, i)) <= main.width[i] * 0.5 + 1.0 and near_jump(main, i):
				out[int(c.uid)] = ["Over a jump or within 16 m of one"]
	return out


## Any gap sample within 16 m of sample i.
static func near_jump(r: LevelRoad, i: int) -> bool:
	if r == null or r.gap.size() != r.n or r.n <= 0:
		return false
	var k := int(ceil(JUMP_NEAR / maxf(r.step, 0.5)))
	for j in range(i - k, i + k + 1):
		if not r.closed and (j < 0 or j >= r.n):
			continue
		if r.gap[r.wrap(j)] == 1:
			return true
	return false


static func _near(pts: PackedVector3Array, p: Vector3, d: float) -> bool:
	for q in pts:
		if Vector2(q.x - p.x, q.z - p.z).length() < d:
			return true
	return false


# ---------------------------------------------------------------- moving

func drag_begin(hit: EditorHit, mods: int) -> bool:
	if editor == null or editor.doc == null or hit == null:
		return false
	if hit.what != "marker" or not owns(hit.kind) or hit.uid <= 0:
		return false
	var nm := "MOVE %s" % str(NOUN.get(hit.kind, hit.kind.to_upper()))
	editor.history.begin_gesture(nm)
	if hit.kind == "crate":
		var c := item_of("crates", hit.uid)
		_drag = {"uid": hit.uid, "kind": hit.kind, "how": "free", "name": nm, "y": _v3(c.get("pos")).y - hit.pos.y}
	else:
		_drag = {"uid": hit.uid, "kind": hit.kind, "how": "slide", "name": nm}
		slide(hit.uid, hit, 0)
	if not editor.selection.has(hit.uid):
		editor.select(PackedInt32Array([hit.uid]))
	return true


func drag_move(hit: EditorHit, _mods: int) -> void:
	_drag_step(hit, 1)


func drag_end(hit: EditorHit, _mods: int) -> void:
	_drag_step(hit, 2)
	_end_drag()
	succeeded()


func _drag_step(hit: EditorHit, phase: int) -> void:
	if _drag.is_empty() or hit == null:
		return
	if _drag.how == "free":
		if hit.hit:
			editor.commit(str(_drag.name), [op_field("crates", int(_drag.uid), "pos", _arr(hit.pos + Vector3.UP * CRATE_UP))], "items_drag")
		return
	var ops := slide(int(_drag.uid), hit, phase)
	if not ops.is_empty():
		editor.commit(str(_drag.name), ops, "items_drag")


func _end_drag() -> void:
	if not _drag.is_empty() and editor != null and editor.history != null:
		editor.history.end_gesture()
	_drag = {}
	_slide = {}


## Esc while the button holds a move: taken back.
func cancel_drag() -> void:
	if not _drag.is_empty() and editor != null and editor.history != null:
		editor.history.cancel_gesture()
	_drag = {}
	_slide = {}


## An anchored item's marker dragged (here or from SELECT): it follows the road spot nearest the
## cursor on its own road; a zone's end bar (sub 3 / 4) moves that end, its middle the whole zone.
func slide(uid: int, hit: EditorHit, phase: int) -> Array:
	if editor == null or editor.doc == null or hit == null:
		return []
	var f := editor.doc.find(uid)
	if f.is_empty() or not (f.get("item") is Dictionary):
		return []
	var sec := str(f.section)
	var it: Dictionary = f.item
	var key := int(it.get("road", -1))
	var r := full_road(key)
	if r == null:
		return []
	if phase == 0:
		_slide = {"uid": uid, "sub": hit.sub, "s0": s_near(r, hit.pos)}
		if sec == "zones" and it.get("a") is Dictionary and it.get("b") is Dictionary:
			_slide["sa"] = r.anchor_s(it.a)
			_slide["sb"] = r.anchor_s(it.b)
		return []
	if _slide.is_empty() or int(_slide.uid) != uid:
		_slide = {"uid": uid, "sub": hit.sub, "s0": s_near(r, hit.pos)}
	var s := s_near(r, hit.pos)
	var out := []
	if sec == "zones":
		var sub := int(_slide.get("sub", 0))
		if sub == 3:
			out.append(op_field(sec, uid, "a", anchor_of(r, s)))
		elif sub == 4:
			out.append(op_field(sec, uid, "b", anchor_of(r, s)))
		elif _slide.has("sa"):
			var ds := delta_s(r, float(_slide.s0), s)
			var sa := float(_slide.sa) + ds
			var sb := float(_slide.sb) + ds
			if not r.closed:
				var lo := minf(sa, sb)
				var hi := maxf(sa, sb)
				if lo < 0.0:
					sa -= lo
					sb -= lo
				elif hi > r.length:
					sa -= hi - r.length
					sb -= hi - r.length
			out.append(op_field(sec, uid, "a", anchor_of(r, sa)))
			out.append(op_field(sec, uid, "b", anchor_of(r, sb)))
	elif sec in ["items", "pads", "barrels"]:
		out.append(op_field(sec, uid, "at", anchor_of(r, s)))
	if phase == 2:
		_slide = {}
	return out


# ---------------------------------------------------------------- deleting, boxes

func delete_ops(uids: PackedInt32Array) -> Array:
	var out := []
	if editor == null or editor.doc == null:
		return out
	for u in uids:
		var f := editor.doc.find(u)
		var sec := str(f.get("section", ""))
		if sec in SECTION.values():
			out.append(op_del(sec, u))
	return out


func item_aabb(uid: int) -> AABB:
	if editor == null or editor.doc == null:
		return AABB()
	var f := editor.doc.find(uid)
	if f.is_empty() or not (f.get("item") is Dictionary):
		return AABB()
	var it: Dictionary = f.item
	var key := int(it.get("road", -1))
	match str(f.section):
		"crates":
			var p := _v3(it.get("pos"))
			return AABB(p - Vector3.ONE * 0.8, Vector3.ONE * 1.6)
		"pads":
			var p := pad_pos(it)
			if not is_nan(p.x):
				return AABB(p - Vector3(3, 1, 3), Vector3(6, 2, 6))
		"items", "barrels":
			var r := full_road(key)
			var p := anchor_pos(key, it.get("at"), 0.0, 1.0)
			if r != null and not is_nan(p.x):
				var w := r.width[r.anchor_i(it.at)] * 0.5
				return AABB(p - Vector3(w, 1.5, w), Vector3(w * 2.0, 3.0, w * 2.0))
		"zones":
			var pa := anchor_pos(key, it.get("a"), 0.0, 0.0)
			var pb := anchor_pos(key, it.get("b"), 0.0, 0.0)
			if not is_nan(pa.x) and not is_nan(pb.x):
				return AABB(pa, Vector3.ZERO).expand(pb).grow(8.0)
	return AABB()


func on_doc_changed(_sections: PackedStringArray, _uids: PackedInt32Array) -> void:
	if _counts_label != null and is_instance_valid(_counts_label):
		_counts_label.text = counts_text()


# ---------------------------------------------------------------- options and inspector

func options(box: VBoxContainer) -> void:
	if editor == null or editor.doc == null:
		return
	box.add_child(EditorKit.tiles(MODE_NAMES, MODES.find(mode), func(i: int) -> void: set_mode(MODES[i]), MODE_ICONS, MODE_TIPS))
	box.add_child(EditorKit.actions([
		["AUTO ITEMS", "tool_items", auto_items, "Crate rows on the straights, about every 400 m (one undo step)."],
		["AUTO DRESS...", "wand", func() -> void: editor.open_dialog(AutoDressDialog.new(editor)),
			"Crate rows, boost pads, rails, scenery and a crowd in one go: you pick which."]]))
	_counts_label = UiKit.label(counts_text(), EditorKit.FONT_SMALL, UiKit.TEXT_DIM)
	_counts_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_counts_label)
	box.add_child(EditorKit.hint("CLICK A ROAD: PLACE · {ed_mod_shift} + CLICK: A PAD IN THAT LANE · DRAG A MARKER: SLIDE IT · {ed_delete} DELETE"))


func set_mode(m: String) -> void:
	if not (m in MODES):
		return
	mode = m
	if editor != null and editor.ui != null:
		editor.ui.refresh_tool()


## "ROWS 3 / 40 · CRATES 0 / 64 · PADS 2 / 64 · BARRELS 1 / 32 · ZONES 1 / 16"
func counts_text() -> String:
	var parts := []
	for pair in [["ROWS", "items"], ["CRATES", "crates"], ["PADS", "pads"], ["BARRELS", "barrels"], ["ZONES", "zones"]]:
		parts.append("%s %d / %d" % [pair[0], list_of(pair[1]).size(), int(CAP[pair[1]])])
	return " · ".join(parts)


func inspect(uids: PackedInt32Array, box: VBoxContainer) -> bool:
	if editor == null or editor.doc == null or uids.is_empty():
		return false
	var k := editor.kind_of(uids[0])
	if not owns(k):
		return false
	var sec: String = SECTION[k]
	var same := PackedInt32Array()
	for u in uids:
		if editor.kind_of(u) == k:
			same.append(u)
	var uid := same[0]
	var it := item_of(sec, uid)
	if it.is_empty():
		return false
	var noun: String = NOUN[k]
	var kind_icon: String = {"item_row": "crate_row", "crate": "crate", "pad": "boost", "barrels": "barrels", "zone": "gravity"}.get(k, "")
	box.add_child(EditorKit.section_icon(noun if same.size() == 1 else "%d × %s" % [same.size(), noun], kind_icon))
	match k:
		"item_row":
			var count := int(it.get("count", 0))
			box.add_child(EditorKit.row("COUNT", EditorKit.toggle("AUTO", count <= 0, func(on: bool) -> void:
				editor.commit("CRATE COUNT", _each(sec, same, "count", 0 if on else _auto_count(uid))))))
			if count > 0:
				box.add_child(EditorKit.row("CRATES", EditorKit.number(count, 1, 5, 1, func(v: float) -> void:
					editor.commit("CRATE COUNT", _each(sec, same, "count", int(v)), "insp_count_%d" % uid), "%d")))
			else:
				box.add_child(EditorKit.hint("AUTO: %d CRATES" % _auto_count(uid)))
			box.add_child(EditorKit.row("INSET", EditorKit.number(float(it.get("inset", 2.5)), 1.5, 5.0, 0.1, func(v: float) -> void:
				editor.commit("CRATE INSET", _each(sec, same, "inset", snappedf(v, 0.01)), "insp_inset_%d" % uid), "%.1f", " m")))
		"pad":
			var lat = it.get("lat")
			var on_line := not (lat is float or lat is int)
			box.add_child(EditorKit.row("LANE", EditorKit.toggle("RACING LINE", on_line, func(on: bool) -> void:
				editor.commit("PAD LANE", _each(sec, same, "lat", null if on else 0.0)))))
			if not on_line:
				box.add_child(EditorKit.row("LANE OFFSET", EditorKit.number(float(lat), -20.0, 20.0, 0.5, func(v: float) -> void:
					editor.commit("PAD LANE", _each(sec, same, "lat", snappedf(v, 0.01)), "insp_lat_%d" % uid), "%.1f", " m")))
			box.add_child(EditorKit.row("TURN", EditorKit.number(float(it.get("turn", 0.0)), -30.0, 30.0, 1.0, func(v: float) -> void:
				editor.commit("PAD TURN", _each(sec, same, "turn", snappedf(v, 0.1)), "insp_turn_%d" % uid), "%d", "°")))
		"zone":
			box.add_child(EditorKit.row("SCALE", EditorKit.number(float(it.get("scale", 0.4)), 0.2, 0.9, 0.05, func(v: float) -> void:
				editor.commit("ZONE GRAVITY", _each(sec, same, "scale", snappedf(v, 0.01)), "insp_scale_%d" % uid), "%.2f", " g")))
			box.add_child(EditorKit.row("EASE", EditorKit.number(float(it.get("ease", 15.0)), 5.0, 40.0, 1.0, func(v: float) -> void:
				editor.commit("ZONE EASE", _each(sec, same, "ease", snappedf(v, 0.1)), "insp_ease_%d" % uid), "%d", " m")))
			var r := full_road(int(it.get("road", -1)))
			if r != null and it.get("a") is Dictionary and it.get("b") is Dictionary:
				var zl := absf(delta_s(r, r.anchor_s(it.a), r.anchor_s(it.b))) if r.closed else absf(r.anchor_s(it.b) - r.anchor_s(it.a))
				box.add_child(EditorKit.hint("%d m LONG · DRAG ITS END BARS ALONG THE ROAD" % roundi(zl)))
		"crate":
			box.add_child(EditorKit.row("POSITION", EditorKit.vec3(_v3(it.get("pos")), func(v: Vector3) -> void:
				editor.commit("MOVE CRATE", [op_field(sec, uid, "pos", _arr(v))], "insp_pos_%d" % uid))))
		"barrels":
			box.add_child(EditorKit.hint("Three explosive drums across the road's middle third."))
	var warn := warning_map()
	for u in same:
		for why in warn.get(u, []):
			var l := EditorKit.hint(str(why).to_upper())
			l.add_theme_color_override("default_color", EditorKit.ERROR_COLOR)
			box.add_child(l)
	return true


func _auto_count(uid: int) -> int:
	if editor != null and editor.build != null:
		var rows = editor.build.stats.get("bake", {}).get("rows", {})
		if rows is Dictionary and rows.has(str(uid)):
			return int(rows[str(uid)])
	return 3


func _each(sec: String, uids: PackedInt32Array, field: String, value: Variant) -> Array:
	var out := []
	for u in uids:
		if not item_of(sec, u).is_empty():
			out.append(op_field(sec, u, field, value))
	return out
