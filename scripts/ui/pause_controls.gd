class_name PauseControls
extends PanelContainer
## Beside the pause menu (and the online MENU, as a child of Hud.pause_panel): the controls for the
## device in use. A pad: a compact picture of it with every bound button's action beside it
## (ControllerDiagram, its family: InputPrompts.pad_style()). The keyboard: a compact drawn
## keyboard and mouse with the bound keys lit (KeyboardDiagram), and each action's keys under it.
## Switches at once when the player uses the other device, and shows a binding changed in OPTIONS
## (Hud hides it while OPTIONS is open over the pause). Never takes the focus or the mouse, so the
## pause menu's D-pad never goes into it. Anchored bottom-left like the pause column, right of it,
## growing upwards from the column's bottom line (Hud._build_pause).
## It is hidden the whole race, and a player may switch device many times there: while hidden it
## only notes that the prompts changed (its pictures too: their `lazy`) and catches up
## when the pause menu opens. Each body is made once, the first time its device is shown, and kept.

const U := Hl2Style.UNIT
const LEFT := 692.0  # (44 px right of the pad-lost note beside PAUSED)
const WIDTH := 604.0  # (the right edge stays at 1296, 23 px from the minimap; 572 inside: the compact picture)
const CELL_W := 278.0  # one action in the keyboard's list (two columns)
const GLYPH_PX := 20.0
const LIST_GLYPHS := 3  # an action's first keys in the list

## The compact pad picture while a pad is shown (null while the keyboard is).
var pad_diagram: ControllerDiagram:
	get:
		return _pad_body if _pad_body and _pad_body.visible else null
## The compact keyboard while the keyboard is shown (null while a pad is).
var keyboard: KeyboardDiagram:
	get:
		return _kb_body if _kb_body and _kb_body.visible else null
## Online: the list has CHAT too.
var online := false
var _box: VBoxContainer
var _device: Label
var _list: GridContainer  # the keyboard's list (made with the keyboard, shown with it)
var _foot: PromptLabel
var _pad_body: ControllerDiagram
var _kb_body: KeyboardDiagram
var _cells := {}  # action -> its LIST_GLYPHS icons (TextureRects: _fill_list sets them, nothing listens)
var _stale := true  # the prompts changed while hidden (and nothing is shown yet)


func _init(is_online := false) -> void:
	online = is_online
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UiKit.box(Color(0.075, 0.075, 0.075, 0.94), Color(1, 1, 1, 0.1), 1, 4, 16)
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	add_theme_stylebox_override("panel", sb)
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = LEFT
	offset_right = LEFT + WIDTH
	offset_bottom = -(82 * U + 24)  # the pause column's bottom line
	offset_top = offset_bottom
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sec := UiKit.section("CONTROLS")
	head.add_child(sec)
	_device = UiKit.label("", 14, UiKit.TEXT_DIM)
	_device.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_device)
	_box.add_child(head)
	_foot = UiKit.prompt("Change them in OPTIONS.", 14, UiKit.TEXT_DIM)
	_box.add_child(_foot)


func _enter_tree() -> void:
	# (InputPrompts emits prompts_changed after every style change too: one handler is enough)
	if not InputPrompts.prompts_changed.is_connected(_on_prompts):
		InputPrompts.prompts_changed.connect(_on_prompts)
	_on_prompts()


func _exit_tree() -> void:
	if InputPrompts.prompts_changed.is_connected(_on_prompts):
		InputPrompts.prompts_changed.disconnect(_on_prompts)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _stale and is_visible_in_tree():
		refresh()


func _on_prompts() -> void:
	if is_visible_in_tree():
		refresh()
	else:
		_stale = true


## A pad in use (InputPrompts.style() is a pad style), else the keyboard and mouse.
static func pad_in_use() -> bool:
	return InputPrompts.style() != InputPrompts.KEYBOARD


## Shows the pad's picture or the keyboard's for the device in use (making it the first time),
## the device's name in the head, and the keys in the keyboard's list.
func refresh() -> void:
	_stale = false
	var want_pad := pad_in_use()
	if want_pad and _pad_body == null:
		_pad_body = ControllerDiagram.new()
		_pad_body.compact = true
		_pad_body.lazy = true
		_pad_body.name = "PadDiagram"
		_box.add_child(_pad_body)
		_box.move_child(_pad_body, 1)
	elif not want_pad and _kb_body == null:
		_kb_body = KeyboardDiagram.new()
		_kb_body.compact = true
		_kb_body.lazy = true
		_kb_body.name = "Keyboard"
		_box.add_child(_kb_body)
		_box.move_child(_kb_body, 1)
		_list = GridContainer.new()
		_list.columns = 2
		_list.add_theme_constant_override("h_separation", 16)
		_list.add_theme_constant_override("v_separation", 4)
		_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box.add_child(_list)
		_box.move_child(_list, 2)
		_make_cells()
	if _pad_body:
		_pad_body.visible = want_pad
	if _kb_body:
		_kb_body.visible = not want_pad
		_list.visible = not want_pad
	_device.text = str(InputPrompts.STYLE_NAMES.get(InputPrompts.style(), "")).to_upper()
	if not want_pad:
		_fill_list()


## The list's cells, once: an action's glyphs (filled by _fill_list) and its short name.
func _make_cells() -> void:
	for act in InputBindings.ACTIONS:
		if act == "chat" and not online:
			continue
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 8)
		cell.custom_minimum_size.x = CELL_W
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var glyphs := HBoxContainer.new()
		glyphs.add_theme_constant_override("separation", 4)
		glyphs.custom_minimum_size.x = 122
		glyphs.alignment = BoxContainer.ALIGNMENT_END
		glyphs.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var list: Array[TextureRect] = []
		for i in LIST_GLYPHS:
			var g := TextureRect.new()
			g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			g.mouse_filter = Control.MOUSE_FILTER_IGNORE
			g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			g.visible = false
			glyphs.add_child(g)
			list.append(g)
		cell.add_child(glyphs)
		var l := UiKit.label(str(InputBindings.SHORT_TITLES.get(act, act.to_upper())), 13, UiKit.TEXT, true)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.clip_text = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(l)
		_list.add_child(cell)
		_cells[act] = list


## Each action's first keys into its icons (the icons stay: only their textures change).
func _fill_list() -> void:
	var keys := InputBindings.all_slots(InputBindings.KEY)
	for act in _cells:
		var specs: Array = (keys[act] as Array).filter(func(s: String) -> bool: return s != "")
		var list: Array = _cells[act]
		for i in list.size():
			var g: TextureRect = list[i]
			var spec: String = specs[i] if i < specs.size() else ""
			var tex := _key_texture(spec)
			g.texture = tex
			g.visible = tex != null
			# (a keycap is as wide as its name, as InputGlyph does it)
			var w := maxf(GLYPH_PX, GLYPH_PX * tex.get_width() / maxf(tex.get_height(), 1.0)) if tex else 0.0
			g.custom_minimum_size = Vector2(w, GLYPH_PX if tex else 0.0)


## A key's or mouse button's icon at GLYPH_PX, else its name on a keycap (null: nothing bound).
static func _key_texture(spec: String) -> Texture2D:
	if spec == "":
		return null
	var tex := InputPrompts.spec_icon(spec, GLYPH_PX, InputPrompts.KEYBOARD)
	if tex == null:
		var t := InputPrompts.spec_text(spec, InputPrompts.KEYBOARD)
		if t != "":
			tex = KeycapTexture.of(t, GLYPH_PX)
	return tex
