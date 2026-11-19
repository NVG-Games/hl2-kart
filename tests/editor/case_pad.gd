extends RefCounted
## editor/case_pad (P8, CI): first the mouse camera (1.4): RMB look 0.15 deg/px, the wheel's speed
## while looking, RMB + W flies, the wheel dollies 12 % toward the cursor's point, MMB pans, Alt +
## LMB orbits at the same distance, the top view and back, F framing into the free area. Then
## the pad's FLY (1.10) with a synthetic device-1 joypad sent through
## Input.parse_input_event (InputPrompts makes it the active pad, as a real one). The left stick
## flies the camera and the right stick turns it (axes read for InputPrompts.active_pad()), the
## floor clamp holds, the D-pad changes the speed and the tool, A / X / Y call test_drive with
## "here" (at the free area's centre) / "start" / "watch", Back and Start ask for help and the menu;
## the GUI focus is let go and stays empty, InputPrompts' safety net never sees a pad event (it does
## once the camera stops taking them), a Dialog on top gets the pad, the reticle shows only while
## the pad flies.

const NEEDS_CONTENT := false
const Sel := preload("res://tests/editor/case_select.gd")
const DEV := 1


func run(t: Node) -> void:
	var doc: LevelDoc = Sel.test_doc()
	var ed: TrackEditor = await Sel.open_editor(t, doc)
	ed.set_tool("select")
	var cam := ed.camera
	var net := NetProbe.new()
	t.get_tree().root.add_child(net)
	var calls := []
	var cmds := []
	cam.on_drive = func(from: String, screen: Vector2) -> void: calls.append([from, screen])
	cam.pad_command.connect(func(what: String) -> void: cmds.append(what))
	await _mouse_camera(t, ed)
	# the pad wakes: InputPrompts makes device 1 the active pad
	await _button(t, JOY_BUTTON_LEFT_STICK, true)
	await _button(t, JOY_BUTTON_LEFT_STICK, false)
	t.check(InputPrompts.using_pad() and InputPrompts.active_pad() == DEV, "a device-1 pad press makes it the active pad")
	t.check(cam.flying() and cam.reticle_shown(), "the editor flies by pad, the reticle shows")
	# fly forward with the left stick
	cam.go_to(Transform3D(Basis.from_euler(Vector3(deg_to_rad(-20.0), 0.0, 0.0)), Vector3(0, 40, 60)))
	var p0 := cam.global_position
	var f0 := -cam.global_basis.z
	await _axis(t, JOY_AXIS_LEFT_Y, -1.0, 8)
	var moved := cam.global_position - p0
	await _axis(t, JOY_AXIS_LEFT_Y, 0.0, 1)
	t.check(moved.dot(f0) > 0.01 and absf(moved.normalized().dot(f0)) > 0.95, "the left stick flies forward (%.3f m)" % moved.length())
	var still := cam.global_position
	await t.frames(3)
	t.check(cam.global_position.is_equal_approx(still), "a stick at rest does not fly")
	# turn with the right stick
	var yaw0 := cam.global_basis.get_euler().y
	await _axis(t, JOY_AXIS_RIGHT_X, 1.0, 6)
	await _axis(t, JOY_AXIS_RIGHT_X, 0.0, 1)
	t.check(cam.global_basis.get_euler().y < yaw0 - 1e-4, "the right stick turns the camera right")
	t.check(EditorCamera.curve(0.15) == 0.0 and absf(EditorCamera.curve(0.6) - 0.25) < 1e-6 and EditorCamera.curve(-1.0) == -1.0,
		"dead zone 0.2, then x^2 of the rest")
	# the floor clamp: never below the terrain + 0.5 m
	cam.go_to(Transform3D(Basis.from_euler(Vector3(deg_to_rad(-60.0), 0.0, 0.0)), Vector3(0, 1.0, 0)))
	await _axis(t, JOY_AXIS_LEFT_Y, -1.0, 8)
	await _axis(t, JOY_AXIS_LEFT_Y, 0.0, 1)
	t.check(cam.global_position.y >= 0.5 - 1e-4, "flying into the ground stops 0.5 m above it (y %.2f)" % cam.global_position.y)
	# D-pad: speed and tool
	var sp := cam.speed
	await _press(t, JOY_BUTTON_DPAD_UP)
	t.check(absf(cam.speed - sp * 1.25) < 1e-3, "D-pad up: fly speed x1.25 (%.1f)" % cam.speed)
	await _press(t, JOY_BUTTON_DPAD_DOWN)
	t.check(absf(cam.speed - sp) < 1e-3, "D-pad down: back")
	await _press(t, JOY_BUTTON_DPAD_RIGHT)
	t.check(ed.tool.id == "road", "D-pad right: the next tool (%s)" % ed.tool.id)
	await _press(t, JOY_BUTTON_DPAD_LEFT)
	await _press(t, JOY_BUTTON_DPAD_LEFT)
	t.check(ed.tool.id == "world", "D-pad left twice: back past SELECT to WORLD (%s)" % ed.tool.id)
	ed.set_tool("select")
	# the focus is let go and stays empty; the safety net never fires
	var btn := Button.new()
	btn.text = "X"
	btn.focus_mode = Control.FOCUS_ALL
	ed.get_node("UI").add_child(btn)
	btn.grab_focus()
	await t.frames(1)
	net.calls = 0
	await _press(t, JOY_BUTTON_DPAD_DOWN)
	await _press(t, JOY_BUTTON_DPAD_UP)
	t.check(ed.get_viewport().gui_get_focus_owner() == null, "a pad press in FLY lets the GUI focus go")
	await _press(t, JOY_BUTTON_DPAD_DOWN)
	await _press(t, JOY_BUTTON_A)
	t.check(ed.get_viewport().gui_get_focus_owner() == null and net.calls == 0, "the focus stays empty and the safety net never fires (%d)" % net.calls)
	cam.set_process_input(false)
	await _press(t, JOY_BUTTON_DPAD_DOWN)
	cam.set_process_input(true)
	t.check(net.calls >= 1, "(the probe works: without the camera taking pad events the safety net fires, %d)" % net.calls)
	await _press(t, JOY_BUTTON_DPAD_UP)
	# A / X / Y drive, Back / Start ask
	calls.clear()
	cmds.clear()
	await _press(t, JOY_BUTTON_A)
	await _press(t, JOY_BUTTON_X)
	await _press(t, JOY_BUTTON_Y)
	var froms := calls.map(func(c: Array) -> String: return c[0])
	t.check(froms == ["here", "start", "watch"], "A / X / Y: test drive from here / the start / watch a bot (%s)" % str(froms))
	t.check(calls.size() == 3 and (calls[0][1] as Vector2).is_equal_approx(ed.free_center()), "FROM HERE drives from the free area's centre (the reticle)")
	await _press(t, JOY_BUTTON_BACK)
	await _press(t, JOY_BUTTON_START)
	t.check(cmds.slice(-2) == ["help", "menu"], "Back asks for help, Start for the EDITOR MENU (%s)" % str(cmds))
	# a Dialog on top owns the pad
	var dlg := Dialog.new("TEST", Vector2(400, 200))
	dlg.add_button("OK", func() -> void: pass)
	ed.get_node("UI").add_child(dlg)
	await t.frames(1)
	calls.clear()
	await _press(t, JOY_BUTTON_X)
	t.check(not cam.flying() and calls.is_empty(), "with a Dialog on top the pad is the Dialog's")
	dlg.queue_free()
	btn.queue_free()
	await t.frames(2)
	t.check(cam.flying(), "and FLY is back when it closes")
	# the keyboard takes over: no FLY, no reticle
	var k := InputEventKey.new()
	k.keycode = KEY_F12
	k.physical_keycode = KEY_F12
	k.pressed = true
	Input.parse_input_event(k)
	await t.frames(2)
	k = k.duplicate()
	k.pressed = false
	Input.parse_input_event(k)
	await t.frames(2)
	t.check(not InputPrompts.using_pad() and not cam.flying() and not cam.reticle_shown(), "a key press ends FLY and hides the reticle")
	net.queue_free()
	await Sel.close_editor(t, ed)


func _mouse_camera(t: Node, ed: TrackEditor) -> void:
	var cam := ed.camera
	cam.go_to(Transform3D(Basis.from_euler(Vector3(deg_to_rad(-30.0), 0.0, 0.0)), Vector3(0, 50, 100)))
	t.check(cam.fly_input(_mb(MOUSE_BUTTON_RIGHT, true, Vector2(700, 400))) and cam.drag == "look", "RMB starts the look")
	var e0 := cam.global_basis.get_euler()
	cam.fly_input(_mm(Vector2(100, -40)))
	var e1 := cam.global_basis.get_euler()
	t.check(absf(rad_to_deg(e1.y - e0.y) + 15.0) < 0.01 and absf(rad_to_deg(e1.x - e0.x) - 6.0) < 0.01, "0.15 deg per px: 100 px right turns 15 deg, 40 px up 6 deg")
	var sp := cam.speed
	cam.fly_input(_mb(MOUSE_BUTTON_WHEEL_UP, true, Vector2(700, 400)))
	t.check(absf(cam.speed - sp * 1.25) < 1e-3, "the wheel while looking: fly speed x1.25")
	cam.set_speed(sp)
	var p0 := cam.global_position
	var f := -cam.global_basis.z
	Input.action_press("ed_forward")
	await t.frames(4)
	Input.action_release("ed_forward")
	t.check((cam.global_position - p0).dot(f) > 0.001, "RMB + W flies forward")
	t.check(cam.fly_input(_mb(MOUSE_BUTTON_RIGHT, false, Vector2(700, 400))) and cam.drag == "", "RMB up ends the look")
	# the wheel dollies 12 % toward the point under the cursor
	cam.go_to(Transform3D(Basis.from_euler(Vector3(deg_to_rad(-30.0), 0.0, 0.0)), Vector3(0, 50, 100)))
	var sc := cam.unproject_position(Vector3(0, 0, 20))
	var aim := cam._pick_point(sc, false)
	var d0 := cam.global_position.distance_to(aim)
	cam.fly_input(_mb(MOUSE_BUTTON_WHEEL_UP, true, sc))
	var d1 := cam.global_position.distance_to(aim)
	t.check(absf(d1 - d0 * 0.88) < 0.05 and cam.unproject_position(aim).distance_to(sc) < 1.0, "a wheel notch dollies 12 %% toward the cursor's point (%.1f -> %.1f m)" % [d0, d1])
	# MMB pans in the camera plane: metres per px = distance x 0.0015
	var p1 := cam.global_position
	cam.fly_input(_mb(MOUSE_BUTTON_MIDDLE, true, sc))
	var dist := cam._dist
	cam.fly_input(_mm(Vector2(50, 0)))
	cam.fly_input(_mb(MOUSE_BUTTON_MIDDLE, false, sc))
	var pan := cam.global_position - p1
	t.check(absf(pan.dot(-cam.global_basis.x) - 50.0 * dist * EditorCamera.PAN_PER_PX) < 0.01 and cam.drag == "", "MMB drag pans (%.2f m for 50 px)" % pan.length())
	# Alt + LMB orbits round the point under the cursor
	var alt := _mb(MOUSE_BUTTON_LEFT, true, sc)
	alt.alt_pressed = true
	t.check(cam.fly_input(alt) and cam.drag == "orbit", "Alt + LMB starts an orbit")
	var piv := cam._pivot
	var r0 := cam.global_position.distance_to(piv)
	var y0 := cam.global_basis.get_euler().y
	cam.fly_input(_mm(Vector2(120, 30)))
	alt = _mb(MOUSE_BUTTON_LEFT, false, sc)
	alt.alt_pressed = true
	cam.fly_input(alt)
	t.check(absf(cam.global_position.distance_to(piv) - r0) < 0.01 and absf(cam.global_basis.get_euler().y - y0) > 0.1 and cam.drag == "",
		"the orbit keeps its distance to the pivot")
	# TOP VIEW and back
	var before := cam.global_transform
	cam.toggle_top(Vector3(10, 0, 10))
	t.check(cam.top and cam.projection == Camera3D.PROJECTION_ORTHOGONAL and cam.global_basis.z.dot(Vector3.UP) > 0.999
		and Vector2(cam.global_position.x, cam.global_position.z).distance_to(Vector2(10, 10)) < 0.01, "T: orthographic, straight down over the point")
	var size0 := cam.size
	cam.fly_input(_mb(MOUSE_BUTTON_WHEEL_UP, true, Vector2(800, 450)))
	t.check(absf(cam.size - size0 * EditorCamera.TOP_ZOOM) < 0.01, "the wheel zooms the top view")
	cam.toggle_top(Vector3.ZERO)
	t.check(not cam.top and cam.projection == Camera3D.PROJECTION_PERSPECTIVE and cam.global_transform.is_equal_approx(before), "T again: back to the perspective view")
	# F: the box centred in the free area, filling 60 % of it
	var box := AABB(Vector3(90, 0, -40), Vector3(20, 4, 20))
	cam.frame(box, ed.free_rect())
	var at := cam.unproject_position(box.get_center())
	var r := box.size.length() * 0.5
	var span := cam.unproject_position(box.get_center() + cam.global_basis.y * r).distance_to(at) * 2.0
	var m := minf(ed.free_rect().size.x, ed.free_rect().size.y)
	t.check(at.distance_to(ed.free_center()) < 2.0 and absf(span / m - EditorCamera.FRAME_FILL) < 0.03, "F frames the box at the free area's centre, %.0f %% of it" % (span / m * 100.0))


func _mb(b: MouseButton, down: bool, at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = down
	e.position = at
	return e


func _mm(rel: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.relative = rel
	e.screen_relative = rel
	e.position = Vector2(700, 400) + rel
	return e


func _button(t: Node, b: JoyButton, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = DEV
	e.button_index = b
	e.pressed = down
	e.pressure = 1.0 if down else 0.0
	Input.parse_input_event(e)
	await t.frames(2)


func _press(t: Node, b: JoyButton) -> void:
	await _button(t, b, true)
	await _button(t, b, false)


func _axis(t: Node, axis: JoyAxis, v: float, frames: int) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = DEV
	e.axis = axis
	e.axis_value = v
	Input.parse_input_event(e)
	await t.frames(frames)


## A screen in InputPrompts.SCREEN_GROUP that counts the safety net's calls (and takes nothing).
class NetProbe:
	extends Control
	var calls := 0

	func _init() -> void:
		add_to_group(InputPrompts.SCREEN_GROUP)

	func focus_default() -> bool:
		calls += 1
		return false
