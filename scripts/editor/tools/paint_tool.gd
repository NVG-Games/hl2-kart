class_name PaintTool
extends EditorTool
## 1.6 PAINT: the ground's five layers. LAYER BASE (erases the four) / DIRT / ROCK / PAVE / SAND,
## the same brush keys as TERRAIN ([ ] size, Shift + [ ] strength, SMOOTH / LINEAR / FLAT falloff),
## Ctrl + LMB paints BASE (erases), Alt + click without moving picks the strongest layer under the
## cursor (the eyedropper); LAYER TEXTURES: one world material per layer through the material
## picker; AUTO PAINT (one undo step): ROCK on slopes, SAND under a height, DIRT beside the roads.
## A stroke writes the document's splat live and becomes one undo step at its end. P16.

const LAYER_NAMES := ["BASE", "DIRT", "ROCK", "PAVE", "SAND"]
const LAYER_KEYS := ["base", "dirt", "rock", "pave", "sand"]
const BRUSH_COLOR := Color(0.55, 0.85, 1.0)

static var _keep := {}
static var _swatches := {}      # albedo path -> its 40 px swatch (null: none)

var layer := 1
var size := 12.0
var strength := 0.5
var falloff := "smooth"
var picking := false
## AUTO PAINT's settings (1.6): ROCK over SLOPE deg, SAND below SAND HEIGHT, DIRT within N m.
var auto := {"rock": true, "slope": 32.0, "sand": false, "sand_below": 0.0, "dirt": 3.0}
var last_dab := {}
var throttle := 1.0 / TerrainTool.DAB_HZ

var _stroke := {}
var _pending := Vector2(NAN, NAN)
var _alt := {}


func _init(ed: TrackEditor) -> void:
	super(ed)
	id = "paint"
	title = "PAINT"
	purpose = "Paint the ground's materials: dirt, rock, paving and sand."
	for k in _keep:
		set(k, (_keep[k] as Dictionary).duplicate() if _keep[k] is Dictionary else _keep[k])


func deactivate() -> void:
	if not _stroke.is_empty():
		stroke_end()
	picking = false
	_save()


func options(box: VBoxContainer) -> void:
	box.add_child(EditorKit.section("LAYER"))
	box.add_child(_layer_row())
	box.add_child(EditorKit.row("SIZE", EditorKit.number(size, TerrainTool.SIZE_MIN, TerrainTool.SIZE_MAX, 1.0, func(v: float) -> void: set_size(v), "%.0f", " m"),
		EditorKit.plain("The brush radius ({ed_brush_smaller} {ed_brush_bigger}).")))
	box.add_child(EditorKit.row("STRENGTH", EditorKit.number(strength, TerrainTool.STRENGTH_MIN, TerrainTool.STRENGTH_MAX, 0.01, func(v: float) -> void: set_strength(v), "%.2f"),
		EditorKit.plain("{ed_strength_down} {ed_strength_up}")))
	box.add_child(EditorKit.row("FALLOFF", EditorKit.modes(["", "", ""], LevelBrush.FALLOFFS.find(falloff), func(i: int) -> void:
		falloff = LevelBrush.FALLOFFS[i]
		_save()
		editor.redraw(), TerrainTool.FALLOFF_ICONS, TerrainTool.FALLOFF_TIPS), "How the brush weakens from its middle to its edge."))
	box.add_child(EditorKit.button("PICK LAYER", func() -> void:
		picking = true
		editor.status("Click the ground to pick its strongest layer.", true),
		"Then click the ground: its strongest layer. Or {ed_mod_alt} + click without moving.", "eyedropper"))
	box.add_child(EditorKit.hint("{ed_place} paints, {ed_mod_ctrl} erases to BASE."))
	box.add_child(EditorKit.section("LAYER TEXTURES"))
	var layers := layer_keys()
	for i in LAYER_KEYS.size():
		var k: String = LAYER_KEYS[i]
		var b := EditorKit.button(_short(str(layers.get(k, ""))), func() -> void: pick_texture(k),
			"The material of the %s layer." % LAYER_NAMES[i])
		b.clip_text = true
		box.add_child(EditorKit.row(LAYER_NAMES[i], b))
	box.add_child(EditorKit.section_icon("AUTO PAINT", "wand"))
	box.add_child(EditorKit.row("ROCK ON SLOPES", EditorKit.check(bool(auto.rock), func(v: bool) -> void: _auto("rock", v))))
	box.add_child(EditorKit.row("STEEPER THAN", EditorKit.number(float(auto.slope), 10.0, 80.0, 1.0, func(v: float) -> void: _auto("slope", v), "%.0f", " deg")))
	box.add_child(EditorKit.row("SAND LOW DOWN", EditorKit.check(bool(auto.sand), func(v: bool) -> void: _auto("sand", v))))
	box.add_child(EditorKit.row("BELOW", EditorKit.number(float(auto.sand_below), LevelDoc.HEIGHT_MIN, LevelDoc.HEIGHT_MAX, 0.5, func(v: float) -> void: _auto("sand_below", v), "%.1f", " m")))
	box.add_child(EditorKit.row("DIRT BY ROADS", EditorKit.number(float(auto.dirt), 0.0, 8.0, 0.5, func(v: float) -> void: _auto("dirt", v), "%.1f", " m"),
		"0 leaves the roadsides alone."))
	box.add_child(EditorKit.button("AUTO PAINT", func() -> void: auto_paint(), "Paints the whole ground by these rules (one undo step).", "wand"))


## The five layers as toggles showing the texture each paints (BASE erases the other four).
func _layer_row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	var group := ButtonGroup.new()
	for i in LAYER_KEYS.size():
		var b := Button.new()
		b.text = LAYER_NAMES[i]
		b.icon = swatch(LAYER_KEYS[i])
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.theme_type_variation = "EdToggle"
		# a swatch is a picture: never tinted (the pressed style darkens icons for the orange)
		for c in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
			b.add_theme_color_override(c, Color.WHITE)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == layer
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 66)
		b.tooltip_text = "Paint %s (%s)." % [LAYER_NAMES[i], _short(_layer_path(LAYER_KEYS[i]).get_file().get_basename())] 			if i > 0 else "BASE: the ground's own texture (erases the other layers)."
		var idx := i
		b.pressed.connect(func() -> void:
			Game.play_ui("res://assets/sound/ui/buttonclick.wav", -10.0)
			set_layer(idx))
		h.add_child(b)
	return h


## The texture file (under assets/) layer k paints with: the bake's, else the base material's.
func _layer_path(k: String) -> String:
	var tl = editor.build.data.get("terrain_layers", {}) if editor != null and editor.build != null else {}
	var p := str(tl.get(k, "")) if tl is Dictionary else ""
	if p == "":
		var key := str(layer_keys().get(k, ""))
		if key != "":
			p = "materials/%s.png" % key
	return p


## A small square of the texture layer k paints (null headless or without the file).
func swatch(k: String) -> Texture2D:
	var path := _layer_path(k)
	if path == "":
		return null
	if _swatches.has(path):
		return _swatches[path]
	var out: Texture2D = null
	var tex := SourceMaterials.tex(path)
	if tex != null and DisplayServer.get_name() != "headless":
		var img := tex.get_image()
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGB8)   # some ground textures keep a mask in alpha (a black square)
			while img.get_width() > 160:
				img.shrink_x2()
			img.resize(40, 40, Image.INTERPOLATE_BILINEAR)
			out = ImageTexture.create_from_image(img)
	_swatches[path] = out
	return out


func hints(_hit: EditorHit) -> Array:
	if picking:
		return [["CLICK PICK THE LAYER"], ["{ed_cancel} CANCEL"]]
	return [["DRAG PAINT %s" % LAYER_NAMES[layer]], ["{ed_mod_ctrl} DRAG ERASE"], ["{ed_mod_alt} CLICK PICK LAYER"],
		["{ed_brush_smaller} {ed_brush_bigger} SIZE"], ["{ed_strength_down} {ed_strength_up} STRENGTH"]]


func status_step() -> String:
	var hv := editor.hover if editor != null else null
	if hv == null or not hv.hit or editor.doc == null or not editor.doc.has_terrain():
		return ""
	var i := _sample_index(Vector2(hv.pos.x, hv.pos.z))
	if i < 0:
		return ""
	return "UNDER THE BRUSH: %s · PAINTING %s" % [LAYER_NAMES[LevelBrush.strongest(editor.doc.splat, i)], LAYER_NAMES[layer]]


func click(hit: EditorHit, mods: int) -> bool:
	if editor == null or editor.doc == null or hit.what == "marker":
		return false
	var p := _ground(hit)
	if is_nan(p.x) or not editor.doc.has_terrain():
		return false
	if picking:
		picking = false
		pick_layer(p)
		return true
	stroke_begin(p, mods)
	stroke_end()
	return true


func drag_begin(hit: EditorHit, mods: int) -> bool:
	if editor == null or editor.doc == null or not editor.doc.has_terrain():
		return false
	var p := _ground(hit)
	if is_nan(p.x):
		return false
	stroke_begin(p, mods)
	return true


func drag_move(hit: EditorHit, _mods: int) -> void:
	if _stroke.is_empty():
		return
	var p := _ground(hit)
	if not is_nan(p.x):
		stroke_to(p)


func drag_end(hit: EditorHit, _mods: int) -> void:
	if _stroke.is_empty():
		return
	var p := _ground(hit)
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
		if picking:
			picking = false
			return true
		if not _stroke.is_empty():
			cancel_drag()
			return true
	return false


## Esc while the button holds a stroke: the splat under it back to the stroke's start.
func cancel_drag() -> void:
	if _stroke.is_empty():
		return
	var st := _stroke
	_stroke = {}
	_pending = Vector2(NAN, NAN)
	var rect: Rect2i = st.rect
	if rect.has_area():
		editor.doc.apply([LevelDoc.op_splat(rect, LevelBrush.region_splat(st.before, editor.doc.res(), rect))])


func process(_delta: float) -> void:
	if not _stroke.is_empty() and not is_nan(_pending.x) and _now() - float(_stroke.t) >= throttle:
		var p := _pending
		_pending = Vector2(NAN, NAN)
		stroke_to(p)
	var shot := TerrainTool.alt_click(editor, _alt)
	if not is_nan(shot.x):
		var p := _ground(editor.pick(shot))
		if not is_nan(p.x):
			pick_layer(p)


func overlay(d: EditorDraw) -> void:
	var t := editor.terrain()
	if t == null:
		return
	var c: Vector2 = _stroke.last if not _stroke.is_empty() else Vector2(NAN, NAN)
	if is_nan(c.x) and editor.hover != null and editor.hover.hit:
		c = Vector2(editor.hover.pos.x, editor.hover.pos.z)
	if is_nan(c.x):
		return
	d.ground_circle(t, c, size, BRUSH_COLOR)
	var inner := LevelBrush.ring(falloff) * size
	if inner < size * 0.98:
		d.ground_circle(t, c, inner, Color(BRUSH_COLOR, 0.45))


# ---------------------------------------------------------------- additions (P16)

func set_layer(i: int) -> void:
	layer = clampi(i, 0, LAYER_KEYS.size() - 1)
	_save()
	_refresh_options()


func set_size(v: float) -> void:
	size = clampf(snappedf(v, 0.1), TerrainTool.SIZE_MIN, TerrainTool.SIZE_MAX)
	_save()
	editor.redraw()
	editor.status("BRUSH SIZE %.0f m" % size)


func set_strength(v: float) -> void:
	strength = clampf(snappedf(v, 0.01), TerrainTool.STRENGTH_MIN, TerrainTool.STRENGTH_MAX)
	_save()
	editor.status("BRUSH STRENGTH %.2f" % strength)


## The eyedropper: the strongest layer under p becomes the brush's.
func pick_layer(p: Vector2) -> void:
	var i := _sample_index(p)
	if i < 0:
		return
	set_layer(LevelBrush.strongest(editor.doc.splat, i))
	editor.status("PAINTING %s" % LAYER_NAMES[layer])


func stroke_begin(p: Vector2, mods: int) -> void:
	var l := 0 if has_mod(mods, MOD_CTRL) else layer
	_stroke = {"layer": l, "before": editor.doc.splat.duplicate(), "rect": Rect2i(), "last": p, "dabs": 0, "t": _now()}
	_pending = Vector2(NAN, NAN)
	dab(p)


func stroke_to(p: Vector2) -> void:
	if _stroke.is_empty():
		return
	if throttle > 0.0 and _now() - float(_stroke.t) < throttle:
		_pending = p
		return
	var last: Vector2 = _stroke.last
	var step := maxf(size * TerrainTool.SPACING, editor.doc.cell() * 0.5)
	var dist := last.distance_to(p)
	if dist < step:
		_pending = Vector2(NAN, NAN)
		return
	var n := mini(int(dist / step), TerrainTool.MAX_DABS)
	var dir := (p - last) / dist
	for k in n:
		dab(last + dir * step * (k + 1))
	_pending = p if dist - n * step >= step else Vector2(NAN, NAN)


func dab(p: Vector2) -> void:
	var doc := editor.doc
	var t := editor.terrain()
	if t == null or t.res != doc.res():
		t = LevelTerrain.from_doc(doc)
	if t == null:
		return
	var t0 := Time.get_ticks_usec()
	var r := LevelBrush.dab_splat(t, doc.splat, p, size, strength, int(_stroke.get("layer", layer)), falloff)
	_stroke.last = p
	_stroke.t = _now()
	_stroke.dabs = int(_stroke.dabs) + 1
	if not r.has_area():
		return
	var sr: Rect2i = _stroke.rect
	_stroke.rect = r if not sr.has_area() else sr.merge(r)
	doc.notify(PackedStringArray(["terrain"]), PackedInt32Array(), r)
	last_dab = {"ms": (Time.get_ticks_usec() - t0) / 1000.0, "rect": r}


## The stroke as one undo step (the touched rect's splat and its before-copy).
func stroke_end() -> void:
	if _stroke.is_empty():
		return
	if not is_nan(_pending.x):
		var p := _pending
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
	var res := editor.doc.res()
	editor.history.push_applied("PAINT: " + str(LAYER_NAMES[int(st.layer)]),
		[LevelDoc.op_splat(rect, LevelBrush.region_splat(editor.doc.splat, res, rect))],
		[LevelDoc.op_splat(rect, LevelBrush.region_splat(st.before, res, rect))])
	editor.bake_now(func(_b: LevelBuild) -> void: pass)
	succeeded()


## AUTO PAINT as one undo step over the whole ground; false with no terrain.
func auto_paint() -> bool:
	var doc := editor.doc
	if not doc.has_terrain():
		editor.toast("No terrain to paint.")
		return false
	var t := editor.terrain()
	if t == null or t.res != doc.res():
		t = LevelTerrain.from_doc(doc)
	var s := doc.splat.duplicate()
	var opts := auto.duplicate()
	var roads := []
	if editor.build != null:
		roads = editor.build.roads.duplicate()
	opts["roads"] = roads
	var rect := LevelBrush.auto_paint(t, s, opts)
	if not rect.has_area():
		return false
	editor.commit("AUTO PAINT", [LevelDoc.op_splat(rect, s)])
	succeeded()
	return true


## LAYER TEXTURES: the material picker for one layer; a pick is one undo step.
func pick_texture(k: String) -> void:
	var cur := str(layer_keys().get(k, ""))
	var mp := MaterialPicker.new(cur)
	mp.picked.connect(func(key: String) -> void: set_texture(k, key))
	editor.open_dialog(mp)


func set_texture(k: String, key: String) -> void:
	if not (k in LAYER_KEYS) or LevelDoc.clean_key(key) != key or key == "":
		return
	editor.commit("LAYER TEXTURE: " + LAYER_NAMES[LAYER_KEYS.find(k)], [LevelDoc.op_set(["terrain", "layers", k], key)])
	_refresh_options()


## The document's layer materials (key -> material key).
func layer_keys() -> Dictionary:
	var tr = editor.doc.data.get("terrain", {}) if editor != null and editor.doc != null else {}
	var l = tr.get("layers", {}) if tr is Dictionary else {}
	return l if l is Dictionary else {}


func _auto(k: String, v: Variant) -> void:
	auto[k] = v
	_save()


func _ground(hit: EditorHit) -> Vector2:
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


func _sample_index(p: Vector2) -> int:
	var doc := editor.doc
	if doc == null or not doc.has_terrain():
		return -1
	var org := doc.origin()
	var c := Vector2i(roundi((p.x - org.x) / doc.cell()), roundi((p.y - org.y) / doc.cell()))
	var res := doc.res()
	if c.x < 0 or c.y < 0 or c.x >= res or c.y >= res:
		return -1
	return c.y * res + c.x


static func _short(key: String) -> String:
	return key.get_file().to_upper() if key != "" else "(DEFAULT)"


func _refresh_options() -> void:
	if editor != null and editor.ui != null and editor.tool == self:
		editor.ui.refresh_tool()


func _save() -> void:
	for k in ["layer", "size", "strength", "falloff", "auto"]:
		var v = get(k)
		_keep[k] = (v as Dictionary).duplicate() if v is Dictionary else v


func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0
