class_name EditorNumber
extends LineEdit
## A number field: type a value, drag sideways, the wheel or Up / Down while it has the focus
## (Shift: ten steps); changed(value, final). A drag sends final false while it runs and final
## true at its end; a typed value, a wheel notch and an arrow press send final true. P10.

signal changed(value: float, final: bool)

var value := 0.0
var min_value := -1.0e9
var max_value := 1.0e9
var step := 0.1
var fmt := "%.1f"
var suffix := ""
## Shown before the value ("X ").
var prefix := ""
## Pixels of mouse travel per step while dragging.
var px_per_step := 4.0
## A multi-selection whose values differ: shows "-" until changed.
var mixed := false

const DRAG_PX := 3.0

var _press := Vector2(-1, -1)
var _drag := false
var _drag_from := 0.0
var _typing := false


func _init() -> void:
	theme_type_variation = "EdNumber"
	alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mouse_default_cursor_shape = Control.CURSOR_HSIZE
	custom_minimum_size = Vector2(64, EditorKit.ROW_H - 4)
	context_menu_enabled = false
	select_all_on_focus = true
	# no focus until a click without a drag: a press must not start typing (the drag needs it)
	focus_mode = Control.FOCUS_NONE
	text_submitted.connect(func(_t: String) -> void:
		_commit_text()
		release_focus())
	focus_exited.connect(func() -> void:
		focus_mode = Control.FOCUS_NONE
		if _typing:
			_commit_text())
	focus_entered.connect(func() -> void:
		_typing = true
		text = "" if mixed else _num(value))


## Sets the value (clamped, snapped); emit: sends changed(value, true) when it differs.
func set_value(v: float, emit := true) -> void:
	var nv := _clean(v)
	var differs := not is_equal_approx(nv, value) or mixed
	value = nv
	mixed = false
	_show()
	if emit and differs:
		changed.emit(value, true)


## Shows "-" (values differ across the selection).
func set_mixed(on := true) -> void:
	mixed = on
	_show()


func _clean(v: float) -> float:
	if is_nan(v) or is_inf(v):
		v = value
	if step > 0.0:
		v = snappedf(v, step)
	return clampf(v, min_value, max_value)


func _num(v: float) -> String:
	return fmt % v


func _show() -> void:
	if has_focus() and _typing:
		return
	text = prefix + ("-" if mixed else _num(value) + suffix)


func _commit_text() -> void:
	_typing = false
	var t := text.strip_edges().trim_prefix(prefix.strip_edges()).strip_edges()
	if suffix != "":
		t = t.trim_suffix(suffix.strip_edges()).strip_edges()
	t = t.replace(",", ".")
	if t.is_valid_float() or t.is_valid_int():
		set_value(t.to_float(), true)
	_show()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and not (has_focus() and _typing):
				_press = mb.position
				_drag = false
				_drag_from = value
				accept_event()
			elif not mb.pressed and _press.x >= 0.0:
				_press = Vector2(-1, -1)
				accept_event()
				if _drag:
					_drag = false
					changed.emit(value, true)
				else:
					# a click without a drag: type a value
					focus_mode = Control.FOCUS_CLICK
					grab_focus()
					if has_method("edit"):
						call("edit")
					select_all()
			return
		if mb.pressed and has_focus() and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_nudge(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1, mb.shift_pressed)
			accept_event()
	elif ev is InputEventMouseMotion and _press.x >= 0.0:
		var mm := ev as InputEventMouseMotion
		var dx := mm.position.x - _press.x
		if not _drag and absf(dx) >= DRAG_PX:
			_drag = true
		if _drag:
			var k := 10.0 if mm.shift_pressed else (0.1 if mm.ctrl_pressed else 1.0)
			var nv := _clean(_drag_from + roundf(dx / px_per_step) * step * k)
			if not is_equal_approx(nv, value) or mixed:
				value = nv
				mixed = false
				_show()
				changed.emit(value, false)
		accept_event()
	elif ev is InputEventKey and ev.is_pressed() and has_focus():
		var k := ev as InputEventKey
		if k.keycode == KEY_UP or k.keycode == KEY_DOWN:
			_nudge(1 if k.keycode == KEY_UP else -1, k.shift_pressed)
			accept_event()


func _nudge(dir: int, ten: bool) -> void:
	_typing = false
	set_value(value + dir * step * (10.0 if ten else 1.0), true)
	_typing = true
	text = _num(value)
	select_all()


## A drag is running (the inspector waits with its rebuild).
func dragging() -> bool:
	return _drag
