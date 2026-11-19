class_name ValidationPanel
extends PanelContainer
## The validation drawer (1.3, F3): the last bake's issues, errors first, each with its icon, the
## plain-English text of 1.8 (key tokens as icons), the item's name and its FIX button when the
## issue has one (TrackEditor.apply_fix: one undo step "FIX: <label>"). A click on a row frames the
## spot and selects the item. Refreshed after every bake. P10.

## Fix id -> button label (1.8), used until LevelFixes.LABELS names it.
const FIX_LABELS := {"close_loop": "CLOSE LOOP", "narrow": "NARROW THE ROAD HERE", "bridge": "MAKE A BRIDGE",
	"clear_grid": "CLEAR THE GRID", "remove_jump": "REMOVE THE JUMP", "smooth": "SMOOTH HEIGHTS HERE",
	"raise_water": "RAISE ABOVE THE WATER", "legal_spot": "MOVE TO A LEGAL SPOT", "hazard_setup": "FIX THE HAZARD",
	"auto_items": "AUTO ITEMS", "delete": "DELETE"}
const ORDER := {"error": 0, "warning": 1, "info": 2}

var editor: TrackEditor
var title: Label
var list: VBoxContainer
var scroll: ScrollContainer
## The shown issues, in the drawer's order.
var shown: Array[Dictionary] = []
## One FIX button per issue that has a fix (meta "issue").
var fix_buttons: Array[Button] = []
var _empty: Label


func _init() -> void:
	name = "ValidationPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	title = UiKit.label("VALIDATION", EditorKit.FONT, Color.WHITE, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	head.add_child(title)
	var close_b := EditorKit.button("CLOSE", func() -> void: visible = false, "{ed_validation}")
	close_b.theme_type_variation = "EdFlat"
	close_b.focus_mode = Control.FOCUS_NONE
	head.add_child(close_b)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	_empty = UiKit.label("No problems: the track is raceable.", EditorKit.FONT_SMALL, UiKit.TEXT_DIM)
	list.add_child(_empty)


func setup(ed: TrackEditor) -> void:
	editor = ed


## The label of a fix id (LevelFixes.LABELS first).
static func fix_label(fix: String) -> String:
	var l = LevelFixes.LABELS.get(fix, "")
	if str(l) != "":
		return str(l)
	return str(FIX_LABELS.get(fix, fix.to_upper().replace("_", " ")))


## The issues of a report in the drawer's order: errors, warnings, then info (stable inside a level).
static func ordered(r: LevelReport) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if r == null:
		return out
	var k := 0
	var keyed := []
	for it in r.items:
		keyed.append([int(ORDER.get(str(it.get("level", "info")), 2)), k, it])
		k += 1
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for e in keyed:
		out.append(e[2])
	return out


func set_report(r: LevelReport) -> void:
	shown = ordered(r)
	fix_buttons.clear()
	for c in list.get_children():
		if c != _empty:
			list.remove_child(c)
			c.queue_free()
	_empty.visible = shown.is_empty()
	var errs := r.errors() if r != null else 0
	var warns := r.warnings() if r != null else 0
	title.text = "VALIDATION: RACEABLE" if errs == 0 and warns == 0 else "VALIDATION: %s" % EditorUI.badge_text(errs, warns)
	for it in shown:
		list.add_child(_row(it))


func _row(it: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 0, 3, 6))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.set_meta("issue", it)
	p.tooltip_text = "Click to show it."
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	var ic := TextureRect.new()
	ic.texture = EditorKit.icon(str(it.get("level", "info")), 16)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	ic.custom_minimum_size = Vector2(18, 18)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)
	var txt := PromptLabel.new(EditorKit.prompt(str(it.get("text", it.get("code", "")))), EditorKit.FONT_SMALL, UiKit.TEXT)
	txt.add_theme_font_override("normal_font", UiKit.font(false))
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.custom_minimum_size.x = 120
	h.add_child(txt)
	var where := _where(it)
	if where != "":
		var w := UiKit.label(where, EditorKit.FONT_SMALL, UiKit.TEXT_DIM)
		w.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		w.custom_minimum_size.x = 90
		w.clip_text = true
		w.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(w)
	var fix := str(it.get("fix", ""))
	if fix != "":
		var label := fix_label(fix)
		var b := EditorKit.button(label, func() -> void: press_fix(it), "FIX: " + label)
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		b.set_meta("issue", it)
		fix_buttons.append(b)
		h.add_child(b)
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			p.accept_event()
			show_issue(it))
	return p


## The item's name or the spot on the lap ("s 412 m").
func _where(it: Dictionary) -> String:
	var u := int(it.get("uid", 0))
	if u > 0 and editor != null and editor.doc != null:
		var f := editor.doc.find(u)
		if not f.is_empty():
			return Outliner.item_name(editor, u, f)
	var s := float(it.get("s", -1.0))
	return "s %d m" % int(s) if s >= 0.0 else ""


## A FIX press: TrackEditor.apply_fix (one undo step).
func press_fix(it: Dictionary) -> void:
	if editor != null:
		editor.apply_fix(it)


## A row's click: frame the spot, select the item.
func show_issue(it: Dictionary) -> void:
	if editor != null:
		editor.frame_issue(it)
