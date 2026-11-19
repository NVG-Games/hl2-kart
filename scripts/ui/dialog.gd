class_name Dialog
extends Control
## Modal window in the HL2 GameUI manner: dimmed screen, dark frame, title, content area and a
## button row with the button hints on its left (PromptBar). B / Esc closes it (in a text field
## being typed in it only stops the typing), LB / RB (Page Up / Page Down) switch its tabs, the
## focus stays inside it while it is the topmost dialog, and goes back where it was when it closes.

signal closed

var frame: PanelContainer
var body: VBoxContainer
var buttons: HBoxContainer
var title_label: Label
## A tab bar the dialog made (Options, How to Play, Find servers): LB / RB switch it, with their
## icons beside it while a pad is in use.
var tabs: TabBar
## The button hints at the left of the button row ("[A] SELECT  [B] BACK"; tabs add "TABS").
var prompt_bar: PromptBar
## Where the focus goes when nothing in the dialog has it (focus_default); null: the tab bar or
## the last button.
var default_focus: Control
## B / Esc in a text field being typed in only stops the typing (a MessageBox: it answers no).
var cancel_stops_typing := true
var _prompts: Array = [["{ui_accept} SELECT"], ["{ui_cancel} BACK"]]  # set_prompts
var _return_focus: Control  # what had the focus before the dialog opened
var _inside: Control  # the last control in the dialog that had the focus
var _tab_glyphs: Array[Control] = []
var _closing := false
var _dir := Vector2.ZERO  # the direction last pressed (D-pad, stick, arrows): the focus trap's way
var _dir_t := 0  # ...and when (msec)

const NAV_DIRS: Array[StringName] = [&"ui_left", &"ui_right", &"ui_up", &"ui_down"]
const NAV_VECS: Array[Vector2] = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]


func _init(title: String, size_px: Vector2) -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(InputPrompts.SCREEN_GROUP)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	frame = PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.offset_left = -size_px.x * 0.5
	frame.offset_right = size_px.x * 0.5
	frame.offset_top = -size_px.y * 0.5
	frame.offset_bottom = size_px.y * 0.5
	add_child(frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	frame.add_child(v)
	title_label = UiKit.label(title, 28, Color.WHITE, true)
	v.add_child(title_label)
	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	v.add_child(body)
	buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	v.add_child(buttons)
	prompt_bar = PromptBar.new(_prompts)
	prompt_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buttons.add_child(prompt_bar)


## The hints at the foot ([[prompt], [prompt, "pad" / "key"], ...], PromptBar); a dialog with
## tabs gets "[LB][RB] TABS" after them.
func set_prompts(entries: Array) -> void:
	_prompts = entries
	prompt_bar.set_entries(_prompts + ([["{ui_tab_prev} {ui_tab_next} TABS"]] if tabs else []))


func add_button(text: String, cb: Callable) -> Button:
	var b := UiKit.button(text)
	b.pressed.connect(cb)
	buttons.add_child(b)
	return b


func close() -> void:
	if _closing:
		return
	_closing = true
	Game.save_settings()
	var vp := get_viewport()
	closed.emit()
	# the focus goes back where it was, unless whoever opened the dialog moved it already
	var f := vp.gui_get_focus_owner() if vp else null
	if (f == null or is_ancestor_of(f)) and is_instance_valid(_return_focus) and not is_ancestor_of(_return_focus) \
			and _return_focus.is_visible_in_tree() and not _return_focus.is_queued_for_deletion():
		_return_focus.grab_focus()
	queue_free()


## The safety net (InputPrompts): give the focus to the dialog's default control. False when the
## dialog is hidden or closing.
func focus_default() -> bool:
	if _closing or not is_visible_in_tree():
		return false
	var c := default_focus
	if not _focusable(c):
		c = tabs if _focusable(tabs) else null
	if c == null:
		for i in range(buttons.get_child_count() - 1, -1, -1):
			var b := buttons.get_child(i) as Control
			if b is BaseButton and _focusable(b) and not (b as BaseButton).disabled:
				c = b
				break
	if c == null:
		return false
	c.grab_focus()
	return true


## The D-pad can focus it (labels have FOCUS_ACCESSIBILITY: only a screen reader's).
static func _focusable(c: Control) -> bool:
	return c != null and is_instance_valid(c) and c.is_visible_in_tree() and c.focus_mode == Control.FOCUS_ALL


## LB / RB: the next or previous tab (wrapping round); a dialog without tabs can use them for
## something else.
func _tab_step(step: int) -> void:
	if tabs == null or not tabs.is_visible_in_tree() or tabs.tab_count < 2:
		return
	var f := get_viewport().gui_get_focus_owner()
	var i := tabs.current_tab
	for _k in tabs.tab_count:
		i = posmod(i + step, tabs.tab_count)
		if not tabs.is_tab_disabled(i) and not tabs.is_tab_hidden(i):
			break
	tabs.current_tab = i
	# the focus was on the page that just went away: the tab bar takes it
	if f == null or not is_instance_valid(f) or not f.is_visible_in_tree():
		tabs.grab_focus()


## This is the dialog on top: no dialog opened after it is showing.
func is_top() -> bool:
	var screens := get_tree().get_nodes_in_group(InputPrompts.SCREEN_GROUP)
	for i in range(screens.size() - 1, -1, -1):
		var d := screens[i] as Dialog
		if d == self:
			return true
		if d and d.is_visible_in_tree() and not d._closing:
			return false
	return true


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_ENTER_TREE:
			_return_focus = get_viewport().gui_get_focus_owner()
			if not get_viewport().gui_focus_changed.is_connected(_on_focus_changed):
				get_viewport().gui_focus_changed.connect(_on_focus_changed)
			if not InputPrompts.prompts_changed.is_connected(_update_tab_glyphs):
				InputPrompts.prompts_changed.connect(_update_tab_glyphs)
		NOTIFICATION_EXIT_TREE:
			if get_viewport().gui_focus_changed.is_connected(_on_focus_changed):
				get_viewport().gui_focus_changed.disconnect(_on_focus_changed)
			if InputPrompts.prompts_changed.is_connected(_update_tab_glyphs):
				InputPrompts.prompts_changed.disconnect(_update_tab_glyphs)
		NOTIFICATION_READY:
			# (after the dialog's own _ready, which made its tabs)
			if tabs:
				_frame_tabs()


## Puts the LB and RB icons on either side of the tab bar and "[LB][RB] TABS" in the hints.
func _frame_tabs() -> void:
	var holder := tabs.get_parent()
	if holder == null:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	holder.add_child(row)
	holder.move_child(row, tabs.get_index())
	holder.remove_child(tabs)
	# every tab shown at its width (a clipping TabBar has no minimum width), RB right after the last
	tabs.clip_tabs = false
	tabs.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for act in ["ui_tab_prev", "", "ui_tab_next"]:
		if act == "":
			row.add_child(tabs)
			continue
		var g := InputGlyph.new(act, 28.0)
		g.style = "pad"  # (the same width on the keyboard, where it is hidden)
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(g)
		_tab_glyphs.append(g)
	set_prompts(_prompts)
	_update_tab_glyphs()


func _update_tab_glyphs() -> void:
	# kept in the layout (alpha 0) so the tabs do not shift when the device changes
	for g in _tab_glyphs:
		g.modulate.a = 1.0 if InputPrompts.using_pad() else 0.0


## The focus trap: the D-pad found a control behind the dialog (Godot looks for the nearest one
## that way in the whole screen): the nearest one in the dialog that way takes it instead, or it
## stays where it was.
func _on_focus_changed(c: Control) -> void:
	if _closing or c == null or not is_visible_in_tree():
		return
	if c == self or is_ancestor_of(c):
		_inside = c
		return
	if is_top():
		_pull_back.call_deferred()


## (deferred: whoever moved the focus may be closing the dialog meanwhile, an answer's handler)
func _pull_back() -> void:
	if _closing or is_queued_for_deletion() or not is_visible_in_tree() or not is_top():
		return
	var f := get_viewport().gui_get_focus_owner()
	if f != null and (f == self or is_ancestor_of(f)):
		return
	if _focusable(_inside) and is_ancestor_of(_inside):
		var to := _toward(_inside, _dir) if Time.get_ticks_msec() - _dir_t < 250 else null
		(to if to else _inside).grab_focus()
	else:
		focus_default()


## The control in this dialog nearest `from` in direction `dir` (null: none that way).
func _toward(from: Control, dir: Vector2) -> Control:
	if dir == Vector2.ZERO:
		return null
	var at := from.get_global_rect().get_center()
	var side := Vector2(-dir.y, dir.x)
	var best: Control = null
	var best_d := INF
	for n in find_children("*", "Control", true, false):
		var c := n as Control
		if c == from or not _focusable(c) or (c is BaseButton and (c as BaseButton).disabled):
			continue
		var d := c.get_global_rect().get_center() - at
		var along := d.dot(dir)
		if along < 4.0:
			continue
		var score := along + absf(d.dot(side)) * 2.0
		if score < best_d:
			best_d = score
			best = c
	return best


func _input(event: InputEvent) -> void:
	if event is InputEventMouse or not event.is_pressed():
		return
	_dir = Vector2.ZERO
	for i in NAV_DIRS.size():
		if event.is_action_pressed(NAV_DIRS[i], true):
			_dir = NAV_VECS[i]
			_dir_t = Time.get_ticks_msec()
			return


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		# B / Esc in a text field being typed in only stops the typing
		var f := get_viewport().gui_get_focus_owner()
		if cancel_stops_typing and f is LineEdit and (f as LineEdit).is_editing() and is_ancestor_of(f) \
				and event.is_action_pressed("ui_cancel"):
			(f as LineEdit).unedit()
			return
		Game.play_ui("res://assets/sound/ui/buttonclickrelease.wav", -5.0)
		close()
	elif event.is_action_pressed("ui_tab_next") or event.is_action_pressed("ui_tab_prev"):
		get_viewport().set_input_as_handled()
		_tab_step(1 if event.is_action_pressed("ui_tab_next") else -1)
