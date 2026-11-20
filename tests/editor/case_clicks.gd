extends RefCounted
## editor/case_clicks (0.3.1, CI, fake registries): what the owner met by hand, by real mouse events
## with frames between the press and the release (as a hand makes them). The TOOL OPTIONS buttons
## take the click (PAINT's layers, PICK LAYER, ITEMS' kinds): a panel button that took the focus on
## the press lost it before the release, and Godot dropped the click. ITEMS and HAZARDS place on a
## click beside the road (snapped onto it), on an open road too; a refused click says why in a
## toast. The badge reads DRAFT while there is no road or the loop is open, not ERROR. The themes'
## PAINT layers look like their names (DIRT is not the coast's grassy dirt).

const NEEDS_CONTENT := false
const S := preload("res://tests/editor/case_select.gd")

var t: Node
var ed: TrackEditor


func run(tt: Node) -> void:
	t = tt
	var doc := LevelDoc.blank("Clicks", 512.0, 257)
	ed = await S.open_editor(t, doc)
	S.look_down(ed, Vector3.ZERO, 320.0)
	await t.frames(2)
	t.check(ed.ui.badge.text == "DRAFT · DRAW A ROAD", "no road: the badge is a draft, not an error (%s)" % ed.ui.badge.text)
	# an open road of four points
	var pts := []
	for p in [Vector3(-120, 0, -60), Vector3(0, 0, -100), Vector3(120, 0, -60), Vector3(130, 0, 70)]:
		pts.append({"uid": doc.new_uid(), "pos": [p.x, 0.0, p.z], "width": 14.0, "style": "asphalt"})
	ed.commit("ROAD", [LevelDoc.op_set(["road"], {"closed": false, "points": pts})])
	await _baked()
	t.check(ed.ui.badge.text == "DRAFT · CLOSE THE LOOP", "an open road: the badge asks to close the loop (%s)" % ed.ui.badge.text)
	var report_pins := 0
	for e in ed.markers._lists.get(EditorMarkers.ISSUES, []):
		if str(e.get("kind", "")) == "issue":
			report_pins += 1
	t.check(report_pins == 0, "and no red pin for it (%d)" % report_pins)
	await _paint_buttons()
	await _items_beside(-1)
	# the loop closed: the same clicks work there
	ed.commit("CLOSE", [LevelDoc.op_set(["road", "closed"], true)])
	await _baked()
	t.check(ed.ui.badge.text.begins_with("RACEABLE") or ed.ui.badge.text.contains("ERROR"), "closed: the usual badge (%s)" % ed.ui.badge.text)
	await _hazard_beside()
	_themes()
	await S.close_editor(t, ed)


func _baked() -> void:
	ed.bake_soon(0.0)
	for i in 600:
		await t.frames(1)
		if ed.build != null and ed.build.revision == ed.doc.revision and not ed.baking():
			break
	await t.frames(2)


func _push(ev: InputEvent) -> void:
	ed.get_viewport().push_input(ev, true)


## A hand's click: move, press, two frames, release.
func _click(p: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	_push(m)
	await t.frames(1)
	for down in [true, false]:
		var b := InputEventMouseButton.new()
		b.position = p
		b.global_position = p
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = down
		b.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		_push(b)
		await t.frames(2)


func _button(text: String) -> Button:
	for b in ed.ui.find_children("*", "Button", true, false):
		var bb := b as Button
		if bb.is_visible_in_tree() and bb.text.strip_edges().to_upper() == text:
			return bb
	return null


func _paint_buttons() -> void:
	ed.set_tool("paint")
	await t.frames(3)
	var pt := ed.tools["paint"] as PaintTool
	pt.set_layer(1)
	await t.frames(2)
	for nm in ["ROCK", "SAND", "PAVE", "BASE", "DIRT"]:
		var b := _button(nm)
		t.check(b != null and b.focus_mode == Control.FOCUS_NONE, "PAINT %s: a button that never takes the focus" % nm)
		if b == null:
			continue
		await _click(b.get_global_rect().get_center())
		t.check(PaintTool.LAYER_NAMES[pt.layer] == nm, "a click on %s picks it (layer %s)" % [nm, PaintTool.LAYER_NAMES[pt.layer]])
		var sel := _button(nm)
		t.check(sel != null and sel.get_theme_color("icon_pressed_color") == Color.WHITE, "%s: its texture swatch is not tinted when picked" % nm)
	var pk := _button("PICK LAYER")
	if pk != null:
		await _click(pk.get_global_rect().get_center())
		t.check(pt.picking, "PICK LAYER takes the click")
		pt.picking = false
	var how := ed.ui.options_box.find_child("ToolHow", false, false) as Label
	t.check(how != null and how.text.contains("drag on the ground"), "the tool options start with how to use the tool")


## ITEMS: a click 9 m past the road's edge puts a crate row on it; on the bare ground far away a
## toast says why nothing happened. A click on BOOST PAD's tile picks it.
func _items_beside(key: int) -> void:
	ed.set_tool("items")
	await t.frames(3)
	var it := ed.tools["items"] as ItemsTool
	var r := ed.road(key)
	t.check(r != null, "the open road is in the bake")
	if r == null:
		return
	var i := r.idx(r.length * 0.4)
	var beside := r.surface(i, r.width[i] * 0.5 + 9.0)
	var n0 := (ed.doc.data.get("items", []) as Array).size()
	await _click(ed.camera.unproject_position(beside))
	await t.frames(2)
	t.check((ed.doc.data.get("items", []) as Array).size() == n0 + 1, "a click 9 m beside the road adds a crate row on it")
	await _click(ed.camera.unproject_position(Vector3(-60, 0, 150)))
	t.check(ed.last_toast.begins_with("Click on a road"), "a click far from any road says so in a toast (%s)" % ed.last_toast)
	var pad_tile: Button = null
	for b in ed.ui.options_box.find_children("*", "Button", true, false):
		if (b as Button).tooltip_text.begins_with("BOOST PAD"):
			pad_tile = b
			break
	if pad_tile != null:
		await _click(pad_tile.get_global_rect().get_center())
		t.check(it.mode == "pad", "a click on the BOOST PAD tile picks it (%s)" % it.mode)


func _hazard_beside() -> void:
	ed.set_tool("hazards")
	await t.frames(3)
	var r := ed.road(-1)
	if r == null:
		t.fail("no main road for HAZARDS")
		return
	# a spot beside the road that is in the view (not under a panel)
	var sp := Vector2(-1, -1)
	for f in [0.55, 0.35, 0.7, 0.2, 0.85, 0.1]:
		var i := r.idx(r.length * f)
		var q := ed.camera.unproject_position(r.surface(i, -(r.width[i] * 0.5 + 6.0)))
		if ed.free_rect().grow(-20.0).has_point(q):
			sp = q
			break
	var n0 := (ed.doc.data.get("hazards", []) as Array).size()
	await _click(sp)
	await t.frames(2)
	var hz := ed.tools["hazards"] as HazardsTool
	t.check((ed.doc.data.get("hazards", []) as Array).size() == n0 + 1, "a click beside the road places the hazard (status '%s', refusal '%s', choice %s, hover %s)" % [ed.status_text, hz.refusal, hz.choice, ed.hover.what if ed.hover != null else "-"])


func _themes() -> void:
	for id in LevelThemes.EDITOR_LAYERS:
		var own: Dictionary = LevelThemes.EDITOR_LAYERS[id]
		if own.has("dirt"):
			t.check(not str(own.dirt).contains("dirtfloor006a"), "%s: DIRT is a dirt texture" % id)
	t.check(str(LevelThemes.EDITOR_LAYERS.coast.base) == "nature/grassfloor002a", "the EMPTY FIELD's coast theme lays grass")
