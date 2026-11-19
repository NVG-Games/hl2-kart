class_name WorldTool
extends EditorTool
## 1.6 WORLD: settings, nothing placed in 3D (4.4). THEME (the look of a shipped circuit in one
## undo step); SKY & LIGHT (the 14 skies with their thumbnails, the presets NOON / GOLDEN HOUR /
## OVERCAST / NIGHT / ALIEN, sun from the sky or custom, sun colour and strength, ambient from the
## sky or a colour with its strength, fog, exposure, glow, sky brightness, GI); WATER (the sea and
## its level; lakes are TERRAIN's); START & SCENERY (start arch, background, the Citadel and
## seagulls for CITY 17); RACE (rescue, off-track limit, default laps, music with PLAY). Every
## change is one undo step (a number dragged folds into one); the view shows a light change at once
## and the bake follows. P16.

## The skies when the content's skies.json is not there (CI): the 14 keys it has.
const SKIES := ["hl1_2desert", "hl1_alien1", "hl1_cliff", "hl1_desert", "hl1_neb7", "hl1_xen8", "sky_borealis01",
	"sky_day01_01", "sky_day01_05", "sky_day01_06", "sky_day01_08", "sky_day02_02", "sky_day02_09", "sky_day03_06"]
const PRESETS := ["noon", "golden", "overcast", "night", "alien"]
const PRESET_NAMES := ["NOON", "GOLDEN HOUR", "OVERCAST", "NIGHT", "ALIEN"]
## What each lighting preset sets over the base (4.4); "sun_el" keeps the azimuth, "erase" keys
## go back to the sky's own.
const PRESET_ENV := {
	"noon": {"sun": "sky", "exposure": 1.08, "ambient_energy": 1.35},
	"golden": {"sun_el": 12.0, "sun_color": [1.0, 0.72, 0.45], "exposure": 1.0, "fog_color": [0.9, 0.7, 0.55], "ambient_energy": 1.35},
	"overcast": {"sun_energy": 0.4, "ambient_energy": 1.4, "fog_begin": 120.0, "fog_end": 900.0},
	"night": {"sky_energy": 0.15, "sun_energy": 0.25, "sun_color": [0.55, 0.65, 1.0], "ambient": [0.08, 0.1, 0.16],
		"ambient_energy": 1.0, "fog_color": [0.04, 0.05, 0.08], "fog_begin": 60.0, "fog_end": 700.0, "exposure": 1.25},
	"alien": {"ambient": [0.45, 0.25, 0.6], "ambient_energy": 1.0, "fog_color": [0.3, 0.15, 0.4], "glow": 0.8},
}
## The keys a preset starts from: the sky's own light (the sky and GI are kept).
const PRESET_BASE := {"sun": "sky", "ambient_energy": 1.35, "fog_begin": 180.0, "fog_end": 1500.0, "fog_sky": 0.0,
	"exposure": 1.08, "glow": 0.35}
const GANTRY_NAMES := ["COMBINE", "BLACK MESA", "MILITARY", "XEN"]
const BACKGROUND_NAMES := ["NONE", "CITY 17", "FOREST"]
const RESCUE_NAMES := ["SCANNER", "CRANE", "BLACK MESA TELEPORT", "XEN PORTAL", "COMBINE TELEPORT", "VORTIGAUNTS"]
## The sun's colour and strength when the sky gives them (Track._make_environment's defaults).
const SKY_SUN_COLOR := Color(1.0, 0.95, 0.86)
const SKY_SUN_ENERGY := 1.75
## A light change shows in the view at most this often while a number is dragged.
const PREVIEW_S := 0.1

var section := ""                 # the open section ("" all)
## The last runtime env sent to the view (tests).
var last_preview := {}

var _preview_due := false
var _preview_t := 0.0


func _init(ed: TrackEditor) -> void:
	super(ed)
	id = "world"
	title = "WORLD"
	purpose = "Sky, sun, fog, water, music and the start arch."


func options(box: VBoxContainer) -> void:
	if editor == null or editor.doc == null:
		return
	var env := env_of()
	var race := race_of()
	# THEME
	box.add_child(EditorKit.section("THEME"))
	var cur_theme := str(editor.doc.data.get("theme", ""))
	var names := []
	for t in LevelThemes.IDS:
		names.append(LevelThemes.title(t))
	var tc := EditorKit.choice(["(PICK A THEME)"] + names, LevelThemes.IDS.find(cur_theme) + 1, func(i: int) -> void:
		if i > 0:
			apply_theme(LevelThemes.IDS[i - 1]))
	box.add_child(EditorKit.row("THEME", tc, "Sky, light, fog, ground textures, start arch, background, rescue and music of a Half-Life place, in one step."))
	# SKY & LIGHT
	box.add_child(EditorKit.section("SKY & LIGHT"))
	var skies := sky_list()
	var sky := str(env.get("sky", LevelDoc.DEFAULT_SKY))
	var so := EditorKit.choice([], -1, func(i: int) -> void: set_env_key("sky", skies[i], "SKY"))
	for i in skies.size():
		var tex := sky_thumb(skies[i])
		if tex != null:
			so.add_icon_item(tex, skies[i].to_upper())
		else:
			so.add_item(skies[i].to_upper())
	so.select(skies.find(sky))
	so.add_theme_constant_override("icon_max_width", 48)
	so.get_popup().add_theme_constant_override("icon_max_width", 96)
	box.add_child(EditorKit.row("SKY", so))
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 2)
	for i in PRESETS.size():
		var p: String = PRESETS[i]
		var b := EditorKit.button(PRESET_NAMES[i], func() -> void: apply_preset(p), "Lighting preset: %s." % PRESET_NAMES[i])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		pr.add_child(b)
	box.add_child(EditorKit.row("PRESETS", pr))
	var sun = env.get("sun", "sky")
	var custom := sun is Dictionary
	box.add_child(EditorKit.row("SUN", EditorKit.modes(["FROM THE SKY", "CUSTOM"], 1 if custom else 0, func(i: int) -> void:
		if i == 0:
			set_env_key("sun", "sky", "SUN")
		else:
			set_env_key("sun", sky_sun(), "SUN")
		_refresh_options())))
	if custom:
		box.add_child(EditorKit.row("AZIMUTH", EditorKit.number(float(sun.get("az", 135.0)), 0.0, 360.0, 1.0, func(v: float) -> void: _sun("az", v), "%.0f", " deg")))
		box.add_child(EditorKit.row("ELEVATION", EditorKit.number(float(sun.get("el", 45.0)), 5.0, 90.0, 1.0, func(v: float) -> void: _sun("el", v), "%.0f", " deg")))
	box.add_child(_opt_row("SUN COLOUR", "sun_color", EditorKit.color(_col(env.get("sun_color"), SKY_SUN_COLOR), func(c: Color, final: bool) -> void: _set_col("sun_color", c, final))))
	box.add_child(_opt_row("SUN STRENGTH", "sun_energy", EditorKit.number(float(env.get("sun_energy", SKY_SUN_ENERGY)), 0.0, 3.0, 0.05,
		func(v: float) -> void: set_env_key("sun_energy", v), "%.2f"), "0 hides the sun."))
	var amb := env.get("ambient") is Array
	box.add_child(EditorKit.row("AMBIENT", EditorKit.modes(["FROM THE SKY", "COLOUR"], 1 if amb else 0, func(i: int) -> void:
		if i == 0:
			erase_env_key("ambient", "AMBIENT")
		else:
			set_env_key("ambient", [0.45, 0.45, 0.5], "AMBIENT")
		_refresh_options())))
	if amb:
		box.add_child(EditorKit.row("AMBIENT COLOUR", EditorKit.color(_col(env.get("ambient"), Color(0.45, 0.45, 0.5)), func(c: Color, final: bool) -> void: _set_col("ambient", c, final))))
	box.add_child(EditorKit.row("AMBIENT STRENGTH", EditorKit.number(float(env.get("ambient_energy", 1.0)), 0.0, 4.0, 0.05,
		func(v: float) -> void: set_env_key("ambient_energy", v), "%.2f"), "Applies to the sky's ambient light too."))
	box.add_child(_opt_row("FOG COLOUR", "fog_color", EditorKit.color(_col(env.get("fog_color"), sky_horizon()), func(c: Color, final: bool) -> void: _set_col("fog_color", c, final)),
		"Without one: the sky's horizon."))
	box.add_child(EditorKit.row("FOG START", EditorKit.number(float(env.get("fog_begin", 180.0)), 20.0, 2000.0, 5.0, func(v: float) -> void: set_env_key("fog_begin", v), "%.0f", " m")))
	box.add_child(EditorKit.row("FOG END", EditorKit.number(float(env.get("fog_end", 1500.0)), 100.0, 6000.0, 10.0, func(v: float) -> void: set_env_key("fog_end", v), "%.0f", " m")))
	box.add_child(EditorKit.row("FOG OVER SKY", EditorKit.number(float(env.get("fog_sky", 0.0)), 0.0, 1.0, 0.05, func(v: float) -> void: set_env_key("fog_sky", v), "%.2f"), "FOG OVER THE SKY: how much the fog covers the sky."))
	box.add_child(EditorKit.row("EXPOSURE", EditorKit.number(float(env.get("exposure", 1.08)), 0.4, 2.0, 0.01, func(v: float) -> void: set_env_key("exposure", v), "%.2f")))
	box.add_child(EditorKit.row("GLOW", EditorKit.number(float(env.get("glow", 0.35)), 0.0, 1.5, 0.05, func(v: float) -> void: set_env_key("glow", v), "%.2f")))
	box.add_child(_opt_row("SKY BRIGHTNESS", "sky_energy", EditorKit.number(float(env.get("sky_energy", 1.0)), 0.1, 2.0, 0.05, func(v: float) -> void: set_env_key("sky_energy", v), "%.2f")))
	box.add_child(EditorKit.row("GI (SDFGI)", EditorKit.check(bool(env.get("sdfgi", true)), func(v: bool) -> void: set_env_key("sdfgi", v, "GI")),
		"Realtime global illumination on MEDIUM graphics and up."))
	# WATER
	box.add_child(EditorKit.section("WATER"))
	var water := water_of()
	box.add_child(EditorKit.row("SEA", EditorKit.check(bool(water.get("sea", false)), func(v: bool) -> void: set_water("sea", v))))
	box.add_child(EditorKit.row("SEA LEVEL", EditorKit.number(float(water.get("level", 0.0)), -200.0, 500.0, 0.5, func(v: float) -> void: set_water("level", v), "%.1f", " m")))
	box.add_child(EditorKit.hint("Lakes: TERRAIN ({ed_tool_terrain}) > ADD LAKE."))
	# START & SCENERY
	box.add_child(EditorKit.section("START & SCENERY"))
	box.add_child(EditorKit.row("START ARCH", EditorKit.choice(GANTRY_NAMES, LevelDoc.GANTRIES.find(str(race.get("gantry", "combine"))),
		func(i: int) -> void: set_race("gantry", LevelDoc.GANTRIES[i], "START ARCH"))))
	var bg := str(race.get("background", "none"))
	box.add_child(EditorKit.row("BACKGROUND", EditorKit.choice(BACKGROUND_NAMES, LevelDoc.BACKGROUNDS.find(bg), func(i: int) -> void:
		set_race("background", LevelDoc.BACKGROUNDS[i], "BACKGROUND")
		_refresh_options())))
	var city := bg == "city17"
	var cit := citadel()
	var labels := ["CITADEL X", "CITADEL Z", "CITADEL SCALE"]
	var idx := [0, 2, 3]
	var lims := [[-3.0, 3.0], [-3.0, 3.0], [0.1, 10.0]]
	var size := editor.doc.world_size()
	for k in 3:
		var ci: int = idx[k]
		var lo: float = lims[k][0] * (size if k < 2 else 1.0)
		var hi: float = lims[k][1] * (size if k < 2 else 1.0)
		var n := EditorKit.number(float(cit[ci]), lo, hi, 1.0 if k < 2 else 0.1, func(v: float) -> void: set_citadel(ci, v), "%.0f" if k < 2 else "%.1f", " m" if k < 2 else "")
		var r := EditorKit.row(labels[k], n, "CITY 17 background only." if not city else "")
		r.modulate.a = 1.0 if city else 0.4
		if not city:
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(r)
	var gulls := race.get("seagulls") is Array and not (race.seagulls as Array).is_empty()
	var gc := EditorKit.check(gulls, func(v: bool) -> void: set_seagulls(v))
	gc.disabled = not city
	box.add_child(EditorKit.row("SEAGULLS", gc, "CITY 17 background only."))
	# RACE
	box.add_child(EditorKit.section("RACE"))
	box.add_child(EditorKit.row("RESCUE", EditorKit.choice(RESCUE_NAMES, LevelDoc.RESCUES.find(str(race.get("rescue", "scanner"))),
		func(i: int) -> void: set_race("rescue", LevelDoc.RESCUES[i], "RESCUE")), "Who puts a kart back on the road."))
	box.add_child(EditorKit.row("OFF-TRACK LIMIT", EditorKit.number(float(race.get("offtrack", 60.0)), 30.0, 200.0, 1.0,
		func(v: float) -> void: set_race("offtrack", v, "OFF-TRACK LIMIT"), "%.0f", " m"), "How far from the road a kart may go before it is rescued."))
	box.add_child(EditorKit.row("DEFAULT LAPS", EditorKit.number(float(race.get("laps", 3)), 1.0, 9.0, 1.0,
		func(v: float) -> void: set_race("laps", int(v), "DEFAULT LAPS"), "%.0f")))
	_music_box(box)


func hints(_hit: EditorHit) -> Array:
	return [["The world's settings are in the TOOL OPTIONS."]]


func process(_delta: float) -> void:
	if _preview_due and Time.get_ticks_msec() / 1000.0 - _preview_t >= PREVIEW_S:
		preview_env()


func on_doc_changed(sections: PackedStringArray, _uids: PackedInt32Array) -> void:
	if "env" in sections:
		_preview_due = true


# ---------------------------------------------------------------- additions (P16)

func env_of() -> Dictionary:
	var e = editor.doc.data.get("env", {}) if editor != null and editor.doc != null else {}
	return e if e is Dictionary else {}


func race_of() -> Dictionary:
	var r = editor.doc.data.get("race", {}) if editor != null and editor.doc != null else {}
	return r if r is Dictionary else {}


func water_of() -> Dictionary:
	var w = editor.doc.data.get("water", {}) if editor != null and editor.doc != null else {}
	return w if w is Dictionary else {}


## THEME: one undo step "THEME: <title>" (LevelThemes.ops).
func apply_theme(theme_id: String) -> void:
	var ops := LevelThemes.ops(editor.doc, theme_id)
	if ops.is_empty():
		return
	editor.commit("THEME: " + LevelThemes.title(theme_id), ops)
	editor.toast("THEME: %s." % LevelThemes.title(theme_id))
	succeeded()
	_refresh_options()


## The env a lighting preset gives (the sky and GI kept); one undo step "LIGHT: <name>".
func apply_preset(p: String) -> void:
	if not PRESET_ENV.has(p):
		return
	editor.commit("LIGHT: " + PRESET_NAMES[PRESETS.find(p)], [LevelDoc.op_set(["env"], preset_env(env_of(), p))])
	succeeded()
	_refresh_options()


## The env of preset p over env (pure: tests, the button).
func preset_env(env: Dictionary, p: String) -> Dictionary:
	var out := PRESET_BASE.duplicate(true)
	out["sky"] = str(env.get("sky", LevelDoc.DEFAULT_SKY))
	out["sdfgi"] = bool(env.get("sdfgi", true))
	var over: Dictionary = PRESET_ENV.get(p, {})
	for k in over:
		if k == "sun_el":
			var s := sky_sun()
			var cur = env.get("sun")
			if cur is Dictionary:
				s["az"] = float(cur.get("az", s.az))
			s["el"] = float(over[k])
			out["sun"] = s
		else:
			out[k] = (over[k] as Array).duplicate() if over[k] is Array else over[k]
	return out


## One env key as one undo step (numbers dragged fold into one: the key's merge key).
func set_env_key(k: String, v: Variant, step := "") -> void:
	if v is float:
		v = snappedf(v, 0.001)
	if _same(env_of().get(k), v):
		return
	editor.commit(step if step != "" else k.to_upper().replace("_", " "), [LevelDoc.op_set(["env", k], v)], "env_" + k)
	_preview_due = true


## Back to the sky's own value (sun colour, sun strength, ambient colour, fog colour, sky brightness).
func erase_env_key(k: String, step := "") -> void:
	if not env_of().has(k):
		return
	editor.commit(step if step != "" else k.to_upper().replace("_", " "), [LevelDoc.op_erase(["env", k])])
	_preview_due = true


func set_water(k: String, v: Variant) -> void:
	if _same(water_of().get(k), v):
		return
	editor.commit("SEA" if k == "sea" else "SEA LEVEL", [LevelDoc.op_set(["water", k], snappedf(v, 0.01) if v is float else v)], "water_" + k)


func set_race(k: String, v: Variant, step := "") -> void:
	if _same(race_of().get(k), v):
		return
	editor.commit(step if step != "" else k.to_upper(), [LevelDoc.op_set(["race", k], v)], "race_" + k)
	succeeded()


## [x, y, z, scale] of the Citadel (the race's, else the compiler's default for the world size).
func citadel() -> Array:
	var c = race_of().get("citadel")
	if c is Array and (c as Array).size() >= 4:
		return (c as Array).duplicate()
	var size := editor.doc.world_size()
	return [-0.9 * size, -260.0, -2.25 * size, 9.0]


func set_citadel(i: int, v: float) -> void:
	var c := citadel()
	c[i] = snappedf(v, 0.01)
	editor.commit("CITADEL", [LevelDoc.op_set(["race", "citadel"], c)], "race_citadel")


## SEAGULLS on: three flocks circling over the track's middle; off: none.
func set_seagulls(on: bool) -> void:
	var out := []
	if on:
		var box := editor.track_aabb()
		var c := box.get_center()
		var top := box.end.y + 25.0
		var r := clampf(maxf(box.size.x, box.size.z) * 0.25, 20.0, 400.0)
		for k in 3:
			var a := TAU * k / 3.0
			out.append([snappedf(c.x + cos(a) * r, 0.1), snappedf(top + k * 6.0, 0.1), snappedf(c.z + sin(a) * r, 0.1), 30.0])
	editor.commit("SEAGULLS", [LevelDoc.op_set(["race", "seagulls"], out)])


## MUSIC: the songs a race on this track picks from (<= 12; none = the game's race pool).
func set_music(ids: Array) -> void:
	var clean := []
	for m in ids:
		if m is String and LevelDoc.is_id(m) and not m in clean and clean.size() < int(LevelDoc.CAPS.music):
			clean.append(m)
	editor.commit("MUSIC", [LevelDoc.op_set(["race", "music"], clean)])


## The view shows the document's sky and light now (the bake follows).
func preview_env() -> void:
	_preview_due = false
	_preview_t = Time.get_ticks_msec() / 1000.0
	last_preview = runtime_env(editor.doc)
	if editor.view != null:
		editor.view.set_env(last_preview)


## {sky, env} as the compiler writes them (env keys copied, sun {az, el} -> sun_dir).
static func runtime_env(doc: LevelDoc) -> Dictionary:
	var e = doc.data.get("env", {}) if doc != null else {}
	if not (e is Dictionary):
		e = {}
	var env := {}
	for k in LevelCompiler.ENV_KEYS:
		if e.has(k) and e[k] != null:
			env[k] = e[k].duplicate() if e[k] is Array else e[k]
	var sun = e.get("sun")
	if sun is Dictionary:
		var az := deg_to_rad(float(sun.get("az", 0.0)))
		var el := deg_to_rad(float(sun.get("el", 45.0)))
		env["sun_dir"] = [cos(el) * sin(az), sin(el), cos(el) * cos(az)]
	var sky := str(e.get("sky", LevelDoc.DEFAULT_SKY))
	var g := _game()
	if g != null and not (g.skies as Dictionary).is_empty() and not (g.skies as Dictionary).has(sky):
		sky = LevelDoc.DEFAULT_SKY
	return {"sky": sky, "env": env}


## The skies to pick from (skies.json's keys, else the 14 names).
static func sky_list() -> Array:
	var g := _game()
	if g != null and not (g.skies as Dictionary).is_empty():
		var keys: Array = (g.skies as Dictionary).keys()
		keys.sort()
		return keys
	return SKIES.duplicate()


## A sky's thumbnail (assets/ui/skies/<name>.png when present).
static func sky_thumb(sky: String) -> Texture2D:
	var p := "res://assets/ui/skies/%s.png" % sky
	if ResourceLoader.exists(p):
		return load(p) as Texture2D
	return null


## The sun of the current sky as {az, el}.
func sky_sun() -> Dictionary:
	var g := _game()
	var info = (g.skies as Dictionary).get(str(env_of().get("sky", LevelDoc.DEFAULT_SKY)), {}) if g != null else {}
	var d = info.get("sun_dir", [0.6, 0.5, 0.6]) if info is Dictionary else [0.6, 0.5, 0.6]
	return LevelThemes.sun_of(Vector3(float(d[0]), maxf(float(d[1]), 0.35), float(d[2])))


func sky_horizon() -> Color:
	var g := _game()
	var info = (g.skies as Dictionary).get(str(env_of().get("sky", LevelDoc.DEFAULT_SKY)), {}) if g != null else {}
	var h = info.get("horizon", [0.6, 0.62, 0.65]) if info is Dictionary else [0.6, 0.62, 0.65]
	return Color(float(h[0]), float(h[1]), float(h[2]))


func _sun(k: String, v: float) -> void:
	var s = env_of().get("sun")
	var d: Dictionary = (s as Dictionary).duplicate() if s is Dictionary else sky_sun()
	d[k] = snappedf(v, 0.01)
	editor.commit("SUN", [LevelDoc.op_set(["env", "sun"], d)], "env_sun_" + k)
	_preview_due = true


func _set_col(k: String, c: Color, final: bool) -> void:
	var v := [snappedf(c.r, 0.001), snappedf(c.g, 0.001), snappedf(c.b, 0.001)]
	if _same(env_of().get(k), v):
		return
	editor.commit(k.to_upper().replace("_", " ").replace("COLOR", "COLOUR"), [LevelDoc.op_set(["env", k], v)], "env_" + k)
	_preview_due = true
	if final:
		_refresh_options()


## A row whose key may be left to the sky: a small SKY button puts it back.
func _opt_row(label: String, k: String, c: Control, tip := "") -> HBoxContainer:
	var r := EditorKit.row(label, c, tip)
	if env_of().has(k):
		var b := EditorKit.button("SKY", func() -> void:
			erase_env_key(k)
			_refresh_options(), "Back to the sky's own.")
		b.custom_minimum_size.x = 44
		r.add_child(b)
	return r


func _music_box(box: VBoxContainer) -> void:
	var g := _game()
	var lib: Array = g.music_library if g != null else []
	var chosen: Array = race_of().get("music", []) if race_of().get("music") is Array else []
	var head := "MUSIC: %d SONG%s" % [chosen.size(), "" if chosen.size() == 1 else "S"] if not chosen.is_empty() else "MUSIC: THE GAME'S RACE MIX"
	box.add_child(EditorKit.row("MUSIC", UiKit.label(head, 14, UiKit.TEXT)))
	if lib.is_empty():
		box.add_child(EditorKit.hint("No music installed."))
		return
	var list := ItemList.new()
	list.select_mode = ItemList.SELECT_MULTI
	list.custom_minimum_size = Vector2(80, EditorKit.ROW_H * 6)
	list.auto_height = false
	var ids := []
	for m in lib:
		ids.append(str(m.id))
		list.add_item("%s · %s" % [str(m.album).to_upper(), str(m.title)])
	for i in ids.size():
		if ids[i] in chosen:
			list.select(i, false)
	list.multi_selected.connect(func(_i: int, _sel: bool) -> void:
		var pick := []
		for j in list.get_selected_items():
			pick.append(ids[j])
		if pick.size() > int(LevelDoc.CAPS.music):
			editor.toast("At most %d songs." % int(LevelDoc.CAPS.music))
			_refresh_options()
			return
		set_music(pick))
	box.add_child(list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var play := EditorKit.button("PLAY", func() -> void:
		var sel := list.get_selected_items()
		var at := list.get_item_at_position(list.get_local_mouse_position(), true)
		var i: int = sel[sel.size() - 1] if not sel.is_empty() else (at if at >= 0 else 0)
		if g != null and i >= 0 and i < ids.size():
			g.play_track(ids[i], "once")
			editor.status("PLAYING " + str(g.music_title(ids[i])).to_upper()), "Preview the last song picked.")
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(play)
	var stop := EditorKit.button("STOP", func() -> void:
		if g != null:
			g.stop_music())
	stop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(stop)
	var none := EditorKit.button("NONE", func() -> void:
		set_music([])
		_refresh_options(), "Back to the game's race mix.")
	none.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(none)
	box.add_child(row)


## a == b without comparing values of different kinds (ints and floats count as one kind).
static func _same(a: Variant, b: Variant) -> bool:
	var ta := TYPE_FLOAT if typeof(a) == TYPE_INT else typeof(a)
	var tb := TYPE_FLOAT if typeof(b) == TYPE_INT else typeof(b)
	return ta == tb and a == b


static func _col(v: Variant, def: Color) -> Color:
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return def


func _refresh_options() -> void:
	if editor != null and editor.ui != null and editor.tool == self:
		editor.ui.refresh_tool()


static func _game() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Game")
	return null
