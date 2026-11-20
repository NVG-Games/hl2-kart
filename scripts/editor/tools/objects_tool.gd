class_name ObjectsTool
extends EditorTool
## 1.6 OBJECTS: Half-Life 2 / HL1 props, lights and effects from the catalog drawer (CatalogPanel,
## at the foot of the free area while the tool is active).
## - STAMP: a ghost of the picked model follows the cursor; LMB places (several clicks, several
##   props); Shift + wheel turns it 15 deg (or the angle snap), Ctrl + wheel scales it 5 %, RANDOM
##   YAW, RANDOM SCALE min / max, ALIGN TO SURFACE (at most 20 deg), SINK; a right click or Esc
##   ends stamping. LIGHTS & FX entries stamp lights, fires, embers and Breencast screens.
## - SCATTER (B toggles): LMB paints the picked models (1-8) by DENSITY, MIN SPACING, SCALE MIN /
##   MAX, RANDOM YAW, ALIGN TO SLOPE and KEEP OFF ROADS, seeded at edit time (the SEED advances per
##   stroke, so the same stroke on the same track gives the same props); Ctrl + LMB erases the
##   picked models in the brush; a dab past the hard cap of 3000 places up to it and toasts.
## - ALONG ROAD: press on a road edge and drag along it; on release a prop every EVERY m at SETBACK
##   m past the edge treatment, FACING THE ROAD or ALONG IT, JITTER along and in yaw, models in
##   pick order (or RANDOM, seeded), on the ground below, sharing one `group` uid (a double click
##   on one selects the row). One undo step.
## The prop inspector has the physics and tag rules (PHYSICS only for PropCatalog.physics_ok
## models, COLLISION NORMAL / NONE / FAR SCENERY, FLOATS ON THE SEA). P17.

const MODES := ["stamp", "scatter", "along"]
const MODE_NAMES := ["STAMP", "SCATTER", "ALONG ROAD"]
## The modes' icons and tips (EditorKit.icon names; {ed_*} written as keys).
const MODE_ICONS := ["stamp", "scatter", "along_road"]
const MODE_TIPS := ["Click to place the picked model, one at a time.", "Drag to paint many at once ({ed_scatter}).",
	"Press on a road's edge and drag along it: a row of them."]
const SECTION := {"prop": "props", "light": "lights", "fire": "fires", "screen": "screens"}
const NOUN := {"prop": "OBJECT", "light": "LIGHT", "fire": "FIRE", "screen": "SCREEN"}
const CAP := {"props": 3000, "lights": 128, "fires": 32, "screens": 16}
const HARD_CAP := 3000
const BUDGET := 1500
const PHYS_CAP := 300
const PICK_MAX := 8
const ALIGN_MAX := 20.0
const LIGHT_UP := 4.0
const BRUSH_MIN := 2.0
const BRUSH_MAX := 200.0
const ROAD_CELL := 16.0
const TAGS := ["", "deco", "far"]
const TAG_NAMES := ["NORMAL", "NONE", "FAR SCENERY"]
const CAP_TOAST := "Prop limit reached (3000)"
const GHOST_COLOR := Color8(255, 155, 0)
const BRUSH_COLOR := Color(0.45, 0.85, 1.0)
const ERASE_COLOR := Color(1.0, 0.35, 0.3)
const LIGHT_COLOR := Color(1.0, 0.92, 0.55)
const FIRE_COLOR := Color(1.0, 0.5, 0.15)
const SCREEN_COLOR := Color(0.4, 0.85, 1.0)
const PROP_COLOR := Color(0.8, 0.8, 0.8)

var mode := "stamp"
## The picked models (catalog order of picking): STAMP uses the first, SCATTER / ALONG ROAD all.
var picked := PackedStringArray()
## A LIGHTS & FX entry being stamped ("" none; it wins over the picked models).
var fx := ""
# STAMP
var yaw := 0.0
var scale := 1.0
var random_yaw := false
var random_scale := false
var scale_min := 0.8
var scale_max := 1.2
var align := false
var sink := 0.0
# SCATTER
var density := 1.0              # props per 100 m2
var spacing := 4.0              # MIN SPACING (m)
var sc_min := 0.8
var sc_max := 1.2
var scatter_yaw := true
var slope := false              # ALIGN TO SLOPE
var keep_off := 3.0             # KEEP OFF ROADS (m past an edge)
var scatter_seed := 1           # SEED: advances per stroke
var radius := 15.0              # the brush
# ALONG ROAD
var every := 20.0
var setback := 3.0
var facing := "road"            # "road" | "along"
var jitter := 0.0               # metres along
var jitter_yaw := 0.0           # degrees
var random_order := false
## The drawer (made on the first activation, in editor.ui.catalog_host).
var catalog: CatalogPanel
## Props whose model the next catalog pick replaces (REPLACE...).
var replacing := PackedInt32Array()
## The last placement's uids (tests, the status line).
var last_placed := PackedInt32Array()

var _next := {"yaw": 0.0, "scale": 1.0}   # the next stamp's random yaw / scale
var _rng := RandomNumberGenerator.new()
var _ghost: Node3D
var _ghost_key := ""
var _stroke := {}
var _along := {}
var _drag := {}
var _count_label: Label
var _rmb_down := -1.0
var _was_rmb := false
var _h: ItemsTool               # the road-spot helpers (a private instance, never in editor.tools)


func _init(ed: TrackEditor) -> void:
	super(ed)
	id = "objects"
	title = "OBJECTS"
	purpose = "Props, lights and effects: stamp, scatter or line a road with them"
	_h = ItemsTool.new(ed)
	_rng.seed = 1
	_roll()


func kinds() -> PackedStringArray:
	return PackedStringArray(["prop", "light", "fire", "screen"])


func activate() -> void:
	show_catalog(true)


func deactivate() -> void:
	_cancel()
	show_catalog(false)
	_free_ghost()


## Opens (or hides) the catalog drawer in editor.ui.catalog_host.
func show_catalog(on: bool) -> void:
	if editor == null or editor.ui == null or editor.ui.catalog_host == null:
		return
	if on and (catalog == null or not is_instance_valid(catalog)):
		catalog = CatalogPanel.new()
		catalog.name = "Catalog"
		editor.ui.catalog_host.add_child(catalog)
		catalog.setup(editor, self)
	if catalog != null and is_instance_valid(catalog):
		catalog.visible = on
		if on:
			catalog.mark(picked, fx)


# ---------------------------------------------------------------- picking from the catalog

## A model cell pressed: picks it (add: Ctrl, a 1-8 set for SCATTER / ALONG ROAD), or replaces the
## model of the props REPLACE... named.
func pick_model(key: String, add := false) -> void:
	if not replacing.is_empty():
		replace_model(replacing, key)
		replacing = PackedInt32Array()
		return
	fx = ""
	if add:
		var at := picked.find(key)
		if at >= 0:
			picked.remove_at(at)
		elif picked.size() < PICK_MAX:
			picked.append(key)
		else:
			editor.status("Pick at most %d models." % PICK_MAX)
	else:
		picked = PackedStringArray([key])
	_roll()
	_mark()
	editor.redraw()
	if editor.ui != null:
		editor.ui.refresh_status()


## A LIGHTS & FX entry pressed: stamping it (STAMP mode).
func pick_fx(entry: String) -> void:
	if PropCatalog.fx_entry(entry).is_empty():
		return
	if not PropCatalog.fx_enabled(entry, editor.doc):
		editor.status("The Breencast screen needs the COMBINE start arch (WORLD > START & SCENERY).")
		return
	fx = entry
	if mode != "stamp":
		set_mode("stamp")
	_mark()
	editor.redraw()


## Right click / Esc: no more stamping.
func end_stamping() -> void:
	picked = PackedStringArray()
	fx = ""
	_free_ghost()
	_mark()
	editor.redraw()


func stamping() -> bool:
	return mode == "stamp" and (fx != "" or not picked.is_empty())


## The drawer's RECENT tab follows what was just placed.
func _recent_changed() -> void:
	if catalog != null and is_instance_valid(catalog) and catalog.tab == PropCatalog.TAB_RECENT:
		catalog.refresh(false)


func _mark() -> void:
	if catalog != null and is_instance_valid(catalog):
		catalog.mark(picked, fx)


func set_mode(m: String) -> void:
	if not (m in MODES):
		return
	_cancel()
	mode = m
	if mode != "stamp":
		_free_ghost()
	if editor != null:
		editor.redraw()
		if editor.ui != null:
			editor.ui.refresh_tool()


## The next stamp's random yaw and scale (rolled after each placement).
func _roll() -> void:
	_next = {"yaw": snappedf(_rng.randf_range(0.0, 360.0), 0.1),
		"scale": snappedf(_rng.randf_range(minf(scale_min, scale_max), maxf(scale_min, scale_max)), 0.05)}


# ---------------------------------------------------------------- STAMP

## {pos, yaw, pitch, roll, scale} of a stamp on a hit (the ghost shows the same).
func stamp_xf(hit: EditorHit) -> Dictionary:
	var y := float(_next.yaw) if random_yaw else yaw
	var sc := float(_next.scale) if random_scale else scale
	sc = clampf(snappedf(sc, 0.05), 0.25, 4.0)
	var tilt := Vector2.ZERO
	if align:
		tilt = tilt_of(hit.normal, y, ALIGN_MAX)
	var p := hit.pos - Vector3.UP * sink
	return {"pos": p, "yaw": wrap_deg(y), "pitch": tilt.x, "roll": tilt.y, "scale": sc}


## Pitch and roll (deg) that tilt a prop of this yaw onto the normal, each at most max_deg.
static func tilt_of(n: Vector3, yaw_deg: float, max_deg: float) -> Vector2:
	if n.length_squared() < 1e-8:
		return Vector2.ZERO
	var l := n.normalized().rotated(Vector3.UP, -deg_to_rad(yaw_deg))
	var roll := rad_to_deg(asin(clampf(-l.x, -1.0, 1.0)))
	var pitch := rad_to_deg(atan2(l.z, l.y))
	return Vector2(snappedf(clampf(pitch, -max_deg, max_deg), 0.1), snappedf(clampf(roll, -max_deg, max_deg), 0.1))


static func wrap_deg(d: float) -> float:
	return snappedf(wrapf(d, -180.0, 180.0), 0.1)


## A prop dict (2.3); uid < 0: a new one from the document (0: a preview without one).
func prop_item(key: String, p: Vector3, y: float, sc: float, pitch := 0.0, roll := 0.0, group := 0, uid := -1) -> Dictionary:
	var it := {"uid": editor.doc.new_uid() if uid < 0 else uid, "model": key, "pos": ItemsTool._arr(p), "yaw": wrap_deg(y),
		"pitch": snappedf(pitch, 0.1), "roll": snappedf(roll, 0.1), "scale": clampf(snappedf(sc, 0.05), 0.25, 4.0),
		"physics": false, "tag": ""}
	if group > 0:
		it["group"] = group
	return it


func prop_count() -> int:
	return list_of("props").size()


## Places the picked model (or the LIGHTS & FX entry) at a hit. Returns the new uid (0 none).
func stamp(hit: EditorHit) -> int:
	if editor == null or editor.doc == null or hit == null or not hit.hit:
		return 0
	if fx != "":
		return place_fx(fx, hit)
	if picked.is_empty():
		return 0
	if prop_count() >= HARD_CAP:
		editor.toast(CAP_TOAST)
		return 0
	var key := picked[0]
	var xf := stamp_xf(hit)
	var it := prop_item(key, xf.pos, xf.yaw, xf.scale, xf.pitch, xf.roll)
	editor.commit("ADD OBJECT", [ItemsTool.op_add("props", it)])
	last_placed = PackedInt32Array([int(it.uid)])
	PropCatalog.note_placed(key)
	_recent_changed()
	_roll()
	succeeded()
	return int(it.uid)


## Stamps a LIGHTS & FX entry at a hit: a light 4 m over it, a fire or embers on it, a screen
## standing on it facing the camera.
func place_fx(entry: String, hit: EditorHit) -> int:
	if not PropCatalog.fx_enabled(entry, editor.doc):
		editor.status("The Breencast screen needs the COMBINE start arch (WORLD > START & SCENERY).")
		return 0
	var e := PropCatalog.fx_entry(entry)
	var sec := str(e.get("section", ""))
	if list_of(sec).size() >= int(CAP.get(sec, 16)):
		editor.toast("Limit reached (%d %s)" % [int(CAP.get(sec, 16)), sec])
		return 0
	var p := hit.pos
	match sec:
		"lights":
			p += Vector3.UP * LIGHT_UP
		"screens":
			p += Vector3.UP * (float(e.item.get("h", 4.5)) * 0.5 + 0.5)
	var made := PropCatalog.fx_item(entry, p, editor.doc)
	if made.is_empty():
		return 0
	var item: Dictionary = made[1]
	if sec == "screens" and editor.camera != null:
		var to := editor.camera.global_position - p
		item["yaw"] = wrap_deg(rad_to_deg(atan2(to.x, to.z)))
	editor.commit("ADD %s" % str(e.get("name", "LIGHT")), [ItemsTool.op_add(sec, item)])
	last_placed = PackedInt32Array([int(item.uid)])
	succeeded()
	return int(item.uid)


## REPLACE...: the props' model, one undo step.
func replace_model(uids: PackedInt32Array, key: String) -> void:
	var ops := []
	for u in uids:
		if not item_of("props", u).is_empty():
			ops.append(ItemsTool.op_field("props", u, "model", key))
			if bool(item_of("props", u).get("physics", false)) and not PropCatalog.physics_ok(key):
				ops.append(ItemsTool.op_field("props", u, "physics", false))
	if ops.is_empty():
		return
	editor.commit("REPLACE MODEL", ops)
	PropCatalog.note_placed(key)
	_recent_changed()


# ---------------------------------------------------------------- SCATTER

## Starts a stroke (erase: Ctrl): one undo step until stroke_end.
func stroke_begin(erase: bool) -> void:
	if editor == null or editor.doc == null:
		return
	_stroke = {"erase": erase, "seed": scatter_seed, "dab": 0, "last": null, "placed": 0, "capped": false,
		"group": 0 if erase else editor.doc.new_uid()}
	editor.history.begin_gesture("ERASE OBJECTS" if erase else "SCATTER")
	if erase:
		return
	var cell := maxf(spacing, 1.0)
	var grid := {}
	var pts := PackedVector3Array()
	for p in list_of("props"):
		if p is Dictionary:
			var v := ItemsTool._v3(p.get("pos"))
			pts.append(v)
			_grid_add(grid, cell, v)
	_stroke["cell"] = cell
	_stroke["grid"] = grid
	_stroke["pts"] = pts
	_stroke["roads"] = _road_grid()


## The stroke reaches p: dabs every 25 % of the radius along the way.
func stroke_to(p: Vector3) -> void:
	if _stroke.is_empty():
		return
	if _stroke.last == null:
		_stroke.last = p
		dab(p)
		return
	var step := maxf(radius * 0.25, 0.5)
	var last: Vector3 = _stroke.last
	var d := Vector2(p.x - last.x, p.z - last.z).length()
	var guard := 0
	while d >= step and guard < 400:
		var f := step / d
		last = last.lerp(p, f)
		dab(last)
		d = Vector2(p.x - last.x, p.z - last.z).length()
		guard += 1
	_stroke.last = last


func stroke_end() -> void:
	if _stroke.is_empty():
		return
	var placed := int(_stroke.placed)
	var erase := bool(_stroke.erase)
	editor.history.end_gesture()
	_stroke = {}
	if not erase and placed > 0:
		scatter_seed += 1
		for k in picked:
			PropCatalog.note_placed(k)
		_recent_changed()
		succeeded()
	_update_count()


## One dab at c: paints (seeded by the stroke's seed and the dab's index) or erases.
func dab(c: Vector3) -> int:
	if _stroke.is_empty():
		return 0
	if bool(_stroke.erase):
		return _erase_at(c)
	if picked.is_empty():
		editor.status("Pick the models to scatter in the catalog (Ctrl + click picks several).")
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(_stroke.seed), int(_stroke.dab)])
	_stroke.dab = int(_stroke.dab) + 1
	var r2 := radius * radius
	var target := int(round(density * PI * r2 / 100.0))
	var pts: PackedVector3Array = _stroke.pts
	var have := 0
	for q in pts:
		if Vector2(q.x - c.x, q.z - c.z).length_squared() <= r2:
			have += 1
	var need := target - have
	if need <= 0:
		return 0
	var half := editor.doc.world_size() * 0.5
	var cell := float(_stroke.cell)
	var grid: Dictionary = _stroke.grid
	var count := prop_count()
	var ops := []
	var made := 0
	var tries := mini(need * 6, 600)
	for k in tries:
		if made >= need:
			break
		var ang := rng.randf() * TAU
		var rr := radius * sqrt(rng.randf())
		var model := picked[rng.randi_range(0, picked.size() - 1)]
		var y := rng.randf_range(0.0, 360.0) if scatter_yaw else 0.0
		var sc := snappedf(rng.randf_range(minf(sc_min, sc_max), maxf(sc_min, sc_max)), 0.05)
		var q := Vector3(c.x + cos(ang) * rr, c.y, c.z + sin(ang) * rr)
		if absf(q.x) > half or absf(q.z) > half:
			continue
		if _near_road(q, keep_off):
			continue
		var g := _ground(q, c.y)
		if is_nan(g.x):
			continue
		if _crowded(grid, cell, g, spacing):
			continue
		if count + made >= HARD_CAP:
			_stroke.capped = true
			break
		var tilt := Vector2.ZERO
		if slope:
			tilt = tilt_of(_ground_normal(g), y, ALIGN_MAX)
		var it := prop_item(model, g, y, sc, tilt.x, tilt.y, int(_stroke.group))
		ops.append(ItemsTool.op_add("props", it))
		_grid_add(grid, cell, g)
		pts.append(g)
		made += 1
	_stroke.pts = pts
	if made > 0:
		editor.commit("SCATTER", ops)
		_stroke.placed = int(_stroke.placed) + made
	if bool(_stroke.capped) and not _stroke.has("toasted"):
		_stroke["toasted"] = true
		editor.toast(CAP_TOAST)
	_update_count()
	return made


## Ctrl + LMB: the props of the picked models (every model when none is picked) inside the brush.
func _erase_at(c: Vector3) -> int:
	var ops := []
	var r2 := radius * radius
	for p in list_of("props"):
		if not (p is Dictionary):
			continue
		if not picked.is_empty() and not (str(p.get("model", "")) in picked):
			continue
		var v := ItemsTool._v3(p.get("pos"))
		if Vector2(v.x - c.x, v.z - c.z).length_squared() <= r2:
			ops.append(ItemsTool.op_del("props", int(p.uid)))
	if not ops.is_empty():
		editor.commit("ERASE OBJECTS", ops)
		_stroke.placed = int(_stroke.placed) + ops.size()
	_update_count()
	return ops.size()


static func _grid_add(grid: Dictionary, cell: float, p: Vector3) -> void:
	var k := Vector2i(floori(p.x / cell), floori(p.z / cell))
	if grid.has(k):
		(grid[k] as Array).append(p)
	else:
		grid[k] = [p]


static func _crowded(grid: Dictionary, cell: float, p: Vector3, d: float) -> bool:
	var cx := floori(p.x / cell)
	var cz := floori(p.z / cell)
	var reach := int(ceil(d / cell))
	var d2 := d * d
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var l = grid.get(Vector2i(cx + dx, cz + dz))
			if l == null:
				continue
			for q in l:
				if Vector2((q as Vector3).x - p.x, (q as Vector3).z - p.z).length_squared() < d2:
					return true
	return false


## Every road sample by 16 m cell: [x, z, half width + side treatment].
func _road_grid() -> Dictionary:
	var g := {}
	if editor.build == null:
		return g
	for r in editor.build.roads:
		if r == null or r.partial or r.n <= 0:
			continue
		for i in r.n:
			var half := r.width[i] * 0.5 + maxf(r.treatment(i, -1), r.treatment(i, 1))
			var k := Vector2i(floori(r.pos[i].x / ROAD_CELL), floori(r.pos[i].z / ROAD_CELL))
			var e := Vector3(r.pos[i].x, half, r.pos[i].z)
			if g.has(k):
				(g[k] as Array).append(e)
			else:
				g[k] = [e]
	return g


## Whether p lies on a road or within `off` metres past its edge (the stroke's road grid).
func _near_road(p: Vector3, off: float) -> bool:
	var g: Dictionary = _stroke.get("roads", {})
	if g.is_empty():
		return false
	var cx := floori(p.x / ROAD_CELL)
	var cz := floori(p.z / ROAD_CELL)
	var reach := int(ceil((off + 30.0) / ROAD_CELL))
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var l = g.get(Vector2i(cx + dx, cz + dz))
			if l == null:
				continue
			for e in l:
				var v: Vector3 = e
				if Vector2(v.x - p.x, v.z - p.z).length() - v.y < off:
					return true
	return false


## The ground under q (the terrain's carved heights; no terrain: the plane at fallback_y).
func _ground(q: Vector3, fallback_y: float) -> Vector3:
	var t := editor.terrain()
	if t != null:
		var h := t.height_at(q.x, q.z)
		if is_nan(h):
			return Vector3(NAN, NAN, NAN)
		return Vector3(q.x, h, q.z)
	if editor.doc.has_terrain():
		return Vector3(NAN, NAN, NAN)
	return Vector3(q.x, fallback_y, q.z)


func _ground_normal(p: Vector3) -> Vector3:
	var t := editor.terrain()
	return t.normal_at(p.x, p.z) if t != null else Vector3.UP


# ---------------------------------------------------------------- ALONG ROAD

## The props of an ALONG ROAD row from s0 to s1 on road key, side -1 / 1 (not yet committed;
## preview: no uids taken from the document).
func along_items(key: int, s0: float, s1: float, side: int, preview := false) -> Array:
	var out := []
	var r := _h.full_road(key)
	if r == null or picked.is_empty():
		return out
	var d := ItemsTool.delta_s(r, s0, s1) if r.closed else s1 - s0
	var dir := 1.0 if d >= 0.0 else -1.0
	var n := floori(absf(d) / maxf(every, 1.0) + 1e-6) + 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([scatter_seed, "along", key])
	var group := 0 if preview else editor.doc.new_uid()
	var room := HARD_CAP - prop_count()
	for k in n:
		if out.size() >= room:
			break
		var s := s0 + dir * k * every
		if jitter > 0.0:
			s += rng.randf_range(-jitter, jitter)
		s = ItemsTool.wrap_s(r, s)
		var i := r.idx(s)
		var lat := side * (r.width[i] * 0.5 + r.treatment(i, side) + setback)
		var p := r.pos[i] + r.flat_right[i] * lat
		var t := editor.terrain()
		if t != null:
			var h := t.height_at(p.x, p.z)
			if not is_nan(h):
				p.y = h
		var y := 0.0
		if facing == "road":
			var to := r.pos[i] - p
			y = rad_to_deg(atan2(to.x, to.z))
		else:
			var f := r.fwd[i] * dir
			y = rad_to_deg(atan2(f.x, f.z))
		if jitter_yaw > 0.0:
			y += rng.randf_range(-jitter_yaw, jitter_yaw)
		var model := picked[rng.randi_range(0, picked.size() - 1)] if random_order else picked[k % picked.size()]
		out.append(prop_item(model, p, y, 1.0, 0.0, 0.0, group, 0 if preview else -1))
	return out


## Writes an ALONG ROAD row (one undo step). Returns the new uids.
func along(key: int, s0: float, s1: float, side: int) -> PackedInt32Array:
	var made := PackedInt32Array()
	if picked.is_empty():
		editor.status("Pick the models to line the road with in the catalog.")
		return made
	if prop_count() >= HARD_CAP:
		editor.toast(CAP_TOAST)
		return made
	var items := along_items(key, s0, s1, side)
	if items.is_empty():
		return made
	var ops := []
	for it in items:
		ops.append(ItemsTool.op_add("props", it))
		made.append(int(it.uid))
	editor.commit("ALONG ROAD", ops)
	if prop_count() >= HARD_CAP:
		editor.toast(CAP_TOAST)
	scatter_seed += 1
	for k in picked:
		PropCatalog.note_placed(k)
	_recent_changed()
	last_placed = made
	succeeded()
	_update_count()
	return made


# ---------------------------------------------------------------- mouse

func click(hit: EditorHit, mods: int) -> bool:
	if editor == null or editor.doc == null or hit == null:
		return false
	if hit.what == "gizmo":
		return false
	match mode:
		"stamp":
			if not stamping() or not hit.hit or hit.what == "marker":
				return false
			stamp(hit)
			return true
		"scatter":
			if not hit.hit or hit.what == "marker":
				return false
			stroke_begin(has_mod(mods, MOD_CTRL))
			stroke_to(hit.pos)
			stroke_end()
			return true
		"along":
			if hit.what == "marker":
				return false
			editor.status("Press on a road's edge and drag along the road.")
			return true
	return false


func double_click(hit: EditorHit, _mods: int) -> bool:
	if editor == null or editor.doc == null or hit == null:
		return false
	if (hit.what == "prop" or (hit.what == "marker" and hit.kind == "prop")) and hit.uid > 0:
		var g := int(item_of("props", hit.uid).get("group", 0))
		if g > 0:
			select_group(g)
			return true
	return false


## Selects every prop of a group (a scatter stroke or an ALONG ROAD row).
func select_group(group: int) -> void:
	var out := PackedInt32Array()
	for p in list_of("props"):
		if p is Dictionary and int(p.get("group", 0)) == group:
			out.append(int(p.uid))
	editor.select(out)
	editor.status("%d objects in this group" % out.size())


func drag_begin(hit: EditorHit, mods: int) -> bool:
	if editor == null or editor.doc == null or hit == null:
		return false
	if mode == "scatter" and hit.hit:
		stroke_begin(has_mod(mods, MOD_CTRL))
		stroke_to(hit.pos)
		return true
	if mode == "along":
		var sp := _h.road_spot(hit, 40.0)
		if sp.is_empty():
			editor.status("Press on a road's edge and drag along the road.")
			return false
		_along = {"key": int(sp.key), "s0": float(sp.s), "s1": float(sp.s), "side": 1 if float(sp.lat) >= 0.0 else -1}
		return true
	# STAMP: an object's marker or model dragged moves it over the ground
	if (hit.what == "marker" and owns(hit.kind)) or (hit.what == "prop" and owns(editor.kind_of(hit.uid))):
		if hit.uid <= 0:
			return false
		var k := editor.kind_of(hit.uid)
		var it := item_of(str(SECTION.get(k, "")), hit.uid)
		if it.is_empty():
			return false
		var p0 := ItemsTool._v3(it.get("pos"))
		var g := _ground(p0, p0.y)
		var nm := "MOVE %s" % str(NOUN.get(k, "OBJECT"))
		editor.history.begin_gesture(nm)
		_drag = {"uid": hit.uid, "kind": k, "name": nm, "off": p0.y - g.y if not is_nan(g.y) else 0.0}
		if not editor.selection.has(hit.uid):
			editor.select(PackedInt32Array([hit.uid]))
		return true
	return false


func drag_move(hit: EditorHit, _mods: int) -> void:
	if not _stroke.is_empty():
		if hit != null and hit.hit:
			stroke_to(hit.pos)
	elif not _along.is_empty():
		var r := _h.full_road(int(_along.key))
		if r != null and hit != null and hit.hit:
			_along.s1 = ItemsTool.s_near(r, hit.pos)
	elif not _drag.is_empty():
		_move_to(hit)
	editor.redraw()


func drag_end(hit: EditorHit, _mods: int) -> void:
	if not _stroke.is_empty():
		if hit != null and hit.hit:
			stroke_to(hit.pos)
		stroke_end()
	elif not _along.is_empty():
		var r := _h.full_road(int(_along.key))
		if r != null and hit != null and hit.hit:
			_along.s1 = ItemsTool.s_near(r, hit.pos)
		var a := _along
		_along = {}
		along(int(a.key), float(a.s0), float(a.s1), int(a.side))
	elif not _drag.is_empty():
		_move_to(hit)
		editor.history.end_gesture()
		_drag = {}
	editor.redraw()


func _move_to(hit: EditorHit) -> void:
	if hit == null or not hit.hit or _drag.is_empty():
		return
	var sec := str(SECTION.get(str(_drag.kind), "props"))
	editor.commit(str(_drag.name), [ItemsTool.op_field(sec, int(_drag.uid), "pos", ItemsTool._arr(hit.pos + Vector3.UP * float(_drag.off)))],
		"objects_drag")


## Esc while the button holds a drag: a SCATTER / ERASE stroke or a move taken back, ALONG ROAD
## dropped.
func cancel_drag() -> void:
	var live := not _stroke.is_empty() or not _drag.is_empty()
	_stroke = {}
	_along = {}
	_drag = {}
	if live and editor != null and editor.history != null:
		editor.history.cancel_gesture()
	if editor != null:
		editor.redraw()


func _cancel() -> void:
	if not _stroke.is_empty():
		stroke_end()
	_along = {}
	if not _drag.is_empty():
		if editor != null and editor.history != null:
			editor.history.end_gesture()
		_drag = {}


func wheel(hit: EditorHit, mods: int, notches: int) -> bool:
	if not stamping():
		return false
	if has_mod(mods, MOD_SHIFT):
		var step := float(editor.snap.get("angle", 15.0)) if bool(editor.snap.get("angle_on", true)) else 15.0
		yaw = wrap_deg(yaw + step * notches)
		random_yaw = false
		editor.status("YAW %d°" % roundi(yaw))
		editor.redraw()
		return true
	if has_mod(mods, MOD_CTRL):
		scale = clampf(snappedf(scale * pow(1.05, notches), 0.05), 0.25, 4.0)
		random_scale = false
		editor.status("SCALE %.2f" % scale)
		editor.redraw()
		return true
	return false


func key(ev: InputEvent) -> bool:
	if editor == null:
		return false
	if _act(ev, "ed_cancel"):
		if not _along.is_empty() or not _stroke.is_empty() or not _drag.is_empty():
			_cancel()
			return true
		if not replacing.is_empty():
			replacing = PackedInt32Array()
			editor.status("")
			return true
		if stamping():
			end_stamping()
			return true
		return false
	if _act(ev, "ed_scatter"):
		set_mode("scatter" if mode != "scatter" else "stamp")
		return true
	# , and . turn the ghost while stamping, else the selected objects (one merged step)
	var left := _act(ev, "ed_turn_left", true)
	if left or _act(ev, "ed_turn_right", true):
		return turn(1.0 if left else -1.0)
	if mode == "scatter":
		if _act(ev, "ed_brush_smaller", true):
			radius = clampf(snappedf(radius * 0.8, 0.5), BRUSH_MIN, BRUSH_MAX)
			editor.status("BRUSH %d m" % roundi(radius))
			editor.redraw()
			return true
		if _act(ev, "ed_brush_bigger", true):
			radius = clampf(snappedf(radius * 1.25, 0.5), BRUSH_MIN, BRUSH_MAX)
			editor.status("BRUSH %d m" % roundi(radius))
			editor.redraw()
			return true
	return false


func _act(ev: InputEvent, action: String, echo := false) -> bool:
	return InputMap.has_action(action) and ev.is_action_pressed(action, echo, true)


## , / . (dir 1 left, -1 right): the stamp's ghost turns by the angle step, else the selected props
## and screens do (ROTATE OBJECT, presses in a row merge). false when there was nothing to turn.
func turn(dir: float) -> bool:
	var step := float(editor.snap.get("angle", 15.0)) if bool(editor.snap.get("angle_on", true)) else 15.0
	if step <= 0.0:
		step = 15.0
	if stamping():
		yaw = wrap_deg(yaw + step * dir)
		random_yaw = false
		editor.status("YAW %d°" % roundi(yaw))
		editor.redraw()
		return true
	var ops := []
	for u in editor.selection.uids:
		var f := editor.doc.find(u)
		if f.is_empty() or not (str(f.section) in ["props", "screens"]) or not (f.item is Dictionary):
			continue
		ops.append(LevelDoc.op_set(editor.doc.path_of(u) + ["yaw"], wrap_deg(float((f.item as Dictionary).get("yaw", 0.0)) + step * dir)))
	if ops.is_empty():
		return false
	editor.commit("ROTATE OBJECT", ops, "objects_turn")
	return true


## The ghost follows the hover; a short right click (a tap, not a look) ends stamping.
func process(_delta: float) -> void:
	if editor == null:
		return
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var now := Time.get_ticks_msec() / 1000.0
	if rmb and not _was_rmb:
		_rmb_down = now
	elif not rmb and _was_rmb and _rmb_down >= 0.0 and now - _rmb_down < 0.25 and stamping():
		end_stamping()
	_was_rmb = rmb
	_update_ghost()


func _update_ghost() -> void:
	if editor.headless or mode != "stamp" or fx != "" or picked.is_empty():
		_free_ghost()
		return
	var h := editor.hover
	var key_now := picked[0]
	if _ghost_key != key_now:
		_free_ghost()
		if not Game.models.has(key_now):
			return
		_ghost = Game.spawn_model(key_now)
		_ghost.name = "StampGhost"
		_ghost_key = key_now
		editor.add_child(_ghost)
	if _ghost == null:
		return
	if h == null or not h.hit or h.what == "marker" or h.what == "gizmo":
		_ghost.visible = false
		return
	var xf := stamp_xf(h)
	_ghost.visible = true
	_ghost.global_position = xf.pos
	_ghost.rotation = Vector3(deg_to_rad(float(xf.pitch)), deg_to_rad(float(xf.yaw)), deg_to_rad(float(xf.roll)))
	_ghost.scale = Vector3.ONE * float(xf.scale)


func _free_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_ghost_key = ""


# ---------------------------------------------------------------- hover, status

func hints(hit: EditorHit) -> Array:
	if hit != null and hit.what == "marker":
		if hit.kind == "issue":
			return [["CLICK SHOW THE PROBLEM"]]
		if owns(hit.kind):
			return [["CLICK SELECT"], ["DRAG MOVE"], ["{ed_delete} DELETE"]]
		return [["CLICK SELECT"]]
	match mode:
		"stamp":
			if stamping():
				var out := [["CLICK PLACE"], ["{ed_mod_shift} WHEEL TURN"], ["{ed_cancel} STOP"]]
				if fx == "":
					out.insert(2, ["{ed_mod_ctrl} WHEEL SCALE"])
				return out
			if hit != null and hit.what == "prop":
				return [["CLICK SELECT"], ["DOUBLE CLICK SELECT ITS GROUP"], ["DRAG MOVE"]]
			return [["PICK AN OBJECT IN THE CATALOG"], ["{ed_scatter} SCATTER"]]
		"scatter":
			return [["DRAG PAINT"], ["{ed_mod_ctrl} DRAG ERASE"], ["{ed_brush_smaller} {ed_brush_bigger} SIZE"], ["{ed_scatter} STAMP"]]
		"along":
			return [["DRAG ALONG A ROAD EDGE: A ROW OF OBJECTS"]]
	return []


func status_step() -> String:
	if not replacing.is_empty():
		return "Pick the new model in the catalog ({ed_cancel} keeps the old one)"
	match mode:
		"stamp":
			if fx != "":
				return "Click to place the %s; {ed_cancel} stops" % str(PropCatalog.fx_entry(fx).get("name", "")).to_lower()
			if picked.is_empty():
				return "Pick an object in the catalog below, then click to place it"
			return "Click to place %s; {ed_cancel} or a right click stops" % PropCatalog.display_name(picked[0])
		"scatter":
			return "Drag to scatter %s ({ed_mod_ctrl} + drag erases)" % ("the picked models" if not picked.is_empty() else "(pick models first)")
		"along":
			return "Press on a road's edge and drag along it: one object every %d m" % roundi(every)
	return ""


# ---------------------------------------------------------------- markers and overlay

func markers(m: EditorMarkers) -> void:
	if editor == null or editor.doc == null:
		return
	for l in list_of("lights"):
		if l is Dictionary:
			var c = l.get("color", [1.0, 0.9, 0.75])
			var col := Color(float(c[0]), float(c[1]), float(c[2])) if c is Array and (c as Array).size() >= 3 else LIGHT_COLOR
			m.add("light", int(l.uid), ItemsTool._v3(l.get("pos")), EditorMarkers.Shape.SUN, col.lerp(Color.WHITE, 0.2), 1.6)
	for f in list_of("fires"):
		if f is Dictionary:
			m.add("fire", int(f.uid), ItemsTool._v3(f.get("pos")), EditorMarkers.Shape.RING, FIRE_COLOR, 1.6)
	var combine := PropCatalog.fx_enabled("screen", editor.doc)
	for s in list_of("screens"):
		if s is Dictionary:
			m.add("screen", int(s.uid), ItemsTool._v3(s.get("pos")), EditorMarkers.Shape.SQUARE,
				SCREEN_COLOR if combine else Color(0.5, 0.5, 0.5), 2.0)
	# props are their models (picked by their bodies); a prop whose model this install lacks has no
	# body, so it gets a dot to stay selectable
	for p in list_of("props"):
		if p is Dictionary and not Game.models.has(str(p.get("model", ""))):
			m.add("prop", int(p.uid), ItemsTool._v3(p.get("pos")), EditorMarkers.Shape.DOT, PROP_COLOR, 0.0)


func overlay(d: EditorDraw) -> void:
	if editor == null or editor.doc == null:
		return
	if editor.selection != null and editor.view != null:
		for u in editor.selection.uids:
			if editor.kind_of(u) == "prop":
				var b := editor.view.item_aabb(u)
				if b.has_volume():
					d.box(b, Color(GHOST_COLOR, 0.8))
	var h := editor.hover
	if not _along.is_empty():
		_overlay_along(d)
		return
	if h == null or not h.hit or h.what == "marker":
		return
	match mode:
		"stamp":
			if fx != "":
				d.circle(h.pos + Vector3.UP * 0.1, Vector3.UP, 1.5, GHOST_COLOR)
			elif not picked.is_empty():
				var xf := stamp_xf(h)
				var box := Game.model_aabb(picked[0]) if Game.models.has(picked[0]) else AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
				var sc := float(xf.scale)
				var p: Vector3 = xf.pos
				d.box(AABB(p + box.position * sc, box.size * sc), GHOST_COLOR)
				var dir := Vector3(sin(deg_to_rad(float(xf.yaw))), 0.0, cos(deg_to_rad(float(xf.yaw))))
				d.arrow(p + Vector3.UP * 0.2, dir, maxf(box.size.length() * sc * 0.6, 1.5), GHOST_COLOR)
		"scatter":
			var col := ERASE_COLOR if Input.is_key_pressed(KEY_CTRL) else BRUSH_COLOR
			var t := editor.terrain()
			if t != null:
				d.ground_circle(t, Vector2(h.pos.x, h.pos.z), radius, col)
			else:
				d.circle(h.pos + Vector3.UP * 0.1, Vector3.UP, radius, col)


func _overlay_along(d: EditorDraw) -> void:
	var items := along_items(int(_along.key), float(_along.s0), float(_along.s1), int(_along.side), true)
	var prev := Vector3(NAN, NAN, NAN)
	for it in items:
		var p := ItemsTool._v3(it.pos)
		d.circle(p + Vector3.UP * 0.2, Vector3.UP, 1.0, GHOST_COLOR)
		if not is_nan(prev.x):
			d.line(prev + Vector3.UP * 0.2, p + Vector3.UP * 0.2, Color(GHOST_COLOR, 0.6))
		prev = p


# ---------------------------------------------------------------- deleting, boxes

func delete_ops(uids: PackedInt32Array) -> Array:
	var out := []
	if editor == null or editor.doc == null:
		return out
	for u in uids:
		var sec := str(editor.doc.find(u).get("section", ""))
		if sec in SECTION.values():
			out.append(ItemsTool.op_del(sec, u))
	return out


func item_aabb(uid: int) -> AABB:
	if editor == null or editor.doc == null:
		return AABB()
	var k := editor.kind_of(uid)
	var it := item_of(str(SECTION.get(k, "")), uid)
	if it.is_empty():
		return AABB()
	var p := ItemsTool._v3(it.get("pos"))
	match k:
		"prop":
			if editor.view != null:
				var b := editor.view.item_aabb(uid)
				if b.has_volume():
					return b
			var key := str(it.get("model", ""))
			var box := Game.model_aabb(key) if Game.models.has(key) else AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
			var sc := float(it.get("scale", 1.0))
			var r := maxf(absf(box.position.x), maxf(absf(box.end.x), maxf(absf(box.position.z), absf(box.end.z)))) * sc
			return AABB(p + Vector3(-r, box.position.y * sc, -r), Vector3(r * 2.0, maxf(box.size.y * sc, 0.5), r * 2.0))
		"light":
			return AABB(p - Vector3.ONE, Vector3.ONE * 2.0)
		"fire":
			var s := 0.5 + float(it.get("size", 1.0))
			return AABB(p - Vector3(s, 0, s), Vector3(s * 2.0, s * 2.0, s * 2.0))
		"screen":
			var w := float(it.get("w", 8.0)) * 0.5
			var hh := float(it.get("h", 4.5)) * 0.5
			return AABB(p - Vector3(w, hh, w), Vector3(w * 2.0, hh * 2.0, w * 2.0))
	return AABB()


func on_doc_changed(_sections: PackedStringArray, _uids: PackedInt32Array) -> void:
	_update_count()


# ---------------------------------------------------------------- options

func options(box: VBoxContainer) -> void:
	if editor == null or editor.doc == null:
		return
	box.add_child(EditorKit.tiles(MODE_NAMES, MODES.find(mode), func(i: int) -> void: set_mode(MODES[i]), MODE_ICONS, MODE_TIPS))
	_count_label = UiKit.label("", EditorKit.FONT_SMALL, UiKit.TEXT, true)
	box.add_child(_count_label)
	_update_count()
	match mode:
		"stamp":
			box.add_child(EditorKit.row("YAW", EditorKit.number(yaw, -180.0, 180.0, 5.0, func(v: float) -> void: yaw = v, "%d", "°")))
			box.add_child(EditorKit.row("SCALE", EditorKit.number(scale, 0.25, 4.0, 0.05, func(v: float) -> void: scale = v, "%.2f")))
			box.add_child(EditorKit.row("RANDOM YAW", EditorKit.check(random_yaw, func(on: bool) -> void: random_yaw = on)))
			box.add_child(EditorKit.row("RANDOM SCALE", EditorKit.check(random_scale, func(on: bool) -> void:
				random_scale = on
				_roll())))
			box.add_child(EditorKit.row("  MIN / MAX", _pair(scale_min, scale_max, 0.5, 2.0, 0.05, func(a: float, b: float) -> void:
				scale_min = a
				scale_max = b
				_roll())))
			box.add_child(EditorKit.row("ALIGN TO SURFACE", EditorKit.check(align, func(on: bool) -> void: align = on)))
			box.add_child(EditorKit.row("SINK", EditorKit.number(sink, 0.0, 2.0, 0.05, func(v: float) -> void: sink = v, "%.2f", " m")))
			box.add_child(EditorKit.hint("CLICK PLACE · {ed_mod_shift} + WHEEL TURN · {ed_mod_ctrl} + WHEEL SCALE · RIGHT MOUSE / {ed_cancel} STOP"))
		"scatter":
			box.add_child(EditorKit.row("BRUSH", EditorKit.number(radius, BRUSH_MIN, BRUSH_MAX, 1.0, func(v: float) -> void: radius = v, "%d", " m")))
			box.add_child(EditorKit.row("DENSITY", EditorKit.number(density, 0.1, 10.0, 0.1, func(v: float) -> void: density = v, "%.1f", " /100 m²")))
			box.add_child(EditorKit.row("MIN SPACING", EditorKit.number(spacing, 1.0, 40.0, 0.5, func(v: float) -> void: spacing = v, "%.1f", " m")))
			box.add_child(EditorKit.row("SCALE MIN / MAX", _pair(sc_min, sc_max, 0.5, 2.0, 0.05, func(a: float, b: float) -> void:
				sc_min = a
				sc_max = b)))
			box.add_child(EditorKit.row("RANDOM YAW", EditorKit.check(scatter_yaw, func(on: bool) -> void: scatter_yaw = on)))
			box.add_child(EditorKit.row("ALIGN TO SLOPE", EditorKit.check(slope, func(on: bool) -> void: slope = on)))
			box.add_child(EditorKit.row("KEEP OFF ROADS", EditorKit.number(keep_off, 0.0, 30.0, 0.5, func(v: float) -> void: keep_off = v, "%.1f", " m")))
			box.add_child(EditorKit.row("SEED", EditorKit.number(scatter_seed, 1, 99999, 1, func(v: float) -> void: scatter_seed = int(v), "%d")))
			box.add_child(EditorKit.hint("DRAG PAINT · {ed_mod_ctrl} + DRAG ERASE · {ed_brush_smaller} {ed_brush_bigger} SIZE · {ed_mod_ctrl} + CLICK IN THE CATALOG: PICK SEVERAL"))
		"along":
			box.add_child(EditorKit.row("EVERY", EditorKit.number(every, 4.0, 100.0, 1.0, func(v: float) -> void: every = v, "%d", " m")))
			box.add_child(EditorKit.row("SETBACK", EditorKit.number(setback, 0.0, 30.0, 0.5, func(v: float) -> void: setback = v, "%.1f", " m")))
			box.add_child(EditorKit.row("FACING", EditorKit.modes(["THE ROAD", "ALONG IT"], 0 if facing == "road" else 1,
				func(i: int) -> void: facing = "road" if i == 0 else "along")))
			box.add_child(EditorKit.row("JITTER", EditorKit.number(jitter, 0.0, 5.0, 0.5, func(v: float) -> void: jitter = v, "%.1f", " m")))
			box.add_child(EditorKit.row("JITTER YAW", EditorKit.number(jitter_yaw, 0.0, 30.0, 1.0, func(v: float) -> void: jitter_yaw = v, "%d", "°")))
			box.add_child(EditorKit.row("ORDER", EditorKit.modes(["PICK ORDER", "RANDOM"], 1 if random_order else 0,
				func(i: int) -> void: random_order = i == 1)))
			box.add_child(EditorKit.hint("PRESS ON A ROAD EDGE AND DRAG ALONG IT · {ed_mod_ctrl} + CLICK IN THE CATALOG: PICK SEVERAL"))


## Two number fields side by side (min / max); cb(a, b).
func _pair(a: float, b: float, lo: float, hi: float, step: float, cb: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	var vals := [a, b]
	for i in 2:
		var k := i
		var n := EditorKit.number(vals[i], lo, hi, step, func(v: float) -> void:
			vals[k] = v
			cb.call(minf(vals[0], vals[1]), maxf(vals[0], vals[1])), "%.2f")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
	return h


## "PROPS 812 / 1500" (red past the soft budget).
func count_text() -> String:
	return "PROPS %d / %d" % [prop_count(), BUDGET]


func _update_count() -> void:
	if _count_label == null or not is_instance_valid(_count_label):
		return
	_count_label.text = count_text()
	_count_label.add_theme_color_override("font_color", EditorKit.ERROR_COLOR if prop_count() > BUDGET else UiKit.TEXT)


# ---------------------------------------------------------------- inspector

func inspect(uids: PackedInt32Array, box: VBoxContainer) -> bool:
	if editor == null or editor.doc == null or uids.is_empty():
		return false
	var k := editor.kind_of(uids[0])
	if not owns(k):
		return false
	var same := PackedInt32Array()
	for u in uids:
		if editor.kind_of(u) == k:
			same.append(u)
	var sec: String = SECTION[k]
	var uid := same[0]
	var it := item_of(sec, uid)
	if it.is_empty():
		return false
	box.add_child(EditorKit.section_icon(str(NOUN[k]) if same.size() == 1 else "%d × %s" % [same.size(), str(NOUN[k])],
		str({"prop": "tool_objects", "light": "light", "fire": "fire", "screen": "screen"}.get(k, ""))))
	if k == "prop":
		_prop_inspector(same, it, box)
		return true
	if same.size() == 1:
		box.add_child(EditorKit.row("POSITION", EditorKit.vec3(ItemsTool._v3(it.get("pos")), func(v: Vector3) -> void:
			editor.commit("MOVE %s" % str(NOUN[k]), [ItemsTool.op_field(sec, uid, "pos", ItemsTool._arr(v))], "insp_pos_%d" % uid))))
	match k:
		"light":
			var c = it.get("color", [1.0, 0.9, 0.75])
			var col := Color(float(c[0]), float(c[1]), float(c[2])) if c is Array and (c as Array).size() >= 3 else LIGHT_COLOR
			box.add_child(EditorKit.row("COLOUR", EditorKit.color(col, func(v: Color) -> void:
				editor.commit("LIGHT COLOUR", _each(sec, same, "color", [snappedf(v.r, 0.001), snappedf(v.g, 0.001), snappedf(v.b, 0.001)]), "insp_col_%d" % uid))))
			box.add_child(EditorKit.row("RANGE", EditorKit.number(float(it.get("range", 16.0)), 1.0, 60.0, 0.5, func(v: float) -> void:
				editor.commit("LIGHT RANGE", _each(sec, same, "range", snappedf(v, 0.01)), "insp_range_%d" % uid), "%.1f", " m")))
			box.add_child(EditorKit.row("ENERGY", EditorKit.number(float(it.get("energy", 1.2)), 0.0, 8.0, 0.05, func(v: float) -> void:
				editor.commit("LIGHT ENERGY", _each(sec, same, "energy", snappedf(v, 0.01)), "insp_energy_%d" % uid), "%.2f")))
		"fire":
			box.add_child(EditorKit.row("SIZE", EditorKit.number(float(it.get("size", 1.0)), 0.0, 3.0, 0.1, func(v: float) -> void:
				editor.commit("FIRE SIZE", _each(sec, same, "size", snappedf(v, 0.01)), "insp_size_%d" % uid), "%.1f")))
			box.add_child(EditorKit.row("SMOKE", EditorKit.number(float(it.get("smoke", 1.0)), 0.0, 3.0, 0.1, func(v: float) -> void:
				editor.commit("FIRE SMOKE", _each(sec, same, "smoke", snappedf(v, 0.01)), "insp_smoke_%d" % uid), "%.1f")))
			box.add_child(EditorKit.row("LIGHT", EditorKit.check(bool(it.get("light", true)), func(on: bool) -> void:
				editor.commit("FIRE LIGHT", _each(sec, same, "light", on)))))
			box.add_child(EditorKit.hint("SIZE 0 = SMOKE ONLY (EMBERS)"))
		"screen":
			var ok := PropCatalog.fx_enabled("screen", editor.doc)
			var w := EditorKit.number(float(it.get("w", 8.0)), 2.0, 20.0, 0.5, func(v: float) -> void:
				editor.commit("SCREEN SIZE", _each(sec, same, "w", snappedf(v, 0.01)), "insp_w_%d" % uid), "%.1f", " m")
			var hh := EditorKit.number(float(it.get("h", 4.5)), 1.0, 12.0, 0.5, func(v: float) -> void:
				editor.commit("SCREEN SIZE", _each(sec, same, "h", snappedf(v, 0.01)), "insp_h_%d" % uid), "%.1f", " m")
			var yw := EditorKit.number(float(it.get("yaw", 0.0)), -180.0, 180.0, 5.0, func(v: float) -> void:
				editor.commit("TURN SCREEN", _each(sec, same, "yaw", wrap_deg(v)), "insp_yaw_%d" % uid), "%d", "°")
			for c2 in [w, hh, yw]:
				(c2 as Control).modulate.a = 1.0 if ok else 0.45
			box.add_child(EditorKit.row("W", w))
			box.add_child(EditorKit.row("H", hh))
			box.add_child(EditorKit.row("YAW", yw))
			if not ok:
				box.add_child(EditorKit.hint("Breencast screens show only with the COMBINE start arch."))
	return true


func _prop_inspector(same: PackedInt32Array, it: Dictionary, box: VBoxContainer) -> void:
	var uid := same[0]
	var key := str(it.get("model", ""))
	box.add_child(EditorKit.row("MODEL", UiKit.label(PropCatalog.display_name(key), EditorKit.FONT_SMALL, UiKit.TEXT), key))
	box.add_child(EditorKit.button("REPLACE...", func() -> void:
		replacing = same.duplicate()
		if editor.tool != self:
			editor.set_tool.call_deferred("objects")
		else:
			show_catalog(true)
		editor.status("Pick the new model in the catalog"), "Then pick the new model in the catalog.", "reverse"))
	if same.size() == 1:
		box.add_child(EditorKit.row("POSITION", EditorKit.vec3(ItemsTool._v3(it.get("pos")), func(v: Vector3) -> void:
			editor.commit("MOVE OBJECT", [ItemsTool.op_field("props", uid, "pos", ItemsTool._arr(v))], "insp_pos_%d" % uid))))
	for pair in [["YAW", "yaw", -180.0, 180.0], ["PITCH", "pitch", -90.0, 90.0], ["ROLL", "roll", -90.0, 90.0]]:
		var field: String = pair[1]
		box.add_child(EditorKit.row(pair[0], EditorKit.number(float(it.get(field, 0.0)), pair[2], pair[3], 1.0, func(v: float) -> void:
			editor.commit("ROTATE OBJECT", _each("props", same, field, wrap_deg(v) if field == "yaw" else snappedf(v, 0.1)), "insp_%s_%d" % [field, uid]), "%d", "°")))
	var far := str(it.get("tag", "")) == "far"
	box.add_child(EditorKit.row("SCALE", EditorKit.number(float(it.get("scale", 1.0)), 0.1 if far else 0.25, 150.0 if far else 4.0, 0.05, func(v: float) -> void:
		editor.commit("SCALE OBJECT", _each("props", same, "scale", snappedf(v, 0.05)), "insp_scale_%d" % uid), "%.2f")))
	var phys_ok := PropCatalog.physics_ok(key)
	var ph := EditorKit.check(bool(it.get("physics", false)), func(on: bool) -> void: set_physics(same, on))
	ph.disabled = not phys_ok and not bool(it.get("physics", false))
	box.add_child(EditorKit.row("PHYSICS", ph, "Knocked about by karts (models of at most 60 kg and under 3 m; scale and tilt are ignored)" if phys_ok else "Only light models under 3 m can be physics objects"))
	var tag := str(it.get("tag", ""))
	box.add_child(EditorKit.row("COLLISION", EditorKit.choice(TAG_NAMES, maxi(TAGS.find(tag if tag != "float" else ""), 0),
		func(i: int) -> void: editor.commit("OBJECT COLLISION", _each("props", same, "tag", TAGS[i])))))
	var sea := _sea_on()
	var fl := EditorKit.check(tag == "float", func(on: bool) -> void:
		editor.commit("FLOATS ON THE SEA", _each("props", same, "tag", "float" if on else "")))
	fl.disabled = not sea
	box.add_child(EditorKit.row("FLOATS", fl, "FLOATS ON THE SEA" if sea else "FLOATS ON THE SEA: turn the sea on (WORLD > WATER) first"))
	var g := int(it.get("group", 0))
	if g > 0:
		var n := 0
		for p in list_of("props"):
			if p is Dictionary and int(p.get("group", 0)) == g:
				n += 1
		box.add_child(EditorKit.button("SELECT ITS GROUP (%d)" % n, func() -> void: select_group(g),
			"Selects the objects placed with it (one SCATTER stroke or ALONG ROAD row).", "select_all"))


## PHYSICS on / off for props (only physics_ok models; at most 300 on a track).
func set_physics(uids: PackedInt32Array, on: bool) -> void:
	var ops := []
	var have := 0
	for p in list_of("props"):
		if p is Dictionary and bool(p.get("physics", false)):
			have += 1
	for u in uids:
		var it := item_of("props", u)
		if it.is_empty() or bool(it.get("physics", false)) == on:
			continue
		if on:
			if not PropCatalog.physics_ok(str(it.get("model", ""))):
				continue
			if have >= PHYS_CAP:
				editor.toast("At most %d physics objects on a track." % PHYS_CAP)
				break
			have += 1
		ops.append(ItemsTool.op_field("props", u, "physics", on))
	if not ops.is_empty():
		editor.commit("OBJECT PHYSICS", ops)


func _sea_on() -> bool:
	var w = editor.doc.data.get("water", {})
	return w is Dictionary and bool(w.get("sea", false))


func _each(sec: String, uids: PackedInt32Array, field: String, value: Variant) -> Array:
	var out := []
	for u in uids:
		if not item_of(sec, u).is_empty():
			out.append(ItemsTool.op_field(sec, u, field, value))
	return out


func list_of(section: String) -> Array:
	if editor == null or editor.doc == null:
		return []
	var l = editor.doc.data.get(section)
	return l if l is Array else []


func item_of(section: String, uid: int) -> Dictionary:
	if editor == null or editor.doc == null or section == "":
		return {}
	var f := editor.doc.find(uid)
	if f.is_empty() or str(f.get("section", "")) != section or not (f.get("item") is Dictionary):
		return {}
	return f.item
