class_name EditorCamera
extends Camera3D
## The editor's fly camera (1.4): RMB look and fly (W A S D, Q / E, Shift x4, Ctrl x0.25, the wheel
## changes the speed), the wheel dollies toward the point under the cursor, MMB pans, Alt + LMB
## orbits, Alt + RMB dollies; every drag captures the mouse and warps it back where the press
## began (C1 N4). T: an orthographic top view and back. F / Shift+F frame into the free area.
## The camera never flies below the terrain + 0.5 m. The pad's FLY (1.10): left stick flies, right
## stick looks, LT / RT down / up, L3 x4, D-pad speed and tool, A / X / Y test drives, Back help,
## Start the EDITOR MENU; pad events are taken in _input (neither the GUI nor InputPrompts' safety
## net see them) and the GUI focus is let go, unless a Dialog is on top. Axes are read for
## InputPrompts.active_pad() (C1 N7). P8.

## A pad press in FLY: "here", "start", "watch", "help", "menu", "faster", "slower", "prev_tool",
## "next_tool".
signal pad_command(what: String)

const LOOK_DEG_PER_PX := 0.15
const PITCH_MAX := 89.0
const SPEED_MIN := 2.0
const SPEED_MAX := 400.0
const SPEED_STEP := 1.25
const FAST := 4.0
const SLOW := 0.25
## A wheel notch dollies this share of the distance to the point under the cursor (at least DOLLY_MIN).
const DOLLY := 0.12
const DOLLY_MIN := 0.5
## MMB pan: metres per px = distance to the pivot x this.
const PAN_PER_PX := 0.0015
## Alt + RMB: metres per px = distance to the pivot x this.
const ALT_DOLLY_PER_PX := 0.005
const FLOOR := 0.5
## F: the box fills this share of the free area.
const FRAME_FILL := 0.6
const PAD_DEADZONE := 0.2
const PAD_LOOK_DEG := 180.0
const TOP_ZOOM := 0.88
const TOP_HEIGHT := 2000.0
const TOP_SIZE_MIN := 5.0
const TOP_SIZE_MAX := 12000.0
## A new track's view (1.4).
const DEFAULT_PITCH := 50.0
const GHOST_EVERY := 0.15
const ORANGE := Color8(255, 155, 0)

var speed := 30.0
var top := false
## The TrackEditor (the parent in editor.tscn; null on a bare camera).
var editor: TrackEditor
## Tests: called as on_drive(from, screen) in place of editor.test_drive by the pad's A / X / Y.
var on_drive := Callable()
## The mouse drag running: "" | "look" | "pan" | "orbit" | "dolly".
var drag := ""

var _btn := MOUSE_BUTTON_NONE
var _press_pos := Vector2.ZERO
var _pivot := Vector3.ZERO
var _dist := 30.0
var _captured := false
var _lost := 0
var _persp_xf := Transform3D()
var _flying := false
var _layer: CanvasLayer
var _reticle: Control
var _ghost: MeshInstance3D
var _ghost_t := 0.0


func _ready() -> void:
	if editor == null:
		editor = get_parent() as TrackEditor
	_layer = CanvasLayer.new()
	_layer.name = "PadReticle"
	_layer.layer = 9
	add_child(_layer)
	_reticle = Reticle.new()
	(_reticle as Reticle).cam = self
	_reticle.visible = false
	_layer.add_child(_reticle)


func _exit_tree() -> void:
	if _captured:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_captured = false


# ---------------------------------------------------------------- the mouse

## RMB look, MMB pan, Alt orbit, wheel; captures + warps the mouse. True when the event was the
## camera's.
func fly_input(ev: InputEvent) -> bool:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if not mb.pressed:
					return false
				var n := 1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1
				if drag == "look":
					set_speed(speed * pow(SPEED_STEP, n))
				elif top:
					_zoom_top(mb.position, n)
				else:
					_dolly_to(mb.position, n)
				return true
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					if drag == "":
						_start("dolly" if mb.alt_pressed and not top else ("pan" if top else "look"), mb)
					return true
				if _btn == MOUSE_BUTTON_RIGHT:
					_end()
					return true
			MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					if drag == "":
						_start("pan", mb)
					return true
				if _btn == MOUSE_BUTTON_MIDDLE:
					_end()
					return true
			MOUSE_BUTTON_LEFT:
				if mb.pressed and mb.alt_pressed and drag == "":
					if top or _over_gizmo(mb.position):
						return false
					_start("orbit", mb)
					return true
				if not mb.pressed and _btn == MOUSE_BUTTON_LEFT:
					_end()
					return true
		return false
	if ev is InputEventMouseMotion and drag != "":
		_motion(ev as InputEventMouseMotion)
		return true
	return false


func set_speed(v: float) -> void:
	speed = clampf(v, SPEED_MIN, SPEED_MAX)
	Game.settings["editor_cam_speed"] = speed


func _start(mode: String, mb: InputEventMouseButton) -> void:
	drag = mode
	_btn = mb.button_index
	_press_pos = mb.position
	_lost = 0
	if mode != "look":
		_pivot = _pick_point(mb.position, mode == "orbit")
		_dist = maxf(global_position.distance_to(_pivot), 1.0)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_captured = true


func _end() -> void:
	drag = ""
	_btn = MOUSE_BUTTON_NONE
	if _captured:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_captured = false
		if is_inside_tree():
			get_viewport().warp_mouse(_press_pos)


func _motion(mm: InputEventMouseMotion) -> void:
	var rel := mm.screen_relative if mm.screen_relative != Vector2.ZERO else mm.relative
	var vrel := mm.relative if mm.relative != Vector2.ZERO else rel
	match drag:
		"look":
			_turn(-rel.x * LOOK_DEG_PER_PX, -rel.y * LOOK_DEG_PER_PX)
		"pan":
			var mpp := Gizmo3D.world_per_px(self, global_position - global_basis.z * _dist) if top else _dist * PAN_PER_PX
			global_position += (-global_basis.x * vrel.x + global_basis.y * vrel.y) * mpp
		"orbit":
			_orbit(-rel.x * LOOK_DEG_PER_PX, -rel.y * LOOK_DEG_PER_PX)
		"dolly":
			var step := -vrel.y * _dist * ALT_DOLLY_PER_PX
			step = minf(step, _dist - 0.5)
			global_position += -global_basis.z * step
			_dist = maxf(_dist - step, 1.0)
	_clamp_floor()


## Yaw and pitch by degrees (pitch clamped to +-89, no roll).
func _turn(yaw_deg: float, pitch_deg: float) -> void:
	var e := global_basis.get_euler()
	var p := clampf(e.x + deg_to_rad(pitch_deg), deg_to_rad(-PITCH_MAX), deg_to_rad(PITCH_MAX))
	global_basis = Basis.from_euler(Vector3(p, e.y + deg_to_rad(yaw_deg), 0.0))


## Round the pivot: the position and the view turn together (the pivot keeps its spot on screen).
func _orbit(yaw_deg: float, pitch_deg: float) -> void:
	var e := global_basis.get_euler()
	var yaw := deg_to_rad(yaw_deg)
	var p := clampf(e.x + deg_to_rad(pitch_deg), deg_to_rad(-PITCH_MAX), deg_to_rad(PITCH_MAX))
	var r := Basis(Vector3.UP, yaw) * Basis(global_basis.x.normalized(), p - e.x)
	global_position = _pivot + r * (global_position - _pivot)
	global_basis = Basis.from_euler(Vector3(p, e.y + yaw, 0.0))


func _dolly_to(screen: Vector2, n: int) -> void:
	var p := _pick_point(screen, false)
	var d := global_position.distance_to(p)
	var dir := (p - global_position).normalized() if d > 1e-3 else -global_basis.z
	var step := maxf(d * DOLLY, DOLLY_MIN)
	if n > 0:
		step = minf(step, maxf(d - 0.2, 0.0))
	global_position += dir * step * float(n)
	_clamp_floor()


func _zoom_top(screen: Vector2, n: int) -> void:
	var vs := _vp_size()
	var s0 := size
	var s1 := clampf(s0 * pow(TOP_ZOOM, n), TOP_SIZE_MIN, TOP_SIZE_MAX)
	var wpp := s0 / vs.y
	var off := screen - vs * 0.5
	var w := global_basis.x * off.x * wpp - global_basis.y * off.y * wpp
	size = s1
	global_position += w * (1.0 - s1 / s0)


## The point under the cursor (a pick, else the terrain, else the plane y = 0); for an orbit with
## nothing under the cursor, the selection's centre.
func _pick_point(screen: Vector2, orbit: bool) -> Vector3:
	if editor != null and editor.is_inside_tree() and editor.doc != null:
		var h := editor.pick(screen)
		if h.hit:
			return h.pos
		if orbit and editor.selection != null and not editor.selection.uids.is_empty():
			var c := SelectTool.selection_center(editor)
			if not is_nan(c.x):
				return c
	var ro := project_ray_origin(screen)
	var rd := project_ray_normal(screen)
	if editor != null and editor.doc != null:
		var t := editor.terrain()
		if t != null:
			var g := t.raycast(ro, rd)
			if not is_nan(g.x):
				return g
	if absf(rd.y) > 1e-4:
		var k := -ro.y / rd.y
		if k > 0.0:
			return ro + rd * k
	return ro + rd * 30.0


func _over_gizmo(screen: Vector2) -> bool:
	return editor != null and editor.gizmo != null and editor.gizmo.visible and editor.gizmo.pick(screen, self) >= 0


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if drag != "" and _captured and _btn != MOUSE_BUTTON_NONE and not Input.is_mouse_button_pressed(_btn):
		# the release went elsewhere (a panel, Alt let go first): end the drag a frame later
		_lost += 1
		if _lost > 1:
			_end()
	else:
		_lost = 0
	if drag == "look" or (top and drag == "pan" and _btn == MOUSE_BUTTON_RIGHT):
		_key_fly(delta)
	var fly := flying()
	if fly != _flying:
		_flying = fly
		if _reticle != null:
			_reticle.visible = fly
		if _ghost != null and not fly:
			_ghost.visible = false
	if fly:
		pad_fly(delta)
		_ghost_t -= delta
		if _ghost_t <= 0.0:
			_ghost_t = GHOST_EVERY
			_update_ghost()
		if _reticle != null:
			_reticle.queue_redraw()


## Held W A S D / Q E while RMB looks (in the top view: the plane of the screen).
func _key_fly(delta: float) -> void:
	var x := _held("ed_right") - _held("ed_left")
	var y := _held("ed_up") - _held("ed_down")
	var z := _held("ed_back") - _held("ed_forward")
	if x == 0.0 and y == 0.0 and z == 0.0:
		return
	var mult := FAST if Input.is_action_pressed("ed_fast") else (SLOW if Input.is_action_pressed("ed_slow") else 1.0)
	var move: Vector3
	if top:
		move = global_basis.x * x - global_basis.y * z
	else:
		var f := -global_basis.z
		move = global_basis.x * x - f * z + Vector3.UP * y
	global_position += move.limit_length(1.0) * speed * mult * delta
	_clamp_floor()


static func _held(action: String) -> float:
	return 1.0 if InputMap.has_action(action) and Input.is_action_pressed(action) else 0.0


func _clamp_floor() -> void:
	if top or editor == null or editor.doc == null:
		return
	var t := editor.terrain()
	if t == null:
		return
	var h := t.height_at(global_position.x, global_position.z)
	if not is_nan(h) and global_position.y < h + FLOOR:
		global_position.y = h + FLOOR


# ---------------------------------------------------------------- the pad (FLY, 1.10)

## The pad flies the camera: it is the active device and no Dialog, help or text field is on top.
func flying() -> bool:
	if editor == null or not editor.is_inside_tree() or editor.doc == null:
		return false
	var ip := _prompts()
	if ip == null or not ip.has_method("using_pad") or not bool(ip.call("using_pad")):
		return false
	return not blocked()


## A Dialog (EDITOR MENU, help, any MessageBox) or a text field has the input.
func blocked() -> bool:
	if editor != null and editor.has_method("_blocked") and bool(editor.call("_blocked")):
		return true
	if not is_inside_tree():
		return true
	for n in get_tree().get_nodes_in_group(InputPrompts.SCREEN_GROUP):
		if n is Dialog and (n as Dialog).is_visible_in_tree() and not bool((n as Dialog).get("_closing")):
			return true
	for n in get_tree().get_nodes_in_group("editor_modal"):
		if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
			return true
	var fo := get_viewport().gui_get_focus_owner()
	return fo is LineEdit or fo is TextEdit


## In FLY every pad event is the editor's: marked handled here (before the GUI and InputPrompts'
## safety net), the GUI focus let go, the buttons acted on.
func _input(ev: InputEvent) -> void:
	if not (ev is InputEventJoypadButton or ev is InputEventJoypadMotion):
		return
	if not flying():
		return
	var vp := get_viewport()
	vp.set_input_as_handled()
	if vp.gui_get_focus_owner() != null:
		vp.gui_release_focus()
	if ev is InputEventJoypadButton and ev.is_pressed() and not ev.is_echo():
		_pad_button(ev)


func _pad_button(ev: InputEvent) -> void:
	var what := ""
	for pair in [["ed_pad_test_here", "here"], ["ed_pad_test", "start"], ["ed_pad_watch", "watch"],
			["ed_pad_help", "help"], ["ed_pad_menu", "menu"], ["ed_pad_faster", "faster"],
			["ed_pad_slower", "slower"], ["ed_pad_prev_tool", "prev_tool"], ["ed_pad_next_tool", "next_tool"]]:
		if InputMap.has_action(pair[0]) and ev.is_action_pressed(pair[0]):
			what = pair[1]
			break
	if what == "":
		return
	pad_command.emit(what)
	match what:
		"here", "start", "watch":
			var c := editor.free_center()
			if on_drive.is_valid():
				on_drive.call(what, c)
			else:
				editor.test_drive(what, c)
		"help":
			if editor.ui != null:
				editor.ui.open_help()
		"menu":
			if editor.ui != null:
				editor.ui.open_menu()
		"faster":
			set_speed(speed * SPEED_STEP)
		"slower":
			set_speed(speed / SPEED_STEP)
		"prev_tool", "next_tool":
			var ids: Array = TrackEditor.TOOL_IDS
			var i := ids.find(editor.tool.id if editor.tool != null else "select")
			i = posmod(i + (1 if what == "next_tool" else -1), ids.size())
			editor.set_tool(ids[i])


## One frame of the pad's fly: left stick (deadzone 0.2, x^2), right stick 180 deg/s, LT / RT,
## L3 x4. In the top view the left stick pans and LT / RT zoom.
func pad_fly(delta: float) -> void:
	var dev := _pad_device()
	if dev < 0:
		return
	var lx := curve(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X))
	var ly := curve(Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
	var rx := curve(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X))
	var ry := curve(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y))
	var lt := curve(Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT))
	var rt := curve(Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT))
	var mult := FAST if Input.is_joy_button_pressed(dev, JOY_BUTTON_LEFT_STICK) else 1.0
	var step := speed * mult * delta
	if top:
		global_position += (global_basis.x * lx - global_basis.y * ly) * step
		if rt != lt:
			size = clampf(size * pow(TOP_ZOOM, (rt - lt) * delta * 6.0), TOP_SIZE_MIN, TOP_SIZE_MAX)
		return
	if rx != 0.0 or ry != 0.0:
		_turn(-rx * PAD_LOOK_DEG * delta, -ry * PAD_LOOK_DEG * delta)
	var move := global_basis.x * lx + (-global_basis.z) * (-ly) + Vector3.UP * (rt - lt)
	if move != Vector3.ZERO:
		global_position += move * step
		_clamp_floor()


## The fly's stick curve: nothing inside the dead zone, then x^2 of the rest.
static func curve(v: float) -> float:
	var a := absf(v)
	if a <= PAD_DEADZONE:
		return 0.0
	var s := minf((a - PAD_DEADZONE) / (1.0 - PAD_DEADZONE), 1.0)
	return signf(v) * s * s


func _pad_device() -> int:
	var ip := _prompts()
	return int(ip.call("active_pad")) if ip != null and ip.has_method("active_pad") else -1


func reticle_shown() -> bool:
	return _reticle != null and _reticle.visible


## The kart ghost at the reticle's road spot (where A drives from).
func _update_ghost() -> void:
	if editor == null:
		return
	var h := editor.road_hit(editor.free_center())
	if _ghost == null:
		_ghost = MeshInstance3D.new()
		_ghost.name = "KartGhost"
		_ghost.top_level = true
		var bm := BoxMesh.new()
		bm.size = Vector3(1.4, 0.6, 2.2)
		_ghost.mesh = bm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(ORANGE, 0.5)
		_ghost.material_override = m
		_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ghost)
	if not h.hit:
		_ghost.visible = false
		return
	var f := Vector3.FORWARD
	var r := editor.road(h.road)
	if r != null and h.sample >= 0 and h.sample < r.fwd.size():
		f = Vector3(r.fwd[h.sample].x, 0.0, r.fwd[h.sample].z)
	if f.length_squared() < 1e-6:
		f = Vector3.FORWARD
	_ghost.global_transform = Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), h.pos + Vector3.UP * 0.4)
	_ghost.visible = true


# ---------------------------------------------------------------- views

## The box fills 60 % of the free area (rect), centred on it; the view's direction is kept.
func frame(aabb: AABB, rect: Rect2) -> void:
	var vs := _vp_size()
	if not rect.has_area():
		rect = Rect2(Vector2.ZERO, vs)
	var c := aabb.get_center()
	var r := maxf(aabb.size.length() * 0.5, 4.0)
	var m := minf(rect.size.x, rect.size.y)
	var fc := rect.get_center()
	var vc := vs * 0.5
	if top:
		size = clampf(2.0 * r * vs.y / (FRAME_FILL * m), TOP_SIZE_MIN, TOP_SIZE_MAX)
		var wpp := size / vs.y
		var p := Vector3(c.x, maxf(c.y + 500.0, TOP_HEIGHT), c.z)
		global_position = p + global_basis.x * (vc.x - fc.x) * wpp + global_basis.y * (fc.y - vc.y) * wpp
		return
	var t := tan(deg_to_rad(fov) * 0.5)
	var d := r * vs.y / (FRAME_FILL * m * t)
	var wpp2 := 2.0 * d * t / vs.y
	var pos := c + global_basis.z * d
	pos += global_basis.x * (vc.x - fc.x) * wpp2 + global_basis.y * (fc.y - vc.y) * wpp2
	global_position = pos
	_clamp_floor()


## A new track's view: the box framed from a 50 deg pitch, looking north (1.4).
func default_view(aabb: AABB, rect: Rect2) -> void:
	if top:
		toggle_top(Vector3(NAN, NAN, NAN))
	global_basis = Basis.from_euler(Vector3(deg_to_rad(-DEFAULT_PITCH), 0.0, 0.0))
	frame(aabb, rect)


## Jumps there (out of the top view).
func go_to(xf: Transform3D) -> void:
	if top:
		projection = PROJECTION_PERSPECTIVE
		top = false
	drag = ""
	global_transform = xf


## TOP VIEW: orthographic, straight down over pivot, sized to what was in view; again: back to the
## last perspective transform.
func toggle_top(pivot: Vector3) -> void:
	if top:
		projection = PROJECTION_PERSPECTIVE
		global_transform = _persp_xf
		top = false
		return
	_persp_xf = global_transform
	var p := pivot
	if is_nan(p.x) or is_nan(p.y) or is_nan(p.z):
		p = global_position - global_basis.z * 60.0
	var dist := maxf(global_position.distance_to(p), 5.0)
	var view_h := 2.0 * dist * tan(deg_to_rad(fov) * 0.5)
	var f := -global_basis.z
	f.y = 0.0
	if f.length_squared() < 1e-6:
		f = Vector3(global_basis.y.x, 0.0, global_basis.y.z)
	if f.length_squared() < 1e-6:
		f = Vector3.FORWARD
	projection = PROJECTION_ORTHOGONAL
	size = clampf(view_h, TOP_SIZE_MIN, TOP_SIZE_MAX)
	global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, f.normalized()), Vector3(p.x, maxf(p.y + 500.0, TOP_HEIGHT), p.z))
	top = true


## The perspective transform (the top view's way back).
func persp_transform() -> Transform3D:
	return _persp_xf if top else global_transform


func _vp_size() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1600, 900)


static func _prompts() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("InputPrompts") if tree and tree.root else null


## The orange cross at the free area's centre while the pad flies (1.10).
class Reticle:
	extends Control
	var cam: EditorCamera

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		if cam == null or cam.editor == null:
			return
		var c := cam.editor.free_center()
		for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + d * 4.0, c + d * 13.0, Color(0, 0, 0, 0.6), 4.0)
			draw_line(c + d * 4.0, c + d * 13.0, EditorCamera.ORANGE, 2.0)
		draw_circle(c, 1.5, EditorCamera.ORANGE)
