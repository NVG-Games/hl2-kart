class_name TrackList
extends VBoxContainer
## The grid of track cards used by EditorHome and TrackBrowser (1.1, 5.3): 200 x 150 cards in NEW
## RACE's picture-card look (orange frame on the card shown, a white frame on focus, dimmed when the
## track cannot be raced), the track's picture or, with none, its road's outline, the short name
## and a badge ("2 ERRORS" in red, "RACEABLE" dim, "KEPT"). The D-pad and the arrows walk the grid
## and stop at its edges (up / down leave it only to up_target / down_target). A click or the D-pad
## selects a card (selected); A, Enter or a double click activates it (activated).
## Entries are CustomTracks.meta dictionaries, template entries ({id "template:<id>", template})
## and the + NEW TRACK card ({id "new", new: true}).

signal selected(entry: Dictionary)
signal activated(entry: Dictionary)

const CARD := Vector2(200, 150)
const NEW_ID := "new"
const TEMPLATE_PREFIX := "template:"
const ERROR_RED := Color(1, 0.45, 0.35)
const SEP := Vector2(12, 12)
## The five templates' road outlines (control points, 0..1 over their bounding square), so the
## TEMPLATES cards draw without building a template; case_home checks them against
## outline_of_doc(LevelTemplates.make(id)).
const TEMPLATE_OUTLINES := {
	"empty": [],
	"oval": [[0.2, 0.7], [0.4, 0.7], [0.6, 0.7], [0.8, 0.7], [0.941, 0.641], [1.0, 0.5], [0.941, 0.359], [0.8, 0.3],
		[0.6, 0.3], [0.4, 0.3], [0.2, 0.3], [0.059, 0.359], [0.0, 0.5], [0.059, 0.641]],
	"figure8": [[0.238, 0.358], [0.372, 0.431], [0.628, 0.569], [0.762, 0.642], [0.87, 0.658], [0.963, 0.603], [1.0, 0.5],
		[0.963, 0.397], [0.87, 0.342], [0.762, 0.358], [0.656, 0.416], [0.557, 0.469], [0.443, 0.531], [0.344, 0.584],
		[0.238, 0.642], [0.13, 0.658], [0.037, 0.603], [0.0, 0.5], [0.037, 0.397], [0.13, 0.342]],
	"hills": [[1.0, 0.516], [0.973, 0.699], [0.85, 0.835], [0.695, 0.907], [0.544, 0.939], [0.394, 0.942], [0.249, 0.897],
		[0.133, 0.798], [0.058, 0.666], [0.011, 0.516], [0.0, 0.345], [0.062, 0.174], [0.208, 0.063], [0.389, 0.058],
		[0.538, 0.125], [0.654, 0.197], [0.778, 0.257], [0.915, 0.354]],
	"city": [[0.0, 0.8], [0.075, 0.875], [0.925, 0.875], [1.0, 0.8], [1.0, 0.65], [1.0, 0.35], [1.0, 0.2], [0.925, 0.125],
		[0.575, 0.125], [0.5, 0.2], [0.5, 0.55], [0.425, 0.625], [0.325, 0.625], [0.25, 0.55], [0.25, 0.2], [0.175, 0.125],
		[0.075, 0.125], [0.0, 0.2]],
}

var columns := 4
var scroll: ScrollContainer
var grid: GridContainer
var empty_label: Label
var cards: Array[Button] = []
## The cards' entries in order (the filter left the others out).
var entries: Array[Dictionary] = []
## The entry shown as selected ({} for none).
var current := {}
## Name / author filter (case-insensitive); the + NEW TRACK card always stays.
var filter := ""
## Up from the first row / down from the last one (null: the D-pad stops there).
var up_target: Control
var down_target: Control
var _all: Array[Dictionary] = []
var _mouse_t := -100000


func _init(cols := 4) -> void:
	columns = cols
	add_theme_constant_override("separation", 8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	grid = GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", int(SEP.x))
	grid.add_theme_constant_override("v_separation", int(SEP.y))
	scroll.add_child(grid)
	empty_label = UiKit.label("", 16, UiKit.TEXT_DIM)
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_label.custom_minimum_size.x = 360
	empty_label.visible = false
	add_child(empty_label)


## The grid's width for `cols` cards (layouts size their columns with it).
static func width_for(cols: int) -> float:
	return cols * CARD.x + (cols - 1) * SEP.x + 12.0


# ---------------------------------------------------------------- entries

## Replaces the cards; `keep_id` (else the selected one, else the first) stays selected.
func set_entries(list: Array, keep_id := "") -> void:
	_all.clear()
	for e in list:
		if e is Dictionary:
			_all.append(e)
	var want := keep_id if keep_id != "" else str(current.get("id", ""))
	var had_focus := has_focus_inside()
	_rebuild()
	var i := index_of(want)
	if i < 0 and not cards.is_empty():
		i = 0
	if i >= 0:
		select(i, had_focus, true)
	else:
		current = {}
		selected.emit(current)


## Filters the cards by name / author.
func set_filter(text: String) -> void:
	filter = text.strip_edges().to_lower()
	var want := str(current.get("id", ""))
	var had_focus := has_focus_inside()
	_rebuild()
	var i := index_of(want)
	if i < 0 and not cards.is_empty():
		i = 0
	if i >= 0:
		select(i, had_focus, true)
	else:
		current = {}
		selected.emit(current)


func index_of(id: String) -> int:
	if id == "":
		return -1
	for i in entries.size():
		if str(entries[i].get("id", "")) == id:
			return i
	return -1


func card_of(id: String) -> Button:
	var i := index_of(id)
	return cards[i] if i >= 0 else null


## The selected card (null for none).
func current_card() -> Button:
	return card_of(str(current.get("id", "")))


func has_focus_inside() -> bool:
	var vp := get_viewport()
	var f := vp.gui_get_focus_owner() if vp else null
	return f != null and is_ancestor_of(f)


## Selects card i (the details follow); focus: it takes the focus too; force: `selected` fires
## even when it was selected already (the cards were rebuilt).
func select(i: int, focus := false, force := false) -> void:
	if i < 0 or i >= cards.size():
		return
	var changed := str(current.get("id", "")) != str(entries[i].get("id", "")) or current != entries[i]
	current = entries[i]
	for k in cards.size():
		_paint(cards[k], k == i)
	if focus and not cards[i].has_focus():
		cards[i].grab_focus()
	if changed or force:
		selected.emit(current)


## Activates the selected card (A on it), as a press does.
func activate() -> void:
	if not current.is_empty():
		activated.emit(current)


## A thumbnail arrived (Game.track_thumb_ready): that card shows it.
func set_thumb(id: String, tex: Texture2D) -> void:
	var b := card_of(id)
	if b != null and tex != null:
		_set_picture(b, tex, [])


func _rebuild() -> void:
	for b in cards:
		grid.remove_child(b)
		b.queue_free()
	cards.clear()
	entries.clear()
	for e in _all:
		if filter != "" and not bool(e.get("new", false)):
			var hay := (str(e.get("name", "")) + " " + str(e.get("author", ""))).to_lower()
			if hay.find(filter) < 0:
				continue
		entries.append(e)
	for i in entries.size():
		var b := make_card(entries[i])
		b.name = "Card_%d" % i
		b.pressed.connect(_on_pressed.bind(i))
		b.gui_input.connect(_on_card_input.bind(i))
		b.focus_entered.connect(_on_focus.bind(i))
		grid.add_child(b)
		cards.append(b)
	empty_label.visible = cards.is_empty() and empty_label.text != ""
	scroll.visible = not cards.is_empty()
	_wire_focus()


## The D-pad round the grid: along a row and no further at its ends, up and down off it only to
## up_target / down_target.
func _wire_focus() -> void:
	var n := cards.size()
	for i in n:
		var b := cards[i]
		var col := i % columns
		if col == 0:
			b.focus_neighbor_left = NodePath(".")
		if col == columns - 1 or i == n - 1:
			b.focus_neighbor_right = NodePath(".")
		if i < columns:
			b.focus_neighbor_top = b.get_path_to(up_target) if _usable(up_target) else NodePath(".")
		if i + columns >= n:
			# the last row (a short one: the card above it in the row before is not "down")
			b.focus_neighbor_bottom = b.get_path_to(down_target) if _usable(down_target) else NodePath(".")
		elif i + columns < n:
			b.focus_neighbor_bottom = b.get_path_to(cards[i + columns])


## Up / down targets changed (a button row rebuilt): the edges again.
func rewire() -> void:
	_wire_focus()


func _usable(c: Control) -> bool:
	return c != null and is_instance_valid(c) and c.is_inside_tree() and is_inside_tree()


func _on_focus(i: int) -> void:
	select(i)


func _on_pressed(i: int) -> void:
	select(i)
	# a click selects (a double click activates); A / Enter on the card activates it
	if Time.get_ticks_msec() - _mouse_t < 800:
		return
	activate()


func _on_card_input(ev: InputEvent, i: int) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_mouse_t = Time.get_ticks_msec()
		if ev.is_pressed() and (ev as InputEventMouseButton).double_click:
			select(i)
			activate()


# ---------------------------------------------------------------- cards

## One card in RaceSetup._pic_card's look: the picture (or the outline), the caption, a badge.
static func make_card(e: Dictionary, size := CARD) -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_ALL
	b.clip_contents = true
	var inner := VBoxContainer.new()
	inner.name = "Inner"
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 6
	inner.offset_right = -6
	inner.offset_top = 6
	inner.offset_bottom = -4
	inner.add_theme_constant_override("separation", 3)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(inner)
	var holder := Control.new()
	holder.name = "Pic"
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.clip_contents = true
	inner.add_child(holder)
	var cap := UiKit.label(caption_of(e), 12, UiKit.TEXT, true)
	cap.name = "Caption"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.clip_text = true
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(cap)
	if bool(e.get("new", false)):
		var plus := UiKit.label("+", 64, UiKit.ORANGE, true)
		plus.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(plus)
	else:
		_set_picture(b, picture_of(e), outline_of(e))
	var bd := badge_of(e)
	if not bd.is_empty():
		var tag := PanelContainer.new()
		tag.name = "Badge"
		tag.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.72), Color(0, 0, 0, 0), 0, 2, 4))
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.anchor_left = 1.0
		tag.anchor_right = 1.0
		tag.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		tag.offset_right = -10
		tag.offset_left = -10
		tag.offset_top = 10
		var l := UiKit.label(str(bd[0]), 10, bd[1], true)
		l.name = "Text"
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.add_child(l)
		b.add_child(tag)
	_paint(b, false)
	b.add_theme_stylebox_override("focus", RacerPicker.focus_style())
	if not pickable(e):
		b.modulate.a = 0.5
	# the menus' button sounds (no hover focus: a resting cursor never changes the selection)
	b.mouse_entered.connect(func(): Game.play_ui("res://assets/sound/ui/buttonrollover.wav", -8.0))
	b.pressed.connect(func(): Game.play_ui("res://assets/sound/ui/buttonclickrelease.wav", -5.0))
	return b


## The card's look: orange when it is the selected one (NEW RACE's picked card).
static func _paint(b: Button, sel: bool) -> void:
	if sel:
		var sb := UiKit.box(Color(0, 0, 0, 0.4), UiKit.ORANGE, 3, 4, 5)
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(st, sb)
	else:
		b.add_theme_stylebox_override("normal", UiKit.box(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.12), 1, 4, 5))
		b.add_theme_stylebox_override("hover", UiKit.box(Color(1, 1, 1, 0.08), Color.WHITE, 2, 4, 5))
		b.add_theme_stylebox_override("pressed", UiKit.box(Color(0, 0, 0, 0.4), UiKit.ORANGE, 3, 4, 5))
		b.add_theme_stylebox_override("hover_pressed", UiKit.box(Color(0, 0, 0, 0.4), UiKit.ORANGE, 3, 4, 5))
	b.set_meta("selected", sel)


## The picture holder shows tex, else the outline.
static func _set_picture(b: Button, tex: Texture2D, outline: Array) -> void:
	var holder := b.get_node_or_null("Inner/Pic") as Control
	if holder == null:
		return
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	if tex != null:
		var pic := TextureRect.new()
		pic.name = "Thumb"
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(pic)
	else:
		var o := Outline.new()
		o.name = "Outline"
		o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		o.set_points(outline)
		holder.add_child(o)


static func caption_of(e: Dictionary) -> String:
	if bool(e.get("new", false)):
		return "NEW TRACK"
	var s := str(e.get("short", e.get("name", "")))
	return s if s != "" else str(e.get("name", "TRACK")).to_upper()


## The card's picture: a custom track's thumbnail (null while it decodes, or when it has none).
static func picture_of(e: Dictionary) -> Texture2D:
	if e.has("template") or bool(e.get("new", false)):
		return null
	var id := str(e.get("id", ""))
	if not CustomTracks.is_custom(id):
		return null
	if e.has("thumb") and not bool(e.get("thumb", false)):
		return null
	return Game.track_thumb(id)


## The outline to draw when there is no picture (header outline, or a template's).
static func outline_of(e: Dictionary) -> Array:
	if e.has("template"):
		return TEMPLATE_OUTLINES.get(str(e.template), [])
	var o = e.get("outline", [])
	return o if o is Array else []


## [text, colour] of the card's badge, or [] for none.
static func badge_of(e: Dictionary) -> Array:
	if e.has("template") or bool(e.get("new", false)) or e.is_empty():
		return []
	if str(e.get("unusable", "")) != "":
		return ["CANNOT BUILD", ERROR_RED]
	var errs := int(e.get("errors", 0))
	if errs > 0:
		return ["%d ERROR%s" % [errs, "" if errs == 1 else "S"], ERROR_RED]
	if not bool(e.get("checked", false)):
		return ["CHECKING..." if CustomTracks.auto_check else "NOT CHECKED", UiKit.TEXT_DIM]
	if bool(e.get("kept", false)):
		return ["KEPT", UiKit.ORANGE]
	if bool(e.get("raceable", false)):
		return ["RACEABLE", UiKit.TEXT_DIM]
	return ["NOT RACEABLE", ERROR_RED]


## Whether the card's track can be raced (templates and + NEW TRACK count as yes: nothing to race).
static func pickable(e: Dictionary) -> bool:
	return why_not(e) == ""


## "" when the track can be raced here, else why not (a custom track: its local facts, 5.1).
static func why_not(e: Dictionary) -> String:
	if e.is_empty():
		return "No track is selected."
	if e.has("template") or bool(e.get("new", false)):
		return ""
	var id := str(e.get("id", ""))
	if not CustomTracks.is_custom(id):
		return "" if Game.track_installed(id) else "It is not built on this computer yet."
	var un := str(e.get("unusable", CustomTracks.unusable(id)))
	if un != "":
		return "It cannot be built: %s" % un.trim_suffix(".") + "."
	var errs := int(e.get("errors", 0))
	if errs > 0:
		return "It has %d error%s: fix %s in the editor first." % [errs, "" if errs == 1 else "s", "it" if errs == 1 else "them"]
	if not bool(e.get("checked", false)):
		return "It is still being checked on this computer." if CustomTracks.auto_check else "It has not been checked on this computer yet."
	if not Game.track_installed(id):
		return "It has no road to race on."
	return ""


## "LAP 2.4 KM · 2 SHORTCUTS · 312 OBJECTS · 6 HAZARDS · 1.3 MB" (what is known).
static func stats_line(e: Dictionary) -> String:
	var parts := PackedStringArray()
	var length := float(e.get("length", 0.0))
	if length > 0.0:
		parts.append("LAP %.1f KM" % (length / 1000.0))
	var br := int(e.get("branches", 0))
	if br > 0:
		parts.append("%d SHORTCUT%s" % [br, "" if br == 1 else "S"])
	var props := int(e.get("props", 0))
	if props > 0:
		parts.append("%d OBJECT%s" % [props, "" if props == 1 else "S"])
	var hz := int(e.get("hazards", 0))
	if hz > 0:
		parts.append("%d HAZARD%s" % [hz, "" if hz == 1 else "S"])
	var size := int(e.get("size", 0))
	if size > 0:
		parts.append(size_text(size))
	return " · ".join(parts)


## NEW RACE's ABOUT THE TRACK for a custom track: "<desc> · by <author> · 2.4 KM · 2 SHORTCUTS".
static func race_line(e: Dictionary) -> String:
	var parts := PackedStringArray()
	if str(e.get("desc", "")) != "":
		parts.append(str(e.desc))
	if str(e.get("author", "")) != "":
		parts.append("by %s" % e.author)
	var length := float(e.get("length", 0.0))
	if length > 0.0:
		parts.append("%.1f KM" % (length / 1000.0))
	var br := int(e.get("branches", 0))
	if br > 0:
		parts.append("%d SHORTCUT%s" % [br, "" if br == 1 else "S"])
	return " · ".join(parts)


static func size_text(bytes: int) -> String:
	if bytes >= 1 << 20:
		return "%.1f MB" % (bytes / 1048576.0)
	return "%d KB" % maxi(1, int(ceil(bytes / 1024.0)))


## "MODIFIED 19 NOV 2026, 14:03" (local time), "" when unknown.
static func date_line(e: Dictionary) -> String:
	var t := int(e.get("modified", 0))
	if t <= 0:
		return ""
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var d := Time.get_datetime_dict_from_unix_time(t + bias * 60)
	var months := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
	return "MODIFIED %d %s %d, %02d:%02d" % [int(d.day), months[clampi(int(d.month) - 1, 0, 11)], int(d.year),
		int(d.hour), int(d.minute)]


## A template's card entry.
static func template_entry(tid: String) -> Dictionary:
	return {"id": TEMPLATE_PREFIX + tid, "template": tid, "name": LevelTemplates.title(tid), "short": LevelTemplates.title(tid),
		"desc": LevelTemplates.describe(tid), "outline": TEMPLATE_OUTLINES.get(tid, [])}


## The + NEW TRACK card's entry.
static func new_entry() -> Dictionary:
	return {"id": NEW_ID, "new": true, "name": "+ NEW TRACK", "short": "NEW TRACK",
		"desc": "Start a new track from a template."}


## A document's road outline: its control points, 0..1 over their bounding square (the header
## outline's frame, EditorSession._outline).
static func outline_of_doc(doc: LevelDoc) -> Array:
	var pts := PackedVector2Array()
	if doc != null:
		for p in doc.data.get("road", {}).get("points", []):
			var q = p.get("pos") if p is Dictionary else null
			if q is Array and q.size() == 3:
				pts.append(Vector2(float(q[0]), float(q[2])))
	if pts.size() < 2:
		return []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for v in pts:
		lo = lo.min(v)
		hi = hi.max(v)
	var side := maxf(maxf(hi.x - lo.x, hi.y - lo.y), 0.001)
	var c := (lo + hi) * 0.5
	var out := []
	for v in pts:
		out.append([snappedf(clampf((v.x - c.x) / side + 0.5, 0.0, 1.0), 0.001), snappedf(clampf((v.y - c.y) / side + 0.5, 0.0, 1.0), 0.001)])
	return out


# ---------------------------------------------------------------- the outline

## A road's outline drawn in a box (0..1 points over the box's square, smoothed when the points
## are few: a template's control points), the start in orange; "NO ROAD YET" when there is none.
class Outline:
	extends Control
	var points := PackedVector2Array()
	var color := Color(1, 1, 1, 0.8)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_points(list: Array) -> void:
		points = PackedVector2Array()
		for p in list:
			if p is Array and p.size() >= 2:
				points.append(Vector2(clampf(float(p[0]), 0.0, 1.0), clampf(float(p[1]), 0.0, 1.0)))
		queue_redraw()

	## The polyline in pixels (tests read it).
	func path_px() -> PackedVector2Array:
		var out := PackedVector2Array()
		if points.size() < 2:
			return out
		var r := Rect2(Vector2.ZERO, size).grow(-maxf(6.0, minf(size.x, size.y) * 0.08))
		var side := minf(r.size.x, r.size.y)
		var o := r.position + (r.size - Vector2(side, side)) * 0.5
		var closed := points[0].distance_to(points[points.size() - 1]) < 0.2 or points.size() < 40
		var src := points
		if points.size() < 40:
			src = _smooth(points, closed)
		for p in src:
			out.append(o + p * side)
		if closed and not out.is_empty():
			out.append(out[0])
		return out

	func _draw() -> void:
		var px := path_px()
		if px.size() < 2:
			var f := get_theme_default_font()
			var t := "NO ROAD YET"
			var fs := 12
			var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, Vector2((size.x - w) * 0.5, size.y * 0.5 + fs * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(1, 1, 1, 0.35))
			return
		draw_polyline(px, Color(0, 0, 0, 0.5), 5.0, true)
		draw_polyline(px, color, 2.0, true)
		draw_circle(px[0], 4.0, UiKit.ORANGE)

	## Catmull-Rom through the points, 6 steps a span.
	static func _smooth(p: PackedVector2Array, closed: bool) -> PackedVector2Array:
		var n := p.size()
		var out := PackedVector2Array()
		var spans := n if closed else n - 1
		for i in spans:
			var p0 := p[posmod(i - 1, n)] if closed or i > 0 else p[0]
			var p1 := p[i]
			var p2 := p[(i + 1) % n]
			var p3 := p[(i + 2) % n] if closed or i + 2 < n else p2
			for k in 6:
				var t := k / 6.0
				var t2 := t * t
				var t3 := t2 * t
				out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
		if not closed:
			out.append(p[n - 1])
		return out


# ---------------------------------------------------------------- the details panel

## The right-hand details of the selected card: big picture (360 x 240) or outline, name,
## "by <author>", description, the stats line, the modified date, a remix credit, and why it
## cannot be raced (red).
class Details:
	extends VBoxContainer
	var pic_size := Vector2(360, 240)
	var frame: PanelContainer
	var holder: Control
	var name_label: Label
	var author_label: Label
	var desc_label: Label
	var stats_label: Label
	var date_label: Label
	var remix_label: Label
	var why_label: Label
	var entry := {}

	func _init(pic := Vector2(360, 240)) -> void:
		pic_size = pic
		custom_minimum_size.x = pic.x
		add_theme_constant_override("separation", 6)
		frame = PanelContainer.new()
		frame.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.1), 1, 4, 0))
		frame.custom_minimum_size = pic_size
		add_child(frame)
		holder = Control.new()
		holder.clip_contents = true
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(holder)
		name_label = UiKit.label("", 24, Color.WHITE, true)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.custom_minimum_size.x = pic.x
		add_child(name_label)
		author_label = UiKit.label("", 15, UiKit.TEXT_DIM)
		add_child(author_label)
		desc_label = _wrapped(15, UiKit.TEXT)
		stats_label = _wrapped(13, UiKit.ORANGE, true)
		date_label = UiKit.label("", 13, UiKit.TEXT_DIM)
		add_child(date_label)
		remix_label = _wrapped(13, UiKit.TEXT_DIM)
		why_label = _wrapped(15, TrackList.ERROR_RED)

	func _wrapped(fs: int, col: Color, bold := false) -> Label:
		var l := UiKit.label("", fs, col, bold)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = pic_size.x
		add_child(l)
		return l

	func show_entry(e: Dictionary) -> void:
		entry = e
		visible = not e.is_empty()
		if e.is_empty():
			return
		name_label.text = str(e.get("name", ""))
		var by := str(e.get("author", ""))
		author_label.text = "by %s" % by if by != "" else ""
		author_label.visible = by != ""
		desc_label.text = str(e.get("desc", ""))
		desc_label.visible = desc_label.text != ""
		stats_label.text = TrackList.stats_line(e)
		stats_label.visible = stats_label.text != ""
		date_label.text = TrackList.date_line(e)
		date_label.visible = date_label.text != ""
		var rx = e.get("remix_of", {})
		remix_label.text = ""
		if rx is Dictionary and str(rx.get("name", "")) != "":
			remix_label.text = "Remix of %s%s" % [rx.name, " by %s" % rx.author if str(rx.get("author", "")) != "" else ""]
		remix_label.visible = remix_label.text != ""
		why_label.text = TrackList.why_not(e)
		why_label.visible = why_label.text != ""
		_picture(TrackList.picture_of(e), TrackList.outline_of(e), bool(e.get("new", false)))

	func set_thumb(id: String, tex: Texture2D) -> void:
		if str(entry.get("id", "")) == id and tex != null:
			_picture(tex, [], false)

	func _picture(tex: Texture2D, outline: Array, plus: bool) -> void:
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
		if plus:
			var l := UiKit.label("+", 120, UiKit.ORANGE, true)
			l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			holder.add_child(l)
		elif tex != null:
			var pic := TextureRect.new()
			pic.texture = tex
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(pic)
		else:
			var o := TrackList.Outline.new()
			o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			o.set_points(outline)
			holder.add_child(o)
