extends RefCounted
## P15: spectators, extras, the object catalog and AUTO DRESS (spec 4.1, 4.3, 4.4). CI parts use
## a fake catalog and empty registries; the parts marked CONTENT run only with the HL content
## (t.content()): the catalog's counts against the probe's on this install, physics_ok, the
## cache, the seven palettes, real crowd models and the dressed oval with real models.

const NEEDS_CONTENT := false
const REG := {"models": {}, "materials": {}, "skies": {}, "music": {}}
const GUID := "0123456789abcdef0123456789abcdef"
## The budgets are this PC's; a CI runner gets three times as long.
var slack := 3.0 if OS.has_environment("GITHUB_ACTIONS") or OS.has_environment("CI") else 1.0
## The probe's counts on this install (model_catalog.py, 571 models; spec 4.1).
const PROBE := {"BUILDINGS": 32, "BRIDGES & BIG STRUCTURES": 18, "ROCKS & CLIFFS": 38, "TREES & PLANTS": 36,
	"XEN FLORA": 13, "STREET FURNITURE": 23, "JUNK & CLUTTER": 53, "VEHICLES": 30, "TRAINS & RAIL": 28, "COMBINE": 14,
	"INDUSTRIAL": 21, "DOCKS & COAST": 13, "ROOFTOP": 14, "LAB & BLACK MESA": 31, "PRISON & INTERIORS": 37,
	"FOREST & FARM": 10, "ANIMATED": 43, "HAZARD RIGS": 12, "GIBS": 29, "DRIVERS": 15, "CROWD PEOPLE": 46, "ITEMS": 15}


func run(t: Node) -> void:
	PropCatalog.set_source(_fake_models(), {"antlion": {"bones": ["a", "b", "c"]}, "props_c17/bench01a": {"bones": ["static_prop"]}})
	_catalog_case(t)
	_crowds_case(t)
	_rules_case(t)
	_people_cap_case(t)
	_eggs_case(t)
	_branch_case(t)
	_dress_case(t)
	_rails_case(t)
	_scenery_budget_case(t)
	_same_twice_case(t)
	PropCatalog.set_source({})
	if t.content():
		_content_case(t)


# ---------------------------------------------------------------- docs

## A fake models.json: one of each rule plus 30 city17 junk props for the palette.
static func _fake_models() -> Dictionary:
	var m := {}
	var add := func(k: String, kind: String, mass: float, a: Array, z: Array) -> void:
		m[k] = {"kind": kind, "mass": mass, "aabb_min": a, "aabb_max": z}
	add.call("props_c17/bench01a", "props", 30.0, [-1, 0, -0.3], [1, 0.9, 0.3])
	add.call("props_c17/lamppost03a", "props", 200.0, [-0.3, 0, -0.3], [0.3, 6, 0.3])
	add.call("props_c17/overpass_001a", "props", 9000.0, [-20, 0, -5], [20, 8, 5])
	add.call("props_c17/furniturecouch001a", "props", 40.0, [-1, 0, -0.5], [1, 0.8, 0.5])
	add.call("props_junk/trashdumpster01a", "props", 100.0, [-1, 0, -0.6], [1, 1.5, 0.6])
	add.call("props_vehicles/car002a", "props", 1000.0, [-2.2, 0, -1], [2.2, 1.5, 1])
	add.call("props_buildings/building001a", "props", 1e6, [-20, 0, -10], [20, 30, 10])
	add.call("props_foliage/tree_pine04", "props", 500.0, [-3, 0, -3], [3, 14, 3])
	add.call("props_foliage/shrub01a", "props", 5.0, [-0.75, 0, -0.75], [0.75, 1, 0.75])
	add.call("cliffs/rock01", "props", 5000.0, [-4, 0, -4], [4, 5, 4])
	add.call("antlion", "props", 50.0, [-1, 0, -1], [1, 1.5, 1])
	add.call("cranes/crane_frame", "props", 9000.0, [-5, 0, -5], [5, 30, 5])
	add.call("props_wasteland/laundry_cart001", "props", 20.0, [-0.5, 0, -0.5], [0.5, 1, 0.5])
	add.call("props_wasteland/barrel01", "props", 200.0, [-0.5, 0, -0.5], [0.5, 1.2, 0.5])
	add.call("props_junk/wood_chunk01", "gibs", 5.0, [-0.2, 0, -0.2], [0.2, 0.2, 0.2])
	add.call("items/healthkit", "props", 1.0, [-0.2, 0, -0.2], [0.2, 0.2, 0.2])
	add.call("humans/group01/male_01", "crowd", 60.0, [-0.3, 0, -0.3], [0.3, 1.8, 0.3])
	add.call("alyx", "drivers", 60.0, [-0.5, 0, -0.2], [0.5, 1.8, 0.2])
	add.call("hl1/crystal", "props", 100.0, [-1, 0, -1], [1, 2, 1])
	add.call("zz_unknown/thing", "props", 100.0, [-1, 0, -1], [1, 2, 1])
	for i in 30:
		add.call("props_junk/fake_%02d" % i, "props", 200.0, [-1.0 - i * 0.1, 0, -1], [1.0 + i * 0.1, 2, 1])
	return m


## The COMBINE TEST OVAL's road (LevelTemplates._oval): 14 m asphalt, two 270 m straights, two
## 90 m bends, the start on the top straight; nothing else on it. `terrain` false: no ground.
static func oval_doc(terrain := true) -> LevelDoc:
	var doc := LevelDoc.blank("CONTENT TEST", 1024.0, 513 if terrain else 0)
	doc.data["guid"] = GUID
	var r := 90.0
	var c45 := r * cos(PI / 4.0)
	var spots := [Vector2(-135, 90), Vector2(-45, 90), Vector2(45, 90), Vector2(135, 90),
		Vector2(135 + c45, c45), Vector2(135 + r, 0), Vector2(135 + c45, -c45), Vector2(135, -90),
		Vector2(45, -90), Vector2(-45, -90), Vector2(-135, -90),
		Vector2(-135 - c45, -c45), Vector2(-135 - r, 0), Vector2(-135 - c45, c45)]
	var pts := []
	for s in spots:
		pts.append({"uid": doc.new_uid(), "pos": [s.x, 0.0, s.y], "width": 14.0, "style": "asphalt"})
	doc.apply([LevelDoc.op_set(["road"], {"closed": true, "start": {"p": pts[1].uid, "t": 0.5}, "points": pts}),
		LevelDoc.op_set(["theme"], "city17")])
	return doc


static func point_uid(doc: LevelDoc, k: int) -> int:
	return int(doc.data.road.points[k].uid)


static func crowd(doc: LevelDoc, at: Dictionary, side: int, extra := {}) -> Dictionary:
	var g := {"uid": doc.new_uid(), "road": -1, "at": at, "side": side, "length": 20.0, "rows": 2, "density": 1.0,
		"setback": 2.5, "role": "citizen", "mood": "fan", "sit": 0.0, "tags": ["start"]}
	g.merge(extra, true)
	return g


static func compile(doc: LevelDoc, opts := {}) -> LevelBuild:
	var o := {"registries": REG, "chunks": false}
	o.merge(opts, true)
	return LevelCompiler.compile(doc, o)


static func vec(v: Variant) -> Vector3:
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


static func codes(b: LevelBuild, code: String) -> Array:
	var out := []
	for it in b.report.items:
		if str(it.code) == code:
			out.append(it)
	return out


## Plan metres from q past the edge of the nearest road (lateral where abreast).
static func road_gap(b: LevelBuild, q: Vector3) -> float:
	var best := INF
	for r in b.roads:
		var i := r.closest(Vector3(q.x, r.pos[0].y, q.z))
		var bd := INF
		for k in r.n:
			var d := Vector2(r.pos[k].x - q.x, r.pos[k].z - q.z).length_squared()
			if d < bd:
				bd = d
				i = k
		var d3 := Vector3(q.x - r.pos[i].x, 0.0, q.z - r.pos[i].z)
		best = minf(best, absf(d3.dot(r.flat_right[i])) - r.width[i] * 0.5)
	return best


static func min_spacing(people: Array) -> float:
	var best := INF
	for a in people.size():
		var p := vec(people[a].pos)
		for b in range(a + 1, people.size()):
			var q := vec(people[b].pos)
			if absf(p.y - q.y) < 1.5:
				best = minf(best, Vector2(p.x - q.x, p.z - q.z).length())
	return best


# ---------------------------------------------------------------- PropCatalog (fake)

func _catalog_case(t: Node) -> void:
	var want := {"props_c17/bench01a": "STREET FURNITURE", "props_c17/lamppost03a": "STREET FURNITURE",
		"props_c17/overpass_001a": "BRIDGES & BIG STRUCTURES", "props_c17/furniturecouch001a": "PRISON & INTERIORS",
		"props_junk/trashdumpster01a": "JUNK & CLUTTER", "props_vehicles/car002a": "VEHICLES",
		"props_buildings/building001a": "BUILDINGS", "props_foliage/tree_pine04": "TREES & PLANTS",
		"cliffs/rock01": "ROCKS & CLIFFS", "antlion": "ANIMATED", "cranes/crane_frame": "HAZARD RIGS",
		"props_wasteland/laundry_cart001": "PRISON & INTERIORS", "props_wasteland/barrel01": "INDUSTRIAL",
		"props_junk/wood_chunk01": "GIBS", "items/healthkit": "ITEMS", "humans/group01/male_01": "CROWD PEOPLE",
		"alyx": "DRIVERS", "hl1/crystal": "XEN FLORA", "zz_unknown/thing": "OTHER"}
	for k in want:
		t.check(str(PropCatalog.fact(k).get("category", "")) == want[k], "catalog: %s is %s (got %s)" % [k, want[k], PropCatalog.fact(k).get("category")])
	var bench := PropCatalog.fact("props_c17/bench01a")
	t.check(bench.physics_ok and bench.knockable and not bench.skinned and bench.collision == "HULL"
		and is_equal_approx(float(bench.size), 2.0) and bench.name == "BENCH01A", "catalog: the bench's facts %s" % bench)
	t.check(not PropCatalog.physics_ok("props_junk/trashdumpster01a") and PropCatalog.fact("props_junk/trashdumpster01a").knockable,
		"catalog: a 100 kg dumpster is no physics prop but knocks over")
	t.check(PropCatalog.fact("props_c17/lamppost03a").collision == "CYLINDER" and PropCatalog.fact("props_foliage/shrub01a").collision == "NONE"
		and PropCatalog.fact("hl1/crystal").collision == "BOX" and PropCatalog.fact("props_buildings/building001a").collision == "MESH",
		"catalog: collision kinds by Track._static_shape's rule")
	t.check(PropCatalog.fact("props_buildings/building001a").big and not PropCatalog.fact("cliffs/rock01").big, "catalog: big over 30 m")
	t.check(PropCatalog.fact("antlion").skinned, "catalog: bones in the meta make it skinned")
	t.check(not PropCatalog.physics_ok("humans/group01/male_01"), "catalog: physics_ok only for props")
	var all := PropCatalog.keys(PropCatalog.TAB_ALL)
	t.check(all.has("props_c17/bench01a") and not all.has("antlion") and not all.has("cranes/crane_frame")
		and not all.has("alyx") and not all.has("items/healthkit") and not all.has("props_junk/wood_chunk01")
		and not all.has("humans/group01/male_01"), "catalog: ALL hides animated, rigs and the hidden kinds")
	t.check(PropCatalog.keys(PropCatalog.TAB_ALL, true).has("antlion"), "catalog: SHOW ANIMATED lists the antlion")
	t.check(PropCatalog.keys(PropCatalog.ANIMATED).has("antlion") and PropCatalog.keys(PropCatalog.HAZARD_RIGS).has("cranes/crane_frame")
		and PropCatalog.keys("GIBS").is_empty() and PropCatalog.keys("STREET FURNITURE").size() == 2, "catalog: tabs by category")
	t.check(PropCatalog.search("BENCH") == PackedStringArray(["props_c17/bench01a"]), "catalog: search is case-insensitive")
	t.check(PropCatalog.search("street furn").size() == 2 and PropCatalog.search("pine 04").size() == 1
		and PropCatalog.search("nothing like it").is_empty(), "catalog: search over key words and the category")
	var tabs := PropCatalog.tabs()
	t.check(tabs.slice(0, 4) == PackedStringArray(["FAVOURITES", "RECENT", "ALL", "LIGHTS & FX"]) and tabs.has("OTHER")
		and not tabs.has("ANIMATED") and PropCatalog.tabs(true).has("ANIMATED"), "catalog: drawer tabs %s" % tabs)
	t.check(int(PropCatalog.counts().get("JUNK & CLUTTER", 0)) == 31 and PropCatalog.count_where("big") == 2, "catalog: counts")
	# LIGHTS & FX
	var fx := PropCatalog.fx_entries()
	t.check(fx.size() == 4 and fx[0].name == "LIGHT" and fx[1].name == "FIRE" and fx[2].name == "EMBERS"
		and fx[3].name == "BREENCAST SCREEN", "catalog: four LIGHTS & FX entries")
	var doc := oval_doc()
	var fi := PropCatalog.fx_item("fire", Vector3(1, 2, 3), doc)
	t.check(fi.size() == 2 and fi[0] == "fires" and fi[1].size == 1.0 and fi[1].smoke == 1.0 and fi[1].light == true
		and fi[1].pos == [1.0, 2.0, 3.0] and int(fi[1].uid) > 0, "catalog: FIRE stamps a fires entry %s" % [fi])
	var em := PropCatalog.fx_item("embers", Vector3.ZERO)
	t.check(em[0] == "fires" and em[1].size == 0.0 and em[1].smoke == 1.0 and not em[1].has("uid"), "catalog: EMBERS = size 0, smoke 1")
	t.check(PropCatalog.fx_item("light", Vector3.ZERO)[0] == "lights" and PropCatalog.fx_item("screen", Vector3.ZERO)[0] == "screens"
		and PropCatalog.fx_item("nope", Vector3.ZERO).is_empty(), "catalog: LIGHT and SCREEN sections")
	t.check(PropCatalog.fx_enabled("screen", doc), "catalog: the screen with the combine arch")
	doc.apply([LevelDoc.op_set(["race", "gantry"], "blackmesa")])
	t.check(not PropCatalog.fx_enabled("screen", doc) and PropCatalog.fx_enabled("light", doc), "catalog: the screen greyed without it")
	# favourites and recent (settings restored)
	var fav0 = Game.settings.get("editor_fav_props", []).duplicate()
	var rec0 = Game.settings.get("editor_recent_props", []).duplicate()
	t.check(PropCatalog.toggle_favourite("cliffs/rock01") and PropCatalog.is_favourite("cliffs/rock01")
		and PropCatalog.keys(PropCatalog.TAB_FAVOURITES).has("cliffs/rock01"), "catalog: a star makes a favourite")
	t.check(not PropCatalog.toggle_favourite("cliffs/rock01") and not PropCatalog.is_favourite("cliffs/rock01"), "catalog: and unstars it")
	for i in 20:
		PropCatalog.note_placed("props_junk/fake_%02d" % i)
	PropCatalog.note_placed("props_junk/fake_05")
	var rec := PropCatalog.recent()
	t.check(rec.size() == 16 and rec[0] == "props_junk/fake_05" and rec[1] == "props_junk/fake_19" and rec.count("props_junk/fake_05") == 1,
		"catalog: RECENT keeps the last 16 placed")
	Game.settings["editor_fav_props"] = fav0
	Game.settings["editor_recent_props"] = rec0
	Game.save_settings()
	# the cache file
	var path: String = t.tmp("prop_catalog.json")
	var f := PropCatalog.facts()
	t.check(PropCatalog.save_cache(path, 7, f.size(), f) == OK, "catalog: cache written")
	var back := PropCatalog.load_cache(path, 7, f.size())
	t.check(JSON.stringify(back, "", true) == JSON.stringify(f, "", true), "catalog: the cache reads back the same facts")
	t.check(PropCatalog.load_cache(path, 8, f.size()).is_empty() and PropCatalog.load_cache(path, 7, f.size() + 1).is_empty(),
		"catalog: another content version or count is not used")
	# the palette
	var pal := LevelDress.palette("city17")
	var cats := LevelThemes.categories("city17")
	var ok := pal.size() == 12
	var sorted := Array(pal)
	sorted.sort()
	for k in pal:
		var e := PropCatalog.fact(k)
		ok = ok and str(e.category) in cats and float(e.size) >= 1.0 and float(e.size) <= 12.0 and not e.skinned and not e.physics_ok
	t.check(ok and Array(pal) == sorted, "palette: 12 static models of the theme's categories, 1-12 m, by key %s" % pal)
	t.check(LevelDress.palette("") == pal and LevelDress.palette("xen") == PackedStringArray(["cliffs/rock01", "hl1/crystal"]),
		"palette: no theme = city17; xen takes what its categories have %s" % LevelDress.palette("xen"))


# ---------------------------------------------------------------- crowds

func _crowds_case(t: Node) -> void:
	var doc := oval_doc()
	var start: Dictionary = doc.data.road.start
	doc.apply([LevelDoc.op_set(["crowds"], [crowd(doc, start, -1), crowd(doc, start, 1, {"sit": 0.5, "mood": "excited"})])])
	var b := compile(doc)
	var groups: Array = b.data.crowd_groups
	var people: Array = b.data.crowds
	t.check(groups.size() == 2 and people.size() > 70, "crowds: 2 groups, %d people" % people.size())
	if groups.size() < 2:
		return
	var main := b.roads[0]
	var s0 := main.anchor_s(start)
	var g0: Dictionary = groups[0]
	t.check(g0.id == 0 and groups[1].id == 1 and g0.kind == "line" and g0.role == "citizen" and g0.side == -1 and groups[1].side == 1
		and g0.bed == "human" and g0.tags == ["start"] and not g0.has("route"), "crowds: group entries %s" % g0)
	t.check(absf(float(g0.watch[0]) - (s0 - 20.0)) < 0.11 and absf(float(g0.watch[1]) - (s0 + 20.0)) < 0.11, "crowds: watch s +- (length / 2 + 10)")
	var pal := Array(LevelCrowds.PALETTE.citizen)
	var ok := true
	var sat := 0
	var centre := [Vector3.ZERO, Vector3.ZERO]
	var cnt := [0, 0]
	for k in people.size():
		var m: Dictionary = people[k]
		ok = ok and m.model in pal and m.role == "citizen" and int(m.group) in [0, 1] and int(m.lod) == LevelCrowds.LOD_CYCLE[k % 20]
		ok = ok and (m.pos as Array).size() == 3 and m.yaw is float and m.seed is int and m.dodge == true
		ok = ok and m.mood == ("fan" if int(m.group) == 0 else "excited")
		if m.pose == "sit":
			sat += 1
			ok = ok and int(m.group) == 1
		centre[int(m.group)] += vec(m.pos)
		cnt[int(m.group)] += 1
	t.check(ok, "crowds: members carry palette models, role, mood, group, the LOD cycle, seed and dodge")
	t.check(sat > 5 and sat < cnt[1] - 5, "crowds: about half of the second group sits (%d of %d)" % [sat, cnt[1]])
	t.check(vec(g0.center).distance_to(centre[0] / float(cnt[0])) < 0.01, "crowds: the centre is the members' mean")
	var sp := min_spacing(people)
	t.check(sp >= 0.75 - 1e-3, "crowds: spacing >= 0.75 seated / 0.85 (min %.3f)" % sp)
	var sp0 := min_spacing(people.filter(func(m): return int(m.group) == 0))
	t.check(sp0 >= SPACING_OK, "crowds: standing spacing >= 0.85 (min %.3f)" % sp0)
	var gap := INF
	for m in people:
		gap = minf(gap, road_gap(b, vec(m.pos)))
	t.check(gap >= 0.5 - 1e-3, "crowds: nobody on a road (closest %.2f m past the edge)" % gap)
	# they face the road
	var m0: Dictionary = people[0]
	var i0 := main.closest(vec(m0.pos))
	var to_road := main.pos[i0] - vec(m0.pos)
	var face := Vector3(sin(float(m0.yaw)), 0.0, cos(float(m0.yaw)))
	t.check(face.dot(Vector3(to_road.x, 0, to_road.z).normalized()) > 0.8, "crowds: people face the road")
	t.check(int(b.stats.people) == people.size() and codes(b, "crowd").is_empty(), "crowds: stats.people, no crowd warning")
	var b2 := compile(doc)
	t.check(JSON.stringify(b2.data.crowds) == JSON.stringify(people) and JSON.stringify(b2.data.crowd_groups) == JSON.stringify(groups),
		"crowds: the same doc compiles the same people")
	# palette filtered by the install's models, then CrowdRules.FALLBACK
	var reg := REG.duplicate(true)
	reg.models = {"humans/group01/male_03": {}}
	var b3 := compile(doc, {"registries": reg})
	t.check(not b3.data.crowds.is_empty() and b3.data.crowds.all(func(m): return m.model == "humans/group01/male_03"),
		"crowds: only the citizen models this install has")
	reg.models = {"odessa": {}}
	var b4 := compile(doc, {"registries": reg})
	t.check(not b4.data.crowds.is_empty() and b4.data.crowds.all(func(m): return m.model == "odessa"), "crowds: CrowdRules.FALLBACK stands in")
	reg.models = {"nobody_at_all": {}}
	var b5 := compile(doc, {"registries": reg})
	var w5 := codes(b5, "crowd")
	t.check(b5.data.crowds.is_empty() and b5.data.crowd_groups.is_empty() and w5.size() == 1
		and str(w5[0].text).contains("no model for their role"), "crowds: no model -> left out with the crowd warning %s" % [w5])
	# no terrain: nothing to stand on beside the road (pits everywhere)
	var bare := oval_doc(false)
	bare.apply([LevelDoc.op_set(["crowds"], [crowd(bare, bare.data.road.start, -1)])])
	var b6 := compile(bare)
	var w6 := codes(b6, "crowd")
	t.check(b6.data.crowds.is_empty() and w6.size() == 1 and str(w6[0].text).begins_with("41 of 41 spectators were left out")
		and str(w6[0].text).contains("over a drop") and int(w6[0].uid) == int(bare.data.crowds[0].uid),
		"crowds: no ground -> nobody over the drop %s" % [w6])
	# in water: the sea over the ground, a lake under one group
	var wet := oval_doc()
	wet.apply([LevelDoc.op_set(["crowds"], [crowd(wet, wet.data.road.start, -1)]), LevelDoc.op_set(["water"], {"sea": true, "level": 0.5})])
	var b7 := compile(wet)
	t.check(b7.data.crowds.is_empty() and str(codes(b7, "crowd")[0].text).contains("in water"), "crowds: nobody under the sea")
	var lake := oval_doc()
	var c0 := vec(g0.center)
	lake.apply([LevelDoc.op_set(["crowds"], [crowd(lake, lake.data.road.start, -1), crowd(lake, lake.data.road.start, 1)]),
		LevelDoc.op_set(["lakes"], [{"uid": lake.new_uid(), "center": [c0.x, c0.z], "size": [60.0, 12.0], "level": 1.0}])])
	var b8 := compile(lake)
	t.check(b8.data.crowd_groups.size() == 1 and int(b8.data.crowd_groups[0].side) == 1 and int(b8.data.crowd_groups[0].id) == 0
		and b8.data.crowds.all(func(m): return int(m.group) == 0), "crowds: a group in a lake is dropped, the other keeps id 0")
	t.check(str(codes(b8, "crowd")[0].text).contains("in water"), "crowds: and the lake is the reason")

const SPACING_OK := 0.85 - 1e-3


# ---------------------------------------------------------------- the rules one by one (hooks)

## Tests: a pit and a reserved corridor beside the start groups before LevelCrowds runs.
class HookCrowds:
	static var pit := Vector2.ZERO
	static var corridor := PackedVector3Array()

	static func compile(ctx: LevelContext) -> void:
		ctx.pits.append({"center": pit, "radius": 4.0, "floor_y": -20.0})
		ctx.reserved.append([corridor, 2.0])
		LevelCrowds.compile(ctx)

	static func lint(ctx: LevelContext) -> void:
		LevelCrowds.lint(ctx)


func _rules_case(t: Node) -> void:
	var doc := oval_doc()
	var start: Dictionary = doc.data.road.start
	doc.apply([LevelDoc.op_set(["crowds"], [crowd(doc, start, -1), crowd(doc, start, 1)])])
	var base := compile(doc)
	if base.data.crowd_groups.size() < 2:
		t.fail("rules: the base crowds did not compile")
		return
	var c0 := vec(base.data.crowd_groups[0].center)
	var c1 := vec(base.data.crowd_groups[1].center)
	HookCrowds.pit = Vector2(c0.x, c0.z)
	HookCrowds.corridor = PackedVector3Array([c1 + Vector3(-1, 0, -30), c1 + Vector3(1, 0, 30)])
	var b := compile(doc, {"hooks": {"crowds": HookCrowds}})
	var people: Array = b.data.crowds
	var ok := true
	for m in people:
		var q := vec(m.pos)
		ok = ok and Vector2(q.x, q.z).distance_to(HookCrowds.pit) > 4.0
		ok = ok and Vector2(q.x, q.z).distance_to(Vector2(c1.x, c1.z)) > 1.9
	var w := codes(b, "crowd")
	t.check(ok and people.size() < base.data.crowds.size() - 10, "rules: nobody in the tentacle's pit or the reserved corridor")
	t.check(w.size() == 1 and str(w[0].text).contains("over a drop") and str(w[0].text).contains("in a hazard's way"),
		"rules: the crowd warning names both %s" % [w])
	# unit checks through spot_fail on a hand-made context
	var ctx := LevelContext.new()
	ctx.doc = doc
	ctx.registries = {"models": {"box": {"aabb_min": [-2, 0, -2], "aabb_max": [2, 3, 2]}}}
	ctx.terrain = LevelTerrain.from_doc(doc)
	ctx.data = {"sea_level": -1000.0, "waters": []}
	ctx.props = [{"model": "box", "pos": [300.0, 0.0, 300.0], "yaw": 0.0}, {"model": "unknown", "pos": [320.0, 0.0, 300.0]}]
	t.check(LevelCrowds.spot_fail(ctx, Vector3(300, 0, 300)) == "prop" and LevelCrowds.spot_fail(ctx, Vector3(302.3, 0, 300)) == "prop"
		and LevelCrowds.spot_fail(ctx, Vector3(302.6, 0, 300)) == "" and LevelCrowds.spot_fail(ctx, Vector3(320, 0, 300)) == "",
		"rules: 0.45 m round a known prop's box, unknown models ignored")
	ctx.data.sea_level = 1.0
	t.check(LevelCrowds.spot_fail(ctx, Vector3(250, 0, 250)) == "water", "rules: under the sea")
	ctx.data.sea_level = -1000.0
	t.check(LevelCrowds.spot_fail(ctx, Vector3(250, NAN, 250)) == "ground", "rules: no ground")
	# a slope of 0.6 (one cell rises 1.2 m per 2 m)
	var steep := LevelDoc.blank("STEEP", 512.0, 257)
	var h := PackedFloat32Array()
	h.resize(257 * 257)
	for z in 257:
		for x in 257:
			h[z * 257 + x] = x * 2.0 * 0.6
	steep.apply([LevelDoc.op_heights_all(h)])
	var sc := LevelContext.new()
	sc.doc = steep
	sc.terrain = LevelTerrain.from_doc(steep)
	sc.data = {"sea_level": -1000.0}
	var q := Vector3(10, sc.ground(10, 10), 10)
	t.check(LevelCrowds.spot_fail(sc, q, true) == "slope" and LevelCrowds.spot_fail(sc, q, false) == "", "rules: slope over 0.45 on the ground only")


func _people_cap_case(t: Node) -> void:
	var doc := oval_doc()
	var at := {"p": point_uid(doc, 8), "t": 0.5}
	var dense := {"length": 120.0, "rows": 4, "density": 2.0, "setback": 3.0, "tags": []}
	doc.apply([LevelDoc.op_set(["crowds"], [crowd(doc, at, 1, dense)])])
	var b := compile(doc)
	var n: int = b.data.crowds.size()
	var budget := codes(b, "budget").filter(func(it): return str(it.text).contains("spectators"))
	t.check(n > 450 and n <= 600 and budget.size() == 1, "people: %d in one dense group -> the 450 budget warning" % n)
	t.check(min_spacing(b.data.crowds) >= SPACING_OK, "people: a dense group keeps 0.85 m apart")
	doc.apply([LevelDoc.op_insert(["crowds"], 1, crowd(doc, at, -1, dense))])
	var b2 := compile(doc)
	var w := codes(b2, "crowd")
	t.check(b2.data.crowds.size() == 600 and w.size() == 1 and str(w[0].text).contains("past the limit of 600"),
		"people: built members stop at 600 %s" % [w])
	var ms := float((b2.stats.get("times", {}) as Dictionary).get("hooks", 0.0))
	t.log("1132 spectators wanted, 600 placed: crowds compile %.1f ms" % ms)
	t.check(ms <= 100.0 * slack, "people: the crowd step <= 100 ms (%.1f ms)" % ms)


# ---------------------------------------------------------------- eggs

func _eggs_case(t: Node) -> void:
	var doc := oval_doc()
	var eggs := [
		{"uid": doc.new_uid(), "kind": "gman", "pos": [0.0, 0.0, -110.0], "yaw": 90.0, "chance": 0.7},
		{"uid": doc.new_uid(), "kind": "holo", "pos": [10.0, 0.0, -102.0], "yaw": 0.0},
		{"uid": doc.new_uid(), "kind": "birds", "pos": [0.0, 0.0, 0.0], "species": "crow", "radius": 10.0, "count": 6},
		{"uid": doc.new_uid(), "kind": "gnome", "pos": [5.0, 0.0, 5.0], "yaw": 180.0},
		{"uid": doc.new_uid(), "kind": "nihilanth", "pos": [0.0, 300.0, 0.0]},
		{"uid": doc.new_uid(), "kind": "lamarr", "pos": [20.0, 0.0, 20.0], "path": [[20.0, 0.0, 20.0], [30.0, 0.0, 20.0]]},
		{"uid": doc.new_uid(), "kind": "zombies", "pos": [40.0, 0.0, 40.0], "path": [[40.0, 0.0, 40.0], [60.0, 0.0, 40.0]], "count": 4},
		{"uid": doc.new_uid(), "kind": "zombies", "pos": [40.0, 0.0, 40.0], "path": [[40.0, 0.0, 40.0]]},
	]
	doc.apply([LevelDoc.op_set(["eggs"], eggs)])
	var b := compile(doc)
	var by := {}
	for e in b.data.crowd_eggs:
		by[str(e.kind)] = e
	var gm: Dictionary = by.get("gman", {})
	var main := b.roads[0]
	var s := main.s[main.closest(Vector3(0, 0, -110))]
	t.check(gm.keys() == ["kind", "pos", "yaw", "s", "model", "window", "chance"] and gm.model == "gman_high"
		and absf(float(gm.s) - s) < 0.11 and absf(float(gm.window[0]) - (s - 40.0)) < 0.2 and absf(float(gm.window[1]) - (s + 40.0)) < 0.2
		and is_equal_approx(float(gm.chance), 0.7) and is_equal_approx(float(gm.yaw), snappedf(PI / 2.0, 0.001)), "eggs: the G-Man %s" % gm)
	t.check(not by.has("holo") and codes(b, "crowd").any(func(it): return str(it.text).contains("hologram needs a jump")),
		"eggs: a hologram on a road without a jump is dropped with a crowd warning")
	t.check(by.get("birds", {}) == {"kind": "birds", "species": "crow", "center": [0.0, 0.0, 0.0], "radius": 10.0, "count": 6},
		"eggs: birds %s" % by.get("birds"))
	t.check(by.get("gnome", {}).keys() == ["kind", "pos", "yaw"] and by.get("nihilanth", {}) == {"kind": "nihilanth", "pos": [0.0, 300.0, 0.0]},
		"eggs: gnome and nihilanth")
	t.check(by.get("lamarr", {}) == {"kind": "lamarr", "path": [[20.0, 0.0, 20.0], [30.0, 0.0, 20.0]]}, "eggs: Lamarr's path")
	t.check(by.get("zombies", {}) == {"kind": "zombies", "path": [[40.0, 0.0, 40.0], [60.0, 0.0, 40.0]], "count": 4, "model": "zombie/classic"},
		"eggs: zombies; the one with a single point is dropped")
	t.check(b.data.crowd_eggs.size() == 6, "eggs: six kept of eight")
	# with a jump on the bottom straight the hologram watches it
	doc.apply([LevelDoc.op_set(["road", "points", "#%d" % point_uid(doc, 8), "gap"], {"len": 12.0, "at": 0.5, "lift": 1.8, "ramp": 16.0})])
	var b2 := compile(doc)
	var holo := {}
	for e in b2.data.crowd_eggs:
		if e.kind == "holo":
			holo = e
	var m2 := b2.roads[0]
	var g: Vector2i = m2.gaps[0] if not m2.gaps.is_empty() else Vector2i.ZERO
	t.check(holo.keys() == ["kind", "pos", "yaw", "gap"] and absf(float(holo.gap[0]) - m2.s[g.x]) < 0.11
		and absf(float(holo.gap[1]) - m2.s[g.y - 1]) < 0.11 and float(holo.gap[1]) > float(holo.gap[0]), "eggs: holo gap = the jump's metres %s" % holo)
	# nobody stands on an egg
	doc.apply([LevelDoc.op_set(["crowds"], [crowd(doc, doc.data.road.start, -1)])])
	var b3 := compile(doc)
	var c := vec(b3.data.crowd_groups[0].center) if not b3.data.crowd_groups.is_empty() else Vector3.ZERO
	doc.apply([LevelDoc.op_insert(["eggs"], 0, {"uid": doc.new_uid(), "kind": "gnome", "pos": [c.x, c.y, c.z], "yaw": 0.0})])
	var b4 := compile(doc)
	t.check(b4.data.crowds.all(func(m): return Vector2(vec(m.pos).x - c.x, vec(m.pos).z - c.z).length() >= 1.2)
		and b4.data.crowds.size() < b3.data.crowds.size(), "eggs: people make way for the gnome")


# ---------------------------------------------------------------- a branch (stub hook)

## A kept branch road (uid 77) 40 m outside the top straight, no jump.
class OneBranch:
	static func build(ctx: LevelContext) -> void:
		var pts := []
		for k in 4:
			pts.append({"uid": 900 + k, "pos": [-90.0 + k * 60.0, 0.0, 130.0], "width": 10.0, "style": "asphalt"})
		var r := LevelRoad.build(pts, ctx.styles, false, {"key": 77})
		ctx.branches = [{"uid": 77, "ok": true}]
		ctx.roads.append(r)


func _branch_case(t: Node) -> void:
	var doc := oval_doc()
	doc.apply([LevelDoc.op_set(["crowds"], [crowd(doc, {"p": 901, "t": 0.5}, 1, {"road": 77, "tags": ["jump", "bogus"]}),
			crowd(doc, {"p": 901, "t": 0.5}, 1, {"road": 55})]),
		LevelDoc.op_set(["eggs"], [{"uid": doc.new_uid(), "kind": "gman", "pos": [0.0, 0.0, 140.0], "yaw": 0.0},
			{"uid": doc.new_uid(), "kind": "holo", "pos": [0.0, 0.0, 138.0], "yaw": 0.0}])])
	var b := compile(doc, {"hooks": {"branches": OneBranch}})
	var gs: Array = b.data.crowd_groups
	t.check(gs.size() == 1 and gs[0].get("route") == "b77" and gs[0].tags == ["jump"], "branch: a group on a branch has its route %s" % [gs])
	var ok: bool = not b.data.crowds.is_empty()
	for m in b.data.crowds:
		ok = ok and road_gap(b, vec(m.pos)) >= 0.5 - 1e-3
	t.check(ok, "branch: nobody on the branch road")
	var gm := {}
	for e in b.data.crowd_eggs:
		if e.kind == "gman":
			gm = e
	t.check(gm.get("route") == "b77", "branch: the G-Man by the branch watches it")
	var br: LevelRoad = b.roads[1] if b.roads.size() > 1 else null
	var rows := LevelDress.items_ops(doc, b).filter(func(op): return int(op[3].road) == 77)
	t.check(br != null and rows.size() == 1 and absf(br.anchor_s(rows[0][3].at) - br.length * 0.5) <= 4.0,
		"branch: AUTO ITEMS puts one row at the branch's middle")
	var w := codes(b, "crowd")
	t.check(w.any(func(it): return str(it.text).contains("beside a branch that is left out"))
		and w.any(func(it): return str(it.text).contains("hologram")), "branch: a group of a missing branch and a jumpless hologram are reported")


# ---------------------------------------------------------------- AUTO DRESS

func _dress_case(t: Node) -> void:
	var doc := oval_doc()
	doc.apply([LevelDoc.op_set(["road", "points", "#%d" % point_uid(doc, 8), "gap"], {"len": 12.0, "at": 0.5, "lift": 1.8, "ramp": 16.0})])
	var b := compile(doc)
	var main := b.roads[0]
	var ops := LevelDress.ops(doc, b, {})
	t.check(not ops.is_empty(), "dress: AUTO DRESS has ops")
	var counts := LevelDress.last.duplicate()
	doc.apply(ops)
	var b2 := compile(doc)
	var m := b2.roads[0]
	var L := m.length
	# crate rows
	var rows := []
	for it in doc.data.items:
		if int(it.road) == -1:
			rows.append(m.anchor_s(it.at))
	rows.sort()
	var jump_s := m.s[m.gaps[0].x] if not m.gaps.is_empty() else -1000.0
	var ok := rows.size() >= 2
	for k in rows.size():
		var s: float = rows[k]
		var i := m.idx(s)
		var u := fposmod(s, L)
		ok = ok and u > 20.0 - 2.0 and u < L - 80.0 + 2.0
		ok = ok and LevelDress._lap_d(s, jump_s, L) > 30.0 - 2.0
		for d in range(-7, 8):
			ok = ok and absf(m.curv[m.wrap(i + d)]) < LevelDress.STRAIGHT
		if k > 0:
			var gap: float = rows[k] - rows[k - 1]
			ok = ok and gap >= 350.0 - 2.5 and gap <= 450.0 + 2.5
	t.check(ok, "dress: %d crate rows 350-450 m apart on straights, off the grid and the jump %s (lap %.0f, jump %.0f)" % [rows.size(), rows, L, jump_s])
	t.check(int(counts.get("rows", 0)) == rows.size() and doc.data.items.all(func(it): return int(it.count) == 0 and is_equal_approx(float(it.inset), 2.5)),
		"dress: auto counts, inset 2.5")
	t.check(LevelDress.items_ops(doc, b2).is_empty() and int(LevelDress.last.rows_kept) == rows.size(), "dress: rows already there are kept and counted")
	# boost pads
	var bends := LevelDress.bends(m)
	t.check(bends.size() == 2 and float(bends[0].length) > 180.0 and float(bends[0].length) < PI * 90.0 + 20.0
		and absf(float(bends[0].length) - float(bends[1].length)) < 4.0, "dress: the oval has two like bends %s" % [bends])
	var pads: Array = doc.data.pads
	ok = pads.size() == 2
	for p in pads:
		var s := m.anchor_s(p.at)
		var i := m.idx(s)
		var after := INF
		for e in bends.slice(0, 2):
			after = minf(after, LevelDress._lap_d(s, m.s[int(e.exit)], L))
		ok = ok and after <= 4.0 and absf(m.curv[i]) < LevelDress.STRAIGHT and p.lat == null and float(p.turn) == 0.0
		for rs in rows:
			ok = ok and LevelDress._lap_d(s, rs, L) >= 10.0
	t.check(ok, "dress: two pads on the racing line at the bend exits, 10 m from crates")
	t.check(codes(b2, "pad_crate").is_empty() and codes(b2, "pad_grid").is_empty() and codes(b2, "no_items").is_empty(), "dress: no pad or item warning")
	t.check(LevelDress.pads_ops(doc, b2).is_empty() and int(LevelDress.last.pads_kept) == 2, "dress: pads already there are kept")
	# rails: the oval's 90 m bends are not tight
	t.check(int(counts.get("rails", -1)) == 0, "dress: no rails on 90 m bends")
	# scenery
	var group := -1
	var props := []
	for p in doc.data.props:
		props.append(p)
		group = int(p.get("group", -1))
	var pal := LevelDress.palette("city17")
	ok = props.size() > 40 and props.size() <= 1500
	var gap_min := INF
	for p in props:
		var q := vec(p.pos)
		var foot := LevelDress._foot(str(p.model), float(p.scale))
		var g := road_gap(b2, q) - foot - LevelDress.SCENERY_ROAD - m.treatment(0, 1)
		gap_min = minf(gap_min, g)
		ok = ok and str(p.model) in pal and int(p.group) == group and float(p.scale) >= 0.8 - 1e-6 and float(p.scale) <= 1.2 + 1e-6
		var g0 := b2.terrain.height_at(q.x, q.z)
		ok = ok and q.y <= g0 + 0.01 and q.y >= g0 - 1.0 and p.physics == false
		var i := m.closest(q)
		ok = ok and not LevelDress._in_grid_s(m.s[i], L)
	t.check(ok and gap_min >= -0.6, "dress: %d props of the palette, on the ground, off the grid, never on a road (closest %.2f)" % [props.size(), gap_min])
	t.check(codes(b2, "prop_on_road").is_empty(), "dress: no prop on a road for the checklist")
	# the grandstand
	var stands: Array = doc.data.crowds
	ok = stands.size() == 2 and int(stands[0].side) == -1 and int(stands[1].side) == 1
	for g in stands:
		ok = ok and g.tags == ["start"] and g.role == "citizen" and g.mood == "fan" and float(g.length) == 20.0
		ok = ok and int(g.rows) == 2 and g.at == doc.data.road.start
	t.check(ok, "dress: one grandstand both sides of the start")
	t.check(LevelDress.crowd_ops(doc, b2).is_empty(), "dress: only one grandstand")
	t.check(not b2.data.crowds.is_empty(), "dress: the grandstand compiles to people")
	var tpl := LevelTemplates.make("oval", "TPL")
	t.check(LevelDress.crowd_ops(tpl, compile(tpl)).is_empty(), "dress: the template's start crowd counts as one")
	# toggles
	var only := LevelDress.ops(oval_doc(), b, {"items": false, "pads": false, "rails": false, "scenery": false})
	t.check(only.size() == 2 and str(only[0][1][0]) == "crowds", "dress: the toggles leave parts out")
	t.check(LevelDress.ops(doc, null, {}).is_empty() and LevelDress.scenery_ops(oval_doc(false), compile(oval_doc(false)), "city17").is_empty(),
		"dress: no bake / no terrain -> nothing")


func _rails_case(t: Node) -> void:
	var doc := oval_doc()
	var b := compile(doc)
	var m := b.roads[0]
	t.check(LevelDress.rails_ops(doc, b).is_empty(), "rails: none under 60 m on the oval")
	var ops := LevelDress.rails_ops(doc, b, 100.0)
	var ok := ops.size() >= 6
	for op in ops:
		var path: Array = op[1]
		var puid := str(path[2]).substr(1).to_int()
		var k := m.point_uids.find(puid)
		var ids := LevelDress._seg_samples(m, k)
		var j: int = ids[ids.size() / 2]
		var sgn := -1.0 if str(path[3]) == "barrier_l" else 1.0
		var out := Vector3(m.pos[j].x, 0, m.pos[j].z).normalized()
		var cmax := 0.0
		for i in ids:
			cmax = maxf(cmax, absf(m.curv[i]))
		ok = ok and op[0] == "set" and path[0] == "road" and (m.flat_right[j] * sgn).dot(out) > 0.3 and 1.0 / cmax < 100.0
		ok = ok and op[2].kind == "rail" and op[2].mat == "metal/metalrail013a"
	t.check(ok, "rails: %d segments of the bends get a rail on their outside" % ops.size())
	doc.apply(ops)
	var b2 := compile(doc)
	t.check(LevelDress.rails_ops(doc, b2, 100.0).is_empty(), "rails: a side with a barrier gets none")
	# a style with its own rails, and an author's NONE, are left alone
	var d3 := oval_doc()
	var pts: Array = d3.data.road.points
	var set := []
	for k in range(3, 7):
		set.append(LevelDoc.op_set(["road", "points", "#%d" % pts[k].uid, "style"], "asphalt_rail"))
	for k in range(10, 14):
		set.append(LevelDoc.op_set(["road", "points", "#%d" % pts[k].uid, "barrier_l"], {"kind": "none"}))
		set.append(LevelDoc.op_set(["road", "points", "#%d" % pts[k].uid, "barrier_r"], {"kind": "none"}))
	d3.apply(set)
	var b3 := compile(d3)
	var kept := []
	for k in range(3, 7) + range(10, 14):
		kept.append("#%d" % pts[k].uid)
	var touched := LevelDress.rails_ops(d3, b3, 100.0).filter(func(op): return str(op[1][2]) in kept)
	t.check(touched.is_empty(), "rails: styled rails and NONE overrides are kept %s" % [touched])


func _scenery_budget_case(t: Node) -> void:
	var doc := oval_doc()
	var props := []
	for k in 1495:
		props.append({"uid": doc.new_uid(), "model": "props_junk/fake_00", "pos": [400.0 + (k % 40) * 2.5, 0.0, 400.0 + (k / 40) * 2.5],
			"yaw": 0.0, "pitch": 0.0, "roll": 0.0, "scale": 1.0, "physics": false, "tag": ""})
	doc.apply([LevelDoc.op_set(["props"], props)])
	var b := compile(doc)
	var ops := LevelDress.scenery_ops(doc, b, "city17")
	t.check(ops.size() == 5, "scenery: stops at the 1500 budget (%d added)" % ops.size())


func _same_twice_case(t: Node) -> void:
	var a := oval_doc()
	var b := oval_doc()
	var oa := LevelDress.ops(a, compile(a), {})
	var ob := LevelDress.ops(b, compile(b), {})
	t.check(not oa.is_empty() and JSON.stringify(oa) == JSON.stringify(ob), "dress: the same doc dresses the same way twice")
	var c := oval_doc()
	c.data["guid"] = "fedcba9876543210fedcba9876543210"
	var oc := LevelDress.ops(c, compile(c), {})
	t.check(JSON.stringify(oc) != JSON.stringify(oa), "dress: another guid dresses differently")


# ---------------------------------------------------------------- CONTENT

func _content_case(t: Node) -> void:
	# computed from the models and their metas (the cache file is made again)
	DirAccess.remove_absolute(PropCatalog.CACHE)
	PropCatalog.reset()
	var t0 := Time.get_ticks_msec()
	var f := PropCatalog.facts()
	var cold := Time.get_ticks_msec() - t0
	t.check(f.size() == Game.models.size(), "content: every model has facts (%d)" % f.size())
	var counts := PropCatalog.counts()
	if Game.models.size() == 571:
		for c in PROBE:
			t.check(int(counts.get(c, 0)) == int(PROBE[c]), "content: %s %d (probe %d)" % [c, int(counts.get(c, 0)), PROBE[c]])
		t.check(int(counts.get("OTHER", 0)) == 0, "content: nothing falls in OTHER")
		t.check(PropCatalog.count_where("physics_ok") == 105, "content: physics_ok has 105 models (%d)" % PropCatalog.count_where("physics_ok"))
		var light := 0
		var differ := []
		for k in Game.models:
			var ok := LevelCompiler._light_enough(Game.models[k], 1.0)
			light += 1 if ok else 0
			if ok != PropCatalog.physics_ok(k) and differ.size() < 4:
				differ.append(k)
		t.check(light == 105 and differ.is_empty(), "content: the compiler knocks over the catalog's 105 PHYSICS models (%d; differ %s)" % [light, str(differ)])
		t.check(PropCatalog.count_where("big") == 36 and PropCatalog.count_where("skinned") == 138,
			"content: 36 big, 138 skinned (%d, %d)" % [PropCatalog.count_where("big"), PropCatalog.count_where("skinned")])
	else:
		print("case_content: %d models, not the probe's install (571): counts not compared" % Game.models.size())
	t.check(FileAccess.file_exists(PropCatalog.CACHE), "content: the facts are cached in %s" % PropCatalog.CACHE)
	PropCatalog.reset()
	t0 = Time.get_ticks_msec()
	var again := PropCatalog.facts()
	var warm := Time.get_ticks_msec() - t0
	t.check(JSON.stringify(again, "", true) == JSON.stringify(f, "", true), "content: the cache gives the same facts (cold %d ms, warm %d ms)" % [cold, warm])
	t.log("catalog facts: %d models, cold %d ms, from the cache %d ms; physics_ok %d, big %d, skinned %d" % [f.size(), cold, warm,
		PropCatalog.count_where("physics_ok"), PropCatalog.count_where("big"), PropCatalog.count_where("skinned")])
	for th in LevelThemes.IDS:
		var pal := LevelDress.palette(th)
		var ok := pal.size() == 12
		for k in pal:
			var e := PropCatalog.fact(k)
			ok = ok and Game.models.has(k) and str(e.category) in LevelThemes.categories(th) and not e.skinned and not e.physics_ok
		t.check(ok, "content: palette(%s) %s" % [th, pal])
	# real crowd models and a dressed oval with real props
	var doc := oval_doc()
	var reg := LevelCompiler.registries()
	var b := LevelCompiler.compile(doc, {"registries": reg, "chunks": false})
	doc.apply(LevelDress.ops(doc, b, {}))
	var b2 := LevelCompiler.compile(doc, {"registries": reg, "chunks": false})
	t.check(not b2.data.crowds.is_empty() and b2.data.crowds.all(func(m): return Game.models.has(str(m.model))),
		"content: spectators wear models this install has")
	t.check(not b2.data.props.is_empty() and b2.data.props.all(func(p): return Game.models.has(str(p.model))) and b2.report.missing.models == 0,
		"content: AUTO DRESS scenery uses real models (%d props)" % b2.data.props.size())
	t.check(codes(b2, "prop_on_road").is_empty(), "content: no scenery on a road")
	_themes_content(t, reg)


## L4: every template and every theme compiles with nothing missing on this install: a theme's
## terrain layer that has a texture but no materials.json entry (coast's sand, white forest's
## grass, Xen's ground) is that texture, not a "not on this computer" warning and the default
## grass.
func _themes_content(t: Node, reg: Dictionary) -> void:
	for id in LevelTemplates.IDS:
		var td := LevelTemplates.make(id, LevelTemplates.title(id))
		var tb := LevelCompiler.compile(td, {"registries": reg, "chunks": false})
		t.check(tb.report.missing_total() == 0 and not tb.report.has("missing"),
			"content: template %s has nothing missing (%s)" % [id, str(tb.report.missing)])
	for th in LevelThemes.IDS:
		var d := oval_doc()
		d.apply(LevelThemes.ops(d, th))
		var layers: Dictionary = d.data.terrain.get("layers", {})
		var b := LevelCompiler.compile(d, {"registries": reg, "chunks": false})
		var tl: Dictionary = b.data.get("terrain_layers", {})
		var files := true
		for k in tl:
			files = files and ResourceLoader.exists("res://assets/" + str(tl[k]))
		t.check(b.report.missing.materials == 0 and tl.size() == layers.size() and files,
			"content: theme %s: its %d terrain layers all resolve to textures (%s)" % [th, layers.size(), str(tl)])
