class_name LevelThemes
## The seven THEMES (4.4): the look of a shipped circuit copied at apply time. P4.
##
## A theme reads res://assets/track/<from>.json (local content, never in git): its sky, env keys,
## terrain_layers (albedo paths "materials/<key>.png" turned back into material keys) and music,
## and Game.track(from).rescue; plus the fixed keys (gantry, background, the rescue when the
## circuit has none). Without that JSON (no content, CI) only the fixed keys and fallback_sky.

const IDS := ["city17", "coast", "blackmesa", "xen", "whiteforest", "novaprospekt", "desert"]
const THEMES := {               # 4.4
	"city17": {"name": "CITY 17", "from": "ct17", "gantry": "combine", "background": "city17", "rescue": "scanner",
		"categories": ["STREET FURNITURE", "JUNK & CLUTTER", "VEHICLES"], "fallback_sky": "sky_day01_01"},
	"coast": {"name": "COAST", "from": "city17_circuit", "gantry": "combine", "background": "none", "rescue": "crane",
		"categories": ["ROCKS & CLIFFS", "DOCKS & COAST", "TREES & PLANTS"], "fallback_sky": "sky_day01_05"},
	"blackmesa": {"name": "BLACK MESA", "from": "black_mesa", "gantry": "blackmesa", "background": "none", "rescue": "teleport",
		"categories": ["LAB & BLACK MESA", "INDUSTRIAL"], "fallback_sky": "sky_day01_01"},
	"xen": {"name": "XEN", "from": "xen", "gantry": "xen", "background": "none", "rescue": "xen_portal",
		"categories": ["XEN FLORA", "ROCKS & CLIFFS"], "fallback_sky": "hl1_xen8"},
	"whiteforest": {"name": "WHITE FOREST", "from": "white_forest", "gantry": "combine", "background": "forest", "rescue": "vortigaunt",
		"categories": ["TREES & PLANTS", "FOREST & FARM", "ROCKS & CLIFFS"], "fallback_sky": "sky_day01_06"},
	"novaprospekt": {"name": "NOVA PROSPEKT", "from": "nova_prospekt", "gantry": "combine", "background": "none", "rescue": "combine_teleport",
		"categories": ["PRISON & INTERIORS", "COMBINE", "INDUSTRIAL"], "fallback_sky": "sky_day02_09"},
	"desert": {"name": "DESERT", "from": "surface_tension", "gantry": "military", "background": "none", "rescue": "crane",
		"categories": ["ROCKS & CLIFFS", "VEHICLES", "JUNK & CLUTTER"], "fallback_sky": "hl1_desert"},
}

## The env keys a theme copies from its circuit, with the ranges of 2.3 (numbers) or a colour.
const ENV_RANGES := {"sun_energy": [0.0, 3.0], "ambient_energy": [0.0, 4.0], "fog_begin": [20.0, 2000.0],
	"fog_end": [100.0, 6000.0], "fog_sky": [0.0, 1.0], "exposure": [0.4, 2.0], "glow": [0.0, 1.5],
	"sky_energy": [0.1, 2.0]}
const ENV_COLOURS := ["sun_color", "ambient", "fog_color"]
## The env a theme starts from (LevelDoc.blank's), before the circuit's keys.
const ENV_BASE := {"sun": "sky", "ambient_energy": 1.0, "fog_begin": 180.0, "fog_end": 1500.0,
	"fog_sky": 0.0, "exposure": 1.08, "glow": 0.35, "sdfgi": true}
## Track's sky ambient strength without an ambient colour (make_environment's default).
const SKY_AMBIENT := 1.35
const LAYER_KEYS := ["base", "dirt", "rock", "pave", "sand"]


static func title(id: String) -> String:
	return str((THEMES.get(id, {}) as Dictionary).get("name", ""))


## The ops of one undo step "THEME: <title>"; sets doc.theme.
static func ops(doc: LevelDoc, id: String) -> Array:
	if doc == null or not THEMES.has(id):
		return []
	var th: Dictionary = THEMES[id]
	var src := circuit(id)
	var out := []
	# sky and light
	var env := ENV_BASE.duplicate(true)
	env["sky"] = str(src.get("sky", th.fallback_sky)) if not src.is_empty() else str(th.fallback_sky)
	var se = src.get("env", {})
	if se is Dictionary:
		for k in ENV_RANGES:
			if se.has(k) and (se[k] is float or se[k] is int):
				env[k] = clampf(float(se[k]), ENV_RANGES[k][0], ENV_RANGES[k][1])
		for k in ENV_COLOURS:
			var c = se.get(k)
			if c is Array and (c as Array).size() >= 3:
				env[k] = [clampf(float(c[0]), 0.0, 1.0), clampf(float(c[1]), 0.0, 1.0), clampf(float(c[2]), 0.0, 1.0)]
		if se.has("sdfgi"):
			env["sdfgi"] = bool(se.sdfgi)
		var d = se.get("sun_dir")
		if d is Array and (d as Array).size() >= 3:
			env["sun"] = sun_of(Vector3(float(d[0]), float(d[1]), float(d[2])))
		if not se.has("ambient") and not se.has("ambient_energy") and not src.is_empty():
			env["ambient_energy"] = SKY_AMBIENT
	out.append(LevelDoc.op_set(["env"], env))
	# terrain layers (material keys)
	var tl = src.get("terrain_layers", {})
	var tr = doc.data.get("terrain")
	if tl is Dictionary and not (tl as Dictionary).is_empty() and tr is Dictionary:
		var layers: Dictionary = (tr.get("layers", {}) as Dictionary).duplicate() if tr.get("layers") is Dictionary else {}
		for k in LAYER_KEYS:
			var key := material_key(str(tl.get(k, "")))
			if key != "":
				layers[k] = key
		out.append(LevelDoc.op_set(["terrain", "layers"], layers))
	# the race: start arch, background, rescue, music
	var race: Dictionary = (doc.data.get("race", {}) as Dictionary).duplicate(true) if doc.data.get("race") is Dictionary else {}
	race["gantry"] = str(th.gantry)
	race["background"] = str(th.background)
	race["rescue"] = _rescue(th)
	var mus = src.get("music")
	if mus is Array:
		var ids := []
		for m in mus:
			if m is String and LevelDoc.is_id(m) and ids.size() < 12:
				ids.append(m)
		race["music"] = ids
	out.append(LevelDoc.op_set(["race"], race))
	out.append(LevelDoc.op_set(["theme"], id))
	return out


# ---------------------------------------------------------------- additions (P4)

## The scenery categories of a theme (AUTO DRESS, LevelDress.palette).
static func categories(id: String) -> PackedStringArray:
	return PackedStringArray((THEMES.get(id, {}) as Dictionary).get("categories", []))


## The circuit JSON a theme copies (res://assets/track/<from>.json), {} without content.
static func circuit(id: String) -> Dictionary:
	if not THEMES.has(id):
		return {}
	var p := "res://assets/track/%s.json" % str(THEMES[id].from)
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}


## An albedo path ("materials/nature/grassfloor002a.png") back as its material key; "" when it
## is not one.
static func material_key(albedo: String) -> String:
	if not albedo.begins_with("materials/"):
		return ""
	var k := albedo.trim_prefix("materials/").get_basename()
	return k if LevelDoc.clean_key(k) == k else ""


## A unit sun direction as the doc's {az, el} (degrees; el kept within 5..90).
static func sun_of(d: Vector3) -> Dictionary:
	d = d.normalized() if d.length_squared() > 1e-9 else Vector3.UP
	var el := rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))
	var az := fposmod(rad_to_deg(atan2(d.x, d.z)), 360.0)
	return {"az": snappedf(az, 0.01), "el": snappedf(clampf(el, 5.0, 90.0), 0.01)}


## The circuit's rescue (Game.track(from).rescue) or the theme's.
static func _rescue(th: Dictionary) -> String:
	var g := _game()
	if g != null and g.has_method("track"):
		var e = g.call("track", str(th.from))
		if e is Dictionary and str(e.get("id", "")) == str(th.from):
			var r := str(e.get("rescue", ""))
			if r in LevelDoc.RESCUES:
				return r
	return str(th.rescue)


static func _game() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Game")
	return null
