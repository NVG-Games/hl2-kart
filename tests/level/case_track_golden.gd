extends RefCounted
## P3 (spec 3.10, C1 S27): the golden facts of every installed circuit. The first run (on the
## unmodified track.gd) records, per circuit, the MeshInstance3D and StaticBody3D counts by name
## key, props / item boxes / pads / hazards / crowd groups, the sun, fog, ambient and the water
## planes into user://level_test/golden_tracks.json; later runs build each circuit again and compare
## (exact counts, floats to 1e-4). A missing file (or a circuit missing from it) is recorded and the
## check passes with a note; `-- regold` records again. Then build_level of a hand-made LevelBuild
## carrying a circuit's data builds its props, items and hazards. Needs the HL2 content.

const NEEDS_CONTENT := true
const TIMEOUT := 600
const EPS := 1e-4
## The circuit build_level is tried with (props, crates, pads, hazards, a lake and the sea).
const LEVEL_CIRCUIT := "surface_tension"


func run(t: Node) -> void:
	var file: String = t.tmp("golden_tracks.json")
	var golden := {}
	var regold: bool = "regold" in t.args or "--regold" in t.args
	if FileAccess.file_exists(file) and not regold:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(file))
		if parsed is Dictionary:
			golden = parsed
	var recorded := false
	var holder := Node3D.new()
	holder.name = "GoldenHolder"
	t.add_child(holder)
	var facts_by_id := {}
	for e in Game.TRACKS:
		var id: String = e["id"]
		if not Game.track_installed(id):
			t.log("%s is not installed here: skipped" % id)
			continue
		var trk := Track.new()
		holder.add_child(trk)
		var ms: float = t.ms(func() -> void: trk.build(id))
		var f := facts(trk)
		facts_by_id[id] = f
		t.log("%s built in %.0f ms: %d mesh keys, %d body keys" % [id, ms, (f["meshes"] as Dictionary).size(), (f["bodies"] as Dictionary).size()])
		t.check(trk.id == id, "%s: Track.id" % id)
		if golden.has(id):
			compare(t, id, golden[id], f)
		else:
			golden[id] = f
			recorded = true
			t.log("%s: no golden facts yet, recorded" % id)
		trk.free()
		await t.frames(1)
	if recorded:
		var fa := FileAccess.open(file, FileAccess.WRITE)
		fa.store_string(JSON.stringify(golden, "\t", true))
		fa.close()
		t.log("golden facts written to %s" % ProjectSettings.globalize_path(file))
	t.check(not facts_by_id.is_empty(), "at least one circuit is installed")
	# build_level: a hand-made LevelBuild carrying a built circuit's data dict
	if Game.track_installed(LEVEL_CIRCUIT):
		await _build_level_case(t, holder, facts_by_id.get(LEVEL_CIRCUIT, {}))
	holder.free()


func _build_level_case(t: Node, holder: Node3D, built: Dictionary) -> void:
	var data: Dictionary = Game.load_json("res://assets/track/%s.json" % LEVEL_CIRCUIT)
	var b := LevelBuild.new()
	b.id = "c_0123456789abcdef"
	b.data = data
	var trk := Track.new()
	holder.add_child(trk)
	if not trk.has_method("build_level"):
		t.log("Track.build_level is not there yet: skipped")
		trk.free()
		return
	trk.call("build_level", b)
	t.check(str(trk.get("build_failed")) == "", "build_level: no build failure")
	t.check(trk.id == b.id, "build_level: Track.id is the build's id")
	t.check(trk.path != null and trk.path.n > 0, "build_level: the path is made")
	var want_props := 0
	for p in data.get("props", []):
		if Game.models.has(str(p["model"])):
			want_props += 1
	var props := trk.get_node_or_null("props")
	t.check(props != null and props.get_child_count() == want_props, "build_level: %d props (got %d)" % [want_props, props.get_child_count() if props else -1])
	t.check(trk.item_boxes.size() == (data.get("item_boxes", []) as Array).size(), "build_level: every item box")
	t.check(_count(trk, "BoostPad") == (data.get("boost_pads", []) as Array).size(), "build_level: every boost pad")
	t.check(trk.hazards != null, "build_level: a hazard director")
	if not built.is_empty() and trk.hazards != null:
		t.check(trk.hazards.list.size() == int(built["hazards"]), "build_level: as many hazards as the built circuit (%d vs %d)" % [trk.hazards.list.size(), int(built["hazards"])])
		t.check(trk.has_sea == bool(built["has_sea"]), "build_level: the sea as the built circuit")
		t.check(_waters(trk).size() == (built["waters"] as Array).size(), "build_level: the water planes as the built circuit")
	t.check(trk.gantry != null, "build_level: the start arch")
	t.check(trk.sun != null and trk.env != null, "build_level: sun and environment")
	if trk.gantry and trk.gantry.speaker:
		t.check(trk.gantry.comment("res://assets/sound/vo/breencast/br_collaboration01.wav", 9), "gantry: takes a comment")
		trk.gantry.silent = true
		t.check(not trk.gantry.comment("vox:hello", 99), "gantry: silent refuses comments")
		trk.gantry._process(0.1)
		t.check(trk.gantry.speaker == null or not trk.gantry.speaker.playing, "gantry: silent stops its speaker")
	# BackgroundLife circles data.bg_center (a custom track's world centre above its ground)
	trk.data["bg_center"] = [10.0, 50.0, 20.0]
	var bg := BackgroundLife.new()
	trk.add_child(bg)
	bg.setup(trk)
	t.check(bg._center.is_equal_approx(Vector3(10, 50, 20)), "BackgroundLife: circles data.bg_center (%s)" % bg._center)
	bg._process(0.5)
	t.check(bg.gunship == null or bg.gunship.global_position.y > 50.0 + 80.0, "BackgroundLife: the gunship flies above bg_center")
	trk.data.erase("bg_center")
	trk.data["rescue"] = "xen_portal"
	t.check(Rescuer.kind_of(trk) == "xen_portal", "Rescuer.kind_of: the track data's rescue first")
	trk.data.erase("rescue")
	t.check(Rescuer.kind_of(trk) == str(Game.track(trk.id).get("rescue", "scanner")), "Rescuer.kind_of: else Game.track's")
	trk.free()
	await t.frames(1)
	# a build without a road, and a custom id nothing can build: build_failed, nothing spawned
	var nb := LevelBuild.new()
	nb.id = "c_00000000000000ff"
	var t2 := Track.new()
	holder.add_child(t2)
	t2.call("build_level", nb)
	t.check(str(t2.get("build_failed")) != "" and t2.get_child_count() == 0, "build_level: a build without a path fails cleanly")
	t2.free()
	if CustomTracks.is_custom("c_0123456789abcdee"):
		var t3 := Track.new()
		holder.add_child(t3)
		t3.build("c_0123456789abcdee")
		t.check(str(t3.get("build_failed")) != "" and t3.path == null, "build: a custom id that is not ready sets build_failed")
		t3.free()
		await t.frames(1)
	else:
		t.log("CustomTracks.is_custom is still a stub: the custom branch of build is not tried")


## The facts of one built track (JSON-friendly).
static func facts(trk: Track) -> Dictionary:
	var meshes := {}
	for n in trk.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var k := key(mi.name)
		var row: Array = meshes.get(k, [0, 0, 0, 0])
		row[0] += 1
		if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			row[1] += 1
		if not mi.visible:
			row[2] += 1
		if mi.mesh and mi.mesh.get_surface_count() > 0 and (mi.get_surface_override_material(0) != null or mi.material_override != null):
			row[3] += 1
		meshes[k] = row
	var bodies := {}
	for n in trk.find_children("*", "StaticBody3D", true, false):
		var sb := n as StaticBody3D
		var k := "%s|%s|%d" % [key(sb.name), str(sb.get_meta("surface", "")), sb.collision_layer]
		bodies[k] = int(bodies.get(k, 0)) + 1
	var classes := {}
	for n in trk.find_children("*", "", true, false):
		var c := n.get_class()
		classes[c] = int(classes.get(c, 0)) + 1
	var props := trk.get_node_or_null("props")
	var sun := trk.sun
	var env := trk.env
	var sdir := sun.global_transform.basis.z if sun else Vector3.ZERO
	var waters := _waters(trk)
	var sky_exp := 0.0
	if env and env.sky and env.sky.sky_material is ShaderMaterial:
		sky_exp = float((env.sky.sky_material as ShaderMaterial).get_shader_parameter("exposure"))
	return {
		"meshes": meshes,
		"bodies": bodies,
		"classes": classes,
		"props": props.get_child_count() if props else 0,
		"item_boxes": trk.item_boxes.size(),
		"pads": _count(trk, "BoostPad"),
		"hazards": trk.hazards.list.size() if trk.hazards else -1,
		"crowd_groups": (trk.data.get("crowd_groups", []) as Array).size(),
		"crowd": trk.crowd != null,
		"has_sea": trk.has_sea,
		"sea_level": trk.sea_level,
		"is_bsp": trk.is_bsp,
		"path_n": trk.path.n if trk.path else 0,
		"sun": [sun.light_energy, sun.visible, sdir.x, sdir.y, sdir.z, sun.light_color.r, sun.light_color.g, sun.light_color.b] if sun else [],
		"fog": [env.fog_depth_begin, env.fog_depth_end, env.fog_light_color.r, env.fog_light_color.g, env.fog_light_color.b, env.fog_sky_affect] if env else [],
		"ambient": [env.ambient_light_source, env.ambient_light_energy, env.ambient_light_color.r, env.ambient_light_color.g, env.ambient_light_color.b, env.ambient_light_sky_contribution] if env else [],
		"tone": [env.tonemap_exposure, env.glow_intensity, sky_exp, env.sdfgi_enabled, env.ssr_enabled, env.ssao_enabled] if env else [],
		"waters": waters,
		"gantry": [trk.gantry.style, trk.gantry.global_position.x, trk.gantry.global_position.y, trk.gantry.global_position.z] if trk.gantry else [],
	}


## Water planes: [x, y, z, w, d] each, in tree order.
static func _waters(trk: Track) -> Array:
	var out := []
	for n in trk.find_children("water_sea*", "MeshInstance3D", false, false):
		var mi := n as MeshInstance3D
		var sz := (mi.mesh as PlaneMesh).size if mi.mesh is PlaneMesh else Vector2.ZERO
		out.append([mi.position.x, mi.position.y, mi.position.z, sz.x, sz.y])
	return out


static func _count(trk: Node, cls: String) -> int:
	var c := 0
	for n in trk.find_children("*", "", true, false):
		var s: Script = n.get_script()
		if s and s.get_global_name() == cls:
			c += 1
	return c


## A node name's key: digit runs as "#", so auto names (@MeshInstance3D@123) and numbered pieces
## group together.
static func key(n: StringName) -> String:
	var s := String(n)
	var out := ""
	var digit := false
	for ch in s:
		if ch >= "0" and ch <= "9":
			if not digit:
				out += "#"
			digit = true
		else:
			out += ch
			digit = false
	return out


func compare(t: Node, id: String, want: Dictionary, got: Dictionary) -> void:
	var before := int(t.get("failures"))
	for k in want:
		if not got.has(k):
			t.fail("%s: fact %s is gone" % [id, k])
			continue
		_same(t, "%s.%s" % [id, k], want[k], got[k])
	for k in got:
		if not want.has(k):
			t.log("%s: new fact %s (not in the golden file)" % [id, k])
	if int(t.get("failures")) == before:
		t.check(true, "%s equals its golden facts" % id)


## Recursive compare: JSON numbers vs Godot ints / floats to EPS, dict keys both ways.
func _same(t: Node, where: String, a: Variant, b: Variant) -> void:
	if a is Dictionary:
		if not b is Dictionary:
			t.fail("%s: a dict became %s" % [where, type_string(typeof(b))])
			return
		for k in a:
			if not (b as Dictionary).has(k):
				t.fail("%s: %s is gone (was %s)" % [where, k, str(a[k])])
			else:
				_same(t, "%s.%s" % [where, k], a[k], b[k])
		for k in b:
			if not (a as Dictionary).has(k):
				t.fail("%s: %s is new (%s)" % [where, k, str(b[k])])
		return
	if a is Array:
		if not b is Array or (b as Array).size() != (a as Array).size():
			t.fail("%s: %s vs %s" % [where, str(a), str(b)])
			return
		for i in (a as Array).size():
			_same(t, "%s[%d]" % [where, i], a[i], b[i])
		return
	if (a is float or a is int) and (b is float or b is int or b is bool):
		if absf(float(a) - float(b)) > EPS:
			t.fail("%s: %s vs %s" % [where, str(a), str(b)])
		return
	if a is bool and (b is bool or b is int or b is float):
		if bool(a) != bool(b):
			t.fail("%s: %s vs %s" % [where, str(a), str(b)])
		return
	if str(a) != str(b):
		t.fail("%s: %s vs %s" % [where, str(a), str(b)])
