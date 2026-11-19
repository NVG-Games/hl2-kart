class_name CatalogPanel
extends PanelContainer
## The OBJECTS drawer (1.6), in EditorUI.catalog_host (220 px at the foot of the free area):
## category tabs (FAVOURITES, RECENT, ALL, LIGHTS & FX, the model categories, ANIMATED with SHOW
## ANIMATED, OTHER), a search field over the key's words and the category, and a grid of 96 x 96
## thumbnails with names, a star (favourite) and a size badge ("12 m"). A click picks a model
## (Ctrl + click adds it to the 1-8 picked for SCATTER / ALONG ROAD); LIGHTS & FX lists the four
## stamps that are not models (the Breencast screen greyed without the COMBINE arch). Thumbnails
## come from PropThumbs (a window only; a grey card with the name until then). Cells are made a
## few per frame so a 400-model tab opens at once. P17.

signal picked(key: String, add: bool)
signal fx_picked(id: String)

const CELL := Vector2(104, 126)
const THUMB := 96
const PER_FRAME := 32
const CARD_COLOR := Color(0.22, 0.23, 0.25)
const PICKED_COLOR := Color8(255, 155, 0)

var editor: TrackEditor
var tool: ObjectsTool
var tab := PropCatalog.TAB_ALL
var query := ""
var show_animated := false
var thumbs: PropThumbs

var _tabs_box: HBoxContainer
var _tab_group := ButtonGroup.new()
var _search: LineEdit
var _animated: Button
var _info: Label
var _grid: HFlowContainer
var _scroll: ScrollContainer
var _cells := {}                 # key (or "fx:<id>") -> Button
var _pending := PackedStringArray()
var _shown := PackedStringArray()
var _picked := PackedStringArray()
var _fx := ""
var _built := false


func _init() -> void:
	name = "Catalog"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func setup(ed: TrackEditor, t: ObjectsTool) -> void:
	editor = ed
	tool = t
	if not _built:
		_build()
	if not picked.is_connected(_on_picked):
		picked.connect(_on_picked)
		fx_picked.connect(_on_fx)
	refresh()


func _build() -> void:
	_built = true
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	v.add_child(top)
	var ts := ScrollContainer.new()
	ts.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	ts.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ts.custom_minimum_size.y = EditorKit.ROW_H + 8
	top.add_child(ts)
	_tabs_box = HBoxContainer.new()
	_tabs_box.add_theme_constant_override("separation", 2)
	ts.add_child(_tabs_box)
	_search = LineEdit.new()
	_search.placeholder_text = "SEARCH"
	_search.custom_minimum_size = Vector2(150, EditorKit.ROW_H - 4)
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(t: String) -> void: set_query(t))
	_search.text_submitted.connect(func(_t: String) -> void: _search.release_focus())
	top.add_child(_search)
	_animated = EditorKit.toggle("SHOW ANIMATED", show_animated, func(on: bool) -> void: set_show_animated(on))
	_animated.tooltip_text = "Creatures and machines (they stand in their bind pose)"
	top.add_child(_animated)
	_info = UiKit.label("", EditorKit.FONT_SMALL, UiKit.TEXT_DIM)
	_info.custom_minimum_size.x = 90
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_info)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	_scroll.add_child(_grid)
	thumbs = PropThumbs.new()
	thumbs.name = "Thumbs"
	add_child(thumbs)
	thumbs.thumb_ready.connect(_on_thumb)
	visibility_changed.connect(func() -> void:
		if thumbs != null:
			thumbs.set_process(is_visible_in_tree()))


# ---------------------------------------------------------------- state

func set_tab(t: String) -> void:
	tab = t
	refresh()


func set_query(q: String) -> void:
	query = q
	if _search != null and _search.text != q:
		_search.text = q
	refresh(false)


func set_show_animated(on: bool) -> void:
	show_animated = on
	if _animated != null:
		_animated.set_pressed_no_signal(on)
	if not on and tab == PropCatalog.ANIMATED:
		tab = PropCatalog.TAB_ALL
	refresh()


## The tabs offered now.
func tabs() -> PackedStringArray:
	return PropCatalog.tabs(show_animated)


## What the grid lists: model keys, or "fx:<id>" for LIGHTS & FX.
func shown() -> PackedStringArray:
	return _shown


## Rebuilds the tab strip (tabs_too) and the grid for the tab and search.
func refresh(tabs_too := true) -> void:
	if not _built:
		return
	if tabs_too:
		_build_tabs()
	_shown = PackedStringArray()
	if tab == PropCatalog.TAB_FX:
		for e in PropCatalog.fx_entries():
			var nm := str(e.name)
			if query == "" or nm.to_lower().contains(query.to_lower().strip_edges()):
				_shown.append("fx:" + str(e.id))
	elif query.strip_edges() != "":
		_shown = PropCatalog.search(query, tab, show_animated)
	else:
		_shown = PropCatalog.keys(tab, show_animated)
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_cells.clear()
	_pending = _shown.duplicate()
	if thumbs != null:
		thumbs.clear_queue()
	_info.text = "%d %s" % [_shown.size(), "ENTRIES" if tab == PropCatalog.TAB_FX else "OBJECTS"]
	_scroll.scroll_vertical = 0
	_fill(PER_FRAME)


func _build_tabs() -> void:
	for c in _tabs_box.get_children():
		_tabs_box.remove_child(c)
		c.queue_free()
	var list := tabs()
	if not (tab in list):
		tab = PropCatalog.TAB_ALL
	for t in list:
		var b := Button.new()
		b.text = t
		b.toggle_mode = true
		b.button_group = _tab_group
		b.theme_type_variation = "EdToggle"
		b.custom_minimum_size.y = EditorKit.ROW_H - 4
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = t == tab
		var tt: String = t
		b.pressed.connect(func() -> void:
			Game.play_ui("res://assets/sound/ui/buttonclick.wav", -10.0)
			set_tab(tt))
		_tabs_box.add_child(b)


func _process(_delta: float) -> void:
	if not _pending.is_empty():
		_fill(PER_FRAME)


## A click anywhere else lets go of the search field (the editor's keys work again).
func _input(ev: InputEvent) -> void:
	if _search == null or not _search.has_focus():
		return
	var mb := ev as InputEventMouseButton
	if mb != null and mb.pressed and not _search.get_global_rect().has_point(mb.position):
		_search.release_focus()


## Makes every waiting cell now (tests).
func flush() -> void:
	_fill(_pending.size())


func cell_count() -> int:
	return _cells.size()


func _fill(n: int) -> void:
	var k := 0
	while k < n and not _pending.is_empty():
		var key := _pending[0]
		_pending.remove_at(0)
		var c := _make_cell(key)
		_grid.add_child(c)
		_cells[key] = c
		k += 1


# ---------------------------------------------------------------- cells

func _make_cell(key: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = CELL
	b.toggle_mode = false
	b.focus_mode = Control.FOCUS_NONE
	b.flat = false
	b.theme_type_variation = "EdFlat"
	b.clip_contents = true
	var is_fx := key.begins_with("fx:")
	var fid := key.substr(3) if is_fx else ""
	var nm := str(PropCatalog.fx_entry(fid).get("name", fid.to_upper())) if is_fx else PropCatalog.display_name(key)
	b.tooltip_text = nm if is_fx else "%s\n%s" % [key, str(PropCatalog.fact(key).get("category", ""))]
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 4
	v.offset_right = -4
	v.offset_top = 4
	b.add_child(v)
	var pic := TextureRect.new()
	pic.name = "Pic"
	pic.custom_minimum_size = Vector2(THUMB, THUMB)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := ColorRect.new()
	card.name = "Card"
	card.color = CARD_COLOR if not is_fx else _fx_color(fid)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pic.add_child(card)
	var cl := UiKit.label(nm, EditorKit.FONT_SMALL - 2, UiKit.TEXT_DIM)
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(cl)
	v.add_child(pic)
	var lab := UiKit.label(nm, EditorKit.FONT_SMALL - 2, UiKit.TEXT)
	lab.clip_text = true
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(lab)
	if is_fx:
		var ok := PropCatalog.fx_enabled(fid, editor.doc if editor != null else null)
		b.disabled = not ok
		if not ok:
			b.tooltip_text = "%s: needs the COMBINE start arch" % nm
		b.pressed.connect(func() -> void: press(key))
		return b
	var sz := PropCatalog.size_of(key)
	if sz > 0.0:
		var badge := UiKit.label(_size_text(sz), EditorKit.FONT_SMALL - 3, Color.WHITE)
		badge.name = "Size"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_stylebox_override("normal", UiKit.box(Color(0, 0, 0, 0.6), Color(0, 0, 0, 0), 0, 3, 2))
		badge.position = Vector2(5, 5)
		b.add_child(badge)
	var star := StarButton.new()
	star.name = "Star"
	star.on = PropCatalog.is_favourite(key)
	star.position = Vector2(CELL.x - 24, 4)
	star.pressed.connect(func() -> void:
		star.on = toggle_star(key)
		star.queue_redraw())
	b.add_child(star)
	b.pressed.connect(func() -> void: press(key, Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)))
	var tex := thumbs.get_thumb(key) if thumbs != null else null
	if tex != null:
		_show_thumb(b, tex)
	_paint(b, key in _picked)
	return b


static func _size_text(m: float) -> String:
	if m >= 10.0:
		return "%d m" % roundi(m)
	return "%.1f m" % m


func _fx_color(fid: String) -> Color:
	match fid:
		"light":
			return Color(0.55, 0.5, 0.25)
		"fire":
			return Color(0.6, 0.3, 0.1)
		"embers":
			return Color(0.35, 0.25, 0.2)
		"screen":
			return Color(0.15, 0.35, 0.45)
	return CARD_COLOR


func _show_thumb(b: Button, tex: Texture2D) -> void:
	var pic := b.find_child("Pic", true, false) as TextureRect
	if pic == null:
		return
	pic.texture = tex
	var card := pic.get_node_or_null("Card")
	if card != null:
		card.visible = false


func _on_thumb(key: String, tex: Texture2D) -> void:
	var b = _cells.get(key)
	if b is Button and is_instance_valid(b):
		_show_thumb(b, tex)


func _paint(b: Button, on: bool) -> void:
	if on:
		b.add_theme_stylebox_override("normal", UiKit.box(Color(0.3, 0.2, 0.05, 0.9), PICKED_COLOR, 2, 4, 4))
	else:
		b.remove_theme_stylebox_override("normal")


# ---------------------------------------------------------------- actions

## A cell's click: a model (add: Ctrl) or a LIGHTS & FX entry ("fx:<id>").
func press(key: String, add := false) -> void:
	if key.begins_with("fx:"):
		fx_picked.emit(key.substr(3))
	else:
		picked.emit(key, add)


## The star: favourite on / off (saved); the FAVOURITES tab follows.
func toggle_star(key: String) -> bool:
	var on := PropCatalog.toggle_favourite(key)
	if tab == PropCatalog.TAB_FAVOURITES:
		refresh(false)
	return on


## Highlights the picked models (and the stamped LIGHTS & FX entry).
func mark(keys: PackedStringArray, fx_id := "") -> void:
	_picked = keys.duplicate()
	_fx = fx_id
	for k in _cells:
		var b = _cells[k]
		if b is Button and is_instance_valid(b):
			_paint(b, (k in _picked) or (fx_id != "" and k == "fx:" + fx_id))


func _on_picked(key: String, add: bool) -> void:
	if tool != null:
		tool.pick_model(key, add)


func _on_fx(fid: String) -> void:
	if tool != null:
		tool.pick_fx(fid)


## The favourite star drawn as a five-pointed star (no font glyph needed).
class StarButton extends Button:
	var on := false

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(20, 20)
		size = Vector2(20, 20)
		tooltip_text = "Favourite"

	func _draw() -> void:
		var c := size * 0.5
		var pts := PackedVector2Array()
		for i in 10:
			var r := 8.0 if i % 2 == 0 else 3.6
			var a := -PI * 0.5 + i * PI / 5.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		if on:
			draw_colored_polygon(pts, Color8(255, 190, 40))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(1, 1, 1, 0.9) if not on else Color8(120, 70, 0), 1.2, true)
