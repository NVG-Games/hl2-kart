class_name EditorUI
extends Control
## The editor's screen (1.3): top bar (the track's name, FILE / EDIT / VIEW, the snap group, the
## COMPLEXITY meter, the validation badge, the orange TEST DRIVE button with its options, HELP),
## the palette with keycaps and "?", the outliner, the tool options and the inspector on the right,
## the status bar (cursor, road, selection, snap, bake state, the tool's step, what the mouse does
## on what is under it), toasts, cards, the validation drawer and the slots P16 / P17 fill (hint
## cards, the catalog drawer), plus the OLDER VERSIONS, TRACK PROPERTIES, SAVE AS, HOST and
## "Save changes?" dialogs. The root lets the mouse through (the viewport's); the panels stop it.
## The panels never keep the keyboard focus (no panel walking: Enter and the arrows stay the
## editor's); text fields keep it while typed in. P10.

const TOOL_NAMES := {"select": "SELECT", "road": "ROAD", "branch": "BRANCH", "terrain": "TERRAIN", "paint": "PAINT",
	"objects": "OBJECTS", "items": "ITEMS", "hazards": "HAZARDS", "crowds": "CROWDS", "world": "WORLD"}
const TOOL_TIPS := {"select": "Select, move, rotate and scale anything.", "road": "Draw and shape the road.",
	"branch": "Forks and shortcuts the bots take too.", "terrain": "Raise, lower, smooth and flatten the ground.",
	"paint": "Paint the ground's materials.", "objects": "Place Half-Life 2 objects, lights and fires.",
	"items": "Item crates, boost pads, barrels and low gravity.", "hazards": "Hazards and enemies along the road.",
	"crowds": "Spectators and extras.", "world": "Sky, sun, fog, water, music and the start arch."}
const GRID_SIZES := [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
const ANGLE_STEPS := [5.0, 15.0, 45.0]
const TOAST_S := 2.5
const TOAST_MAX := 4
const DRAWER_H := 300.0
const GAP := 8.0
const NO_ROAD := "No road yet: press {ed_tool_road} and click on the ground, or hold the button and draw."
## The COMPLEXITY terms (4.5): stats key, label, budget.
const BUDGETS := [["props", "PROPS", 1500.0], ["lights", "LIGHTS", 64.0], ["people", "PEOPLE", 450.0],
	["heavy", "HEAVY HAZARDS", 6.0], ["crates", "CRATES", 64.0]]
const BAR_W := 120.0
const DIFFS := ["EASY", "NORMAL", "HARD"]

# menu ids
enum { F_NEW, F_OPEN, F_SAVE, F_SAVE_AS, F_DUPLICATE, F_PROPS, F_OLDER, F_THUMB, F_HOST, F_FOLDER, F_EXIT_HOME, F_EXIT_MENU,
	E_UNDO, E_REDO, E_CUT, E_COPY, E_PASTE, E_PASTE_HERE, E_DUPLICATE, E_DELETE, E_SELECT_ALL, E_DESELECT, E_REVERSE,
	V_TOP, V_FRAME, V_HOME, V_LINE, V_ZONES, V_PINS, V_GRID, V_LABELS, V_UNHIDE, V_SPEED, V_MUSIC }
const ACTION_OF := {F_SAVE: "ed_save", F_SAVE_AS: "ed_save_as", E_UNDO: "ed_undo", E_REDO: "ed_redo", E_CUT: "ed_cut",
	E_COPY: "ed_copy", E_PASTE: "ed_paste", E_PASTE_HERE: "ed_paste_here", E_DUPLICATE: "ed_duplicate",
	E_DELETE: "ed_delete", E_SELECT_ALL: "ed_select_all", V_TOP: "ed_top", V_FRAME: "ed_frame_all", V_HOME: "ed_home",
	V_LINE: "ed_line", V_UNHIDE: "ed_unhide"}

var editor: TrackEditor
var report: LevelReport
## The last bake's stats (set_stats).
var last_stats := {}
## {value, terms: [[label, n, budget]], text} of the last stats (4.5).
var complexity := {"value": 0.0, "terms": [], "text": ""}
## VIEW toggles the overlays read (zones, pins, grid, labels).
var view_flags := {"zones": true, "pins": true, "grid": false, "labels": false, "music": true}

var top_bar: PanelContainer
var left: PanelContainer
var right: PanelContainer
var status_bar: PanelContainer
var name_button: Button
var file_menu: MenuButton
var edit_menu: MenuButton
var view_menu: MenuButton
var grid_toggle: Button
var grid_size: OptionButton
var angle_toggle: Button
var angle_step: OptionButton
var surface_toggle: Button
var complexity_box: HBoxContainer
var complexity_bar: ComplexityBar
var badge: Button
var test_button: Button
var test_more: Button
var help_button: Button
var palette: VBoxContainer
var tool_buttons := {}          # id -> Button
var outliner: Outliner
var options_title: Button
var options_scroll: ScrollContainer
var options_box: VBoxContainer
var options_open := true
var inspector: Inspector
var pos_label: Label
var road_label: Label
var sel_label: Label
var snap_label: Label
var bake_label: Label
var message: PromptLabel
var hints_holder: Control
var hints_bar: PromptBar
var toasts: VBoxContainer
var card_panel: PanelContainer
var card_label: Label
var empty_hint: PromptLabel
var drawer: ValidationPanel
## P17's catalog drawer goes here (OBJECTS: 220 tall at the bottom of the free area).
var catalog_host: Control
## P16's hint cards go here (the top of the free area).
var hint_host: Control
## The open EDITOR MENU (null: none).
var menu: EditorMenu
## Every toast shown (tests, headless runs).
var toast_log: PackedStringArray = []

var _built := false
var _last_tool := ""
var _status_dirty := true
var _hint_key := "~"
var _after_save := Callable()
var _test_pop: PopupPanel


func _init() -> void:
	name = "EditorUI"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(ed: TrackEditor) -> void:
	editor = ed
	theme = EditorKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not is_in_group(InputPrompts.SCREEN_GROUP):
		add_to_group(InputPrompts.SCREEN_GROUP)
	if not _built:
		_build()
	if is_inside_tree() and not get_viewport().gui_focus_changed.is_connected(_on_focus_changed):
		get_viewport().gui_focus_changed.connect(_on_focus_changed)
	if ed.history != null and not ed.history.changed.is_connected(_on_history):
		ed.history.changed.connect(_on_history)
	_sync_snap()
	_tool_tips()
	refresh_tool()
	refresh_inspector()
	refresh_status()
	if ed.card != "":
		show_card(ed.card)


## The safety net (InputPrompts): the editor's panels never take the focus (no panel walking); a
## pad flies the camera, the keyboard keeps its shortcuts.
func focus_default() -> bool:
	return false


func refresh_tool() -> void:
	if not _built or editor == null or editor.tool == null:
		return
	var id := editor.tool.id
	for t in tool_buttons:
		(tool_buttons[t] as Button).set_pressed_no_signal(t == id)
	if _last_tool != "" and _last_tool != id:
		Game.play_ui("res://assets/sound/ui/buttonclick.wav", -8.0)
	_last_tool = id
	for c in options_box.get_children():
		options_box.remove_child(c)
		c.queue_free()
	editor.tool.options(options_box)
	var title := str(TOOL_NAMES.get(id, id.to_upper()))
	options_title.text = "%s  TOOL OPTIONS · %s" % ["-" if options_open else "+", title]
	options_scroll.visible = options_open and options_box.get_child_count() > 0
	_hint_key = "~"
	refresh_status()


func refresh_inspector() -> void:
	if inspector != null:
		inspector.refresh()
	if outliner != null:
		outliner.refresh()


func refresh_status() -> void:
	_status_dirty = true


func set_report(r: LevelReport) -> void:
	report = r
	if not _built:
		return
	var errs := r.errors() if r != null else 0
	var warns := r.warnings() if r != null else 0
	badge.text = badge_text(errs, warns)
	badge.icon = EditorKit.icon("error" if errs > 0 else "tick", 16)
	var col := EditorKit.ERROR_COLOR if errs > 0 else (EditorKit.WARN_COLOR if warns > 0 else EditorKit.OK_COLOR)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		badge.add_theme_color_override(k, col)
	badge.tooltip_text = "The track can be raced." if errs == 0 else "Fix the errors before hosting it (F3 shows them)."
	drawer.set_report(r)
	# an open road or no road: the button says why it will not drive (only that stops it, 1.7)
	var why := editor.session.drive_blocker() if editor != null and editor.session != null and editor.session.is_open() else ""
	test_button.tooltip_text = EditorKit.plain(why) if why != "" else "Drive it from the start (%s)." % InputPrompts.action_text("ed_test", "keyboard")
	if not bool(view_flags.pins) and editor != null and editor.markers != null:
		editor.markers.set_issues(LevelReport.new())


func set_stats(stats: Dictionary) -> void:
	last_stats = stats
	if not _built:
		return
	var res := 0
	if editor != null and editor.doc != null and editor.doc.has_terrain():
		res = editor.doc.res()
	complexity = complexity_of(stats, res)
	complexity_bar.value = float(complexity.value)
	complexity_bar.color = complexity_color(float(complexity.value))
	complexity_bar.queue_redraw()
	complexity_box.tooltip_text = "COMPLEXITY %d %%\n%s" % [int(roundf(float(complexity.value) * 100.0)), str(complexity.text)]


func show_card(text: String) -> void:
	if not _built:
		return
	card_label.text = text
	card_panel.visible = true
	_status_dirty = true


func hide_card() -> void:
	if not _built:
		return
	card_panel.visible = false
	_status_dirty = true


func toast(text: String) -> void:
	toast_log.append(text)
	if not _built:
		return
	var p := PanelContainer.new()
	p.theme_type_variation = "EdCard"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := PromptLabel.new(EditorKit.prompt(text), EditorKit.FONT, UiKit.TEXT)
	l.add_theme_font_override("normal_font", UiKit.font(true))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 300
	p.add_child(l)
	toasts.add_child(p)
	while toasts.get_child_count() > TOAST_MAX:
		var old := toasts.get_child(0)
		toasts.remove_child(old)
		old.queue_free()
	var tw := p.create_tween()
	tw.tween_interval(TOAST_S)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


func open_menu() -> void:
	if editor == null:
		return
	if menu != null and is_instance_valid(menu) and not menu.is_queued_for_deletion():
		menu.close()
		return
	menu = EditorMenu.new(editor)
	menu.closed.connect(func() -> void: menu = null)
	editor.open_dialog(menu)


func open_help() -> void:
	for c in get_children():
		if c is HelpOverlay:
			c.queue_free()
			return
	if editor == null:
		return
	var h := HelpOverlay.new(editor)
	h.name = "HelpOverlay"
	add_child(h)
	if h.size == Vector2.ZERO:
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func is_typing() -> bool:
	if not is_inside_tree():
		return false
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


# ---------------------------------------------------------------- additions (P10)

## F3 / the badge: shows or hides the validation drawer.
func toggle_validation() -> void:
	if not _built:
		return
	drawer.visible = not drawer.visible
	if drawer.visible:
		drawer.set_report(report)
		# slides up from the bottom (by its offsets: the anchors keep it right on a resize)
		var fb := -TrackEditor.BAR_BOTTOM - GAP
		drawer.modulate.a = 0.0
		drawer.offset_top = fb - DRAWER_H + 40.0
		drawer.offset_bottom = fb + 40.0
		var tw := drawer.create_tween().set_parallel(true)
		tw.tween_property(drawer, "modulate:a", 1.0, 0.15)
		tw.tween_property(drawer, "offset_top", fb - DRAWER_H, 0.15)
		tw.tween_property(drawer, "offset_bottom", fb, 0.15)


## "RACEABLE", "RACEABLE · 5 WARNINGS", "2 ERRORS · 5 WARNINGS".
static func badge_text(errs: int, warns: int) -> String:
	var w := "%d WARNING%s" % [warns, "" if warns == 1 else "S"]
	if errs == 0:
		return "RACEABLE" if warns == 0 else "RACEABLE · " + w
	var e := "%d ERROR%s" % [errs, "" if errs == 1 else "S"]
	return e if warns == 0 else e + " · " + w


## 4.5: max(props / 1500, lights / 64, people / 450, heavy hazards / 6, crates / 64,
## res^2 / 1025^2 x 0.8) of a bake's stats, with each term for the breakdown.
static func complexity_of(s: Dictionary, res: int) -> Dictionary:
	var v := 0.0
	var terms := []
	var parts := PackedStringArray()
	for b in BUDGETS:
		var n := int(s.get(b[0], 0))
		v = maxf(v, n / float(b[2]))
		terms.append([b[1], n, int(b[2])])
		parts.append("%s %d / %d" % [b[1], n, int(b[2])])
	if res > 0:
		v = maxf(v, float(res * res) / (1025.0 * 1025.0) * 0.8)
		terms.append(["TERRAIN", res, 1025])
		parts.append("TERRAIN %d x %d" % [res, res])
	return {"value": v, "terms": terms, "text": " · ".join(parts)}


## The meter's colour: yellow past 80 %, red past 100 %.
static func complexity_color(v: float) -> Color:
	if v > 1.0:
		return EditorKit.ERROR_COLOR
	if v > 0.8:
		return EditorKit.WARN_COLOR
	return EditorKit.OK_COLOR


## The menus' and the bar's ids run through TrackEditor's own shortcut code (one behaviour for the
## key and the menu).
func run_action(action: String) -> void:
	if editor == null or not editor.has_method("_shortcut"):
		return
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	editor.call("_shortcut", ev)
	refresh_status()


## Asks "Save changes to <name>?" when the track is unsaved, then calls go (SAVE saves first).
func confirm_leave(go: Callable) -> void:
	if editor == null or editor.session == null or not editor.session.dirty():
		go.call()
		return
	var d := SaveChanges.new(_track_name())
	d.answered.connect(func(choice: String) -> void: _left(choice, go))
	editor.open_dialog(d)


func _left(choice: String, go: Callable) -> void:
	if choice == "save":
		_after_save = go
		editor.save()
	elif choice == "discard":
		go.call()


func request_exit(where: String) -> void:
	confirm_leave(func() -> void: editor.exit_to(where))


# ---------------------------------------------------------------- building

func _build() -> void:
	_built = true
	var vs := Vector2(TrackEditor.PANEL_LEFT, TrackEditor.PANEL_RIGHT)
	# top bar
	top_bar = PanelContainer.new()
	top_bar.name = "TopBar"
	top_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	top_bar.add_theme_stylebox_override("panel", UiKit.box(UiKit.FRAME_BG, Color(1, 1, 1, 0.1), 1, 0, 6))
	add_child(top_bar)
	_place(top_bar, 0, 0, 1, 0, 0, 0, 0, TrackEditor.BAR_TOP)
	top_bar.add_child(_build_top())
	# left column: palette + outliner
	left = PanelContainer.new()
	left.name = "Left"
	left.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(left)
	_place(left, 0, 0, 0, 1, 0, TrackEditor.BAR_TOP, vs.x, -TrackEditor.BAR_BOTTOM)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left.add_child(lv)
	lv.add_child(_build_palette())
	lv.add_child(HSeparator.new())
	outliner = Outliner.new()
	lv.add_child(outliner)
	# right column: tool options + inspector
	right = PanelContainer.new()
	right.name = "Right"
	right.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(right)
	_place(right, 1, 0, 1, 1, -vs.y, TrackEditor.BAR_TOP, 0, -TrackEditor.BAR_BOTTOM)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	right.add_child(rv)
	options_title = EditorKit.button("TOOL OPTIONS", _toggle_options, "Show or hide the tool's options.")
	options_title.theme_type_variation = "EdFlat"
	options_title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	options_title.add_theme_color_override("font_color", UiKit.ORANGE)
	options_title.clip_text = true
	rv.add_child(options_title)
	options_scroll = ScrollContainer.new()
	options_scroll.name = "ToolOptions"
	options_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(options_scroll)
	options_box = VBoxContainer.new()
	options_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_box.add_theme_constant_override("separation", 4)
	options_scroll.add_child(options_box)
	rv.add_child(HSeparator.new())
	rv.add_child(EditorKit.section("INSPECTOR"))
	inspector = Inspector.new()
	rv.add_child(inspector)
	# status bar
	status_bar = PanelContainer.new()
	status_bar.name = "StatusBar"
	status_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	status_bar.add_theme_stylebox_override("panel", UiKit.box(UiKit.FRAME_BG, Color(1, 1, 1, 0.1), 1, 0, 8))
	add_child(status_bar)
	_place(status_bar, 0, 1, 1, 1, 0, -TrackEditor.BAR_BOTTOM, 0, 0)
	status_bar.add_child(_build_status())
	# the free area's overlays
	var fl := TrackEditor.PANEL_LEFT + GAP
	var fr := -TrackEditor.PANEL_RIGHT - GAP
	var ft := TrackEditor.BAR_TOP + GAP
	var fb := -TrackEditor.BAR_BOTTOM - GAP
	hint_host = Control.new()
	hint_host.name = "HintHost"
	hint_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_host)
	_place(hint_host, 0, 0, 1, 0, fl, ft, fr, ft + 140.0)
	catalog_host = Control.new()
	catalog_host.name = "CatalogHost"
	catalog_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(catalog_host)
	_place(catalog_host, 0, 1, 1, 1, TrackEditor.PANEL_LEFT, -TrackEditor.BAR_BOTTOM - 220.0, -TrackEditor.PANEL_RIGHT, -TrackEditor.BAR_BOTTOM)
	empty_hint = PromptLabel.new(EditorKit.prompt(NO_ROAD), EditorKit.FONT + 2, UiKit.TEXT)
	empty_hint.name = "EmptyHint"
	empty_hint.add_theme_font_override("normal_font", UiKit.font(true))
	empty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_hint.fit_content = true
	empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_hint.visible = false
	add_child(empty_hint)
	_place(empty_hint, 0, 0.5, 1, 0.5, fl + 60.0, -40.0, fr - 60.0, 40.0)
	card_panel = PanelContainer.new()
	card_panel.name = "Card"
	card_panel.theme_type_variation = "EdCard"
	card_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_panel.visible = false
	card_label = UiKit.label("", 20, Color.WHITE, true)
	card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_panel.add_child(card_label)
	add_child(card_panel)
	var cx := (TrackEditor.PANEL_LEFT - TrackEditor.PANEL_RIGHT) * 0.5
	var cy := (TrackEditor.BAR_TOP - TrackEditor.BAR_BOTTOM) * 0.5
	_place(card_panel, 0.5, 0.5, 0.5, 0.5, cx - 200.0, cy - 36.0, cx + 200.0, cy + 36.0)
	drawer = ValidationPanel.new()
	drawer.setup(editor)
	drawer.visible = false
	add_child(drawer)
	_place(drawer, 0, 1, 1, 1, fl, fb - DRAWER_H, fr, fb)
	toasts = VBoxContainer.new()
	toasts.name = "Toasts"
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	toasts.add_theme_constant_override("separation", 6)
	add_child(toasts)
	_place(toasts, 1, 0, 1, 0, fr - 340.0, ft, fr, ft + 300.0)
	outliner.setup(editor)
	inspector.setup(editor)


## Anchors (a*) and offsets (o*) in one call.
func _place(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob


func _build_top() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	name_button = EditorKit.button("MY TRACK", _open_properties, "Track properties: name, description, AUTO DRESS...")
	name_button.theme_type_variation = "EdFlat"
	name_button.add_theme_font_override("font", UiKit.font(true))
	name_button.clip_text = true
	name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_button.custom_minimum_size = Vector2(170, 30)
	name_button.focus_mode = Control.FOCUS_NONE
	h.add_child(name_button)
	file_menu = _menu("FILE", [
		[F_NEW, "NEW TRACK"], [F_OPEN, "OPEN"], [-1], [F_SAVE, "SAVE"], [F_SAVE_AS, "SAVE AS..."], [F_DUPLICATE, "DUPLICATE"],
		[-1], [F_PROPS, "TRACK PROPERTIES..."], [F_OLDER, "OLDER VERSIONS..."], [F_THUMB, "SET THUMBNAIL FROM CAMERA"],
		[-1], [F_HOST, "HOST ONLINE WITH THIS TRACK..."], [F_FOLDER, "OPEN TRACKS FOLDER"],
		[-1], [F_EXIT_HOME, "EXIT TO TRACK EDITOR"], [F_EXIT_MENU, "EXIT TO MAIN MENU"]])
	h.add_child(file_menu)
	edit_menu = _menu("EDIT", [
		[E_UNDO, "UNDO"], [E_REDO, "REDO"], [-1], [E_CUT, "CUT"], [E_COPY, "COPY"], [E_PASTE, "PASTE"],
		[E_PASTE_HERE, "PASTE IN PLACE"], [E_DUPLICATE, "DUPLICATE"], [E_DELETE, "DELETE"], [-1],
		[E_SELECT_ALL, "SELECT ALL"], [E_DESELECT, "DESELECT"], [-1], [E_REVERSE, "REVERSE TRACK DIRECTION"]])
	h.add_child(edit_menu)
	view_menu = _menu("VIEW", [
		[V_TOP, "TOP VIEW", true], [V_FRAME, "FRAME TRACK"], [V_HOME, "GO TO START"], [V_LINE, "RACING LINE", true], [-1],
		[V_ZONES, "ZONES", true], [V_PINS, "ISSUE PINS", true], [V_GRID, "GRID", true], [V_LABELS, "LABELS", true],
		[V_UNHIDE, "SHOW HIDDEN"], [-1], [V_SPEED, "CAMERA SPEED..."], [V_MUSIC, "MUSIC", true]])
	h.add_child(view_menu)
	h.add_child(VSeparator.new())
	# snap group
	grid_toggle = EditorKit.toggle("GRID", true, func(on: bool) -> void: _set_snap("on", on))
	grid_toggle.tooltip_text = "Grid snap (G). Hold Ctrl while dragging to invert it."
	h.add_child(grid_toggle)
	var gl := []
	for g in GRID_SIZES:
		gl.append(("%s m" % str(g)).replace(".0 m", " m"))
	grid_size = EditorKit.choice(gl, 2, func(i: int) -> void: _set_snap("grid", GRID_SIZES[i]))
	grid_size.custom_minimum_size.x = 78
	grid_size.tooltip_text = "Grid step"
	h.add_child(grid_size)
	angle_toggle = EditorKit.toggle("ANGLE", true, func(on: bool) -> void: _set_snap("angle_on", on))
	angle_toggle.tooltip_text = "Angle snap for rotations"
	h.add_child(angle_toggle)
	var al := []
	for a in ANGLE_STEPS:
		al.append("%d°" % int(a))
	angle_step = EditorKit.choice(al, 1, func(i: int) -> void: _set_snap("angle", ANGLE_STEPS[i]))
	angle_step.custom_minimum_size.x = 62
	angle_step.tooltip_text = "Angle step"
	h.add_child(angle_step)
	surface_toggle = EditorKit.toggle("SURFACE", true, func(on: bool) -> void: _set_snap("surface", on))
	surface_toggle.tooltip_text = "Drop what you move onto what is under it"
	h.add_child(surface_toggle)
	for b in [grid_toggle, grid_size, angle_toggle, angle_step, surface_toggle]:
		(b as Control).focus_mode = Control.FOCUS_NONE
	h.add_child(VSeparator.new())
	# COMPLEXITY
	complexity_box = HBoxContainer.new()
	complexity_box.add_theme_constant_override("separation", 6)
	complexity_box.mouse_filter = Control.MOUSE_FILTER_STOP
	complexity_box.tooltip_text = "COMPLEXITY"
	var cl := UiKit.label("COMPLEXITY", EditorKit.FONT_SMALL, UiKit.TEXT_DIM, true)
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	complexity_box.add_child(cl)
	complexity_bar = ComplexityBar.new()
	complexity_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	complexity_box.add_child(complexity_bar)
	complexity_box.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			toast("COMPLEXITY %d %%: %s" % [int(roundf(float(complexity.value) * 100.0)), str(complexity.text)]))
	h.add_child(complexity_box)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(spacer)
	badge = EditorKit.button("RACEABLE", toggle_validation, "{ed_validation} the validation list")
	badge.theme_type_variation = "EdFlat"
	badge.icon = EditorKit.icon("tick", 16)
	badge.add_theme_font_override("font", UiKit.font(true))
	badge.focus_mode = Control.FOCUS_NONE
	h.add_child(badge)
	var key := InputPrompts.action_text("ed_test", "keyboard")
	test_button = EditorKit.button("TEST DRIVE  " + key, func() -> void: _drive("start"), "Drive it from the start ({ed_test}).")
	test_button.theme_type_variation = "EdAccent"
	test_button.add_theme_font_override("font", UiKit.font(true))
	test_button.focus_mode = Control.FOCUS_NONE
	h.add_child(test_button)
	test_more = EditorKit.button("", _open_test_options, "Test drive options")
	test_more.theme_type_variation = "EdAccent"
	test_more.icon = theme.get_icon("arrow", "OptionButton") if theme != null else null
	test_more.add_theme_color_override("icon_normal_color", Color.BLACK)
	test_more.custom_minimum_size.x = 30
	test_more.focus_mode = Control.FOCUS_NONE
	h.add_child(test_more)
	help_button = EditorKit.button("HELP", open_help, "{ed_help} keys and mouse")
	help_button.theme_type_variation = "EdFlat"
	help_button.add_theme_font_override("font", UiKit.font(true))
	help_button.focus_mode = Control.FOCUS_NONE
	h.add_child(help_button)
	return h


func _menu(title: String, items: Array) -> MenuButton:
	var mb := MenuButton.new()
	mb.text = title
	mb.focus_mode = Control.FOCUS_NONE
	mb.switch_on_hover = true
	if mb.has_method("set_disable_shortcuts"):
		mb.call("set_disable_shortcuts", true)
	var pm := mb.get_popup()
	for it in items:
		var id: int = it[0]
		if id < 0:
			pm.add_separator()
			continue
		if it.size() > 2 and it[2]:
			pm.add_check_item(it[1], id)
		else:
			pm.add_item(it[1], id)
		var act := str(ACTION_OF.get(id, ""))
		if act != "" and InputMap.has_action(act):
			for ev in InputMap.action_get_events(act):
				if ev is InputEventKey:
					var k := ev as InputEventKey
					var code := k.get_keycode_with_modifiers() if k.keycode != KEY_NONE else k.get_physical_keycode_with_modifiers()
					pm.set_item_accelerator(pm.get_item_index(id), code)
					break
	pm.id_pressed.connect(menu_pressed)
	pm.about_to_popup.connect(_menus_state)
	return mb


## The menus' items as they stand now (undo names, check marks).
func _menus_state() -> void:
	if editor == null:
		return
	var pm := edit_menu.get_popup()
	var h := editor.history
	pm.set_item_text(pm.get_item_index(E_UNDO), "UNDO " + h.undo_name() if h != null and h.can_undo() else "UNDO")
	pm.set_item_text(pm.get_item_index(E_REDO), "REDO " + h.redo_name() if h != null and h.can_redo() else "REDO")
	pm.set_item_disabled(pm.get_item_index(E_UNDO), h == null or not h.can_undo())
	pm.set_item_disabled(pm.get_item_index(E_REDO), h == null or not h.can_redo())
	var vm := view_menu.get_popup()
	vm.set_item_checked(vm.get_item_index(V_TOP), editor.camera != null and editor.camera.top)
	vm.set_item_checked(vm.get_item_index(V_LINE), editor.show_line)
	for p in [[V_ZONES, "zones"], [V_PINS, "pins"], [V_GRID, "grid"], [V_LABELS, "labels"], [V_MUSIC, "music"]]:
		vm.set_item_checked(vm.get_item_index(p[0]), bool(view_flags[p[1]]))
	var fm := file_menu.get_popup()
	fm.set_item_disabled(fm.get_item_index(F_DUPLICATE), editor.session == null or editor.session.path == "")


func menu_pressed(id: int) -> void:
	if editor == null:
		return
	var act := str(ACTION_OF.get(id, ""))
	if act != "" and id != F_SAVE_AS:
		run_action(act)
		return
	match id:
		F_NEW, F_OPEN, F_EXIT_HOME:
			request_exit("home")
		F_EXIT_MENU:
			request_exit("menu")
		F_SAVE_AS:
			save_as()
		F_DUPLICATE:
			_duplicate()
		F_PROPS:
			_open_properties()
		F_OLDER:
			_open_older()
		F_THUMB:
			set_thumbnail()
		F_HOST:
			host_online()
		F_FOLDER:
			OS.shell_open(ProjectSettings.globalize_path(CustomTracks.mine_dir()))
		E_DESELECT:
			if editor.selection != null:
				editor.selection.clear()
		E_REVERSE:
			if editor.doc != null:
				editor.commit("REVERSE TRACK DIRECTION", editor.doc.reverse_ops())
		V_ZONES, V_PINS, V_GRID, V_LABELS, V_MUSIC:
			var k: String = {V_ZONES: "zones", V_PINS: "pins", V_GRID: "grid", V_LABELS: "labels", V_MUSIC: "music"}[id]
			view_flags[k] = not bool(view_flags[k])
			if k == "pins" and editor.markers != null:
				editor.markers.set_issues(report if view_flags.pins and report != null else LevelReport.new())
			elif k == "music":
				if view_flags.music:
					Game.play_music_mode(str(Game.settings.get("menu_music", "random")))
				else:
					Game.stop_music()
			editor.redraw()
			editor.refresh_markers()
		V_SPEED:
			_open_speed()


func _build_palette() -> VBoxContainer:
	palette = VBoxContainer.new()
	palette.name = "Palette"
	palette.add_theme_constant_override("separation", 3)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for id in TrackEditor.TOOL_IDS:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 2)
		var b := Button.new()
		b.text = TOOL_NAMES.get(id, id.to_upper())
		b.theme_type_variation = "EdToggle"
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = EditorKit.ROW_H
		b.focus_mode = Control.FOCUS_NONE
		b.icon = EditorKit.keycap(InputPrompts.action_text("ed_tool_" + id, "keyboard"))
		b.add_theme_constant_override("h_separation", 10)
		var tid: String = id
		b.pressed.connect(func() -> void:
			if editor != null:
				editor.set_tool(tid))
		h.add_child(b)
		var q := Button.new()
		q.text = "?"
		q.theme_type_variation = "EdFlat"
		q.focus_mode = Control.FOCUS_NONE
		q.custom_minimum_size = Vector2(26, EditorKit.ROW_H)
		q.tooltip_text = "Show this tool's hint again"
		q.pressed.connect(func() -> void:
			if editor != null:
				HintCard.recall(editor, tid))
		h.add_child(q)
		tool_buttons[id] = b
		palette.add_child(h)
	return palette


## The tooltips name the tools' purpose (the tool's own text when it has one).
func _tool_tips() -> void:
	for id in tool_buttons:
		var t: EditorTool = editor.tools.get(id) if editor != null else null
		var tip := str(TOOL_TIPS.get(id, ""))
		if t != null and t.purpose != "":
			tip = t.purpose
		(tool_buttons[id] as Button).tooltip_text = "%s (%s)\n%s" % [TOOL_NAMES.get(id, id), InputPrompts.action_text("ed_tool_" + id, "keyboard"), tip]


func _build_status() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	pos_label = _status_label(190)
	road_label = _status_label(200)
	sel_label = _status_label(96)
	snap_label = _status_label(84)
	bake_label = _status_label(108)
	for l in [pos_label, road_label, sel_label, snap_label, bake_label]:
		h.add_child(l)
	message = PromptLabel.new("", EditorKit.FONT_SMALL, UiKit.ORANGE)
	message.add_theme_font_override("normal_font", UiKit.font(true))
	message.fit_content = false
	message.custom_minimum_size = Vector2(0, 20)
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message.size_flags_stretch_ratio = 0.6
	message.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	message.clip_contents = true
	h.add_child(message)
	hints_holder = Control.new()
	hints_holder.name = "Hints"
	hints_holder.clip_contents = true
	hints_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hints_holder.custom_minimum_size = Vector2(0, 20)
	hints_holder.resized.connect(refresh_status)
	h.add_child(hints_holder)
	hints_bar = PromptBar.new([], EditorKit.FONT_SMALL, UiKit.TEXT)
	hints_bar.add_theme_constant_override("separation", 18)
	hints_holder.add_child(hints_bar)
	return h


func _status_label(w: float) -> Label:
	var l := UiKit.label("", EditorKit.FONT_SMALL, UiKit.TEXT_DIM)
	l.custom_minimum_size.x = w
	l.clip_text = true
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---------------------------------------------------------------- per frame

func _process(_delta: float) -> void:
	if editor == null:
		return
	if _status_dirty:
		_update_status()
	if _after_save.is_valid() and editor.bake_state != "SAVING..." and (editor.session == null or not editor.session.saving):
		var go := _after_save
		_after_save = Callable()
		if editor.session != null and not editor.session.dirty():
			go.call()
	# the tool options take what they need, at most 45 % of the column
	if options_scroll.visible:
		var want := options_box.get_combined_minimum_size().y
		var cap := maxf(right.size.y * 0.45, 80.0)
		var h := minf(want, cap)
		if absf(options_scroll.custom_minimum_size.y - h) > 0.5:
			options_scroll.custom_minimum_size.y = h


## The status bar, the name, the empty state and the hints now.
func _update_status() -> void:
	_status_dirty = false
	var hv := editor.hover
	if hv != null and hv.hit:
		pos_label.text = "x %.1f z %.1f y %.1f" % [hv.pos.x, hv.pos.z, hv.pos.y]
	else:
		pos_label.text = ""
	road_label.text = _road_text(hv)
	var n := editor.selection.uids.size() if editor.selection != null else 0
	sel_label.text = "" if n == 0 else "%d selected" % n
	snap_label.text = ("GRID %s m" % str(editor.snap.get("grid", 1.0))).replace(".0 m", " m") if bool(editor.snap.get("on", true)) else "GRID OFF"
	bake_label.text = editor.bake_state
	bake_label.add_theme_color_override("font_color", EditorKit.ERROR_COLOR if editor.bake_state.ends_with("FAILED") else UiKit.TEXT_DIM)
	var msg := editor.status_text
	if msg == "" and editor.tool != null:
		msg = editor.tool.status_step()
	var pm := EditorKit.prompt(msg)
	if message.prompt != pm:
		message.prompt = pm
	_sync_snap()
	# the name, "*" when unsaved
	var nm := _track_name()
	var dirty := editor.session != null and editor.session.dirty()
	name_button.text = nm + (" *" if dirty else "")
	name_button.tooltip_text = "%s%s\nClick: TRACK PROPERTIES" % [nm, " (unsaved)" if dirty else ""]
	# the empty state
	var pts = editor.doc.data.get("road", {}).get("points", []) if editor.doc != null and editor.doc.data.get("road") is Dictionary else []
	empty_hint.visible = (pts as Array).is_empty() and not card_panel.visible
	_update_hints(hv)


func _road_text(hv: EditorHit) -> String:
	if hv == null or not hv.hit:
		return ""
	if hv.road > 0 and editor.doc != null:
		var f := editor.doc.find(hv.road)
		var bn := str(f.get("item", {}).get("name", "BRANCH")) if f.get("item") is Dictionary else "BRANCH"
		return "BRANCH %s u %d m" % [bn.to_upper(), int(hv.s)]
	if hv.road == -1 or (hv.road == -2 and editor.road(-1) != null and editor.road(-1).n > 0):
		return "ROAD s %d m lat %.1f" % [int(hv.s), hv.lat]
	return ""


## What the mouse does on what is under the cursor (tool.hints), cut to the bar's width.
func _update_hints(hv: EditorHit) -> void:
	var entries: Array = editor.tool.hints(hv if hv != null else EditorHit.new()) if editor.tool != null else []
	var list := []
	for e in entries:
		var p := str(e[0]) if e is Array and not (e as Array).is_empty() else str(e)
		var when := str(e[1]) if e is Array and (e as Array).size() > 1 else ""
		list.append([EditorKit.prompt(p), when])
	var key := str(list) + str(int(hints_holder.size.x))
	if key == _hint_key:
		return
	_hint_key = key
	hints_bar.set_entries(list)
	hints_bar.position = Vector2(0, maxf((hints_holder.size.y - hints_bar.get_combined_minimum_size().y) * 0.5, 0.0))
	hints_bar.size = hints_bar.get_combined_minimum_size()
	var room := hints_holder.size.x
	while list.size() > 0 and hints_bar.get_combined_minimum_size().x > room and room > 0.0:
		list.pop_back()
		hints_bar.set_entries(list)
		hints_bar.size = hints_bar.get_combined_minimum_size()


func _on_focus_changed(c: Control) -> void:
	# the panels never keep the focus (no panel walking); text fields keep it while typed in
	if c == null or not is_ancestor_of(c) or c is LineEdit or c is TextEdit:
		return
	c.release_focus.call_deferred()


func _on_history() -> void:
	refresh_status()


# ---------------------------------------------------------------- the snap group

func _set_snap(k: String, v: Variant) -> void:
	if editor == null:
		return
	editor.snap[k] = v
	var s = Game.settings.get("editor_snap")
	if not (s is Dictionary):
		s = {}
	s = (s as Dictionary).duplicate()
	s[k] = v
	Game.settings["editor_snap"] = s
	refresh_status()


## The toggles and dropdowns follow editor.snap (G changes it from the keyboard).
func _sync_snap() -> void:
	if editor == null or grid_toggle == null:
		return
	grid_toggle.set_pressed_no_signal(bool(editor.snap.get("on", true)))
	angle_toggle.set_pressed_no_signal(bool(editor.snap.get("angle_on", true)))
	surface_toggle.set_pressed_no_signal(bool(editor.snap.get("surface", true)))
	var gi := GRID_SIZES.find(float(editor.snap.get("grid", 1.0)))
	if gi >= 0 and grid_size.selected != gi:
		grid_size.select(gi)
	var ai := ANGLE_STEPS.find(float(editor.snap.get("angle", 15.0)))
	if ai >= 0 and angle_step.selected != ai:
		angle_step.select(ai)


func _toggle_options() -> void:
	options_open = not options_open
	refresh_tool()


# ---------------------------------------------------------------- test drive

func _drive(from: String) -> void:
	if editor == null:
		return
	if from == "here":
		editor.test_drive("here", editor.free_center())
	else:
		editor.test_drive(from)


## The TEST DRIVE arrow: FROM THE START / FROM HERE / WATCH A BOT LAP, then BOTS, LAPS, HAZARDS,
## DIFFICULTY (settings.editor_test).
func _open_test_options() -> void:
	if _test_pop != null and is_instance_valid(_test_pop):
		_test_pop.queue_free()
	var pop := PopupPanel.new()
	_test_pop = pop
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size.x = 320
	pop.add_child(v)
	for e in [["FROM THE START", "start", "ed_test"], ["FROM HERE", "here", "ed_test_here"], ["WATCH A BOT LAP", "watch", "ed_test_watch"]]:
		var from: String = e[1]
		var b := EditorKit.button("%s   %s" % [e[0], EditorKit.plain("{%s}" % e[2])], func() -> void:
			pop.hide()
			_drive(from))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(b)
	v.add_child(HSeparator.new())
	var st := EditorSession.test_options({})
	v.add_child(EditorKit.row("BOTS", EditorKit.slider(0, 7, 1, st.bots, func(x: float) -> void: _test_set("bots", int(x)))))
	v.add_child(EditorKit.row("LAPS", EditorKit.slider(1, 9, 1, st.laps, func(x: float) -> void: _test_set("laps", int(x)))))
	v.add_child(EditorKit.row("HAZARDS", EditorKit.check(int(st.hazards) == 1, func(on: bool) -> void: _test_set("hazards", 1 if on else 0))))
	v.add_child(EditorKit.row("DIFFICULTY", EditorKit.modes(DIFFS, int(st.difficulty), func(i: int) -> void: _test_set("difficulty", i))))
	add_child(pop)
	pop.popup_hide.connect(pop.queue_free)
	var at := test_more.get_screen_position() + Vector2(test_more.size.x - 340.0, test_more.size.y + 4.0)
	pop.popup(Rect2i(Vector2i(at), Vector2i(340, 10)))


static func _test_set(k: String, v: int) -> void:
	var s = Game.settings.get("editor_test")
	s = (s as Dictionary).duplicate() if s is Dictionary else {}
	s[k] = v
	Game.settings["editor_test"] = s


# ---------------------------------------------------------------- FILE

func _track_name() -> String:
	if editor == null or editor.doc == null:
		return ""
	return str(editor.doc.data.get("name", "MY TRACK"))


## SAVE AS: a new name, then a new file (TrackEditor.save(true)).
func save_as() -> void:
	var d := MessageBox.new("SAVE AS", "Save a copy of the track under a new name:", true, false, "SAVE", "CANCEL")
	d.field.text = _track_name()
	d.field.max_length = 48
	d.answered.connect(func(ok: bool, t: String) -> void:
		if not ok:
			return
		_rename(t)
		editor.save(true))
	editor.open_dialog(d)


## HOST ONLINE WITH THIS TRACK: "Host <name> online?" with the name to change, then
## TrackEditor.host_online (it refuses while the track has errors).
func host_online() -> void:
	var d := MessageBox.new("HOST ONLINE", "Host %s online? Your friends download it in the lobby." % _track_name(), true, false, "HOST", "CANCEL")
	d.field.text = _track_name()
	d.field.max_length = 48
	d.answered.connect(func(ok: bool, t: String) -> void:
		if not ok:
			return
		_rename(t)
		editor.host_online())
	editor.open_dialog(d)


## A new name (one undo step); a saved track's file is renamed too.
func _rename(t: String) -> void:
	var nm := LevelDoc.clean_text(t, 48)
	if nm == "" or nm == _track_name():
		return
	editor.commit("RENAME", [LevelDoc.op_set(["name"], nm), LevelDoc.op_set(["short"], nm.to_upper().left(16))])
	var s := editor.session
	if s != null and s.path != "" and LevelIO.slug(nm) + LevelIO.EXT != s.path.get_file():
		var np := EditorSession.rename_track(s.path, nm)
		if np != "":
			s.path = np


func _duplicate() -> void:
	var s := editor.session
	if s == null or s.path == "":
		toast("Save the track first.")
		return
	var p := s.path
	confirm_leave(func() -> void:
		var why := s.open_copy(p, false)
		if why != "":
			toast("It could not be copied (%s)." % why)
			return
		_reopen())


## The editor again on the session's (new) document.
func _reopen() -> void:
	if editor != null and editor.is_inside_tree():
		editor.get_tree().change_scene_to_file.call_deferred("res://scenes/editor.tscn")


## SET THUMBNAIL FROM CAMERA: the camera's view as the track's picture (kept by the next save).
func set_thumbnail() -> void:
	if editor == null or editor.camera == null:
		return
	if editor.headless:
		toast("There is no picture without a window.")
		return
	var sv := SubViewport.new()
	sv.size = LevelIO.THUMB_SIZE
	sv.world_3d = editor.get_world_3d()
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cam := Camera3D.new()
	cam.fov = editor.camera.fov
	cam.far = editor.camera.far
	sv.add_child(cam)
	editor.add_child(sv)
	cam.global_transform = editor.camera.global_transform
	cam.current = true
	var shown := [editor.draw.visible, editor.gizmo.visible]
	editor.draw.visible = false
	editor.gizmo.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	editor.draw.visible = shown[0]
	editor.gizmo.visible = shown[1]
	sv.queue_free()
	if img == null or img.is_empty():
		toast("The picture could not be taken.")
		return
	editor.doc.thumb = img.save_png_to_buffer()
	editor.doc.thumb_custom = true
	editor.doc.notify(PackedStringArray(["thumb"]))
	toast("Thumbnail set: SAVE keeps it.")


func _open_properties() -> void:
	if editor != null:
		editor.open_dialog(PropertiesDialog.new(self))


func _open_older() -> void:
	if editor != null:
		editor.open_dialog(OlderDialog.new(self))


func _open_speed() -> void:
	var pop := PopupPanel.new()
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = 300
	pop.add_child(v)
	v.add_child(EditorKit.section("CAMERA SPEED"))
	var sp := editor.camera.speed if editor.camera != null else 30.0
	v.add_child(EditorKit.slider(2, 400, 1, sp, func(x: float) -> void:
		if editor.camera != null:
			if editor.camera.has_method("set_speed"):
				editor.camera.call("set_speed", x)
			else:
				editor.camera.speed = x, "%d m/s"))
	add_child(pop)
	pop.popup_hide.connect(pop.queue_free)
	pop.popup(Rect2i(Vector2i(view_menu.get_screen_position() + Vector2(0, view_menu.size.y + 4)), Vector2i(300, 10)))


# ---------------------------------------------------------------- inner classes

## The COMPLEXITY meter: a thin bar, its colour by value (yellow past 0.8, red past 1.0).
class ComplexityBar:
	extends Control
	var value := 0.0
	var color := EditorKit.OK_COLOR

	func _init() -> void:
		custom_minimum_size = Vector2(EditorUI.BAR_W, 10)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiKit.TRACK)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(value, 0.0, 1.0), size.y)), color)
		draw_rect(Rect2(Vector2(size.x * 0.8, 0), Vector2(1, size.y)), Color(1, 1, 1, 0.35))
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.2), false, 1.0)


## "Save changes to <name>?" SAVE / DISCARD / CANCEL; answered("save" | "discard" | "cancel").
class SaveChanges:
	extends Dialog
	signal answered(choice: String)
	var _done := false

	func _init(track_name: String) -> void:
		super("UNSAVED CHANGES", Vector2(640, 250))
		var l := UiKit.label("Save changes to %s?" % track_name, 18, UiKit.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 580
		body.add_child(l)
		add_button("CANCEL", func() -> void: _answer("cancel"))
		add_button("DISCARD", func() -> void: _answer("discard"))
		default_focus = add_button("SAVE", func() -> void: _answer("save"))

	func _ready() -> void:
		default_focus.grab_focus.call_deferred()

	func _answer(c: String) -> void:
		if _done:
			return
		_done = true
		answered.emit(c)
		close()

	func close() -> void:
		if not _done:
			_done = true
			answered.emit("cancel")
		super()


## TRACK PROPERTIES: name, short name, description, the author (read-only), the remix credit and
## AUTO DRESS; OK commits the changes as one undo step.
class PropertiesDialog:
	extends Dialog
	var ui: EditorUI
	var name_f: LineEdit
	var short_f: LineEdit
	var desc_f: LineEdit

	func _init(owner_ui: EditorUI) -> void:
		super("TRACK PROPERTIES", Vector2(760, 520))
		ui = owner_ui
		var d: Dictionary = ui.editor.doc.data
		name_f = UiKit.text_field(str(d.get("name", "")), "Track name", func(_t: String) -> void: pass, 420)
		name_f.max_length = 48
		body.add_child(UiKit.row("NAME", name_f, 200))
		short_f = UiKit.text_field(str(d.get("short", "")), "Short name (lists, the HUD)", func(_t: String) -> void: pass, 420)
		short_f.max_length = 16
		body.add_child(UiKit.row("SHORT NAME", short_f, 200))
		desc_f = UiKit.text_field(str(d.get("desc", "")), "A line about it", func(_t: String) -> void: pass, 420)
		desc_f.max_length = 200
		body.add_child(UiKit.row("DESCRIPTION", desc_f, 200))
		var author := str(d.get("author", ""))
		body.add_child(UiKit.row("AUTHOR", UiKit.label(author if author != "" else "you", 18, UiKit.TEXT_DIM), 200))
		var rm = d.get("remix_of")
		if rm is Dictionary:
			body.add_child(UiKit.row("REMIX OF", UiKit.label("%s by %s" % [str(rm.get("name", "?")), str(rm.get("author", "?"))], 18, UiKit.TEXT_DIM), 200))
		var dress := UiKit.button("AUTO DRESS...", 220)
		dress.pressed.connect(func() -> void:
			var e := ui.editor
			close()
			e.open_dialog(AutoDressDialog.new(e)))
		body.add_child(dress)
		add_button("CANCEL", close)
		default_focus = add_button("OK", _ok)

	func _ready() -> void:
		name_f.grab_focus.call_deferred()

	func _ok() -> void:
		var e := ui.editor
		var d: Dictionary = e.doc.data
		var nm := name_f.text.strip_edges()
		var ops := []
		if short_f.text.strip_edges() != str(d.get("short", "")) and short_f.text.strip_edges() != "":
			ops.append(LevelDoc.op_set(["short"], short_f.text.strip_edges().left(16)))
		if desc_f.text.strip_edges() != str(d.get("desc", "")):
			ops.append(LevelDoc.op_set(["desc"], desc_f.text.strip_edges().left(200)))
		if not ops.is_empty():
			e.commit("TRACK PROPERTIES", ops)
		if nm != "" and nm != str(d.get("name", "")):
			ui._rename(nm)
		close()


## OLDER VERSIONS: the last five saves; one opens as an unsaved copy.
class OlderDialog:
	extends Dialog
	var ui: EditorUI

	func _init(owner_ui: EditorUI) -> void:
		super("OLDER VERSIONS", Vector2(640, 460))
		ui = owner_ui
		var guid := str(ui.editor.doc.data.get("guid", ""))
		var list := CustomTracks.history(guid)
		if list.is_empty():
			var l := UiKit.label("No older versions yet: each SAVE keeps the one before it (the last five).", 18, UiKit.TEXT_DIM)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 580
			body.add_child(l)
		var first: Button = null
		for it in list:
			var when := Time.get_datetime_string_from_unix_time(int(it.modified), true)
			var p := str(it.path)
			var b := UiKit.button("%s   OPEN AS A COPY" % when, 560)
			b.pressed.connect(func() -> void: _open(p))
			body.add_child(b)
			if first == null:
				first = b
		default_focus = first if first != null else add_button("CLOSE", close)
		if first != null:
			add_button("CLOSE", close)

	func _open(p: String) -> void:
		var e := ui.editor
		close()
		ui.confirm_leave(func() -> void:
			var why := e.session.open_copy(p, false)
			if why != "":
				ui.toast("That version could not be opened (%s)." % why)
				return
			ui._reopen())
