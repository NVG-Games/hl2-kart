class_name HelpOverlay
extends Control
## The help overlay (1.11; F1, the pad's Back, EDITOR MENU > HELP): full screen over a 0.94 dim,
## KEYBOARD & MOUSE on the left (forced key style) and CONTROLLER on the right (the pad's style),
## each column a grid of rows "icon(s) + words" (the words of a column share one left edge) drawn
## through EditorKit.prompt (combos expand into their
## modifier keycaps + "+" + the key; mouse buttons are words), sections CAMERA, SELECT & MOVE,
## EDIT, ROAD & BRANCHES, TERRAIN & PAINT, OBJECTS, TEST DRIVE. Any key, a click, B or Back closes
## it (Start closes it and opens the EDITOR MENU); SHOW HINTS AGAIN brings every tool's card back.
## It ends with "Pipes and caves are not part of the editor." It sits in "editor_modal" while
## shown, so the pad stops flying the camera. P16.

const DIM := 0.94
const FONT := 14
const ICON_PX := 20.0
const PROMPT_W := 200.0
const WORDS_W := 290.0
const GROUP := "editor_modal"
const LAST_LINE := "Pipes and caves are not part of the editor."
## [section, [[prompt, words], ...]] of the keyboard and mouse (two columns of sections).
const KEYS := [
	[["CAMERA", [
		["RIGHT MOUSE + {ed_forward}{ed_left}{ed_back}{ed_right}", "FLY (HOLD THE BUTTON)"],
		["RIGHT MOUSE + {ed_down} {ed_up}", "DOWN / UP"],
		["RIGHT MOUSE + WHEEL", "FLYING SPEED"],
		["{ed_pan}", "PAN (HOLD)"],
		["{ed_orbit} + LEFT MOUSE", "ORBIT"],
		["WHEEL", "ZOOM TO THE CURSOR"],
		["{ed_top}", "TOP VIEW"],
		["{ed_focus} / {ed_frame_all}", "FRAME THE SELECTION / THE TRACK"],
		["{ed_home}", "GO TO THE START"]]],
	["SELECT & MOVE", [
		["{ed_tool_select} ... {ed_tool_world}", "THE TEN TOOLS"],
		["LEFT MOUSE", "SELECT, PLACE, PAINT"],
		["{ed_mod_shift} + LEFT MOUSE", "ADD TO THE SELECTION"],
		["{ed_mod_ctrl} + LEFT MOUSE", "TOGGLE IN THE SELECTION"],
		["{ed_move} {ed_rotate} {ed_scale}", "GIZMO: MOVE / ROTATE / SCALE"],
		["{ed_space}", "WORLD / LOCAL AXES"],
		["{ed_grid}", "GRID SNAP ON / OFF"],
		["{ed_raise} {ed_lower}", "RAISE / LOWER BY THE GRID"],
		["{ed_drop} / {ed_drop_align}", "DROP TO THE SURFACE / AND ALIGN"],
		["{ed_hide} / {ed_unhide}", "HIDE / SHOW ALL"]]],
	["EDIT", [
		["{ed_undo} / {ed_redo}", "UNDO / REDO"],
		["{ed_copy} {ed_cut} {ed_paste}", "COPY / CUT / PASTE AT THE CURSOR"],
		["{ed_paste_here}", "PASTE IN PLACE"],
		["{ed_duplicate}", "DUPLICATE"],
		["{ed_delete}", "DELETE"],
		["{ed_select_all}", "SELECT ALL OF THE TOOL'S KIND"],
		["{ed_save} / {ed_save_as}", "SAVE / SAVE AS"],
		["{ed_validation}", "PROBLEMS (VALIDATION)"],
		["{ed_cancel}", "CANCEL, DESELECT, EDITOR MENU"]]]],
	[["ROAD & BRANCHES", [
		["LEFT MOUSE", "EXTEND THE ROAD / SELECT A POINT"],
		["{ed_mod_shift} + DRAG", "A POINT'S HEIGHT"],
		["{ed_draw} + DRAG", "DRAW A ROAD FREEHAND"],
		["{ed_close_loop}", "CLOSE / OPEN THE LOOP"],
		["{ed_jump}", "A JUMP ON THE SEGMENT"],
		["{ed_finish}", "BRANCH: FINISH IT"],
		["{ed_line}", "THE RACING LINE"]]],
	["TERRAIN & PAINT", [
		["DRAG", "SCULPT / PAINT"],
		["{ed_mod_ctrl} + DRAG", "LOWER (RAISE) / ERASE"],
		["{ed_mod_shift} + DRAG", "SMOOTH"],
		["{ed_mod_alt} + CLICK", "PICK THE HEIGHT / THE LAYER"],
		["{ed_brush_smaller} {ed_brush_bigger}", "BRUSH SIZE"],
		["{ed_strength_down} {ed_strength_up}", "BRUSH STRENGTH"]]],
	["OBJECTS", [
		["{ed_scatter}", "STAMP / SCATTER"],
		["{ed_mod_shift} + WHEEL", "TURN THE GHOST"],
		["{ed_mod_ctrl} + WHEEL", "SIZE THE GHOST"],
		["{ed_turn_left} {ed_turn_right}", "TURN"]]],
	["TEST DRIVE", [
		["{ed_test}", "FROM THE START"],
		["{ed_test_here}", "FROM UNDER THE CURSOR"],
		["{ed_test_watch}", "WATCH A BOT LAP"],
		["{ed_fast_forward}", "FAST FORWARD (WATCHING, HOLD)"],
		["{ed_help}", "THIS HELP"]]]],
]
## The controller's sections.
const PAD := [
	["CAMERA", [
		["{ed_pad_move_x}", "FLY"],
		["{ed_pad_look_x}", "LOOK"],
		["{ed_pad_down} {ed_pad_up}", "DOWN / UP"],
		["{ed_pad_fast}", "FAST"],
		["{ed_pad_faster} {ed_pad_slower}", "FLYING SPEED"]]],
	["SELECT & MOVE", [
		["{ed_pad_prev_tool} {ed_pad_next_tool}", "THE TOOL BEFORE / AFTER"]]],
	["TEST DRIVE", [
		["{ed_pad_test_here}", "FROM THE MIDDLE OF THE VIEW"],
		["{ed_pad_test}", "FROM THE START"],
		["{ed_pad_watch}", "WATCH A BOT LAP"],
		["{ed_fast_forward}", "FAST FORWARD (WATCHING, HOLD)"]]],
	["EDIT", [
		["{ed_pad_menu}", "EDITOR MENU: TOOLS, UNDO, SAVE, VIEW"],
		["{ed_pad_help}", "THIS HELP"],
		["{ui_cancel}", "BACK / CLOSE"]]],
]
const PAD_NOTE := "The mouse and keyboard build the track; the controller flies the camera, test-drives and works the menus."

var editor: TrackEditor
## The prompt rows built (tests): [{side: "keys" | "pad", section, prompt, words}].
var rows: Array = []
var hints_button: Button
var _born := -1


func _init(ed: TrackEditor) -> void:
	editor = ed
	name = "HelpOverlay"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_NONE
	_build()


func _enter_tree() -> void:
	if not is_in_group(GROUP):
		add_to_group(GROUP)
	_born = Engine.get_process_frames()


func _exit_tree() -> void:
	if is_in_group(GROUP):
		remove_from_group(GROUP)


func close() -> void:
	if is_queued_for_deletion():
		return
	if is_in_group(GROUP):
		remove_from_group(GROUP)
	visible = false
	queue_free()


## Any key (a modifier alone is not one), B or Back closes it; Start closes it and the camera
## opens the EDITOR MENU. The press that opened it (this frame) is let be.
func _input(ev: InputEvent) -> void:
	if not visible or Engine.get_process_frames() == _born:
		return
	if ev is InputEventKey:
		var k := ev as InputEventKey
		if not k.pressed or k.echo or k.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
			return
		get_viewport().set_input_as_handled()
		close()
	elif ev is InputEventJoypadButton and ev.is_pressed():
		get_viewport().set_input_as_handled()
		if ev.is_action_pressed("ed_pad_menu"):
			close()
			var cam = editor.camera if editor != null else null
			if cam != null and cam.has_method("_pad_button"):
				cam.call("_pad_button", ev)
			elif editor != null and editor.ui != null:
				editor.ui.open_menu()
		elif ev.is_action_pressed("ui_cancel") or ev.is_action_pressed("ed_pad_help") or ev.is_action_pressed("ed_pad_menu"):
			close()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and (ev as InputEventMouseButton).button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		accept_event()
		close()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, DIM)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 40)
	m.add_theme_constant_override("margin_top", 28)
	m.add_theme_constant_override("margin_bottom", 24)
	add_child(m)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	var title := UiKit.label("HELP", 24, UiKit.ORANGE, true)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(scroll)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 36)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(cols)
	# KEYBOARD & MOUSE: two columns of sections under one heading
	var kb := VBoxContainer.new()
	kb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kb.add_child(_heading("KEYBOARD & MOUSE"))
	var kcols := HBoxContainer.new()
	kcols.add_theme_constant_override("separation", 28)
	kcols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kb.add_child(kcols)
	for col in KEYS:
		var c := _grid()
		for sec in col:
			_section(c, "keys", sec, InputPrompts.KEYBOARD)
		kcols.add_child(c)
	cols.add_child(kb)
	var pad := VBoxContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("separation", 2)
	pad.add_child(_heading("CONTROLLER"))
	var pst := InputPrompts.pad_style()
	var pg := _grid()
	for sec in PAD:
		_section(pg, "pad", sec, pst)
	pad.add_child(pg)
	var note := UiKit.label(PAD_NOTE, FONT, UiKit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = PROMPT_W + WORDS_W - 60.0
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(note)
	cols.add_child(pad)
	# the foot: the last line, SHOW HINTS AGAIN, how to close
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 24)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var last := UiKit.label(LAST_LINE, FONT + 1, UiKit.TEXT)
	last.mouse_filter = Control.MOUSE_FILTER_IGNORE
	last.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	last.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(last)
	hints_button = EditorKit.button("SHOW HINTS AGAIN", func() -> void:
		HintCard.reset(editor)
		close(), "Every tool shows its hint card again the next time it is picked.")
	hints_button.focus_mode = Control.FOCUS_NONE
	foot.add_child(hints_button)
	var how := PromptLabel.new("ANY KEY OR {ui_cancel} CLOSES", FONT, UiKit.TEXT_DIM)
	how.style = InputPrompts.pad_style()
	how.icon_px = ICON_PX
	foot.add_child(how)
	v.add_child(foot)


func _heading(text: String) -> Label:
	var l := UiKit.label(text, 18, UiKit.ORANGE, true)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A column of sections: [keys | words], the key column as wide as its widest prompt.
func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 2)
	return g


func _section(grid: GridContainer, side: String, sec: Array, style_id: String) -> void:
	var h := UiKit.label(str(sec[0]), FONT, Color.WHITE, true)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.custom_minimum_size.y = 26
	h.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	grid.add_child(h)
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(gap)
	for r in sec[1]:
		var p := PromptLabel.new(EditorKit.prompt(str(r[0])), FONT, UiKit.TEXT)
		p.add_theme_font_override("normal_font", UiKit.font(true))
		p.style = style_id
		p.icon_px = ICON_PX
		p.autowrap_mode = TextServer.AUTOWRAP_OFF
		p.fit_content = true
		p.custom_minimum_size.x = PROMPT_W * 0.5
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(p)
		var w := UiKit.label(str(r[1]), FONT, UiKit.TEXT_DIM)
		w.mouse_filter = Control.MOUSE_FILTER_IGNORE
		w.custom_minimum_size.x = WORDS_W if side == "pad" else WORDS_W - 70.0
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(w)
		rows.append({"side": side, "section": str(sec[0]), "prompt": p.prompt, "words": str(r[1])})
