class_name HazardsTool
extends EditorTool
## 1.6 HAZARDS: traps and Half-Life enemies on the main road (4.2). Tool options list every type
## grouped TURRETS & SOLDIERS / COMBINE MACHINES / CREATURES / TRAPS / TRAINS & BRIDGES with its
## one-line description (heavy ones say "HEAVY: 2 of 8"). With a setup type chosen the main road
## is tinted green / red from `editor.flags("hz_<key>")` and a click on red is refused with the
## reason in the status line. A click on the road places the chosen type at that spot, on the
## clicked side; its setup comes in the same undo step (a see-saw turns its segment into the
## stretch through LevelHazards.seesaw_ops, antlions paint their 16 m sand band through
## LevelBrush.band_splat; the compiler builds the rest). A hazard is a triangle marker; its zone a
## translucent strip with two end bars (drag them along the road); types with points (apache hover,
## mines, the arc's core, antlion thumpers) show them as dots: Ctrl + click adds one to the selected
## hazard, Delete removes the selected point. Inspector: TYPE, MOUNT / STYLE, SIDE, ZONE,
## DIFFICULTY (EASY / NORMAL / BRUTAL writes p from LevelHazards.difficulty_p), ADVANCED (SETBACK
## and the type's params and inputs from TYPES; editing a param makes it CUSTOM) and the compile's
## lint lines for it. P19.

const GROUPS := ["TURRETS & SOLDIERS", "COMBINE MACHINES", "CREATURES", "TRAPS", "TRAINS & BRIDGES"]
## Each group's icon (EditorKit.icon names): its heading in the options, its hazards' outliner rows.
const GROUP_ICONS := {"TURRETS & SOLDIERS": "crosshair", "COMBINE MACHINES": "machine", "CREATURES": "creature",
	"TRAPS": "trap", "TRAINS & BRIDGES": "train"}
const SECTION := "hazards"
## Hard caps (2.10): hazards, heavy ones (LevelDoc.CAPS.heavy), points per hazard.
const CAP := 48
const HEAVY_CAP := 8
## The sand band antlions paint (4.2) and the layer it uses.
const SAND_WIDTH := 16.0
## Sub ids of a hazard's markers: 0 the hazard, 3 / 4 its zone's end bars, POINT_SUB + k its points.
const SUB_A := 3
const SUB_B := 4
const POINT_SUB := 10
const MIN_ZONE := 10.0
## Hover points' default height over the road (apache: h 40-60).
const HOVER_H := 50.0
## The arc core's height over the click, and how far from the road the thumper may stand.
const CORE_UP := 5.0
const THUMPER_REACH := 40.0
const HAZARD_COLOR := Color(1.0, 0.42, 0.18)
const POINT_COLOR := Color(1.0, 0.75, 0.3)
const ZONE_COLOR := Color(1.0, 0.35, 0.15)
const LINT_COLOR := Color(1.0, 0.82, 0.2)
const ERROR_COLOR := Color(0.92, 0.2, 0.16)
const OK_TINT := Color(0.25, 0.85, 0.35, 0.32)
const BAD_TINT := Color(0.95, 0.2, 0.15, 0.32)
const RING_COLOR := Color(1.0, 0.45, 0.2, 0.55)
## The names a setup key goes by in a refusal ("A ceiling turret needs a tunnel.").
const SETUP_NOUN := {"turret_ceiling": "A ceiling turret", "tripmine": "A tripmine", "tentacle": "A tentacle",
	"antlion": "Antlions", "column": "A Combine column", "seesaw": "A see-saw bridge", "train": "A level crossing"}
## What each kind of point is called in hints and the inspector.
const POINT_NOUN := {"hover": "HOVER POINT", "mines": "MINE", "core": "CORE", "thumpers": "THUMPER"}
const FEELS := ["easy", "normal", "brutal"]
const FEEL_NAMES := ["EASY", "NORMAL", "BRUTAL"]

## The ADVANCED rows are shown (kept across rebuilds and tool switches).
static var advanced_open := false
static var _choices: Array = []

## The chosen entry of the list (a CHOICES id).
var choice := "turret"
## The hazard point picked last: {uid, k} ({} none). Delete removes it while its hazard is selected.
var point := {}
## Why the last click was refused ("" none).
var refusal := ""
var _h: ItemsTool               # the road-spot helpers (a private instance, never in editor.tools)
var _drag := {}                 # a marker drag of this tool: {uid, name}
var _slide := {}                # {uid, sub, s0, at, za, zb}
var _last := 0                  # the hazard placed last (Ctrl + click adds its points when nothing is selected)
var _counts: Label
var _desc_line := ""
var _models := {}               # uid -> the view's stand-in model of a hazard (sync_models)
var _models_root: Node3D


func _init(ed: TrackEditor) -> void:
	super(ed)
	id = "hazards"
	title = "HAZARDS"
	purpose = "Traps and Half-Life enemies along the road"
	_h = ItemsTool.new(ed)


func kinds() -> PackedStringArray:
	return PackedStringArray(["hazard", "hazard_point"])


func deactivate() -> void:
	_end_drag()


# ---------------------------------------------------------------- the list

## A hazard type's icon: its group's ("tool_hazards" for an unknown type).
static func icon_of(type: String) -> String:
	var td = LevelHazards.TYPES.get(type)
	return str(GROUP_ICONS.get(str(td.get("group", "")), "tool_hazards")) if td is Dictionary else "tool_hazards"


## The entries of the list: [{id, type, mount, style, label, group, desc, heavy, setup}] in the
## groups' order; the turret is FLOOR and CEILING, the strike zone MORTAR and ARC.
static func choices() -> Array:
	if not _choices.is_empty():
		return _choices
	var out := []
	for g in GROUPS:
		for ty in LevelHazards.TYPES:
			var td: Dictionary = LevelHazards.TYPES[ty]
			if str(td.group) != g:
				continue
			var base := {"id": ty, "type": ty, "mount": "", "style": "", "label": str(td.label), "group": g,
				"desc": str(td.desc), "heavy": bool(td.heavy), "setup": str(td.setup)}
			if ty == "turret":
				var fl := base.duplicate()
				fl.mount = "floor"
				fl.desc = "A sentry gun beside the road that locks on and fires a burst."
				out.append(fl)
				var ce := base.duplicate()
				ce.id = "turret_ceiling"
				ce.mount = "ceiling"
				ce.label = "CEILING TURRET"
				ce.setup = "turret_ceiling"
				ce.desc = "A turret hanging upside down from a tunnel's ceiling, firing at the karts below."
				out.append(ce)
			elif ty == "strike_zone":
				var mo := base.duplicate()
				mo.style = "mortar"
				mo.label = "MORTAR ZONE"
				mo.desc = "Mortar shells land on marked spots of the road in its zone."
				out.append(mo)
				var ar := base.duplicate()
				ar.id = "strike_arc"
				ar.style = "arc"
				ar.label = "ARC ZONE"
				ar.desc = "Arcs from a Combine core beside the road strike marked spots in its zone."
				out.append(ar)
			else:
				out.append(base)
	_choices = out
	return out


## The entry of a list id ({} unknown).
static func choice_of(cid: String) -> Dictionary:
	for c in choices():
		if str(c.id) == cid:
			return c
	return {}


## The list entry a doc hazard belongs to.
static func choice_for(hz: Dictionary) -> Dictionary:
	var ty := str(hz.get("type", ""))
	if ty == "turret" and str(hz.get("mount", "floor")) == "ceiling":
		return choice_of("turret_ceiling")
	if ty == "strike_zone" and str(hz.get("style", "mortar")) == "arc":
		return choice_of("strike_arc")
	return choice_of(ty)


func set_choice(cid: String) -> void:
	if choice_of(cid).is_empty():
		return
	choice = cid
	refusal = ""
	if editor != null:
		if editor.ui != null:
			editor.ui.refresh_tool()
		editor.redraw()


## The setup key of the chosen entry ("" none).
func chosen_setup() -> String:
	return str(choice_of(choice).get("setup", ""))


# ---------------------------------------------------------------- the document

func list_of() -> Array:
	return _h.list_of(SECTION)


func item_of(uid: int) -> Dictionary:
	return _h.item_of(SECTION, uid)


func main_road() -> LevelRoad:
	return _h.full_road(-1)


static func td_of(hz: Dictionary) -> Dictionary:
	return LevelHazards.TYPES.get(str(hz.get("type", "")), {})


## How many heavy hazards the document has.
func heavy_count() -> int:
	var n := 0
	for hz in list_of():
		if hz is Dictionary and bool(td_of(hz).get("heavy", false)):
			n += 1
	return n


## "HAZARDS 6 / 48 · HEAVY 2 / 8"
func counts_text() -> String:
	return "HAZARDS %d / %d · HEAVY %d / %d" % [list_of().size(), CAP, heavy_count(), HEAVY_CAP]


## Lap metres of a hazard's own spot: its anchor, else its zone's middle (NAN when unknown).
func hazard_s(hz: Dictionary) -> float:
	var m := main_road()
	if m == null:
		return NAN
	if hz.get("at") is Dictionary:
		return m.anchor_s(hz.at)
	var z := zone_s(hz)
	if z.is_empty():
		return NAN
	return ItemsTool.wrap_s(m, (float(z[0]) + float(z[1])) * 0.5)


## The zone as lap metres [start, end] (end >= start, may pass the lap's end on a loop), the stored
## zone or the type's default round the hazard; [] for a type without a zone.
func zone_s(hz: Dictionary) -> Array:
	var m := main_road()
	if m == null:
		return []
	var z = hz.get("zone")
	if z is Array and (z as Array).size() == 2 and z[0] is Dictionary and z[1] is Dictionary:
		var z0 := m.anchor_s(z[0])
		var z1 := m.anchor_s(z[1])
		if z1 < z0 and m.closed:
			z1 += m.length
		return [z0, z1]
	var pl: Dictionary = td_of(hz).get("placement", {})
	if not (pl.get("zone") is Array) or not (hz.get("at") is Dictionary):
		return []
	var s := m.anchor_s(hz.at)
	return [s + float(pl.zone[0]), s + float(pl.zone[1])]


## The setback a hazard stands at (its own or the type's default, clamped; NAN when it has none).
static func setback_of(hz: Dictionary) -> float:
	var pl: Dictionary = td_of(hz).get("placement", {})
	var sb: Array = pl.get("setback", [])
	if sb.is_empty():
		return NAN
	var v = hz.get("setback")
	var x := float(v) if (v is float or v is int) else float(sb[2])
	return clampf(x, float(sb[0]), float(sb[1]))


## Where the marker of a hazard stands (NAN x when its road is not baked).
## The view's stand-in models (4.2): each hazard's default model (LevelHazards.marker_model_for)
## where its marker stands on the last bake's road, facing the road (along it in the middle), no
## collision; a node is kept while its uid and model stay. Hidden hazards and models this install
## lacks are left out. TrackEditor calls it after every bake and when the hidden set changes.
func sync_models() -> void:
	if editor == null or editor.doc == null or editor.view == null or not editor.view.is_inside_tree():
		return
	if _models_root == null or not is_instance_valid(_models_root):
		_models_root = Node3D.new()
		_models_root.name = "HazardModels"
		editor.view.add_child(_models_root)
		_models = {}
	var hidden := editor.session.hidden if editor.session != null else PackedInt32Array()
	var keep := {}
	var m := main_road()
	for hz in list_of():
		if not (hz is Dictionary) or m == null:
			continue
		var u := int(hz.get("uid", 0))
		var key := LevelHazards.marker_model_for(hz)
		if u <= 0 or key == "" or u in hidden or not Game.models.has(key):
			continue
		var p := marker_pos(hz)
		var s := hazard_s(hz)
		if is_nan(p.x) or is_nan(s):
			continue
		var n: Node3D = _models.get(u)
		if n == null or not is_instance_valid(n) or str(n.get_meta("model", "")) != key:
			if n != null and is_instance_valid(n):
				n.queue_free()
			n = Game.spawn_model(key)
			for c in n.find_children("*", "CollisionObject3D", true, false):
				c.queue_free()
			n.set_meta("model", key)
			_models_root.add_child(n)
			_models[u] = n
		keep[u] = true
		n.global_transform = model_transform(hz, m, m.idx(s), p)
	for u in _models.keys():
		if not keep.has(u):
			var gone: Node3D = _models[u]
			if gone != null and is_instance_valid(gone):
				gone.queue_free()
			_models.erase(u)


## Where a hazard's stand-in model stands: the marker's spot on the ground (a ceiling turret hangs
## upside down from it), facing the road from its side or along the race in the middle.
func model_transform(hz: Dictionary, m: LevelRoad, i: int, p: Vector3) -> Transform3D:
	var f := Vector3(m.fwd[i].x, 0.0, m.fwd[i].z)
	if f.length_squared() < 1e-6:
		f = Vector3.FORWARD
	f = f.normalized()
	var side := int(hz.get("side", 0))
	var ty := str(hz.get("type", ""))
	var ceiling := ty == "turret" and str(hz.get("mount", "floor")) == "ceiling"
	var face := f
	if side != 0 and not ceiling and ty != "column":
		face = -Vector3(m.flat_right[i].x, 0.0, m.flat_right[i].z).normalized() * signf(side)
		if face.length_squared() < 1e-6:
			face = f
	var b := Basis.looking_at(face, Vector3.UP)
	if ceiling:
		return Transform3D(Basis(face, PI) * b, p)
	if ty == "column":
		return Transform3D(b, p)
	return Transform3D(b, p - Vector3.UP * 1.5)


## The view's stand-in models by uid (tests).
func model_nodes() -> Dictionary:
	return _models


func marker_pos(hz: Dictionary) -> Vector3:
	var m := main_road()
	var s := hazard_s(hz)
	if m == null or is_nan(s):
		return Vector3(NAN, NAN, NAN)
	var i := m.idx(s)
	var ty := str(hz.get("type", ""))
	var side := int(hz.get("side", 0))
	var w := m.width[i] * 0.5
	if ty == "turret" and str(hz.get("mount", "floor")) == "ceiling":
		var h := m.height[i] - 0.6 if m.height.size() == m.n and m.height[i] > 1.0 else 4.0
		return m.surface(i, clampf(float(hz.get("lat", 0.0)) if _num(hz.get("lat")) else 0.0, -w, w), h)
	if ty == "column":
		return m.surface(i, 0.0, LevelHazards.DECK_UP)
	var sb := setback_of(hz)
	var sides: Array = (td_of(hz).get("placement", {}) as Dictionary).get("side", [])
	if sides.is_empty() or side == 0:
		return m.surface(i, 0.0, 1.5)
	var sgn := -1.0 if side < 0 else 1.0
	var out := w + (sb if not is_nan(sb) else 4.0)
	return m.pos[i] + m.right[i] * sgn * w + m.flat_right[i] * sgn * (out - w) + Vector3.UP * 1.5


## The point kind of a type ("" none) and its [min, max].
static func points_kind(hz: Dictionary) -> String:
	var pts: Dictionary = (td_of(hz).get("placement", {}) as Dictionary).get("pts", {})
	if pts.is_empty():
		return ""
	if str(hz.get("type", "")) == "strike_zone" and str(hz.get("style", "mortar")) != "arc":
		return ""
	return str(pts.get("kind", ""))


static func points_max(hz: Dictionary) -> int:
	var pts: Dictionary = (td_of(hz).get("placement", {}) as Dictionary).get("pts", {})
	return int(pts.get("max", 0))


static func points_min(hz: Dictionary) -> int:
	var pts: Dictionary = (td_of(hz).get("placement", {}) as Dictionary).get("pts", {})
	return int(pts.get("min", 0))


## The world spot of a hazard's point k (NAN x when unknown).
func point_pos(hz: Dictionary, k: int) -> Vector3:
	var pts: Array = hz.get("pts", []) if hz.get("pts") is Array else []
	if k < 0 or k >= pts.size():
		return Vector3(NAN, NAN, NAN)
	var q = pts[k]
	var m := main_road()
	if q is Dictionary:
		if q.get("pos") != null:
			return ItemsTool._v3(q.pos)
		if m == null or not (q.get("at") is Dictionary):
			return Vector3(NAN, NAN, NAN)
		var i := m.anchor_i(q.at)
		match points_kind(hz):
			"hover":
				return m.surface(i, float(q.get("lat", 0.0)), float(q.get("h", HOVER_H)))
			"thumpers":
				var sg := -1.0 if int(q.get("side", 1)) < 0 else 1.0
				var sb := float(q.get("setback", 6.0))
				var w := m.width[i] * 0.5
				return m.pos[i] + m.right[i] * sg * w + m.flat_right[i] * sg * sb + Vector3.UP * 1.0
		return m.surface(i, float(q.get("lat", 0.0)), 0.4)
	if q is Array:
		var a: Array = q
		if a.size() >= 3 and points_kind(hz) == "core":
			return Vector3(float(a[0]), float(a[1]), float(a[2]))
		if m != null and a.size() >= 2:
			var i := m.idx(float(a[0]))
			return m.surface(i, float(a[1]), float(a[2]) if a.size() >= 3 else 0.4)
	return Vector3(NAN, NAN, NAN)


static func _num(v: Variant) -> bool:
	return v is float or v is int


# ---------------------------------------------------------------- legal spots

## The exported sample (the flags' index) of a dense main-road sample.
static func flag_index(i: int, flags: PackedByteArray) -> int:
	if flags.is_empty():
		return -1
	return clampi(i / 3, 0, flags.size() - 1)


## Whether a setup key may sit at dense main sample i (true for "" = no setup).
func legal_at(key: String, i: int) -> bool:
	if key == "":
		return true
	var f := editor.flags("hz_" + key)
	var e := flag_index(i, f)
	return e >= 0 and f[e] == 1


## Why a setup key cannot sit at dense main sample i (the status line's words).
func refusal_reason(key: String, i: int) -> String:
	var m := main_road()
	var noun := str(SETUP_NOUN.get(key, "This hazard"))
	if m == null or editor.flags("hz_" + key).is_empty():
		return "Wait for the track to bake (a closed loop), then click again."
	var k := m.kind(i)
	var gap := m.gap.size() == m.n and m.gap[i] == 1
	var see := m.seesaw.size() == m.n and m.seesaw[i] == 1
	match key:
		"turret_ceiling":
			return "%s needs a tunnel." % noun
		"tripmine":
			if see:
				return "%s cannot sit on a see-saw stretch." % noun
			return "%s cannot sit on a jump." % noun
		"tentacle":
			if k == "tunnel":
				return "%s cannot sit in a tunnel." % noun
			if gap:
				return "%s cannot sit on a jump." % noun
			return "%s needs room for its pit: no other road within 12 m." % noun
		"antlion":
			if k != "open":
				return "%s need an open road (not a street, a bridge or a tunnel)." % noun
			return "%s need open ground near the road's height beside most of the next 100 m." % noun
		"column":
			if k == "tunnel" or gap:
				return "%s needs open sky over the road (not a tunnel or a jump)." % noun
			return "%s needs no other road over its footbridge." % noun
		"seesaw":
			return "%s needs a straight, level segment of one width, at least %d m long, with no tunnel, jump or bank." \
				% [noun, roundi(LevelHazards.SEESAW_LEN + LevelHazards.SEESAW_SPARE)]
		"train":
			if k == "tunnel" or k == "bridge" or gap:
				return "%s needs an open road or a street (not a tunnel, a bridge or a jump)." % noun
			return "%s needs flat ground (%d %% at most) along its line and no other road within 3 m." \
				% [noun, roundi(LevelHazards.TRAIN_GRADE * 100.0)]
	return "%s cannot go here." % noun


# ---------------------------------------------------------------- placing

func click(hit: EditorHit, mods: int) -> bool:
	if editor == null or editor.doc == null or hit == null:
		return false
	if hit.what == "gizmo":
		return false
	if hit.what == "marker":
		if hit.kind == "hazard_point" and hit.uid > 0:
			point = {"uid": hit.uid, "k": hit.sub - POINT_SUB}
			editor.select(PackedInt32Array([hit.uid]))
			editor.status("%s %d selected: %s removes it." % [str(POINT_NOUN.get(points_kind(item_of(hit.uid)), "POINT")),
				hit.sub - POINT_SUB + 1, EditorKit.plain("{ed_delete}")])
			return true
		point = {}
		return false   # the common rule: select
	if not hit.hit:
		return false
	if has_mod(mods, MOD_CTRL):
		var pu := points_target()
		if pu > 0:
			add_point(pu, hit)
			return true
	if hit.what == "prop":
		return false
	return place(hit) > 0 or refusal != ""


## Places the chosen type at the road spot of a hit (its side from the click). Returns the new
## hazard's uid; 0 when refused (`refusal` and the status line say why).
func place(hit: EditorHit) -> int:
	refusal = ""
	var sp := _h.road_spot(hit, ItemsTool.REACH)
	if sp.is_empty():
		return _refuse("Click on the road (or next to it)." if editor.build != null else "Wait for the track to bake.")
	if int(sp.key) != -1:
		return _refuse("Hazards go on the main road, not on a branch.")
	var c := choice_of(choice)
	if c.is_empty():
		return _refuse("Pick a hazard in the tool options.")
	var m := main_road()
	if m == null:
		return _refuse("Wait for the track to bake.")
	if list_of().size() >= CAP:
		editor.toast("Limit reached (%d hazards)" % CAP)
		return _refuse("At most %d hazards on a track." % CAP)
	if bool(c.heavy) and heavy_count() >= HEAVY_CAP:
		editor.toast("Limit reached (%d heavy hazards)" % HEAVY_CAP)
		return _refuse("At most %d heavy hazards (striders, columns, see-saws, antlions, guards, cranes) on a track." % HEAVY_CAP)
	var i := int(sp.i)
	var key := str(c.setup)
	if key != "" and not legal_at(key, i):
		return _refuse(refusal_reason(key, i))
	var ty := str(c.type)
	if ty == "seesaw":
		return _place_seesaw(m, i)
	var hz := new_hazard(c, m, float(sp.s), float(sp.lat))
	var ops := [ItemsTool.op_add(SECTION, hz)]
	var step := "ADD %s" % str(c.label)
	if ty == "antlion":
		var band := sand_ops(hz)
		ops.append_array(band)
	editor.commit(step, ops)
	_placed(int(hz.uid))
	return int(hz.uid)


## A new doc hazard of a list entry at s metres, `lat` the clicked lateral (its side).
func new_hazard(c: Dictionary, m: LevelRoad, s: float, lat: float) -> Dictionary:
	var ty := str(c.type)
	var td: Dictionary = LevelHazards.TYPES[ty]
	var pl: Dictionary = td.placement
	var u := editor.doc.new_uid()
	var hz := {"uid": u, "type": ty, "at": null, "side": 0, "zone": null, "feel": "normal", "pts": [], "p": {}}
	var sides: Array = pl.side
	if not sides.is_empty():
		var sd := 1 if lat >= 0.0 else -1
		if sides.has(0) and absf(lat) < m.width[m.idx(s)] * 0.15:
			sd = 0
		if not sides.has(sd):
			sd = int(sides[sides.size() - 1])
		hz.side = sd
	if bool(pl.at):
		hz.at = ItemsTool.anchor_of(m, s)
	elif pl.zone is Array:
		hz.zone = [ItemsTool.anchor_of(m, s + float(pl.zone[0])), ItemsTool.anchor_of(m, s + float(pl.zone[1]))]
	if hz.at == null and hz.zone == null:
		hz.at = ItemsTool.anchor_of(m, s)
	var sb: Array = pl.setback
	if not sb.is_empty():
		hz["setback"] = float(sb[2])
	if ty == "turret":
		hz["mount"] = str(c.mount) if str(c.mount) != "" else "floor"
		if hz.mount == "ceiling":
			var w := m.width[m.idx(s)] * 0.5
			hz["lat"] = snappedf(clampf(lat, -w, w), 0.01)
			hz.side = 0
	if ty == "strike_zone":
		hz["style"] = str(c.style) if str(c.style) != "" else "mortar"
	return hz


## The see-saw: its segment becomes the stretch and the hazard sits on it (one undo step).
func _place_seesaw(m: LevelRoad, i: int) -> int:
	var k := m.seg[i]
	if k < 0 or k >= m.point_uids.size():
		return _refuse("No segment here.")
	var puid := m.point_uids[k]
	var ops := LevelHazards.seesaw_ops(editor.doc, puid, true)
	var u := 0
	for op in ops:
		if op is Array and str(op[0]) == "insert" and op[3] is Dictionary:
			u = int((op[3] as Dictionary).get("uid", 0))
	if u == 0:
		return _refuse("This segment already has its see-saw bridge.")
	editor.commit("ADD SEE-SAW BRIDGE", ops)
	_placed(u)
	return u


## The ops that paint an antlion zone's 16 m sand band (its side, or both), [] with no terrain.
func sand_ops(hz: Dictionary) -> Array:
	var doc := editor.doc
	var m := main_road()
	var z := zone_s(hz)
	if doc == null or m == null or z.is_empty() or not doc.has_terrain():
		return []
	var t := editor.terrain()
	if t == null or t.res != doc.res():
		t = LevelTerrain.from_doc(doc)
	if t == null:
		return []
	var s := doc.splat.duplicate()
	var layer := LevelBrush.LAYERS.find("sand")
	var rect := LevelBrush.band_splat(t, s, m, m.idx(float(z[0])), m.idx(float(z[1])), int(hz.get("side", 0)), SAND_WIDTH, layer)
	if not rect.has_area():
		return []
	return [LevelDoc.op_splat(rect, LevelBrush.region_splat(s, doc.res(), rect))]


func _placed(u: int) -> void:
	_last = u
	point = {}
	editor.select(PackedInt32Array([u]))
	editor.status("")
	succeeded()


func _refuse(why: String) -> int:
	refusal = why
	editor.refuse(why)
	return 0


## The hazard Ctrl + click adds points to: the selected one with points, else the last placed.
func points_target() -> int:
	if editor.selection != null:
		for u in editor.selection.uids:
			var hz := item_of(u)
			if not hz.is_empty() and points_kind(hz) != "":
				return u
	var last := item_of(_last)
	if not last.is_empty() and points_kind(last) != "":
		return _last
	return 0


## Adds a point of the hazard's kind at a hit (the arc's single core is replaced). One undo step.
func add_point(uid: int, hit: EditorHit) -> bool:
	var hz := item_of(uid)
	var kind := points_kind(hz)
	if kind == "":
		return false
	var pts: Array = (hz.get("pts", []) as Array).duplicate(true) if hz.get("pts") is Array else []
	var mx := points_max(hz)
	if kind != "core" and pts.size() >= mx:
		editor.status("A %s has at most %d %ss." % [str(td_of(hz).label), mx, str(POINT_NOUN[kind]).to_lower()])
		return false
	var q = _point_at(hz, kind, hit)
	if q == null:
		editor.status("Click on the road." if kind != "core" else "Click beside the road.")
		return false
	if kind == "core":
		pts = [q]
	else:
		pts.append(q)
	editor.commit("ADD %s" % str(POINT_NOUN[kind]), [ItemsTool.op_field(SECTION, uid, "pts", pts)])
	point = {"uid": uid, "k": pts.size() - 1}
	editor.select(PackedInt32Array([uid]))
	succeeded()
	return true


## A point of `kind` for a hit (null when the hit cannot hold one).
func _point_at(hz: Dictionary, kind: String, hit: EditorHit) -> Variant:
	var m := main_road()
	if m == null:
		return null
	match kind:
		"core":
			return ItemsTool._arr(hit.pos + Vector3.UP * CORE_UP)
		"thumpers":
			var sp := _h.road_spot(hit, THUMPER_REACH)
			if sp.is_empty() or int(sp.key) != -1:
				return null
			return {"at": ItemsTool.anchor_of(m, float(sp.s)), "side": 1 if float(sp.lat) >= 0.0 else -1,
				"setback": snappedf(clampf(float(sp.off), 2.0, 30.0), 0.1)}
		"hover", "mines":
			var sp2 := _h.road_spot(hit, 30.0 if kind == "hover" else 0.0)
			if sp2.is_empty() or int(sp2.key) != -1:
				return null
			var o := {"at": ItemsTool.anchor_of(m, float(sp2.s)), "lat": snappedf(float(sp2.lat), 0.01)}
			if kind == "hover":
				o["h"] = HOVER_H
			return o
	return null


## Removes point k of a hazard (one undo step); false when there is no such point.
func remove_point(uid: int, k: int) -> bool:
	var hz := item_of(uid)
	if hz.is_empty() or not (hz.get("pts") is Array) or k < 0 or k >= (hz.pts as Array).size():
		return false
	var pts: Array = (hz.pts as Array).duplicate(true)
	pts.remove_at(k)
	editor.commit("DELETE %s" % str(POINT_NOUN.get(points_kind(hz), "POINT")), [ItemsTool.op_field(SECTION, uid, "pts", pts)])
	point = {}
	return true


func key(ev: InputEvent) -> bool:
	if editor == null or point.is_empty():
		return false
	if InputMap.has_action("ed_delete") and ev.is_action_pressed("ed_delete", false, true):
		var u := int(point.uid)
		if editor.selection != null and editor.selection.has(u) and editor.selection.uids.size() == 1:
			return remove_point(u, int(point.k))
		point = {}
	return false


# ---------------------------------------------------------------- hover

func hints(hit: EditorHit) -> Array:
	var c := choice_of(choice)
	var noun := str(c.get("label", "HAZARD"))
	if hit == null or not hit.hit:
		return [["CLICK THE ROAD: %s" % noun]]
	if hit.what == "marker":
		if hit.kind == "issue":
			return [["CLICK SHOW THE PROBLEM"]]
		if hit.kind == "hazard_point":
			return [["CLICK SELECT THIS POINT"], ["DRAG MOVE IT"], ["{ed_delete} DELETE IT"]]
		if hit.kind == "hazard":
			if hit.sub == SUB_A or hit.sub == SUB_B:
				return [["DRAG MOVE THIS END OF THE ZONE"], ["CLICK SELECT"]]
			return [["CLICK SELECT"], ["DRAG SLIDE ALONG THE ROAD"], ["{ed_delete} DELETE"]]
		return [["CLICK SELECT"]]
	var out := []
	var pu := points_target()
	if hit.what == "road" and hit.road == -1:
		var key := str(c.get("setup", ""))
		var m := main_road()
		var i := hit.sample if hit.sample >= 0 else (m.closest(hit.pos) if m != null else -1)
		if key != "" and m != null and i >= 0 and i < m.n and not legal_at(key, i):
			out.append(["NO %s HERE" % noun])
		else:
			var side := ""
			var sides: Array = ((LevelHazards.TYPES.get(str(c.get("type", "")), {}) as Dictionary).get("placement", {}) as Dictionary).get("side", [])
			if not sides.is_empty() and str(c.id) != "turret_ceiling":
				side = " ON THE RIGHT" if hit.lat >= 0.0 else " ON THE LEFT"
			out.append(["CLICK PLACE: %s%s" % [noun, side]])
	elif hit.what == "road":
		out.append(["HAZARDS GO ON THE MAIN ROAD"])
	else:
		out.append(["CLICK THE ROAD: %s" % noun])
	if pu > 0:
		var k := points_kind(item_of(pu))
		out.append(["{ed_mod_ctrl} CLICK ADD A %s" % str(POINT_NOUN.get(k, "POINT"))])
	return out


func status_step() -> String:
	if refusal != "":
		return refusal
	var c := choice_of(choice)
	var noun := str(c.get("label", "HAZARD")).to_lower()
	if str(c.get("setup", "")) != "":
		return "Click a green stretch of the road for a %s (red: it cannot go there)" % noun
	return "Click the road for a %s, on the side you click" % noun


# ---------------------------------------------------------------- markers and overlay

func markers(mk: EditorMarkers) -> void:
	if editor == null or editor.doc == null:
		return
	var lint := lint_map()
	for hz in list_of():
		if not (hz is Dictionary):
			continue
		var u := int(hz.uid)
		var p := marker_pos(hz)
		if is_nan(p.x):
			continue
		var col := HAZARD_COLOR
		var lv := str(lint.get(u, {}).get("level", ""))
		if lv == "error":
			col = ERROR_COLOR
		elif lv == "warning":
			col = LINT_COLOR
		mk.add("hazard", u, p, EditorMarkers.Shape.TRIANGLE, col, 2.5, 0)
		var z := zone_s(hz)
		var m := main_road()
		if not z.is_empty() and m != null:
			mk.add("hazard", u, m.surface(m.idx(float(z[0])), 0.0, 0.5), EditorMarkers.Shape.BAR, ZONE_COLOR, 3.0, SUB_A)
			mk.add("hazard", u, m.surface(m.idx(float(z[1])), 0.0, 0.5), EditorMarkers.Shape.BAR, ZONE_COLOR, 3.0, SUB_B)
		var pts: Array = hz.get("pts", []) if hz.get("pts") is Array else []
		if points_kind(hz) != "":
			for k in pts.size():
				var q := point_pos(hz, k)
				if not is_nan(q.x):
					mk.add("hazard_point", u, q, EditorMarkers.Shape.DOT, POINT_COLOR, 1.4, POINT_SUB + k)


func overlay(d: EditorDraw) -> void:
	if editor == null or editor.doc == null or d == null:
		return
	var m := main_road()
	if m == null:
		return
	if editor.tool == self:
		var key := chosen_setup()
		if key != "":
			var f := editor.flags("hz_" + key)
			if not f.is_empty():
				d.flags_on_road(m, f, OK_TINT, BAD_TINT)
	draw_zones(d)
	for hz in list_of():
		if not (hz is Dictionary):
			continue
		var u := int(hz.uid)
		var sel := editor.selection != null and editor.selection.has(u)
		if sel:
			var p := marker_pos(hz)
			var rg := range_of(hz)
			if not is_nan(p.x) and rg > 0.0:
				d.circle(p, Vector3.UP, rg, RING_COLOR)
			var pts: Array = hz.get("pts", []) if hz.get("pts") is Array else []
			for k in pts.size():
				var q := point_pos(hz, k)
				if not is_nan(q.x) and not is_nan(p.x):
					d.line(p, q, Color(POINT_COLOR, 0.6))


## The hazards' zone strips on the road (this tool's overlay; VIEW > ZONES in the others).
func draw_zones(d: EditorDraw) -> void:
	var m := main_road()
	if m == null or d == null:
		return
	for hz in list_of():
		if not (hz is Dictionary):
			continue
		var z := zone_s(hz)
		if z.is_empty():
			continue
		var sel := editor.selection != null and editor.selection.has(int(hz.uid))
		var w := m.width[m.idx(float(z[0]))] * 0.5
		var col := Color(ZONE_COLOR, 0.34 if sel else 0.18)
		var a := float(z[0])
		var b := float(z[1])
		if m.closed and b - a >= m.length:
			b = a + m.length - m.step
		var aa := ItemsTool.wrap_s(m, a)
		var bb := ItemsTool.wrap_s(m, b)
		if m.closed and bb < aa:
			d.strip_on_road(m, aa, m.length, -w, w, col)
			d.strip_on_road(m, 0.0, bb, -w, w, col)
		else:
			d.strip_on_road(m, minf(aa, bb), maxf(aa, bb), -w, w, col)


## The range ring's radius of a hazard (its p "range" or the row's default; 0 none).
static func range_of(hz: Dictionary) -> float:
	for row in LevelHazards.params_of(hz):
		if str(row[0]) == "range":
			var p: Dictionary = hz.get("p", {}) if hz.get("p") is Dictionary else {}
			var v = p.get("range", row[5])
			return float(v) if _num(v) else float(row[5])
	return 0.0


## uid -> the worst report item of the last bake about that hazard ({level, text}).
func lint_map() -> Dictionary:
	var out := {}
	if editor == null or editor.build == null or editor.build.report == null:
		return out
	for it in editor.build.report.items:
		var code := str(it.get("code", ""))
		if not (code in ["hazard_lint", "hazard_setup", "over_cap"]):
			continue
		var u := int(it.get("uid", 0))
		if u <= 0 or item_of(u).is_empty():
			continue
		if not out.has(u) or str(it.level) == "error":
			out[u] = {"level": str(it.level), "text": str(it.text)}
	return out


## The report lines of the last bake about a hazard: [{level, text}].
func lint_lines(uid: int) -> Array:
	var out := []
	if editor == null or editor.build == null or editor.build.report == null:
		return out
	for it in editor.build.report.items:
		if int(it.get("uid", 0)) == uid and str(it.get("level", "")) in ["error", "warning"]:
			out.append({"level": str(it.level), "text": str(it.text)})
	return out


# ---------------------------------------------------------------- moving

func drag_begin(hit: EditorHit, _mods: int) -> bool:
	if editor == null or editor.doc == null or hit == null:
		return false
	if hit.what != "marker" or not owns(hit.kind) or hit.uid <= 0:
		return false
	var hz := item_of(hit.uid)
	if hz.is_empty():
		return false
	var nm := "MOVE %s" % str(choice_for(hz).get("label", "HAZARD"))
	if hit.kind == "hazard_point":
		nm = "MOVE %s" % str(POINT_NOUN.get(points_kind(hz), "POINT"))
		point = {"uid": hit.uid, "k": hit.sub - POINT_SUB}
	elif hit.sub == SUB_A or hit.sub == SUB_B:
		nm = "HAZARD ZONE"
	editor.history.begin_gesture(nm)
	_drag = {"uid": hit.uid, "name": nm}
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
	var ops := slide(int(_drag.uid), hit, phase)
	if not ops.is_empty():
		editor.commit(str(_drag.name), ops, "hazards_drag")


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


## A hazard's marker dragged (here or from SELECT): the hazard slides along the main road with its
## zone (a setup type only onto green), an end bar (sub 3 / 4) moves that end of the zone, a point
## (sub 10 +) follows the cursor. A see-saw stays on its stretch.
func slide(uid: int, hit: EditorHit, phase: int) -> Array:
	if editor == null or editor.doc == null or hit == null:
		return []
	var hz := item_of(uid)
	var m := main_road()
	if hz.is_empty() or m == null:
		return []
	if phase == 0 or _slide.is_empty() or int(_slide.get("uid", 0)) != uid:
		_slide = {"uid": uid, "sub": hit.sub, "s0": ItemsTool.s_near(m, hit.pos), "z": zone_s(hz),
			"at": m.anchor_s(hz.at) if hz.get("at") is Dictionary else NAN}
		if phase == 0:
			return []
	var sub := int(_slide.sub)
	var out := []
	if sub >= POINT_SUB:
		var k := sub - POINT_SUB
		var kind := points_kind(hz)
		var pts: Array = (hz.get("pts", []) as Array).duplicate(true) if hz.get("pts") is Array else []
		if kind == "" or k < 0 or k >= pts.size():
			return []
		var q = _point_at(hz, kind, hit)
		if q == null:
			return []
		if kind == "hover" and pts[k] is Dictionary and _num((pts[k] as Dictionary).get("h")):
			q["h"] = float(pts[k].h)
		pts[k] = q
		out.append(ItemsTool.op_field(SECTION, uid, "pts", pts))
	elif sub == SUB_A or sub == SUB_B:
		var z: Array = _slide.z
		if z.is_empty():
			return []
		var s := ItemsTool.s_near(m, hit.pos)
		var a := float(z[0])
		var b := float(z[1])
		if sub == SUB_A:
			a = b - _len_ok(hz, fposmod(b - s, m.length) if m.closed else b - s)
		else:
			b = a + _len_ok(hz, fposmod(s - a, m.length) if m.closed else s - a)
		out.append(ItemsTool.op_field(SECTION, uid, "zone", [ItemsTool.anchor_of(m, a), ItemsTool.anchor_of(m, b)]))
	else:
		if str(hz.get("type", "")) == "seesaw":
			if phase == 1:
				editor.status("A see-saw bridge stays on its stretch: move the road's points instead.")
			return []
		var ds := ItemsTool.delta_s(m, float(_slide.s0), ItemsTool.s_near(m, hit.pos))
		var key := LevelHazards.setup_of(hz)
		var s_new := float(_slide.at) + ds if not is_nan(float(_slide.at)) else NAN
		var s_ref := s_new
		if is_nan(s_ref) and not (_slide.z as Array).is_empty():
			s_ref = (float(_slide.z[0]) + float(_slide.z[1])) * 0.5 + ds
		if key != "" and not is_nan(s_ref) and not legal_at(key, m.idx(ItemsTool.wrap_s(m, s_ref))):
			editor.status(refusal_reason(key, m.idx(ItemsTool.wrap_s(m, s_ref))))
			return []
		if not is_nan(s_new):
			out.append(ItemsTool.op_field(SECTION, uid, "at", ItemsTool.anchor_of(m, s_new)))
		if hz.get("zone") is Array and not (_slide.z as Array).is_empty():
			out.append(ItemsTool.op_field(SECTION, uid, "zone", [ItemsTool.anchor_of(m, float(_slide.z[0]) + ds),
				ItemsTool.anchor_of(m, float(_slide.z[1]) + ds)]))
	if phase == 2:
		_slide = {}
	return out


## A zone length kept within the type's zone_len (else at least MIN_ZONE m).
static func _len_ok(hz: Dictionary, ln: float) -> float:
	var zl: Array = (td_of(hz).get("placement", {}) as Dictionary).get("zone_len", [])
	if zl.size() == 2:
		return clampf(ln, float(zl[0]), float(zl[1]))
	return maxf(ln, MIN_ZONE)


# ---------------------------------------------------------------- deleting, boxes

## Hazards removed; a see-saw takes its stretch with it (LevelHazards.seesaw_ops off).
func delete_ops(uids: PackedInt32Array) -> Array:
	var out := []
	if editor == null or editor.doc == null:
		return out
	var gone := {}
	for u in uids:
		var hz := item_of(u)
		if hz.is_empty() or gone.has(u):
			continue
		if str(hz.get("type", "")) == "seesaw" and hz.get("at") is Dictionary:
			var ops := LevelHazards.seesaw_ops(editor.doc, int(hz.at.get("p", 0)), false)
			for op in ops:
				if op is Array and str(op[0]) == "remove":
					var ru := int(str(op[2]).trim_prefix("#"))
					if gone.has(ru):
						continue
					gone[ru] = true
				out.append(op)
			if not ops.is_empty():
				continue
		gone[u] = true
		out.append(ItemsTool.op_del(SECTION, u))
	if not point.is_empty() and gone.has(int(point.uid)):
		point = {}
	return out


func item_aabb(uid: int) -> AABB:
	var hz := item_of(uid)
	if hz.is_empty():
		return AABB()
	var p := marker_pos(hz)
	if is_nan(p.x):
		return AABB()
	var box := AABB(p - Vector3(3, 2, 3), Vector3(6, 4, 6))
	var m := main_road()
	var z := zone_s(hz)
	if m != null and not z.is_empty():
		box = box.expand(m.pos[m.idx(float(z[0]))]).expand(m.pos[m.idx(float(z[1]))])
	return box


func on_doc_changed(_sections: PackedStringArray, _uids: PackedInt32Array) -> void:
	if _counts != null and is_instance_valid(_counts):
		_counts.text = counts_text()
	if not point.is_empty():
		var hz := item_of(int(point.uid))
		var n := (hz.pts as Array).size() if hz.get("pts") is Array else 0
		if hz.is_empty() or int(point.k) >= n:
			point = {}


# ---------------------------------------------------------------- tool options

func options(box: VBoxContainer) -> void:
	if editor == null or editor.doc == null:
		return
	var all := choices()
	# the chosen one first (the list below scrolls): its name, what it does, the counts
	var cur := choice_of(choice)
	var line := str(cur.get("desc", ""))
	if bool(cur.get("heavy", false)):
		line += " HEAVY: %d of %d." % [heavy_count(), HEAVY_CAP]
	if str(cur.get("setup", "")) != "":
		line += " Green on the road: where it may go."
	_desc_line = line
	box.add_child(EditorKit.section_icon("PLACING: %s" % str(cur.get("label", "-")), icon_of(str(cur.get("type", "")))))
	box.add_child(EditorKit.hint(line))
	_counts = UiKit.label(counts_text(), EditorKit.FONT_SMALL, UiKit.TEXT_DIM)
	_counts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_counts)
	box.add_child(EditorKit.hint("● NEEDS A SETUP · CLICK THE ROAD: PLACE · {ed_mod_ctrl} + CLICK: ADD A POINT · DRAG THE END BARS: ZONE · {ed_delete} DELETE"))
	var group := ButtonGroup.new()
	for g in GROUPS:
		box.add_child(EditorKit.section_icon(g, str(GROUP_ICONS.get(g, ""))))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 2)
		grid.add_theme_constant_override("v_separation", 2)
		for c in all:
			if str(c.group) != g:
				continue
			var cid := str(c.id)
			var b := EditorKit.toggle(str(c.label) + (" ●" if str(c.setup) != "" else ""), cid == choice, func(on: bool) -> void:
				if on:
					set_choice(cid))
			b.tooltip_text = "%s\n%s" % [b.text, str(c.desc)]
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.clip_text = true
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			b.custom_minimum_size.x = 100
			b.set_meta("hazard", cid)
			b.button_group = group
			grid.add_child(b)
		box.add_child(grid)


## The description line of the chosen entry (as the options show it).
func desc_text() -> String:
	return _desc_line


# ---------------------------------------------------------------- inspector

func inspect(uids: PackedInt32Array, box: VBoxContainer) -> bool:
	if editor == null or editor.doc == null or uids.is_empty():
		return false
	if editor.kind_of(uids[0]) != "hazard":
		return false
	var uid := uids[0]
	var hz := item_of(uid)
	if hz.is_empty():
		return false
	var td := td_of(hz)
	var c := choice_for(hz)
	var label := str(c.get("label", td.get("label", "HAZARD")))
	box.add_child(EditorKit.section_icon(label if uids.size() == 1 else "%s · %d SELECTED" % [label, uids.size()], icon_of(str(hz.get("type", "")))))
	box.add_child(EditorKit.row("TYPE", UiKit.label("%s · %s" % [label, str(td.get("group", ""))], EditorKit.FONT_SMALL, UiKit.TEXT_DIM)))
	box.add_child(EditorKit.hint(str(c.get("desc", td.get("desc", "")))))
	var ty := str(hz.type)
	var pl: Dictionary = td.placement
	if ty == "turret":
		var mounts := ["floor", "ceiling"]
		box.add_child(EditorKit.row("MOUNT", EditorKit.modes(["FLOOR", "CEILING"], mounts.find(str(hz.get("mount", "floor"))),
			func(i: int) -> void: set_mount(uid, mounts[i]))))
	if ty == "strike_zone":
		var styles := ["mortar", "arc"]
		box.add_child(EditorKit.row("STYLE", EditorKit.modes(["MORTAR", "ARC"], styles.find(str(hz.get("style", "mortar"))),
			func(i: int) -> void: set_field(uid, "style", styles[i], "HAZARD STYLE"))))
	var sides: Array = pl.side
	if not sides.is_empty() and not (ty == "turret" and str(hz.get("mount", "floor")) == "ceiling"):
		var names := []
		for sd in sides:
			names.append("LEFT" if int(sd) < 0 else ("RIGHT" if int(sd) > 0 else "BOTH"))
		box.add_child(EditorKit.row("SIDE", EditorKit.modes(names, sides.find(int(hz.get("side", 0))),
			func(i: int) -> void: set_side(uid, int(sides[i])))))
	_zone_rows(uid, hz, box)
	# DIFFICULTY
	var feel := str(hz.get("feel", "normal"))
	box.add_child(EditorKit.row("DIFFICULTY", null, "EASY gives the karts more time; BRUTAL less."))
	var dm := EditorKit.modes(FEEL_NAMES, FEELS.find(feel), func(i: int) -> void: set_feel(uid, FEELS[i]))
	dm.set_meta("difficulty", true)
	box.add_child(dm)
	if feel == "custom":
		box.add_child(EditorKit.hint("CUSTOM: set in ADVANCED. Pick EASY, NORMAL or BRUTAL to start again."))
	_points_rows(uid, hz, box)
	# ADVANCED
	var adv := EditorKit.toggle(("- " if advanced_open else "+ ") + "ADVANCED", advanced_open, func(on: bool) -> void:
		HazardsTool.advanced_open = on
		if editor.ui != null:
			editor.ui.refresh_inspector())
	adv.set_meta("advanced", true)
	box.add_child(adv)
	if advanced_open:
		_advanced_rows(uid, hz, box)
	# lint
	for ln in lint_lines(uid):
		var l := EditorKit.hint(str(ln.text))
		l.add_theme_color_override("default_color", EditorKit.ERROR_COLOR if str(ln.level) == "error" else EditorKit.WARN_COLOR)
		l.set_meta("lint", str(ln.level))
		box.add_child(l)
	return true


func _zone_rows(uid: int, hz: Dictionary, box: VBoxContainer) -> void:
	var z := zone_s(hz)
	var m := main_road()
	if z.is_empty() or m == null:
		return
	var s := hazard_s(hz)
	if is_nan(s):
		return
	var a := float(z[0]) - s
	var b := float(z[1]) - s
	if m.closed:
		a = ItemsTool.delta_s(m, s, float(z[0]))
		b = a + (float(z[1]) - float(z[0]))
	var lim := m.length if m.closed else maxf(m.length, 1.0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var na := EditorKit.number(roundf(a), -lim, lim, 1.0, func(v: float) -> void: set_zone(uid, v, NAN), "%d", " m")
	na.tooltip_text = "Where the zone starts: metres from the hazard (minus: before it)."
	var nb := EditorKit.number(roundf(b), -lim, lim, 1.0, func(v: float) -> void: set_zone(uid, NAN, v), "%d", " m")
	nb.tooltip_text = "Where the zone ends: metres from the hazard."
	na.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(na)
	row.add_child(nb)
	box.add_child(EditorKit.row("ZONE", row, "Start and end of the stretch it covers; drag its end bars on the road too."))
	box.add_child(EditorKit.hint("%d m LONG · DRAG ITS END BARS ALONG THE ROAD" % roundi(float(z[1]) - float(z[0]))))


func _points_rows(uid: int, hz: Dictionary, box: VBoxContainer) -> void:
	var kind := points_kind(hz)
	if kind == "":
		return
	var n := (hz.get("pts", []) as Array).size() if hz.get("pts") is Array else 0
	var noun := str(POINT_NOUN[kind])
	var txt := "%sS %d / %d" % [noun, n, points_max(hz)]
	if n < points_min(hz):
		txt += " · FEWER THAN %d: THE GAME MAKES THEM UP" % points_min(hz)
	box.add_child(EditorKit.row("POINTS", UiKit.label(txt, EditorKit.FONT_SMALL, UiKit.TEXT_DIM)))
	box.add_child(EditorKit.hint("{ed_mod_ctrl} + CLICK THE ROAD: ADD A %s · CLICK ONE + {ed_delete}: REMOVE IT" % noun))
	if n > 0:
		box.add_child(EditorKit.button("CLEAR %sS" % noun, func() -> void:
			editor.commit("CLEAR %sS" % noun, [ItemsTool.op_field(SECTION, uid, "pts", [])])
			point = {}
			if editor.ui != null:
				editor.ui.refresh_inspector()))


func _advanced_rows(uid: int, hz: Dictionary, box: VBoxContainer) -> void:
	var td := td_of(hz)
	var pl: Dictionary = td.placement
	var sb: Array = pl.setback
	if not sb.is_empty():
		box.add_child(EditorKit.row("SETBACK", EditorKit.number(setback_of(hz), float(sb[0]), float(sb[1]), 0.1,
			func(v: float) -> void: set_field(uid, "setback", snappedf(v, 0.01), "HAZARD SETBACK", "hz_sb_%d" % uid), "%.1f", " m"),
			"How far past the road's edge it stands."))
	if str(hz.type) == "turret" and str(hz.get("mount", "floor")) == "ceiling":
		var m := main_road()
		var w := 7.0
		if m != null and hz.get("at") is Dictionary:
			w = m.width[m.anchor_i(hz.at)] * 0.5
		box.add_child(EditorKit.row("ACROSS", EditorKit.number(float(hz.get("lat", 0.0)) if _num(hz.get("lat")) else 0.0, -w, w, 0.1,
			func(v: float) -> void: set_field(uid, "lat", snappedf(v, 0.01), "HAZARD ACROSS", "hz_lat_%d" % uid), "%.1f", " m"),
			"Where it hangs across the tunnel (0 = the middle)."))
	var p: Dictionary = hz.get("p", {}) if hz.get("p") is Dictionary else {}
	for row in LevelHazards.params_of(hz):
		box.add_child(_param_row(uid, row, p.get(row[0], row[5]), true))
	for row in td.get("inputs", []):
		box.add_child(_param_row(uid, row, p.get(row[0], row[5]), false))


## One ADVANCED row of a TYPES params / inputs row: a choice, a switch, a pair, a pattern grid or
## a number. `param` rows make the hazard CUSTOM when changed.
func _param_row(uid: int, row: Array, value: Variant, param: bool) -> Control:
	var k := str(row[0])
	var label := str(row[1])
	var mn = row[2]
	var mx = row[3]
	var stp := float(row[4]) if _num(row[4]) else 1.0
	var def = row[5]
	if k == "pattern":
		return _pattern_row(uid, value if value is Array else def)
	if mn is Array:
		var opts: Array = mn
		var names := []
		for o in opts:
			names.append(str(o).get_file().to_upper().replace("_", " "))
		return EditorKit.row(label, EditorKit.choice(names, opts.find(str(value)), func(i: int) -> void:
			set_param(uid, k, opts[i], param)))
	if mn is bool:
		return EditorKit.row(label, EditorKit.check(bool(value), func(on: bool) -> void: set_param(uid, k, on, param)))
	var fmt := "%d" if stp >= 1.0 else ("%.1f" if stp >= 0.1 else "%.2f")
	if def is Array:
		var pair: Array = value if (value is Array and (value as Array).size() == 2) else def
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 4)
		for j in 2:
			var jj := j
			var nb := EditorKit.number(float(pair[j]), float(mn), float(mx), stp, func(v: float) -> void:
				var cur: Array = _pair_now(uid, k, def)
				cur[jj] = _snap(v, stp)
				if cur[0] > cur[1]:
					cur[1 - jj] = cur[jj]
				set_param(uid, k, cur, param, "hz_%s_%d" % [k, uid]), fmt)
			nb.tooltip_text = "LOWEST" if j == 0 else "HIGHEST"
			nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(nb)
		return EditorKit.row(label, h)
	var x := float(value) if _num(value) else float(def)
	return EditorKit.row(label, EditorKit.number(x, float(mn), float(mx), stp, func(v: float) -> void:
		set_param(uid, k, _snap(v, stp), param, "hz_%s_%d" % [k, uid]), fmt))


func _pair_now(uid: int, k: String, def: Array) -> Array:
	var p = item_of(uid).get("p", {})
	var v = p.get(k) if p is Dictionary else null
	if v is Array and (v as Array).size() == 2:
		return (v as Array).duplicate()
	return def.duplicate()


static func _snap(v: float, stp: float) -> Variant:
	if stp >= 1.0 and is_equal_approx(stp, roundf(stp)):
		return int(roundf(v / stp) * stp)
	return snappedf(v, stp)


## The field gate's PATTERN: rows of on / off lanes (up to 6), + ROW / - ROW.
func _pattern_row(uid: int, pat: Array) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.add_child(EditorKit.section("PATTERN (A ROW PER STEP; ON = A FIELD)"))
	var lanes := _lanes(uid)
	var rows: Array = _pattern_fit(pat, lanes)
	var grid := GridContainer.new()
	grid.columns = lanes
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	for r in rows.size():
		for l in lanes:
			var rr := r
			var ll := l
			var b := EditorKit.toggle("ON" if int(rows[r][l]) == 1 else "-", int(rows[r][l]) == 1, func(on: bool) -> void:
				var cur := _pattern_fit(_pattern_now(uid), _lanes(uid))
				cur[rr][ll] = 1 if on else 0
				set_param(uid, "pattern", cur, true))
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(b)
	v.add_child(grid)
	var h := HBoxContainer.new()
	h.add_child(EditorKit.button("+ ROW", func() -> void:
		var cur := _pattern_fit(_pattern_now(uid), _lanes(uid))
		if cur.size() < 6:
			var nr := []
			for l in _lanes(uid):
				nr.append(1 if l == cur.size() % _lanes(uid) else 0)
			cur.append(nr)
			set_param(uid, "pattern", cur, true)))
	h.add_child(EditorKit.button("- ROW", func() -> void:
		var cur := _pattern_fit(_pattern_now(uid), _lanes(uid))
		if cur.size() > 1:
			cur.pop_back()
			set_param(uid, "pattern", cur, true)))
	v.add_child(h)
	return v


func _lanes(uid: int) -> int:
	var p = item_of(uid).get("p", {})
	var v = p.get("lanes") if p is Dictionary else null
	return clampi(int(v) if _num(v) else 3, 2, 4)


func _pattern_now(uid: int) -> Array:
	var p = item_of(uid).get("p", {})
	var v = p.get("pattern") if p is Dictionary else null
	if v is Array:
		return v
	var td: Dictionary = LevelHazards.TYPES.field_gate
	for row in td.params:
		if str(row[0]) == "pattern":
			return row[5]
	return [[1, 0, 0]]


## Pattern rows cut or padded to `lanes` columns of 0 / 1 (1-6 rows).
static func _pattern_fit(pat: Array, lanes: int) -> Array:
	var out := []
	for r in pat:
		if out.size() >= 6:
			break
		var row := []
		for l in lanes:
			var x = r[l] if (r is Array and l < (r as Array).size()) else 0
			row.append(1 if (_num(x) and int(x) != 0) or (x is bool and x) else 0)
		out.append(row)
	if out.is_empty():
		var row := []
		for l in lanes:
			row.append(1 if l == 0 else 0)
		out.append(row)
	return out


# ---------------------------------------------------------------- edits (one undo step each)

func set_field(uid: int, field: String, value: Variant, step_name: String, merge := "") -> void:
	if item_of(uid).is_empty():
		return
	editor.commit(step_name, [ItemsTool.op_field(SECTION, uid, field, value)], merge)


func set_side(uid: int, side: int) -> void:
	var hz := item_of(uid)
	if hz.is_empty():
		return
	var ops := [ItemsTool.op_field(SECTION, uid, "side", side)]
	editor.commit("HAZARD SIDE", ops)
	if editor.ui != null:
		editor.ui.refresh_inspector()


## FLOOR / CEILING of a turret (the ceiling one needs a tunnel: the compile says so otherwise).
func set_mount(uid: int, mount: String) -> void:
	var hz := item_of(uid)
	if hz.is_empty() or str(hz.get("type", "")) != "turret":
		return
	var ops := [ItemsTool.op_field(SECTION, uid, "mount", mount)]
	if mount == "ceiling":
		ops.append(ItemsTool.op_field(SECTION, uid, "lat", 0.0))
	editor.commit("TURRET MOUNT", ops)
	if mount == "ceiling" and hz.get("at") is Dictionary and main_road() != null:
		var i := main_road().anchor_i(hz.at)
		if not legal_at("turret_ceiling", i):
			editor.status(refusal_reason("turret_ceiling", i))
	if editor.ui != null:
		editor.ui.refresh_inspector()


## ZONE start / end in metres from the hazard (NAN keeps that end). One undo step (typing merges).
func set_zone(uid: int, start_m: float, end_m: float) -> void:
	var hz := item_of(uid)
	var m := main_road()
	var z := zone_s(hz)
	var s := hazard_s(hz)
	if hz.is_empty() or m == null or z.is_empty() or is_nan(s):
		return
	var a := float(z[0])
	var b := float(z[1])
	if not is_nan(start_m):
		a = s + start_m
		a = b - _len_ok(hz, b - a)
	if not is_nan(end_m):
		b = s + end_m
		b = a + _len_ok(hz, b - a)
	editor.commit("HAZARD ZONE", [ItemsTool.op_field(SECTION, uid, "zone", [ItemsTool.anchor_of(m, a), ItemsTool.anchor_of(m, b)])],
		"hz_zone_%d" % uid)


## DIFFICULTY (4.2): EASY / NORMAL / BRUTAL rewrite the params of p that have a feel (T / P) from
## LevelHazards.difficulty_p, the mount's and style's rows alike; the other params and the inputs
## are kept. One undo step.
func set_feel(uid: int, feel: String) -> void:
	var hz := item_of(uid)
	if hz.is_empty() or not (feel in FEELS):
		return
	var p: Dictionary = (hz.get("p", {}) as Dictionary).duplicate(true) if hz.get("p") is Dictionary else {}
	var fp := feel_p(hz, feel)
	for k in fp:
		p[k] = fp[k]
	editor.commit("DIFFICULTY: %s" % feel.to_upper(), [ItemsTool.op_field(SECTION, uid, "feel", feel), ItemsTool.op_field(SECTION, uid, "p", p)])
	if editor.ui != null:
		editor.ui.refresh_inspector()


## The p values a feel gives a doc hazard: the rows with a feel (T / P) of its type, mount and style.
static func feel_p(hz: Dictionary, feel: String) -> Dictionary:
	var out := {}
	var ty := str(hz.get("type", ""))
	var base := LevelHazards.difficulty_p(ty, feel)
	var f: Array = LevelHazards.FEEL_SCALE.get(feel, LevelHazards.FEEL_SCALE.normal)
	var plain := {}
	var td: Dictionary = LevelHazards.TYPES.get(ty, {})
	for row in td.get("params", []):
		plain[str(row[0])] = row[5]
	for row in LevelHazards.params_of(hz):
		var k := str(row[0])
		var fk := str(row[6])
		if fk != "T" and fk != "P":
			continue
		if base.has(k) and plain.has(k) and str(plain[k]) == str(row[5]):
			out[k] = base[k]
		else:
			out[k] = LevelHazards._scaled(row, row[5], float(f[0]) if fk == "T" else float(f[1]))
	return out


## An ADVANCED field: p[k] = value; a param (not an input) makes the hazard CUSTOM. Typing merges.
func set_param(uid: int, k: String, value: Variant, param: bool, merge := "") -> void:
	var hz := item_of(uid)
	if hz.is_empty():
		return
	var np := _p_with(hz, k, value)
	if k == "lanes" and str(hz.get("type", "")) == "field_gate":
		np["pattern"] = _pattern_fit(_pattern_now(uid), clampi(int(value), 2, 4))
	var ops := [ItemsTool.op_field(SECTION, uid, "p", np)]
	var was := str(hz.get("feel", "normal"))
	if param and was != "custom":
		ops.append(ItemsTool.op_field(SECTION, uid, "feel", "custom"))
	editor.commit("HAZARD: %s" % k.to_upper().replace("_", " "), ops, merge)
	if (param and was != "custom") or k == "pattern" or k == "lanes" or merge == "":
		if editor.ui != null:
			editor.ui.refresh_inspector()


static func _p_with(hz: Dictionary, k: String, value: Variant) -> Dictionary:
	var p: Dictionary = (hz.get("p", {}) as Dictionary).duplicate(true) if hz.get("p") is Dictionary else {}
	p[k] = value
	return p
