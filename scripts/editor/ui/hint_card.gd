class_name HintCard
extends PanelContainer
## The tool hint cards (1.11): the first time each tool is picked (settings.editor_hints holds the
## ids seen) a card at the top of the free area with the tool's name and three lines with its key
## icons. Not modal (the mouse goes through it): it fades after the tool's first successful action
## (EditorTool.succeeded -> done) or after 12 s; the palette's "?" brings it back (recall); HELP's
## SHOW HINTS AGAIN clears the ids seen (reset). P16.

## Seconds a card stays before it fades by itself.
const SHOW_S := 12.0
const FADE_S := 0.6
const WIDTH := 600.0
## Three lines per tool ({ed_*} combos show their modifier keys through EditorKit.prompt).
const TEXTS := {
	"select": ["Click to select, {ed_mod_shift} + click adds, drag a box to select several.",
		"{ed_move} {ed_rotate} {ed_scale}: move, turn and size it with the gizmo.",
		"{ed_delete} deletes, {ed_undo} undoes anything."],
	"road": ["Click the ground to extend the road from the last point you added.",
		"Click its first point (or press {ed_close_loop}) to close the loop.",
		"Hold {ed_draw} and drag to draw a road freehand."],
	"road_closed": ["Drag a point to move it, {ed_mod_shift} + drag for its height.",
		"Drag a + dot to add a point.",
		"{ed_test} drives it."],
	"branch": ["Click the road where the branch leaves.",
		"Click the ground to lay it out, then the road where it rejoins.",
		"{ed_finish} finishes it. The bots take it too."],
	"terrain": ["Drag to sculpt: {ed_mod_ctrl} inverts, {ed_mod_shift} smooths.",
		"{ed_brush_smaller} {ed_brush_bigger} brush size, {ed_strength_down} {ed_strength_up} strength.",
		"ADD LAKE in the tool options: drag a rectangle on the ground."],
	"paint": ["Drag to paint the layer, {ed_mod_ctrl} + drag erases it.",
		"{ed_mod_alt} + click picks the layer under the cursor.",
		"AUTO PAINT does slopes, sand and roadsides in one go."],
	"objects": ["Pick a model in the catalog, then click to place it.",
		"{ed_mod_shift} + WHEEL turns it, {ed_mod_ctrl} + WHEEL sizes it.",
		"{ed_scatter} paints many at once (SCATTER)."],
	"items": ["Click the road for a row of item crates.",
		"A BOOST PAD sits on the racing line; LOW GRAVITY is a stretch of road.",
		"AUTO ITEMS fills the straights for you."],
	"hazards": ["Pick a hazard in the tool options, then click the road.",
		"Green on the road shows where it may go.",
		"DIFFICULTY in the inspector: EASY, NORMAL or BRUTAL."],
	"crowds": ["Click beside the road for a crowd of spectators.",
		"Drag its end bars to make it longer.",
		"WHO and MOOD are in the inspector."],
	"world": ["THEME sets the sky, light, ground, music and start arch in one step.",
		"Every setting here is one undo step ({ed_undo}).",
		"{ed_test} to see it in a race."],
}

var tool_id := ""
var age := 0.0
var fading := false


## The card of tool_id on its first pick (none when its id was seen).
static func maybe_show(ed: TrackEditor, tool_id: String) -> void:
	if ed == null or tool_id == "" or not TEXTS.has(tool_id):
		return
	var seen := seen_ids()
	if tool_id in seen:
		return
	seen.append(tool_id)
	_set_seen(seen)
	_show(ed, tool_id)


## The tool's first successful action: its card fades.
static func done(ed: TrackEditor, tool_id: String) -> void:
	var c := current(ed)
	if c != null and c.tool_id == tool_id:
		c.fade()


## The palette's "?": the tool's card again (seen or not).
static func recall(ed: TrackEditor, tool_id: String) -> void:
	if ed == null or not TEXTS.has(tool_id):
		return
	_show(ed, tool_id)


# ---------------------------------------------------------------- additions (P16)

## SHOW HINTS AGAIN: forgets the ids seen, then shows the active tool's card.
static func reset(ed: TrackEditor) -> void:
	_set_seen([])
	if ed != null and ed.tool != null:
		maybe_show(ed, ed.tool.id)


## The ids whose cards were seen (settings.editor_hints).
static func seen_ids() -> Array:
	var g := _game()
	var v = g.settings.get("editor_hints", []) if g != null else []
	var out := []
	if v is Array or v is PackedStringArray:
		for x in v:
			out.append(str(x))
	return out


## The card shown now (null: none).
static func current(ed: TrackEditor) -> HintCard:
	var host := _host(ed)
	if host == null:
		return null
	for c in host.get_children():
		if c is HintCard and not (c as HintCard).fading and not c.is_queued_for_deletion():
			return c
	return null


## The three lines of a tool's card (ROAD: the closed loop's when the road is a loop).
static func lines(ed: TrackEditor, tool_id: String) -> Array:
	var key := tool_id
	if tool_id == "road" and ed != null and ed.doc != null:
		var r = ed.doc.data.get("road", {})
		if r is Dictionary and bool(r.get("closed", false)):
			key = "road_closed"
	return TEXTS.get(key, [])


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = "EdCard"


func _process(delta: float) -> void:
	age += delta
	if age >= SHOW_S and not fading:
		fade()


## Fades out and frees itself.
func fade() -> void:
	if fading:
		return
	fading = true
	if not is_inside_tree():
		queue_free()
		return
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, FADE_S)
	tw.tween_callback(queue_free)


static func _show(ed: TrackEditor, tool_id: String) -> void:
	var host := _host(ed)
	if host == null:
		return
	for c in host.get_children():
		if c is HintCard:
			host.remove_child(c)
			c.queue_free()
	var card := HintCard.new()
	card.name = "HintCard"
	card.tool_id = tool_id
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var tn := str(EditorUI.TOOL_NAMES.get(tool_id, tool_id.to_upper()))
	var head := UiKit.label(tn, EditorKit.FONT, UiKit.ORANGE, true)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	for line in lines(ed, tool_id):
		var l := PromptLabel.new(EditorKit.prompt(str(line)), EditorKit.FONT, UiKit.TEXT)
		l.add_theme_font_override("normal_font", UiKit.font(false))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = WIDTH - 24.0
		v.add_child(l)
	host.add_child(card)
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.0
	card.anchor_bottom = 0.0
	card.offset_left = -WIDTH * 0.5
	card.offset_right = WIDTH * 0.5
	card.offset_top = 8.0
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.modulate.a = 0.0
	var tw := card.create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.2)


static func _host(ed: TrackEditor) -> Control:
	if ed == null or ed.ui == null or not is_instance_valid(ed.ui):
		return null
	var h = ed.ui.get("hint_host")
	return h if h is Control and is_instance_valid(h) else null


## Keeps the ids in settings.editor_hints and writes that one key to the settings file (the
## other settings stay as the file has them: nothing half-changed elsewhere gets saved with it).
static func _set_seen(ids: Array) -> void:
	var g := _game()
	if g == null:
		return
	g.settings["editor_hints"] = ids
	var p := str(g.call("settings_path")) if g.has_method("settings_path") else ""
	if p == "":
		return
	var cfg := ConfigFile.new()
	cfg.load(p)
	cfg.set_value("settings", "editor_hints", ids)
	cfg.save(p)


static func _game() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Game")
	return null
