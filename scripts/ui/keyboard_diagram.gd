class_name KeyboardDiagram
extends Control
## A drawn keyboard (ANSI, with the player's own legends on the letters and digits) and mouse, the
## bound keys lit: orange, each with its action's number in a badge (OPTIONS > KEYBOARD & MOUSE: the
## numbers are the table's, 1 = the first action), or compact without numbers or free keys' legends
## (the pause panel). A binding is a physical key without its side, so both Shift (Ctrl, Alt, Win)
## keys light for one. Keys not on it (the numpad, F13 and up, media keys, the ISO key): unplaced().
## Draws itself again when the prompts change (a binding, the device). Never takes the focus.

## A bound key or mouse button was clicked (interactive): the page starts listening on its slot.
signal key_clicked(spec: String)

const UNIT_FULL := 41.0
const UNIT_COMPACT := 24.0
## The drawn keyboard (key units; 1 = one letter key): [key, legend, x, y, width]. Both Shift, Ctrl,
## Alt and Win keys are listed: a binding lights both (a binding is a physical key without its side).
const KEYS := [
	[KEY_ESCAPE, "ESC", 0, 0, 1],
	[KEY_F1, "F1", 2, 0, 1],
	[KEY_F2, "F2", 3, 0, 1],
	[KEY_F3, "F3", 4, 0, 1],
	[KEY_F4, "F4", 5, 0, 1],
	[KEY_F5, "F5", 6.5, 0, 1],
	[KEY_F6, "F6", 7.5, 0, 1],
	[KEY_F7, "F7", 8.5, 0, 1],
	[KEY_F8, "F8", 9.5, 0, 1],
	[KEY_F9, "F9", 11, 0, 1],
	[KEY_F10, "F10", 12, 0, 1],
	[KEY_F11, "F11", 13, 0, 1],
	[KEY_F12, "F12", 14, 0, 1],
	[KEY_QUOTELEFT, "`", 0, 1.25, 1],
	[KEY_1, "1", 1, 1.25, 1],
	[KEY_2, "2", 2, 1.25, 1],
	[KEY_3, "3", 3, 1.25, 1],
	[KEY_4, "4", 4, 1.25, 1],
	[KEY_5, "5", 5, 1.25, 1],
	[KEY_6, "6", 6, 1.25, 1],
	[KEY_7, "7", 7, 1.25, 1],
	[KEY_8, "8", 8, 1.25, 1],
	[KEY_9, "9", 9, 1.25, 1],
	[KEY_0, "0", 10, 1.25, 1],
	[KEY_MINUS, "-", 11, 1.25, 1],
	[KEY_EQUAL, "=", 12, 1.25, 1],
	[KEY_BACKSPACE, "BKSP", 13, 1.25, 2],
	[KEY_TAB, "TAB", 0, 2.25, 1.5],
	[KEY_Q, "Q", 1.5, 2.25, 1],
	[KEY_W, "W", 2.5, 2.25, 1],
	[KEY_E, "E", 3.5, 2.25, 1],
	[KEY_R, "R", 4.5, 2.25, 1],
	[KEY_T, "T", 5.5, 2.25, 1],
	[KEY_Y, "Y", 6.5, 2.25, 1],
	[KEY_U, "U", 7.5, 2.25, 1],
	[KEY_I, "I", 8.5, 2.25, 1],
	[KEY_O, "O", 9.5, 2.25, 1],
	[KEY_P, "P", 10.5, 2.25, 1],
	[KEY_BRACKETLEFT, "[", 11.5, 2.25, 1],
	[KEY_BRACKETRIGHT, "]", 12.5, 2.25, 1],
	[KEY_BACKSLASH, "\\", 13.5, 2.25, 1.5],
	[KEY_CAPSLOCK, "CAPS", 0, 3.25, 1.75],
	[KEY_A, "A", 1.75, 3.25, 1],
	[KEY_S, "S", 2.75, 3.25, 1],
	[KEY_D, "D", 3.75, 3.25, 1],
	[KEY_F, "F", 4.75, 3.25, 1],
	[KEY_G, "G", 5.75, 3.25, 1],
	[KEY_H, "H", 6.75, 3.25, 1],
	[KEY_J, "J", 7.75, 3.25, 1],
	[KEY_K, "K", 8.75, 3.25, 1],
	[KEY_L, "L", 9.75, 3.25, 1],
	[KEY_SEMICOLON, ";", 10.75, 3.25, 1],
	[KEY_APOSTROPHE, "'", 11.75, 3.25, 1],
	[KEY_ENTER, "ENTER", 12.75, 3.25, 2.25],
	[KEY_SHIFT, "SHIFT", 0, 4.25, 2.25],
	[KEY_Z, "Z", 2.25, 4.25, 1],
	[KEY_X, "X", 3.25, 4.25, 1],
	[KEY_C, "C", 4.25, 4.25, 1],
	[KEY_V, "V", 5.25, 4.25, 1],
	[KEY_B, "B", 6.25, 4.25, 1],
	[KEY_N, "N", 7.25, 4.25, 1],
	[KEY_M, "M", 8.25, 4.25, 1],
	[KEY_COMMA, ",", 9.25, 4.25, 1],
	[KEY_PERIOD, ".", 10.25, 4.25, 1],
	[KEY_SLASH, "/", 11.25, 4.25, 1],
	[KEY_SHIFT, "SHIFT", 12.25, 4.25, 2.75],
	[KEY_CTRL, "CTRL", 0, 5.25, 1.25],
	[KEY_META, "WIN", 1.25, 5.25, 1.25],
	[KEY_ALT, "ALT", 2.5, 5.25, 1.25],
	[KEY_SPACE, "", 3.75, 5.25, 6.25],
	[KEY_ALT, "ALT", 10, 5.25, 1.25],
	[KEY_META, "WIN", 11.25, 5.25, 1.25],
	[KEY_MENU, "MENU", 12.5, 5.25, 1.25],
	[KEY_CTRL, "CTRL", 13.75, 5.25, 1.25],
	[KEY_PRINT, "PRT", 15.25, 0, 1],
	[KEY_SCROLLLOCK, "SCR", 16.25, 0, 1],
	[KEY_PAUSE, "PAU", 17.25, 0, 1],
	[KEY_INSERT, "INS", 15.25, 1.25, 1],
	[KEY_HOME, "HOME", 16.25, 1.25, 1],
	[KEY_PAGEUP, "PG UP", 17.25, 1.25, 1],
	[KEY_DELETE, "DEL", 15.25, 2.25, 1],
	[KEY_END, "END", 16.25, 2.25, 1],
	[KEY_PAGEDOWN, "PG DN", 17.25, 2.25, 1],
	[KEY_UP, "^", 16.25, 4.25, 1],
	[KEY_LEFT, "<", 15.25, 5.25, 1],
	[KEY_DOWN, "v", 16.25, 5.25, 1],
	[KEY_RIGHT, ">", 17.25, 5.25, 1],
]
## The mouse: its body, then [button, x, y, width, height].
const MOUSE_BODY := Rect2(18.75, 1.25, 2.5, 4)
const MOUSE := [
	[MOUSE_BUTTON_LEFT, 18.75, 1.25, 1.25, 1.6],
	[MOUSE_BUTTON_RIGHT, 20, 1.25, 1.25, 1.6],
	[MOUSE_BUTTON_MIDDLE, 19.8, 1.6, 0.4, 0.9],
	[MOUSE_BUTTON_XBUTTON2, 18.45, 2.75, 0.3, 0.6],
	[MOUSE_BUTTON_XBUTTON1, 18.45, 3.45, 0.3, 0.6],
]
const SIZE := Vector2(21.25, 6.25)  # key units

const FREE_KEY := Color(0.16, 0.16, 0.16)
const FREE_EDGE := Color(1, 1, 1, 0.12)
const FREE_LEGEND := Color(1, 1, 1, 0.5)
const INK := Color(0.06, 0.06, 0.06)  # a lit key's legend (KeycapTexture's)
const BADGE := Color(0.075, 0.075, 0.075)
const MOUSE_FILL := Color(1, 1, 1, 0.03)
# in key units
const INSET := 0.06  # each key is drawn this much inside its cell
const RADIUS := 0.12
const LEGEND := 0.3  # the legend's font size
const LEGEND_PAD := 0.07  # a legend keeps this far from the key's sides
const BADGE_R := 0.19
const BADGE_AT := 0.2  # the badge's centre, from the key's top-right corner
const BADGE_FONT := 0.26
const NUDGE := 0.08  # a badged key's legend moves this far left (and down)
const MOUSE_RADIUS := 1.1
const MIN_FONT := 6
const PULSE_RATE := 5.0

static var _placed := {}  # every spec drawn (KEYS and MOUSE) -> true

## UNIT_COMPACT, no badges, no legends on free keys.
var compact := false:
	set(v):
		compact = v
		refresh()
## Hover tooltips, a white frame on the key under the mouse, and key_clicked.
var interactive := false:
	set(v):
		interactive = v
		mouse_filter = Control.MOUSE_FILTER_STOP if v else Control.MOUSE_FILTER_IGNORE
		queue_redraw()
## Badges with the action's number (ignored when compact).
var numbered := true:
	set(v):
		numbered = v
		queue_redraw()
## This action's keys white, the other lit keys dimmed ("" = none): the table's focused action.
var highlight_action := "":
	set(v):
		highlight_action = v
		queue_redraw()
## This key or button pulses: the spec of a slot that is listening ("" = none).
var pulse_spec := "":
	set(v):
		pulse_spec = v
		_t = 0.0
		set_process(v != "")
		queue_redraw()
## {} = the player's keyboard slots (InputBindings.slots(action, KEY)); previews and tests may pass
## {action: [specs]}.
var binds := {}:
	set(v):
		binds = v
		refresh()
## While hidden, only note that the prompts changed and catch up when shown (the pause panel's
## keyboard: hidden the whole race).
var lazy := false

var _lit := {}  # spec -> the index in InputBindings.ACTIONS of the action it is bound to
var _off := Vector2.ZERO  # the picture is centred in the control
var _hover := ""  # the spec under the mouse
var _box := StyleBoxFlat.new()
var _t := 0.0
var _stale := false  # lazy: the prompts changed while it was hidden


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.anti_aliasing = true
	set_process(false)
	resized.connect(_place)
	refresh()


func _enter_tree() -> void:
	if not InputPrompts.prompts_changed.is_connected(_on_prompts):
		InputPrompts.prompts_changed.connect(_on_prompts)
	refresh()


func _exit_tree() -> void:
	if InputPrompts.prompts_changed.is_connected(_on_prompts):
		InputPrompts.prompts_changed.disconnect(_on_prompts)


func _on_prompts() -> void:
	if lazy and is_inside_tree() and not is_visible_in_tree():
		_stale = true
		return
	refresh()


# ---------------------------------------------------------------- API
## Reads the bindings again and redraws.
func refresh() -> void:
	_stale = false
	_lit.clear()
	var b := _binds()
	for i in InputBindings.ACTIONS.size():
		for spec in b.get(InputBindings.ACTIONS[i], []):
			if str(spec) != "":
				_lit[str(spec)] = i
	custom_minimum_size = (SIZE * _unit()).ceil()
	_place()
	queue_redraw()


## Where a key or mouse spec is drawn, in this control's pixels (the left one of a pair); Rect2()
## when it is not on the picture.
func key_rect(spec: String) -> Rect2:
	var u := _unit()
	for k in KEYS:
		if InputBindings.key_spec(k[0]) == spec:
			return Rect2(_off + Vector2(k[2], k[3]) * u, Vector2(k[4], 1.0) * u)
	for m in MOUSE:
		if "m%d" % m[0] == spec:
			return Rect2(_off + Vector2(m[1], m[2]) * u, Vector2(m[3], m[4]) * u)
	return Rect2()


## Bound keyboard and mouse slots the picture has no key for: [[action, slot, spec]]. {} = the
## player's bindings.
static func unplaced(bind_map: Dictionary) -> Array:
	var out := []
	var mine := InputBindings.all_slots(InputBindings.KEY) if bind_map.is_empty() else {}
	for act in InputBindings.ACTIONS:
		var slots: Array = bind_map.get(act, []) if not bind_map.is_empty() else mine.get(act, [])
		for i in slots.size():
			var spec := str(slots[i])
			if spec != "" and not placed(spec):
				out.append([act, i, spec])
	return out


## The picture has a key or a mouse button for this spec.
static func placed(spec: String) -> bool:
	if _placed.is_empty():
		for k in KEYS:
			_placed[InputBindings.key_spec(k[0])] = true
		for m in MOUSE:
			_placed["m%d" % m[0]] = true
	return _placed.has(spec)


## The spec drawn under `p` ("" = none).
func spec_at(p: Vector2) -> String:
	var u := _unit()
	for m in MOUSE:
		if Rect2(_off + Vector2(m[1], m[2]) * u, Vector2(m[3], m[4]) * u).has_point(p):
			return "m%d" % m[0]
	for k in KEYS:
		if Rect2(_off + Vector2(k[2], k[3]) * u, Vector2(k[4], 1.0) * u).has_point(p):
			return InputBindings.key_spec(k[0])
	return ""


# ---------------------------------------------------------------- inside
func _unit() -> float:
	return UNIT_COMPACT if compact else UNIT_FULL


func _binds() -> Dictionary:
	return binds if not binds.is_empty() else InputBindings.all_slots(InputBindings.KEY)


func _place() -> void:
	_off = ((size - SIZE * _unit()) * 0.5).floor().max(Vector2.ZERO)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var u := _unit()
	var font := UiKit.font(true)
	for k in KEYS:
		var r := Rect2(_off + Vector2(k[2], k[3]) * u, Vector2(k[4], 1.0) * u).grow(-INSET * u)
		var radii := [RADIUS * u, RADIUS * u, RADIUS * u, RADIUS * u]
		_draw_key(r, InputBindings.key_spec(k[0]), _legend(k[0], k[1]), int(k[0]), radii, font, u)
	# the mouse: its body, then its buttons lit like keys (the big ones follow the body's round top)
	var body := Rect2(_off + MOUSE_BODY.position * u, MOUSE_BODY.size * u)
	var br := minf(MOUSE_RADIUS * u, body.size.x * 0.5)
	_box.bg_color = MOUSE_FILL
	_box.border_color = UiKit.NOB
	_box.set_border_width_all(2)
	_box.set_corner_radius_all(int(br))
	draw_style_box(_box, body)
	for m in MOUSE:
		var r := Rect2(_off + Vector2(m[1], m[2]) * u, Vector2(m[3], m[4]) * u).grow(-INSET * u)
		var small := minf(r.size.x, r.size.y) * 0.5
		var c := minf(RADIUS * u, small)
		var radii := [c, c, c, c]  # top-left, top-right, bottom-right, bottom-left
		if m[0] == MOUSE_BUTTON_LEFT:
			radii[0] = br - INSET * u
		elif m[0] == MOUSE_BUTTON_RIGHT:
			radii[1] = br - INSET * u
		elif m[0] == MOUSE_BUTTON_MIDDLE:
			radii = [small, small, small, small]
		_draw_key(r, "m%d" % m[0], "", 0, radii, font, u)


## One key (or mouse button): free, lit, the highlighted action's, pulsing or under the mouse.
func _draw_key(r: Rect2, spec: String, legend: String, code: int, radii: Array, font: Font, u: float) -> void:
	var idx: int = _lit.get(spec, -1)
	var lit := idx >= 0
	var fill := FREE_KEY
	var ink := FREE_LEGEND
	var edge := FREE_EDGE
	var bw := 1
	if lit:
		ink = INK
		edge = Color(0, 0, 0, 0)
		bw = 0
		fill = UiKit.ORANGE
		if highlight_action != "":
			fill = Color.WHITE if InputBindings.ACTIONS[idx] == highlight_action else Color(UiKit.ORANGE, 0.45)
	if spec == pulse_spec:
		fill.a *= 0.55 + 0.45 * absf(sin(_t * PULSE_RATE))
	if interactive and spec == _hover:
		edge = Color.WHITE if lit else Color(1, 1, 1, 0.35)
		bw = 2 if lit else 1
	_box.bg_color = fill
	_box.border_color = edge
	_box.set_border_width_all(bw)
	_box.corner_radius_top_left = int(radii[0])
	_box.corner_radius_top_right = int(radii[1])
	_box.corner_radius_bottom_right = int(radii[2])
	_box.corner_radius_bottom_left = int(radii[3])
	draw_style_box(_box, r)
	var badge := lit and numbered and not compact
	var nudge := Vector2(-NUDGE * u, NUDGE * u) if badge and legend != "" else Vector2.ZERO
	if lit or not compact:
		if code in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			_draw_arrow(r.get_center() + nudge, code, ink, u)
		elif legend != "":
			_draw_legend(r, legend, r.get_center() + nudge, ink, font, u, badge)
	if badge:
		_draw_badge(_badge_centre(r, spec, u), str(idx + 1), font, u)


## A key's legend centred on `c`, as big as LEGEND allows and the key's width takes; two words that
## would have to shrink a lot ("PG DN") go on two lines instead. A badged key's legend sits NUDGE
## left of the centre: it keeps that much more from the left edge ("END"), and two lines keep
## clear of the badge too ("PG DN").
func _draw_legend(r: Rect2, legend: String, c: Vector2, ink: Color, font: Font, u: float, badged := false) -> void:
	var fs := roundi(LEGEND * u)
	var room := r.size.x - 2.0 * LEGEND_PAD * u - (2.0 * NUDGE * u if badged else 0.0)
	var lines := PackedStringArray([legend])
	var one := _fit(font, legend, fs, room)
	if legend.contains(" ") and one < fs * 0.85:
		var two := legend.split(" ", false, 1)
		var room2 := room - (BADGE_R * u if badged else 0.0)
		var fit2 := mini(_fit(font, two[0], fs, room2), _fit(font, two[1], fs, room2))
		if fit2 > one:
			lines = two
			one = fit2
	fs = one
	var gap := fs * 1.05  # between two lines' baselines
	var base := c.y + fs * 0.36 - gap * 0.5 * (lines.size() - 1)
	for i in lines.size():
		var tw := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(c.x - tw * 0.5, base + gap * i).round(), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


## The font size (at most `fs`, at least MIN_FONT) at which `text` is no wider than `room`.
static func _fit(font: Font, text: String, fs: int, room: float) -> int:
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return fs if tw <= room else maxi(floori(fs * room / tw), MIN_FONT)


## Where a key's number goes: its top-right corner; on the mouse, inside the big buttons, under the
## wheel and beside the side buttons (too small to carry it).
func _badge_centre(r: Rect2, spec: String, u: float) -> Vector2:
	if spec.begins_with("m"):
		var mb := int(spec.substr(1))
		if mb == MOUSE_BUTTON_LEFT or mb == MOUSE_BUTTON_RIGHT:
			return r.get_center() + Vector2(0, 0.2 * u)
		if mb == MOUSE_BUTTON_MIDDLE:
			return Vector2(r.get_center().x, r.end.y + (BADGE_R + 0.08) * u)
		return Vector2(r.end.x + (BADGE_R + 0.12) * u, r.get_center().y)
	return Vector2(r.end.x - (BADGE_AT - INSET) * u, r.position.y + (BADGE_AT - INSET) * u)


## A disc with the action's number; a capsule as wide as a two-digit one ("10": CHAT) needs.
func _draw_badge(c: Vector2, n: String, font: Font, u: float) -> void:
	var fs := maxi(roundi(BADGE_FONT * u), MIN_FONT)
	var tw := font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var rad := BADGE_R * u
	var half := maxf(tw * 0.5 + 0.07 * u - rad, 0.0)  # how far each round end sits from the centre
	if half > 0.0:
		c.x -= half  # (it grows to the left, into the key, so it never leaves the key's corner)
		draw_rect(Rect2(c.x - half, c.y - rad, 2.0 * half, 2.0 * rad), BADGE)
		draw_circle(Vector2(c.x - half, c.y), rad, BADGE, true, -1.0, true)
		draw_circle(Vector2(c.x + half, c.y), rad, BADGE, true, -1.0, true)
	else:
		draw_circle(c, rad, BADGE, true, -1.0, true)
	draw_string(font, Vector2(c.x - tw * 0.5, c.y + fs * 0.36).round(), n, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


## An arrow key's legend: a small filled triangle pointing its way.
func _draw_arrow(c: Vector2, code: int, col: Color, u: float) -> void:
	var a := 0.15 * u  # half the base
	var h := 0.24 * u  # height
	var pts := PackedVector2Array([Vector2(0, -h * 0.55), Vector2(a, h * 0.45), Vector2(-a, h * 0.45)])
	var turn := {KEY_UP: 0.0, KEY_RIGHT: PI * 0.5, KEY_DOWN: PI, KEY_LEFT: -PI * 0.5}[code] as float
	for i in pts.size():
		pts[i] = c + pts[i].rotated(turn)
	draw_colored_polygon(pts, col)
	# (polygons are not antialiased: a thin smooth outline softens the edges)
	var ring := pts.duplicate()
	ring.append(pts[0])
	draw_polyline(ring, col, 1.0, true)


## A key's legend: letters and digits as the player's layout labels them, the rest from KEYS.
func _legend(code: int, table: String) -> String:
	if (code >= KEY_A and code <= KEY_Z) or (code >= KEY_0 and code <= KEY_9):
		var t := InputPrompts.spec_text(InputBindings.key_spec(code), InputPrompts.KEYBOARD)
		return t if t != "" and t.length() <= 2 else table
	return table


# ---------------------------------------------------------------- the mouse over it
func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseMotion:
		var s := spec_at((event as InputEventMouseMotion).position)
		if s != _hover:
			_hover = s
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _lit.has(s) else Control.CURSOR_ARROW
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var s := spec_at(mb.position)
			if _lit.has(s):
				accept_event()
				key_clicked.emit(s)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != "":
		_hover = ""
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		queue_redraw()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and _stale and is_visible_in_tree():
		refresh()


func _get_tooltip(at_position: Vector2) -> String:
	if not interactive:
		return ""
	var s := spec_at(at_position)
	if s == "":
		return ""
	var name_ := InputPrompts.spec_text(s, InputPrompts.KEYBOARD)
	if not _lit.has(s):
		return "%s: free" % name_
	return "%s: %s" % [name_, str(InputBindings.TITLES[InputBindings.ACTIONS[_lit[s]]]).to_upper()]
