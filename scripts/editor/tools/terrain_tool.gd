class_name TerrainTool
extends EditorTool
## 1.6 TERRAIN: the height brushes RAISE / LOWER / SMOOTH / FLATTEN / NOISE (LMB paints, dabs every
## 25 % of the radius along the stroke at 60 Hz at most; Ctrl inverts raise / lower, Shift smooths;
## Alt + click without moving picks FLATTEN's height), SIZE / STRENGTH by [ ] and Shift + [ ], the
## falloff shown as the brush circle's inner ring, ROADS FOLLOW THE GROUND, ADD LAKE (drag a
## rectangle; the level dot drags up and down, the corner squares resize), SHOW CARVE, RESIZE
## WORLD and NO TERRAIN. A stroke writes the document's heights live (each dab rebuilds its chunks
## through doc.notify -> TrackEditor.refresh_terrain), then at its end becomes one undo step
## (EditHistory.push_applied: the touched rect and its before-copy, plus the followed points'
## sets) and the collision tiles under it are rebuilt. P16.

const BRUSHES := ["raise", "lower", "smooth", "flatten", "noise"]
const BRUSH_NAMES := ["RAISE", "LOWER", "SMOOTH", "FLATTEN", "NOISE"]
const FALLOFF_NAMES := ["SMOOTH", "LINEAR", "FLAT"]
const SIZE_MIN := 2.0
const SIZE_MAX := 200.0
const STRENGTH_MIN := 0.01
const STRENGTH_MAX := 1.0
## Dabs along a stroke: every SPACING x the radius, at most DAB_HZ batches a second.
const SPACING := 0.25
const DAB_HZ := 60.0
## At most this many dabs per batch (a fast flick over a small brush).
const MAX_DABS := 12
const LAKE_COLOR := Color(0.25, 0.6, 1.0)
const BRUSH_COLOR := Color8(255, 155, 0)
const LAKE_MIN := 4.0
const LAKE_MAX := 2000.0
## A press + release of Alt + LMB that moved the camera less than this is a click (the eyedropper).
const PICK_EPS := 0.001

## Brush settings survive the test drive's scene changes (the tool object does not).
static var _keep := {}

var brush := "raise"
var size := 20.0                 # the brush radius (m)
var strength := 0.5
var falloff := "smooth"
var noise_scale := 32.0
var noise_seed := 1
var follow := true               # ROADS FOLLOW THE GROUND
var target := NAN                # FLATTEN's picked height (NAN: the first dab's)
var lake_mode := false           # ADD LAKE: LMB drags a rectangle
var picking := false             # PICK HEIGHT: the next click is the eyedropper
var show_carve := true           # off: the natural ground is shown
## The last dab (tests, the status line): {ms, chunks, rect}.
var last_dab := {}
## The last stroke's end: {rect, points, tiles_ms}.
var last_stroke := {}
## Dab batches wait this long apart (tests set 0).
var throttle := 1.0 / DAB_HZ

var _stroke := {}                # {mode, before, rect, last, target, dabs, t}
var _pending := Vector2(NAN, NAN)
var _lake := {}                  # the lake drag: {kind: "new" | "level" | "corner", ...}
var _alt := {}                   # an Alt + LMB press the camera took: {xf, screen}
var _natural_shown := false


func _init(ed: TrackEditor) -> void:
	super(ed)
	id = "terrain"
	title = "TERRAIN"
	purpose = "Raise, lower, smooth and flatten the ground; lakes; the world's size."
	for k in _keep:
		set(k, _keep[k])


func kinds() -> PackedStringArray:
	return PackedStringArray(["lake"])


func markers(m: EditorMarkers) -> void:
	if editor == null or editor.doc == null:
		return
	for lk in editor.doc.data.get("lakes", []):
		if not (lk is Dictionary) or int(lk.get("uid", 0)) <= 0:
			continue
		var u := int(lk.uid)
		var c := lake_center(lk)
		var hs := lake_size(lk) * 0.5
		var y := float(lk.get("level", 0.0))
		m.add("lake", u, Vector3(c.x, y, c.y), EditorMarkers.Shape.DOT, LAKE_COLOR, 2.0, 0)
		var k := 1
		for sg in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			m.add("lake", u, Vector3(c.x + sg.x * hs.x, y, c.y + sg.y * hs.y), EditorMarkers.Shape.SQUARE, LAKE_COLOR, 2.0, k)
			k += 1


func activate() -> void:
	_alt.clear()


func deactivate() -> void:
	if not _stroke.is_empty():
		stroke_end()
	if not _lake.is_empty() and _lake.get("kind") != "new":
		editor.history.end_gesture()
	_lake.clear()
	picking = false
	if _natural_shown:
		set_show_carve(true)
	_save()


func options(box: VBoxContainer) -> void:
	box.add_child(EditorKit.section("BRUSH"))
	box.add_child(EditorKit.modes(BRUSH_NAMES, BRUSHES.find(brush), func(i: int) -> void:
		set_brush(BRUSHES[i])
		_refresh_options()))
	box.add_child(EditorKit.row("SIZE", EditorKit.number(size, SIZE_MIN, SIZE_MAX, 1.0, func(v: float) -> void: set_size(v), "%.0f", " m"),
		EditorKit.plain("The brush radius ({ed_brush_smaller} {ed_brush_bigger}).")))
	box.add_child(EditorKit.row("STRENGTH", EditorKit.number(strength, STRENGTH_MIN, STRENGTH_MAX, 0.01, func(v: float) -> void: set_strength(v), "%.2f"),
		EditorKit.plain("{ed_strength_down} {ed_strength_up}")))
	box.add_child(EditorKit.row("FALLOFF", EditorKit.modes(FALLOFF_NAMES, LevelBrush.FALLOFFS.find(falloff), func(i: int) -> void:
		falloff = LevelBrush.FALLOFFS[i]
		_save()
		editor.redraw())))
	if brush == "noise":
		box.add_child(EditorKit.row("NOISE SCALE", EditorKit.number(noise_scale, 8.0, 256.0, 1.0, func(v: float) -> void:
			noise_scale = v
			_save(), "%.0f", " m")))
		box.add_child(EditorKit.row("SEED", EditorKit.number(noise_seed, 0.0, 99999.0, 1.0, func(v: float) -> void:
			noise_seed = int(v)
			_save(), "%.0f")))
	if brush == "flatten":
		var txt := "HEIGHT %.1f m" % target if not is_nan(target) else "the height under the first dab"
		box.add_child(EditorKit.row("TARGET", UiKit.label(txt, 14, UiKit.TEXT)))
		box.add_child(EditorKit.button("PICK HEIGHT", func() -> void:
			picking = true
			editor.status("Click the ground to pick the height.", true), "Or {ed_mod_alt} + click without moving."))
	var ft := EditorKit.toggle("ROADS FOLLOW THE GROUND", follow, func(v: bool) -> void:
		follow = v
		_save())
	ft.tooltip_text = "Road points with FOLLOW GROUND keep their height above the ground you sculpt."
	box.add_child(ft)
	box.add_child(EditorKit.hint("{ed_place} sculpts, {ed_mod_ctrl} swaps RAISE and LOWER, {ed_mod_shift} smooths."))
	box.add_child(EditorKit.section("WATER"))
	box.add_child(EditorKit.toggle("ADD LAKE", lake_mode, func(on: bool) -> void:
		lake_mode = on
		editor.redraw()))
	box.add_child(EditorKit.hint("Drag a rectangle on the ground; drag its middle dot up and down."))
	box.add_child(EditorKit.section("WORLD"))
	box.add_child(EditorKit.row("SHOW CARVE", EditorKit.check(show_carve, func(v: bool) -> void: set_show_carve(v)),
		"Off: the natural ground, without the roads cut into it."))
	var doc := editor.doc
	# short enough for the column; the tooltip says it in full
	var info := "NO TERRAIN"
	var full := "No terrain: floating roads over a void."
	if doc.has_terrain():
		var cell := str(snappedf(doc.cell(), 0.01))
		info = "%d m · %d² · %s m" % [int(doc.world_size()), doc.res(), cell]
		full = "%d m across, %d x %d heights, %s m cells." % [int(doc.world_size()), doc.res(), doc.res(), cell]
	var il := UiKit.label(info, EditorKit.FONT_SMALL, UiKit.TEXT)
	il.clip_text = true
	il.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	il.tooltip_text = full
	il.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(EditorKit.row("WORLD SIZE", il, full))
	box.add_child(EditorKit.button("RESIZE WORLD...", func() -> void: editor.open_dialog(ResizeDialog.new(self)),
		"Resample the ground to another world size or resolution."))
	box.add_child(EditorKit.row("NO TERRAIN", EditorKit.check(not doc.has_terrain(), func(v: bool) -> void: set_terrain(not v)),
		"Floating roads over a void: every open edge is a pit."))


func inspect(uids: PackedInt32Array, box: VBoxContainer) -> bool:
	if uids.is_empty() or editor == null:
		return false
	for u in uids:
		if editor.kind_of(u) != "lake":
			return false
	var f := editor.doc.find(uids[0])
	if f.is_empty():
		return false
	var lk: Dictionary = f.item
	var path: Array = f.path
	box.add_child(EditorKit.section("LAKE" if uids.size() == 1 else "%d LAKES" % uids.size()))
	var list := uids.duplicate()
	box.add_child(EditorKit.row("LEVEL", EditorKit.number(float(lk.get("level", 0.0)), LevelDoc.HEIGHT_MIN, LevelDoc.HEIGHT_MAX, 0.1,
		func(v: float) -> void:
			var ops := []
			for u in list:
				ops.append(LevelDoc.op_set(editor.doc.path_of(u) + ["level"], snappedf(v, 0.01)))
			editor.commit("LAKE LEVEL", ops, "lake_level"), "%.1f", " m")))
	if uids.size() == 1:
		var sz := lake_size(lk)
		box.add_child(EditorKit.row("WIDTH", EditorKit.number(sz.x, LAKE_MIN, LAKE_MAX, 1.0, func(v: float) -> void:
			var cur := lake_size(editor.doc.get_at(path))
			editor.commit("LAKE SIZE", [LevelDoc.op_set(path + ["size"], [snappedf(v, 0.01), cur.y])], "lake_size"), "%.0f", " m")))
		box.add_child(EditorKit.row("DEPTH", EditorKit.number(sz.y, LAKE_MIN, LAKE_MAX, 1.0, func(v: float) -> void:
			var cur := lake_size(editor.doc.get_at(path))
			editor.commit("LAKE SIZE", [LevelDoc.op_set(path + ["size"], [cur.x, snappedf(v, 0.01)])], "lake_size"), "%.0f", " m")))
		box.add_child(EditorKit.hint("Drag the dot for the level, a corner for the size."))
	return true


func hints(hit: EditorHit) -> Array:
	if hit != null and hit.what == "marker" and hit.kind == "lake":
		if hit.sub == 0:
			return [["DRAG LEVEL UP / DOWN"], ["CLICK SELECT"], ["{ed_delete} DELETE"]]
		return [["DRAG RESIZE THE LAKE"], ["CLICK SELECT"]]
	if picking:
		return [["CLICK PICK THE HEIGHT"], ["{ed_cancel} CANCEL"]]
	if lake_mode:
		return [["DRAG ADD A LAKE"], ["{ed_cancel} CANCEL"]]
	var nm: String = BRUSH_NAMES[BRUSHES.find(brush)]
	var out := [["DRAG %s" % nm]]
	if brush in ["raise", "lower"]:
		out.append(["{ed_mod_ctrl} DRAG %s" % ("LOWER" if brush == "raise" else "RAISE")])
	if brush != "smooth":
		out.append(["{ed_mod_shift} DRAG SMOOTH"])
	if brush == "flatten":
		out.append(["{ed_mod_alt} CLICK PICK HEIGHT"])
	out.append(["{ed_brush_smaller} {ed_brush_bigger} SIZE"])
	out.append(["{ed_strength_down} {ed_strength_up} STRENGTH"])
	return out


func status_step() -> String:
	if not _lake.is_empty() and _lake.get("kind") == "level":
		return "LEVEL %.1f m" % float(_lake.get("level", 0.0))
	var p := _hover_ground()
	if is_nan(p.x):
		return ""
	var h := natural_at(p)
	if is_nan(h):
		return "NO GROUND HERE"
	var s := "HEIGHT %.1f m" % h
	if brush == "flatten" and not is_nan(target):
		s += " · TARGET %.1f m" % target
	return s


func click(hit: EditorHit, mods: int) -> bool:
	if editor == null or editor.doc == null:
		return false
	if hit.what == "marker":
		return false
	var p := ground_of(hit)
	if picking:
		picking = false
		if not is_nan(p.x):
			pick_height(p)
		return true
	if lake_mode or is_nan(p.x) or not editor.doc.has_terrain():
		return false
	stroke_begin(p, mods)
	stroke_end()
	return true


func drag_begin(hit: EditorHit, mods: int) -> bool:
	if editor == null or editor.doc == null:
		return false
	if hit.what == "marker" and hit.kind == "lake" and hit.uid > 0:
		return _lake_grab(hit)
	var p := ground_of(hit)
	if is_nan(p.x):
		return false
	if lake_mode:
		_lake = {"kind": "new", "a": p, "b": p}
		editor.redraw()
		return true
	if not editor.doc.has_terrain():
		return false
	stroke_begin(p, mods)
	return true


func drag_move(hit: EditorHit, mods: int) -> void:
	if not _lake.is_empty():
		_lake_move(hit)
		return
	if _stroke.is_empty():
		return
	var p := ground_of(hit)
	if not is_nan(p.x):
		stroke_to(p)


func drag_end(hit: EditorHit, mods: int) -> void:
	if not _lake.is_empty():
		_lake_move(hit)
		_lake_end()
		return
	if _stroke.is_empty():
		return
	var p := ground_of(hit)
	if not is_nan(p.x):
		_pending = p
	stroke_end()


func key(ev: InputEvent) -> bool:
	if not ev.is_pressed():
		return false
	if ev.is_action_pressed("ed_brush_smaller", true, true):
		set_size(size * 0.8)
		return true
	if ev.is_action_pressed("ed_brush_bigger", true, true):
		set_size(size * 1.25)
		return true
	if ev.is_action_pressed("ed_strength_down", true, true):
		set_strength(strength - 0.05)
		return true
	if ev.is_action_pressed("ed_strength_up", true, true):
		set_strength(strength + 0.05)
		return true
	if ev.is_action_pressed("ed_cancel", false, true):
		return cancel()
	return false


func process(_delta: float) -> void:
	if not _stroke.is_empty() and not is_nan(_pending.x):
		if _now() - float(_stroke.get("t", 0.0)) >= throttle:
			var p := _pending
			_pending = Vector2(NAN, NAN)
			stroke_to(p)
	var shot := alt_click(editor, _alt)
	if not is_nan(shot.x):
		var p := ground_of(editor.pick(shot))
		if not is_nan(p.x):
			pick_height(p)


func overlay(d: EditorDraw) -> void:
	var t := editor.terrain()
	if not _lake.is_empty() and _lake.get("kind") == "new":
		var a: Vector2 = _lake.a
		var b: Vector2 = _lake.b
		var y := maxf(natural_at(a) if not is_nan(natural_at(a)) else 0.0, natural_at(b) if not is_nan(natural_at(b)) else 0.0) + 0.3
		var pts := PackedVector3Array([Vector3(a.x, y, a.y), Vector3(b.x, y, a.y), Vector3(b.x, y, b.y), Vector3(a.x, y, b.y)])
		d.polyline(pts, LAKE_COLOR, true, true)
		return
	if lake_mode or t == null:
		return
	var c := _hover_ground()
	if not _stroke.is_empty():
		c = _stroke.last
	if is_nan(c.x):
		return
	d.ground_circle(t, c, size, BRUSH_COLOR)
	var inner := LevelBrush.ring(falloff) * size
	if inner < size * 0.98:
		d.ground_circle(t, c, inner, Color(BRUSH_COLOR, 0.45))


func on_doc_changed(sections: PackedStringArray, _uids: PackedInt32Array) -> void:
	if _natural_shown and _stroke.is_empty() and "terrain" in sections:
		set_show_carve(true)


func delete_ops(uids: PackedInt32Array) -> Array:
	var idx: Array[int] = []
	var lakes = editor.doc.data.get("lakes", [])
	if not (lakes is Array):
		return []
	for i in lakes.size():
		if lakes[i] is Dictionary and int(lakes[i].get("uid", 0)) in uids:
			idx.append(i)
	idx.sort()
	idx.reverse()
	var out := []
	for i in idx:
		out.append(LevelDoc.op_remove(["lakes"], i))
	return out


func item_aabb(uid: int) -> AABB:
	var f := editor.doc.find(uid)
	if f.is_empty() or f.section != "lakes":
		return AABB()
	var c := lake_center(f.item)
	var s := lake_size(f.item)
	var y := float(f.item.get("level", 0.0))
	return AABB(Vector3(c.x - s.x * 0.5, y - 1.0, c.y - s.y * 0.5), Vector3(s.x, 2.0, s.y))


# ---------------------------------------------------------------- additions (P16): the brush

func set_brush(b: String) -> void:
	if b in BRUSHES:
		brush = b
		_save()


func set_size(v: float) -> void:
	size = clampf(snappedf(v, 0.1), SIZE_MIN, SIZE_MAX)
	_save()
	editor.redraw()
	editor.status("BRUSH SIZE %.0f m" % size)


func set_strength(v: float) -> void:
	strength = clampf(snappedf(v, 0.01), STRENGTH_MIN, STRENGTH_MAX)
	_save()
	editor.status("BRUSH STRENGTH %.2f" % strength)


## The FLATTEN height under p (the eyedropper).
func pick_height(p: Vector2) -> void:
	var h := natural_at(p)
	if is_nan(h):
		return
	target = snappedf(h, 0.01)
	if brush != "flatten":
		set_brush("flatten")
	editor.status("FLATTEN TO %.1f m" % target)
	_refresh_options()


## The stroke's first dab: the mode (Ctrl inverts, Shift smooths), the before-copy, FLATTEN's height.
func stroke_begin(p: Vector2, mods: int) -> void:
	var doc := editor.doc
	var m := brush
	if has_mod(mods, MOD_SHIFT):
		m = "smooth"
	elif has_mod(mods, MOD_CTRL):
		m = {"raise": "lower", "lower": "raise"}.get(m, m)
	if _natural_shown:
		set_show_carve(true)
	var tg := target
	if m == "flatten" and is_nan(tg):
		tg = natural_at(p)
		if is_nan(tg):
			tg = 0.0
	_stroke = {"mode": m, "before": doc.heights.duplicate(), "rect": Rect2i(), "last": p, "target": tg, "dabs": 0,
		"t": _now()}
	_pending = Vector2(NAN, NAN)
	dab(p)


## Dabs from the last one to p every SPACING x the radius (at most MAX_DABS; the rest of the way
## waits for the next batch).
func stroke_to(p: Vector2) -> void:
	if _stroke.is_empty():
		return
	if throttle > 0.0 and _now() - float(_stroke.t) < throttle:
		_pending = p
		return
	var last: Vector2 = _stroke.last
	var step := maxf(size * SPACING, editor.doc.cell() * 0.5)
	var dist := last.distance_to(p)
	if dist < step:
		_pending = Vector2(NAN, NAN)
		return
	var n := mini(int(dist / step), MAX_DABS)
	var dir := (p - last) / dist
	# the batch's dabs write the heights, then one notice for their rect: one re-carve and one
	# rebuild of each chunk, not one per dab (12 dabs on a chunk rebuilt it 12 times)
	var batch := Rect2i()
	for k in n:
		var r := dab(last + dir * step * (k + 1), false)
		if r.has_area():
			batch = r if not batch.has_area() else batch.merge(r)
	if batch.has_area():
		var t0 := Time.get_ticks_usec()
		editor.doc.notify(PackedStringArray(["terrain"]), PackedInt32Array(), batch)
		var lt := editor.terrain()
		last_dab = {"ms": (Time.get_ticks_usec() - t0) / 1000.0, "chunks": lt.chunks_in(batch).size() if lt != null else 0,
			"rect": batch, "dabs": n}
	# a flick past MAX_DABS: the rest of the way in the next batch
	_pending = p if dist - n * step >= step else Vector2(NAN, NAN)


## One dab at p: the heights written, the document told (TrackEditor copies them into the live
## terrain, re-carves the rect and rebuilds its chunks; collision waits for the stroke's end).
## notify false: the caller tells the document once for a batch. Returns the dab's rect.
func dab(p: Vector2, notify := true) -> Rect2i:
	var doc := editor.doc
	var t := editor.terrain()
	if t == null or t.res != doc.res() or doc.heights.size() != t.res * t.res:
		t = LevelTerrain.from_doc(doc)
	if t == null:
		return Rect2i()
	var t0 := Time.get_ticks_usec()
	var m := str(_stroke.get("mode", brush))
	var r: Rect2i
	if m == "noise":
		r = LevelBrush.dab_noise(t, doc.heights, p, size, strength, falloff, noise_scale, noise_seed)
	else:
		r = LevelBrush.dab_height(t, doc.heights, p, size, strength, m, falloff, float(_stroke.get("target", 0.0)), noise_seed)
	_stroke.last = p
	_stroke.t = _now()
	_stroke.dabs = int(_stroke.dabs) + 1
	if not r.has_area():
		return r
	var sr: Rect2i = _stroke.rect
	_stroke.rect = r if not sr.has_area() else sr.merge(r)
	if not notify:
		return r
	doc.notify(PackedStringArray(["terrain"]), PackedInt32Array(), r)
	var lt := editor.terrain()
	last_dab = {"ms": (Time.get_ticks_usec() - t0) / 1000.0, "chunks": lt.chunks_in(r).size() if lt != null else 0, "rect": r}
	return r


## The stroke's end: one undo step (the touched rect and its before-copy, plus ROADS FOLLOW THE
## GROUND's point sets), the collision tiles under it, a bake.
func stroke_end() -> void:
	if _stroke.is_empty():
		return
	if not is_nan(_pending.x):
		var p := _pending
		_pending = Vector2(NAN, NAN)
		var th := throttle
		throttle = 0.0
		stroke_to(p)
		throttle = th
	var st := _stroke
	_stroke = {}
	_pending = Vector2(NAN, NAN)
	var rect: Rect2i = st.rect
	if not rect.has_area():
		return
	var doc := editor.doc
	var res := doc.res()
	var before: PackedFloat32Array = st.before
	var do_ops := [LevelDoc.op_heights(rect, LevelBrush.region(doc.heights, res, rect))]
	var undo_ops := [LevelDoc.op_heights(rect, LevelBrush.region(before, res, rect))]
	var pts := LevelBrush.follow_ops(doc, before, rect) if follow else []
	if not pts.is_empty():
		var inv := doc.apply(pts)
		do_ops.append_array(pts)
		undo_ops = inv + undo_ops
	var nm: String = BRUSH_NAMES[maxi(BRUSHES.find(str(st.mode)), 0)]
	editor.history.push_applied("TERRAIN: " + nm, do_ops, undo_ops)
	var t0 := Time.get_ticks_usec()
	if editor.view != null:
		editor.view.update_terrain(rect, true)
	last_stroke = {"rect": rect, "points": pts.size(), "tiles_ms": (Time.get_ticks_usec() - t0) / 1000.0, "dabs": int(st.dabs)}
	# a bake of this revision now, so one held back during the drag is dropped
	editor.bake_now(func(_b: LevelBuild) -> void: pass)
	succeeded()


## Esc while the button holds a stroke or a lake drag (TrackEditor.end_press): taken back.
func cancel_drag() -> void:
	var was := picking
	picking = false
	cancel()
	picking = was


## Esc: a lake drag or a stroke stops and is taken back; false when nothing was going on.
func cancel() -> bool:
	if picking:
		picking = false
		return true
	if not _lake.is_empty():
		if _lake.get("kind") != "new":
			editor.history.cancel_gesture()
		_lake.clear()
		editor.redraw()
		return true
	if not _stroke.is_empty():
		var st := _stroke
		_stroke = {}
		_pending = Vector2(NAN, NAN)
		var rect: Rect2i = st.rect
		if rect.has_area():
			editor.doc.apply([LevelDoc.op_heights(rect, LevelBrush.region(st.before, editor.doc.res(), rect))])
		return true
	return false


## SHOW CARVE: off shows the natural ground (the chunks rebuilt from it) until it is turned back on
## or the ground is edited.
func set_show_carve(on: bool) -> void:
	show_carve = on
	var v := editor.view
	var t := editor.terrain()
	if v == null or t == null:
		_natural_shown = false
		return
	var full := Rect2i(0, 0, t.res, t.res)
	if not on and not _natural_shown:
		var nat := LevelTerrain.new()
		nat.res = t.res
		nat.cell = t.cell
		nat.origin = t.origin
		nat.natural = t.natural
		nat.heights = t.natural.duplicate()
		nat.splat = t.splat
		nat.layers = t.layers
		v.terrain_live = nat
		v.update_terrain(full, false)
		v.terrain_live = t
		_natural_shown = true
	elif on and _natural_shown:
		_natural_shown = false
		v.update_terrain(full, false)


## NO TERRAIN off / on (one undo step).
func set_terrain(on: bool) -> void:
	var ops := LevelBrush.terrain_ops(editor.doc, on)
	if ops.is_empty():
		return
	editor.commit("TERRAIN ON" if on else "NO TERRAIN", ops)
	_refresh_options()


## RESIZE WORLD (one undo step); false when the pair is not allowed.
func resize_world(size_m: float, res: int) -> bool:
	var ops := LevelBrush.resample(editor.doc, size_m, res)
	if ops.is_empty():
		return false
	editor.commit("RESIZE WORLD", ops)
	editor.toast("World: %d m, %d x %d." % [int(size_m), res, res])
	_refresh_options()
	return true


## ADD LAKE in one go (the rectangle a..b on the ground, world x / z): its level from the ground in
## it; returns the uid (0 when the lake limit is reached).
func add_lake(a: Vector2, b: Vector2) -> int:
	var doc := editor.doc
	var lakes = doc.data.get("lakes", [])
	var cap := int(LevelDoc.CAPS.get("lakes", 16))
	if lakes is Array and lakes.size() >= cap:
		editor.toast("Lake limit reached (%d)." % cap)
		return 0
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var sz := Vector2(clampf(hi.x - lo.x, LAKE_MIN, LAKE_MAX), clampf(hi.y - lo.y, LAKE_MIN, LAKE_MAX))
	var c := (lo + hi) * 0.5
	var u := doc.new_uid()
	var lk := {"uid": u, "center": [snappedf(c.x, 0.001), snappedf(c.y, 0.001)], "size": [snappedf(sz.x, 0.01), snappedf(sz.y, 0.01)],
		"level": snappedf(lake_level(c, sz), 0.01)}
	editor.commit("ADD LAKE", [LevelDoc.op_insert(["lakes"], -1, lk)])
	editor.select(PackedInt32Array([u]))
	succeeded()
	return u


## A new lake's level: 60 % of the way from the lowest to the highest natural ground inside it,
## at least 0.3 m over the lowest.
func lake_level(c: Vector2, sz: Vector2) -> float:
	var lo := INF
	var hi := -INF
	for j in 9:
		for i in 9:
			var h := natural_at(c + Vector2((i / 8.0 - 0.5) * sz.x, (j / 8.0 - 0.5) * sz.y))
			if not is_nan(h):
				lo = minf(lo, h)
				hi = maxf(hi, h)
	if lo == INF:
		return 0.0
	return maxf(lo + (hi - lo) * 0.6, lo + 0.3)


## The ground point (world x, z) of a hit: the live terrain under its ray, else its position.
func ground_of(hit: EditorHit) -> Vector2:
	if hit == null:
		return Vector2(NAN, NAN)
	var t := editor.terrain() if editor != null else null
	if t != null and hit.ray_dir.length_squared() > 1e-9 and hit.ray_from != Vector3.ZERO:
		var g := t.raycast(hit.ray_from, hit.ray_dir)
		if not is_nan(g.x):
			return Vector2(g.x, g.z)
	if hit.hit:
		return Vector2(hit.pos.x, hit.pos.z)
	return Vector2(NAN, NAN)


## The document's natural ground at p (NAN outside it or with no terrain).
func natural_at(p: Vector2) -> float:
	var doc := editor.doc
	if doc == null or not doc.has_terrain():
		return NAN
	return LevelBrush.sample(doc.heights, doc.res(), doc.origin(), doc.cell(), p.x, p.y)


static func lake_center(lk: Variant) -> Vector2:
	var c = lk.get("center") if lk is Dictionary else null
	return Vector2(float(c[0]), float(c[1])) if c is Array and c.size() >= 2 else Vector2.ZERO


static func lake_size(lk: Variant) -> Vector2:
	var s = lk.get("size") if lk is Dictionary else null
	return Vector2(float(s[0]), float(s[1])) if s is Array and s.size() >= 2 else Vector2(40, 40)


## The camera's Alt + LMB (orbit) that ended without moving it: an Alt + click (the eyedropper).
## state holds the press between frames; returns its screen point once, NAN otherwise. P8's camera
## takes Alt + LMB before any tool sees it, so this watches the camera instead.
static func alt_click(ed: TrackEditor, state: Dictionary) -> Vector2:
	var none := Vector2(NAN, NAN)
	if ed == null or ed.camera == null:
		return none
	var orbit := ed.camera.drag == "orbit"
	if orbit and state.is_empty():
		state["xf"] = ed.camera.global_transform
		# the hover's screen point: the mouse before the camera captured it
		state["screen"] = ed.hover.screen if ed.hover != null else Vector2.ZERO
		state["t"] = Time.get_ticks_msec()
		return none
	if not orbit and not state.is_empty():
		var xf: Transform3D = state.xf
		var sc: Vector2 = state.screen
		var quick := Time.get_ticks_msec() - int(state.t) < 600
		state.clear()
		if quick and xf.origin.distance_to(ed.camera.global_transform.origin) < PICK_EPS \
				and xf.basis.z.distance_to(ed.camera.global_transform.basis.z) < PICK_EPS:
			return sc
	return none


func _hover_ground() -> Vector2:
	var hv := editor.hover if editor != null else null
	if hv == null or not hv.hit:
		return Vector2(NAN, NAN)
	return Vector2(hv.pos.x, hv.pos.z)


func _lake_grab(hit: EditorHit) -> bool:
	var f := editor.doc.find(hit.uid)
	if f.is_empty() or f.section != "lakes":
		return false
	var lk: Dictionary = f.item
	var c := lake_center(lk)
	var s := lake_size(lk)
	if hit.sub == 0:
		_lake = {"kind": "level", "uid": hit.uid, "path": f.path, "level": float(lk.get("level", 0.0)), "center": c}
		editor.history.begin_gesture("LAKE LEVEL")
	else:
		var sg: Vector2 = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)][clampi(hit.sub - 1, 0, 3)]
		_lake = {"kind": "corner", "uid": hit.uid, "path": f.path, "fixed": c - sg * s * 0.5}
		editor.history.begin_gesture("LAKE SIZE")
	return true


func _lake_move(hit: EditorHit) -> void:
	match str(_lake.get("kind", "")):
		"new":
			var p := ground_of(hit)
			if not is_nan(p.x):
				_lake.b = p
			editor.redraw()
		"level":
			var y := _ray_height(hit, _lake.center)
			if is_nan(y):
				return
			y = clampf(snappedf(y, 0.05), LevelDoc.HEIGHT_MIN, LevelDoc.HEIGHT_MAX)
			_lake.level = y
			editor.commit("LAKE LEVEL", [LevelDoc.op_set((_lake.path as Array) + ["level"], y)])
			_lake["moved"] = true
		"corner":
			var p := ground_of(hit)
			if is_nan(p.x):
				return
			var fx: Vector2 = _lake.fixed
			var lo := Vector2(minf(fx.x, p.x), minf(fx.y, p.y))
			var hi := Vector2(maxf(fx.x, p.x), maxf(fx.y, p.y))
			var sz := Vector2(clampf(hi.x - lo.x, LAKE_MIN, LAKE_MAX), clampf(hi.y - lo.y, LAKE_MIN, LAKE_MAX))
			var c := (lo + hi) * 0.5
			var path: Array = _lake.path
			editor.commit("LAKE SIZE", [LevelDoc.op_set(path + ["center"], [snappedf(c.x, 0.001), snappedf(c.y, 0.001)]),
				LevelDoc.op_set(path + ["size"], [snappedf(sz.x, 0.01), snappedf(sz.y, 0.01)])])
			_lake["moved"] = true


func _lake_end() -> void:
	var lk := _lake
	_lake = {}
	if lk.get("kind") == "new":
		var a: Vector2 = lk.a
		var b: Vector2 = lk.b
		if a.distance_to(b) > 1.0:
			add_lake(a, b)
		editor.redraw()
		return
	editor.history.end_gesture()
	succeeded()


## Where the ray of hit crosses the vertical plane through c facing the camera (a height).
func _ray_height(hit: EditorHit, c: Vector2) -> float:
	var dir := hit.ray_dir
	if dir.length_squared() < 1e-9:
		return hit.pos.y if hit.hit else NAN
	var n := Vector3(dir.x, 0.0, dir.z)
	if n.length_squared() < 1e-6:
		return NAN  # looking straight down: no height from the mouse
	n = n.normalized()
	var den := n.dot(dir)
	if absf(den) < 1e-6:
		return NAN
	var tt := n.dot(Vector3(c.x, 0.0, c.y) - hit.ray_from) / den
	return (hit.ray_from + dir * tt).y


func _refresh_options() -> void:
	if editor != null and editor.ui != null and editor.tool == self:
		editor.ui.refresh_tool()


func _save() -> void:
	for k in ["brush", "size", "strength", "falloff", "noise_scale", "noise_seed", "follow", "target"]:
		_keep[k] = get(k)


func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0


## RESIZE WORLD: the allowed (size, resolution) pairs (2.3); OK resamples the ground (one undo step).
class ResizeDialog:
	extends Dialog
	var tool: TerrainTool
	var pick := 0

	func _init(t: TerrainTool) -> void:
		super("RESIZE WORLD", Vector2(560, 420))
		tool = t
		var doc := t.editor.doc
		var l := UiKit.label("The ground is resampled; roads and objects stay where they are.", 16, UiKit.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 500
		body.add_child(l)
		var group := ButtonGroup.new()
		var first: Button = null
		for i in LevelDoc.WORLDS.size():
			var p: Array = LevelDoc.WORLDS[i]
			var cell := float(p[0]) / (int(p[1]) - 1)
			var b := UiKit.button("%d m   ·   %d x %d   ·   %d m CELLS" % [int(p[0]), int(p[1]), int(p[1]), int(cell)], 500)
			b.toggle_mode = true
			b.button_group = group
			var cur := is_equal_approx(float(p[0]), doc.world_size()) and int(p[1]) == doc.res()
			b.button_pressed = cur
			if cur:
				pick = i
				first = b
			var idx := i
			b.pressed.connect(func() -> void: pick = idx)
			body.add_child(b)
			if first == null and i == 0:
				first = b
		default_focus = first
		add_button("RESIZE", func() -> void:
			var p: Array = LevelDoc.WORLDS[pick]
			close()
			tool.resize_world(float(p[0]), int(p[1])))
		add_button("CANCEL", close)
