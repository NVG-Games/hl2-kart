class_name CrowdsTool
extends EditorTool
## 1.6 CROWDS: spectator groups and the extras (eggs). GROUP mode: a click on a road or on the
## ground within 30 m of its edge puts a 20 m group on that side (anchored, 2.3); its marker
## slides along the road and its two end bars change its length. EXTRAS modes place an egg where
## you click (G-Man, birds, gnome, zombies, hologram, Lamarr, Nihilanth); the path eggs (zombies,
## Lamarr) take Ctrl + click points. Tool options show "PEOPLE n / 450" from the last bake
## (red past 450). P17.

const MODES := ["group", "gman", "birds", "gnome", "zombies", "holo", "lamarr", "nihilanth"]
const MODE_NAMES := ["GROUP", "G-MAN", "BIRDS", "GNOME", "ZOMBIES", "HOLOGRAM", "LAMARR", "NIHILANTH"]
const ROLE_NAMES := ["CITIZENS", "REFUGEES", "REBELS", "METROCOPS", "COMBINE", "SCIENTISTS", "GUARDS", "VORTIGAUNTS",
	"ALIEN SLAVES", "SOLDIERS (HECU)", "ZOMBIES", "CAMEOS"]
const MOOD_NAMES := ["FANS", "POLITE", "EXCITED", "LOYAL", "MILITARY", "CHANTING", "SCARED"]
const SPECIES_NAMES := ["PIGEONS", "CROWS", "SEAGULLS", "BOIDS"]
const PATH_KINDS := ["zombies", "lamarr"]
const EGG_NAMES := {"gman": "G-MAN", "birds": "BIRDS", "gnome": "GNOME", "zombies": "ZOMBIES", "holo": "HOLOGRAM",
	"lamarr": "LAMARR", "nihilanth": "NIHILANTH"}
const CAP_GROUPS := 100
const CAP_EGGS := 24
const CAP_PATH := 16
const PEOPLE_BUDGET := 450
const PEOPLE_CAP := 600
const REACH := 30.0             # a click this far past a road's edge still makes a group on it
const GROUP_LEN := 20.0
const LEN_MIN := 6.0
const LEN_MAX := 120.0
const ROW_M := 0.9              # metres per row (LevelCrowds: setback + 0.9 r)
const NIHILANTH_UP := 20.0
const GROUP_COLOR := Color(0.75, 0.55, 1.0)
const EGG_COLOR := Color(0.45, 1.0, 0.6)
const PATH_COLOR := Color(0.45, 1.0, 0.6, 0.8)

var mode := "group"
var _h: ItemsTool               # the road-spot helpers (a private instance, never in editor.tools)
var _drag := {}
var _slide := {}
var _last_egg := 0              # the last path egg placed: Ctrl + click adds its points
var _people_label: Label
var _insp_people: PromptLabel   # the inspector's PEOPLE line (kept current after each bake too)


func _init(ed: TrackEditor) -> void:
	super(ed)
	id = "crowds"
	title = "CROWDS"
	purpose = "Spectators beside the road, and the extras (G-Man, birds, zombies...)"
	_h = ItemsTool.new(ed)


func kinds() -> PackedStringArray:
	return PackedStringArray(["crowd", "egg"])


func activate() -> void:
	if editor != null and not editor.baked.is_connected(_on_baked):
		editor.baked.connect(_on_baked)


func deactivate() -> void:
	_end_drag()
	if editor != null and editor.baked.is_connected(_on_baked):
		editor.baked.disconnect(_on_baked)


func _on_baked(_b: LevelBuild) -> void:
	_update_people()


# ---------------------------------------------------------------- placing

func click(hit: EditorHit, mods: int) -> bool:
	if editor == null or editor.doc == null or hit == null:
		return false
	if has_mod(mods, MOD_CTRL) and hit.hit and hit.what != "marker" and hit.what != "gizmo":
		var eu := path_egg()
		if eu > 0:
			add_path_point(eu, hit.pos)
			return true
	if hit.what == "marker" or hit.what == "gizmo" or not hit.hit:
		return false
	if mode == "group":
		if hit.what == "prop":
			return false
		var sp := _h.road_spot(hit, REACH)
		if sp.is_empty():
			editor.status("Click on a road or right beside it." if editor.build != null else "Wait for the track to bake.")
			return true
		return place_group(sp) > 0
	if hit.what == "water":
		editor.status("Extras stand on the ground, not on the water.")
		return true
	return place_egg(mode, hit.pos) > 0


## A 20 m group on the clicked side of the road (2 rows, density 1, setback 2.5, citizens, fans).
func place_group(sp: Dictionary) -> int:
	if _h.list_of("crowds").size() >= CAP_GROUPS:
		editor.toast("Limit reached (%d crowd groups)" % CAP_GROUPS)
		return 0
	var r := _h.full_road(int(sp.key))
	if r == null:
		return 0
	var u := editor.doc.new_uid()
	var g := {"uid": u, "road": int(sp.key), "at": ItemsTool.anchor_of(r, float(sp.s)), "side": 1 if float(sp.lat) >= 0.0 else -1,
		"length": GROUP_LEN, "rows": 2, "density": 1.0, "setback": 2.5, "role": "citizen", "mood": "fan", "sit": 0.0, "tags": []}
	editor.commit("ADD CROWD", [ItemsTool.op_add("crowds", g)])
	editor.select(PackedInt32Array([u]))
	succeeded()
	return u


## An egg of `kind` at p (facing the nearest road); path eggs start their path there.
func place_egg(kind: String, p: Vector3) -> int:
	if not (kind in EGG_NAMES):
		return 0
	if _h.list_of("eggs").size() >= CAP_EGGS:
		editor.toast("Limit reached (%d extras)" % CAP_EGGS)
		return 0
	var at := p + (Vector3.UP * NIHILANTH_UP if kind == "nihilanth" else Vector3.ZERO)
	var u := editor.doc.new_uid()
	var e := {"uid": u, "kind": kind, "pos": ItemsTool._arr(at), "yaw": snappedf(face_road(p), 0.1)}
	match kind:
		"gman":
			e["chance"] = 0.5
		"birds":
			e["species"] = "pigeon"
			e["radius"] = 12.0
			e["count"] = 8
		"zombies":
			e["path"] = [ItemsTool._arr(p)]
			e["count"] = 3
		"lamarr":
			e["path"] = [ItemsTool._arr(p)]
	editor.commit("ADD %s" % str(EGG_NAMES[kind]), [ItemsTool.op_add("eggs", e)])
	if kind in PATH_KINDS:
		_last_egg = u
	editor.select(PackedInt32Array([u]))
	succeeded()
	return u


## The path egg Ctrl + click adds to: the selected one, else the last placed (0 none).
func path_egg() -> int:
	if editor.selection != null:
		for u in editor.selection.uids:
			var e := _h.item_of("eggs", u)
			if str(e.get("kind", "")) in PATH_KINDS:
				return u
	var last := _h.item_of("eggs", _last_egg)
	if str(last.get("kind", "")) in PATH_KINDS:
		return _last_egg
	return 0


func add_path_point(uid: int, p: Vector3) -> void:
	var e := _h.item_of("eggs", uid)
	var path: Array = (e.get("path", []) as Array).duplicate(true) if e.get("path") is Array else []
	if path.size() >= CAP_PATH:
		editor.status("A path has at most %d points." % CAP_PATH)
		return
	path.append(ItemsTool._arr(p))
	editor.commit("ADD PATH POINT", [ItemsTool.op_field("eggs", uid, "path", path)])


## Degrees of yaw that turn a model's front (+Z) toward the nearest road sample.
func face_road(p: Vector3) -> float:
	var best := INF
	var to := Vector3.ZERO
	if editor != null and editor.build != null:
		for r in editor.build.roads:
			if r == null or r.partial or r.n <= 0:
				continue
			var i := r.closest(p)
			var d := Vector2(r.pos[i].x - p.x, r.pos[i].z - p.z).length()
			if d < best:
				best = d
				to = r.pos[i] - p
	if best == INF or Vector2(to.x, to.z).length() < 0.01:
		return 0.0
	return rad_to_deg(atan2(to.x, to.z))


# ---------------------------------------------------------------- hover

func hints(hit: EditorHit) -> Array:
	if hit != null and hit.what == "marker":
		if hit.kind == "issue":
			return [["CLICK SHOW THE PROBLEM"]]
		if hit.kind == "crowd":
			if hit.sub in [3, 4]:
				return [["DRAG MOVE THIS END"], ["CLICK SELECT"]]
			return [["CLICK SELECT"], ["DRAG SLIDE ALONG THE ROAD"], ["{ed_delete} DELETE"]]
		if hit.kind == "egg":
			return [["CLICK SELECT"], ["DRAG MOVE"], ["{ed_delete} DELETE"]]
		return [["CLICK SELECT"]]
	var out := []
	if mode == "group":
		out.append(["CLICK BESIDE A ROAD: A CROWD ON THAT SIDE"])
	else:
		out.append(["CLICK PLACE %s" % str(EGG_NAMES.get(mode, mode.to_upper()))])
	if path_egg() > 0:
		out.append(["{ed_mod_ctrl} CLICK ADD A PATH POINT"])
	return out


func status_step() -> String:
	if mode == "group":
		return "Click beside a road for a crowd on that side; drag its end bars to make it longer"
	if mode in PATH_KINDS:
		return "Click to place, then {ed_mod_ctrl} + click to add the points of its path"
	return "Click to place %s" % str(EGG_NAMES.get(mode, mode.to_upper()))


# ---------------------------------------------------------------- markers and overlay

## {s, l, r, i, lat_in, lat_out} of a group on its road ({} unknown).
func group_span(g: Dictionary) -> Dictionary:
	var r := _h.full_road(int(g.get("road", -1)))
	if r == null or not (g.get("at") is Dictionary) or r.n <= 0:
		return {}
	var s := r.anchor_s(g.at)
	var i := r.idx(s)
	var side := -1 if int(g.get("side", 1)) < 0 else 1
	var edge := r.width[i] * 0.5 + r.treatment(i, side)
	var inner := edge + float(g.get("setback", 2.5))
	var outer := inner + ROW_M * maxf(float(g.get("rows", 2)), 1.0)
	return {"r": r, "s": s, "l": float(g.get("length", GROUP_LEN)), "i": i, "side": side,
		"lat_in": inner * side, "lat_out": outer * side}


func markers(m: EditorMarkers) -> void:
	if editor == null or editor.doc == null:
		return
	for g in _h.list_of("crowds"):
		if not (g is Dictionary):
			continue
		var sp := group_span(g)
		if sp.is_empty():
			continue
		var r: LevelRoad = sp.r
		var u := int(g.uid)
		var mid := (float(sp.lat_in) + float(sp.lat_out)) * 0.5
		m.add("crowd", u, r.surface(int(sp.i), mid, 1.0), EditorMarkers.Shape.DIAMOND, GROUP_COLOR, 2.0, 0)
		var sa := ItemsTool.wrap_s(r, float(sp.s) - float(sp.l) * 0.5)
		var sb := ItemsTool.wrap_s(r, float(sp.s) + float(sp.l) * 0.5)
		m.add("crowd", u, r.surface(r.idx(sa), mid, 0.5), EditorMarkers.Shape.BAR, GROUP_COLOR, 3.0, 3)
		m.add("crowd", u, r.surface(r.idx(sb), mid, 0.5), EditorMarkers.Shape.BAR, GROUP_COLOR, 3.0, 4)
	for e in _h.list_of("eggs"):
		if not (e is Dictionary):
			continue
		var u := int(e.uid)
		m.add("egg", u, ItemsTool._v3(e.get("pos")), EditorMarkers.Shape.RING, EGG_COLOR, 2.0, 0)
		var path = e.get("path")
		if path is Array:
			for k in (path as Array).size():
				m.add("egg", u, ItemsTool._v3(path[k]), EditorMarkers.Shape.DOT, PATH_COLOR, 1.0, 10 + k)


func overlay(d: EditorDraw) -> void:
	if editor == null or editor.doc == null:
		return
	for g in _h.list_of("crowds"):
		if not (g is Dictionary):
			continue
		var sp := group_span(g)
		if sp.is_empty():
			continue
		var r: LevelRoad = sp.r
		var sel := editor.selection != null and editor.selection.has(int(g.uid))
		var col := Color(GROUP_COLOR, 0.4 if sel else 0.2)
		var lo := minf(float(sp.lat_in), float(sp.lat_out))
		var hi := maxf(float(sp.lat_in), float(sp.lat_out))
		var s0 := float(sp.s) - float(sp.l) * 0.5
		var s1 := float(sp.s) + float(sp.l) * 0.5
		# on the ground where it is higher than the road's plane (hills beside the road)
		var gt := editor.terrain()
		if r.closed and (s0 < 0.0 or s1 > r.length):
			var a := ItemsTool.wrap_s(r, s0)
			var b := ItemsTool.wrap_s(r, s1)
			d.strip_on_road(r, a, r.length, lo, hi, col, gt)
			d.strip_on_road(r, 0.0, b, lo, hi, col, gt)
		else:
			d.strip_on_road(r, maxf(s0, 0.0), minf(s1, r.length), lo, hi, col, gt)
	for e in _h.list_of("eggs"):
		if not (e is Dictionary):
			continue
		var p := ItemsTool._v3(e.get("pos"))
		var path = e.get("path")
		if path is Array and (path as Array).size() > 1:
			var pts := PackedVector3Array()
			for q in path:
				pts.append(ItemsTool._v3(q) + Vector3.UP * 0.3)
			d.polyline(pts, PATH_COLOR, false, true)
		if str(e.get("kind", "")) == "birds":
			d.circle(p + Vector3.UP * 0.3, Vector3.UP, float(e.get("radius", 12.0)), Color(EGG_COLOR, 0.6))


# ---------------------------------------------------------------- moving

func drag_begin(hit: EditorHit, _mods: int) -> bool:
	if editor == null or editor.doc == null or hit == null:
		return false
	if hit.what != "marker" or not owns(hit.kind) or hit.uid <= 0:
		return false
	if not editor.selection.has(hit.uid):
		editor.select(PackedInt32Array([hit.uid]))
	if hit.kind == "egg":
		var e := _h.item_of("eggs", hit.uid)
		var nm := "MOVE PATH POINT" if hit.sub >= 10 else "MOVE %s" % str(EGG_NAMES.get(str(e.get("kind", "")), "EXTRA"))
		editor.history.begin_gesture(nm)
		_drag = {"uid": hit.uid, "how": "egg", "sub": hit.sub, "name": nm, "start": ItemsTool._v3(e.get("pos")),
			"from": hit.pos}
		return true
	editor.history.begin_gesture("MOVE CROWD")
	_drag = {"uid": hit.uid, "how": "slide", "name": "MOVE CROWD"}
	slide(hit.uid, hit, 0)
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
	if _drag.how == "egg":
		if not hit.hit:
			return
		var u := int(_drag.uid)
		var sub := int(_drag.sub)
		if sub >= 10:
			var e := _h.item_of("eggs", u)
			var path: Array = (e.get("path", []) as Array).duplicate(true) if e.get("path") is Array else []
			if sub - 10 < path.size():
				path[sub - 10] = ItemsTool._arr(hit.pos)
				editor.commit(str(_drag.name), [ItemsTool.op_field("eggs", u, "path", path)], "crowds_drag")
			return
		var e2 := _h.item_of("eggs", u)
		var up := NIHILANTH_UP if str(e2.get("kind", "")) == "nihilanth" else 0.0
		editor.commit(str(_drag.name), [ItemsTool.op_field("eggs", u, "pos", ItemsTool._arr(hit.pos + Vector3.UP * up))], "crowds_drag")
		return
	var ops := slide(int(_drag.uid), hit, phase)
	if not ops.is_empty():
		editor.commit(str(_drag.name), ops, "crowds_drag")


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


## A group's marker dragged (here or from SELECT): its middle slides it along its road, an end bar
## (sub 3 / 4) moves that end (the other one stays; 6-120 m).
func slide(uid: int, hit: EditorHit, phase: int) -> Array:
	if editor == null or editor.doc == null or hit == null:
		return []
	var g := _h.item_of("crowds", uid)
	if g.is_empty():
		return []
	var sp := group_span(g)
	if sp.is_empty():
		return []
	var r: LevelRoad = sp.r
	if phase == 0 or _slide.is_empty() or int(_slide.get("uid", 0)) != uid:
		_slide = {"uid": uid, "sub": hit.sub, "s0": ItemsTool.s_near(r, hit.pos), "s": float(sp.s), "l": float(sp.l)}
		if phase == 0:
			return []
	var s := ItemsTool.s_near(r, hit.pos)
	var out := []
	var sub := int(_slide.sub)
	if sub == 3 or sub == 4:
		var c := float(_slide.s)
		var half := float(_slide.l) * 0.5
		var other := c + half if sub == 3 else c - half
		var d := ItemsTool.delta_s(r, other, s) if r.closed else s - other
		var nl := clampf(absf(d), LEN_MIN, LEN_MAX)
		var nc := other + signf(d if d != 0.0 else (-1.0 if sub == 3 else 1.0)) * nl * 0.5
		out.append(ItemsTool.op_field("crowds", uid, "at", ItemsTool.anchor_of(r, nc)))
		out.append(ItemsTool.op_field("crowds", uid, "length", snappedf(nl, 0.1)))
	else:
		var ds := ItemsTool.delta_s(r, float(_slide.s0), s) if r.closed else s - float(_slide.s0)
		out.append(ItemsTool.op_field("crowds", uid, "at", ItemsTool.anchor_of(r, float(_slide.s) + ds)))
	if phase == 2:
		_slide = {}
	return out


# ---------------------------------------------------------------- deleting, boxes

func delete_ops(uids: PackedInt32Array) -> Array:
	var out := []
	if editor == null or editor.doc == null:
		return out
	for u in uids:
		var sec := str(editor.doc.find(u).get("section", ""))
		if sec == "crowds" or sec == "eggs":
			out.append(ItemsTool.op_del(sec, u))
	return out


func item_aabb(uid: int) -> AABB:
	var g := _h.item_of("crowds", uid)
	if not g.is_empty():
		var sp := group_span(g)
		if sp.is_empty():
			return AABB()
		var r: LevelRoad = sp.r
		var mid := (float(sp.lat_in) + float(sp.lat_out)) * 0.5
		var a := r.surface(r.idx(ItemsTool.wrap_s(r, float(sp.s) - float(sp.l) * 0.5)), mid, 0.0)
		var b := r.surface(r.idx(ItemsTool.wrap_s(r, float(sp.s) + float(sp.l) * 0.5)), mid, 2.0)
		return AABB(a, Vector3.ZERO).expand(b).grow(2.0)
	var e := _h.item_of("eggs", uid)
	if not e.is_empty():
		var p := ItemsTool._v3(e.get("pos"))
		var box := AABB(p - Vector3(1, 0, 1), Vector3(2, 2, 2))
		var path = e.get("path")
		if path is Array:
			for q in path:
				box = box.expand(ItemsTool._v3(q))
		if str(e.get("kind", "")) == "birds":
			box = box.grow(float(e.get("radius", 12.0)))
		return box
	return AABB()


func on_doc_changed(_sections: PackedStringArray, _uids: PackedInt32Array) -> void:
	_update_people()


# ---------------------------------------------------------------- options and inspector

func options(box: VBoxContainer) -> void:
	if editor == null or editor.doc == null:
		return
	box.add_child(EditorKit.section("PLACE"))
	box.add_child(EditorKit.modes(MODE_NAMES.slice(0, 4), MODES.slice(0, 4).find(mode),
		func(i: int) -> void: set_mode(MODES[i])))
	box.add_child(EditorKit.modes(MODE_NAMES.slice(4), MODES.slice(4).find(mode),
		func(i: int) -> void: set_mode(MODES[4 + i])))
	_people_label = UiKit.label("", EditorKit.FONT_SMALL, UiKit.TEXT, true)
	box.add_child(_people_label)
	_update_people()
	box.add_child(EditorKit.hint("CLICK BESIDE A ROAD: A CROWD · DRAG ITS END BARS: LONGER · {ed_mod_ctrl} + CLICK: A PATH POINT (ZOMBIES, LAMARR)"))


func set_mode(m: String) -> void:
	if not (m in MODES):
		return
	mode = m
	if editor != null and editor.ui != null:
		editor.ui.refresh_tool()


## The people the last bake placed (stats.people).
func people() -> int:
	if editor == null or editor.build == null:
		return 0
	return int(editor.build.stats.get("people", 0))


## "PEOPLE 212 / 450" (red past the budget).
func people_text() -> String:
	return "PEOPLE %d / %d" % [people(), PEOPLE_BUDGET]


func _update_people() -> void:
	if _insp_people != null and is_instance_valid(_insp_people):
		_insp_people.prompt = people_text()
	if _people_label == null or not is_instance_valid(_people_label):
		return
	_people_label.text = people_text()
	_people_label.add_theme_color_override("font_color", EditorKit.ERROR_COLOR if people() > PEOPLE_BUDGET else UiKit.TEXT)


func inspect(uids: PackedInt32Array, box: VBoxContainer) -> bool:
	if editor == null or editor.doc == null or uids.is_empty():
		return false
	var k := editor.kind_of(uids[0])
	if k == "crowd":
		_group_inspector(uids, box)
		return true
	if k == "egg":
		_egg_inspector(uids[0], box)
		return true
	return false


func _group_inspector(uids: PackedInt32Array, box: VBoxContainer) -> void:
	var same := PackedInt32Array()
	for u in uids:
		if editor.kind_of(u) == "crowd":
			same.append(u)
	var uid := same[0]
	var g := _h.item_of("crowds", uid)
	box.add_child(EditorKit.section("CROWD" if same.size() == 1 else "%d CROWDS" % same.size()))
	var roles: Array = LevelDoc.CROWD_ROLES
	var moods: Array = LevelDoc.CROWD_MOODS
	box.add_child(EditorKit.row("WHO", EditorKit.choice(ROLE_NAMES, roles.find(str(g.get("role", "citizen"))),
		func(i: int) -> void: editor.commit("CROWD WHO", _each(same, "role", roles[i])))))
	box.add_child(EditorKit.row("MOOD", EditorKit.choice(MOOD_NAMES, moods.find(str(g.get("mood", "fan"))),
		func(i: int) -> void: editor.commit("CROWD MOOD", _each(same, "mood", moods[i])))))
	box.add_child(EditorKit.row("SIDE", EditorKit.modes(["LEFT", "RIGHT"], 0 if int(g.get("side", 1)) < 0 else 1,
		func(i: int) -> void: editor.commit("CROWD SIDE", _each(same, "side", -1 if i == 0 else 1)))))
	box.add_child(EditorKit.row("ROWS", EditorKit.number(float(g.get("rows", 2)), 1, 4, 1, func(v: float) -> void:
		editor.commit("CROWD ROWS", _each(same, "rows", int(v)), "insp_rows_%d" % uid), "%d")))
	box.add_child(EditorKit.row("DENSITY", EditorKit.number(float(g.get("density", 1.0)), 0.5, 2.0, 0.1, func(v: float) -> void:
		editor.commit("CROWD DENSITY", _each(same, "density", snappedf(v, 0.01)), "insp_density_%d" % uid), "%.1f", " /m")))
	box.add_child(EditorKit.row("SETBACK", EditorKit.number(float(g.get("setback", 2.5)), 0.5, 20.0, 0.5, func(v: float) -> void:
		editor.commit("CROWD SETBACK", _each(same, "setback", snappedf(v, 0.01)), "insp_setback_%d" % uid), "%.1f", " m")))
	box.add_child(EditorKit.row("LENGTH", EditorKit.number(float(g.get("length", GROUP_LEN)), LEN_MIN, LEN_MAX, 1.0, func(v: float) -> void:
		editor.commit("CROWD LENGTH", _each(same, "length", snappedf(v, 0.1)), "insp_length_%d" % uid), "%d", " m")))
	box.add_child(EditorKit.row("SEATED", EditorKit.slider(0, 100, 5, roundf(float(g.get("sit", 0.0)) * 100.0), func(v: float) -> void:
		editor.commit("CROWD SEATED", _each(same, "sit", snappedf(v / 100.0, 0.01)), "insp_sit_%d" % uid), "%d %%")))
	var tags: Array = g.get("tags", []) if g.get("tags") is Array else []
	for pair in [["CHEER THE START", "start"], ["WATCH THE JUMP", "jump"]]:
		var tag: String = pair[1]
		box.add_child(EditorKit.row(pair[0], EditorKit.check(tag in tags, func(on: bool) -> void:
			var ops := []
			for u in same:
				var cur = _h.item_of("crowds", u).get("tags", [])
				var nt: Array = (cur as Array).duplicate() if cur is Array else []
				if on and not (tag in nt):
					nt.append(tag)
				elif not on:
					nt.erase(tag)
				ops.append(ItemsTool.op_field("crowds", u, "tags", nt))
			editor.commit("CROWD TAGS", ops))))
	_insp_people = EditorKit.hint(people_text())
	_insp_people.name = "People"
	box.add_child(_insp_people)
	# built before the bake that places the people (and in SELECT): the next bakes update it
	if not editor.baked.is_connected(_on_baked):
		editor.baked.connect(_on_baked)


func _egg_inspector(uid: int, box: VBoxContainer) -> void:
	var e := _h.item_of("eggs", uid)
	if e.is_empty():
		return
	var kind := str(e.get("kind", ""))
	box.add_child(EditorKit.section(str(EGG_NAMES.get(kind, kind.to_upper()))))
	box.add_child(EditorKit.row("POSITION", EditorKit.vec3(ItemsTool._v3(e.get("pos")), func(v: Vector3) -> void:
		editor.commit("MOVE EXTRA", [ItemsTool.op_field("eggs", uid, "pos", ItemsTool._arr(v))], "insp_pos_%d" % uid))))
	box.add_child(EditorKit.row("YAW", EditorKit.number(float(e.get("yaw", 0.0)), -180.0, 180.0, 5.0, func(v: float) -> void:
		editor.commit("TURN EXTRA", [ItemsTool.op_field("eggs", uid, "yaw", snappedf(v, 0.1))], "insp_yaw_%d" % uid), "%d", "°")))
	match kind:
		"gman":
			box.add_child(EditorKit.row("CHANCE", EditorKit.slider(0, 100, 5, roundf(float(e.get("chance", 0.5)) * 100.0), func(v: float) -> void:
				editor.commit("G-MAN CHANCE", [ItemsTool.op_field("eggs", uid, "chance", snappedf(v / 100.0, 0.01))], "insp_chance_%d" % uid), "%d %%")))
		"birds":
			var sp: Array = LevelDoc.SPECIES
			box.add_child(EditorKit.row("SPECIES", EditorKit.choice(SPECIES_NAMES, sp.find(str(e.get("species", "pigeon"))),
				func(i: int) -> void: editor.commit("BIRDS", [ItemsTool.op_field("eggs", uid, "species", sp[i])]))))
			box.add_child(EditorKit.row("RADIUS", EditorKit.number(float(e.get("radius", 12.0)), 4.0, 60.0, 1.0, func(v: float) -> void:
				editor.commit("BIRDS RADIUS", [ItemsTool.op_field("eggs", uid, "radius", snappedf(v, 0.1))], "insp_radius_%d" % uid), "%d", " m")))
	if kind == "birds" or kind == "zombies":
		box.add_child(EditorKit.row("COUNT", EditorKit.number(float(e.get("count", 8 if kind == "birds" else 3)), 1, 40, 1, func(v: float) -> void:
			editor.commit("EXTRA COUNT", [ItemsTool.op_field("eggs", uid, "count", int(v))], "insp_count_%d" % uid), "%d")))
	if kind in PATH_KINDS:
		var n := (e.get("path", []) as Array).size() if e.get("path") is Array else 0
		box.add_child(EditorKit.hint("PATH: %d POINT%s · {ed_mod_ctrl} + CLICK ADDS ONE" % [n, "" if n == 1 else "S"]))
		box.add_child(EditorKit.button("CLEAR PATH", func() -> void:
			var p0 := ItemsTool._v3(_h.item_of("eggs", uid).get("pos"))
			editor.commit("CLEAR PATH", [ItemsTool.op_field("eggs", uid, "path", [ItemsTool._arr(p0)])])))
	if kind == "holo":
		box.add_child(EditorKit.hint("The hologram plays beside the nearest jump of the nearest road."))


func _each(uids: PackedInt32Array, field: String, value: Variant) -> Array:
	var out := []
	for u in uids:
		if not _h.item_of("crowds", u).is_empty():
			out.append(ItemsTool.op_field("crowds", u, field, value))
	return out
