class_name TrainHazard
extends Hazard
## A Combine train crosses the road on a timetable that is a pure function of the shared
## clock, so every peer sees the same train with no network traffic. The crossing lamps
## flash and the bell rings `warn` seconds before the engine reaches the road; each owner
## tests its own karts against the cars' boxes. Computer drivers stop at the line.

const LAMP := Color(1.0, 0.12, 0.08)
const BRAKE := 12.0         # m/s2: how hard the computer drivers brake for the stop line

var _a := Vector3.ZERO
var _b := Vector3.ZERO
var _dir := Vector3.FORWARD
var _len := 260.0           # the line a..b
var _cars: Array = []       # [length, front axis ("x", "-x", "z", "-z"), lift, centre offset, model, body, shape]
var _train_len := 0.0
var _lamps: Array[OmniLight3D] = []
var _lamp_glows: Array[MeshInstance3D] = []
var _bell: AudioStreamPlayer3D
var _wheels: AudioStreamPlayer3D
var _snd := {}


func defaults() -> Dictionary:
	return {"a": [], "b": [], "cross": 130.0, "road_half": 16.0, "profile": [], "speed": 28.0, "period": 26.0,
		"first": 50.0, "warn": 4.5, "half_w": 1.8, "gap": 0.8, "lamps": [], "stop": [s - 16.0, s + 16.0],
		"cars": ["props_combine/combinetrain01a", "props_combine/combine_train02a", "props_combine/combine_train02b"],
		"car_axis": ["-x", "z", "z"]}


func build() -> void:
	var a: Array = p["a"]
	var b: Array = p["b"]
	_a = Vector3(a[0], a[1], a[2]) if a.size() == 3 else global_position - global_basis.z * 130.0
	_b = Vector3(b[0], b[1], b[2]) if b.size() == 3 else global_position + global_basis.z * 130.0
	_len = _a.distance_to(_b)
	_dir = (_b - _a).normalized()
	var cars: Array = p["cars"]
	var axes: Array = p["car_axis"]
	for j in cars.size():
		var key := pick_model([cars[j], "props_combine/combine_train02a"])
		var axis := str(axes[j]) if j < axes.size() and key == str(cars[j]) else "z"
		var box := Game.model_aabb(key) if key != "" else AABB(Vector3(-1.6, 0.0, -8.0), Vector3(3.2, 6.0, 16.0))
		var length := box.size.x if axis.ends_with("x") else box.size.z
		var c := box.get_center()
		var node: Node3D = null
		if visual and key != "":
			node = Game.spawn_model(key)
			add_child(node)
			node.visible = false
		var body := AnimatableBody3D.new()
		body.collision_layer = Game.LAYER_WORLD
		body.collision_mask = 0
		body.set_meta("surface", "wall")
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(float(p["half_w"]) * 2.0, 4.6, length)
		shape.shape = bs
		shape.position = Vector3(0.0, 2.3, 0.0)
		shape.disabled = true
		body.add_child(shape)
		add_child(body)
		_cars.append([length, axis, -box.position.y, Vector3(c.x, 0.0, c.z), node, body, shape])
		_train_len += length + (float(p["gap"]) if j > 0 else 0.0)
	_snd["horn"] = sounds([["ambient/alarms/razortrain_horn1.wav"], ["ambient/alarms/klaxon1.wav"]])
	_snd["impact"] = sounds([["vehicles/v8/vehicle_impact_heavy1.wav", "vehicles/v8/vehicle_impact_heavy2.wav",
		"vehicles/v8/vehicle_impact_heavy3.wav", "vehicles/v8/vehicle_impact_heavy4.wav"]])
	if not visual:
		return
	var lamps: Array = p["lamps"]
	var mid := global_position
	for l in lamps:
		var at := Vector3(l[0], l[1], l[2])
		mid += (at - global_position) / lamps.size()
		var lamp := light(LAMP, 9.0, 0.0, true)
		lamp.global_position = at
		_lamps.append(lamp)
		var g := glow("materials/sprites/redglow1.png", 1.4, LAMP)
		g.global_position = at
		g.visible = false
		_lamp_glows.append(g)
	var host := Node3D.new()
	add_child(host)
	host.global_position = mid
	_bell = loop(["ambient/alarms/train_crossing_bell_loop1.wav", "ambient/alarms/warningbell1.wav"], host, 25.0, -2.0)
	if _cars[0][4]:
		_wheels = loop(["ambient/machines/razor_train_wheels_loop1.wav", "vehicles/apc/apc_cruise_loop3.wav"],
			_cars[0][4], 40.0, 2.0)


# ---------------------------------------------------------------- the timetable (pure)
## [cycle, seconds into it, a -> b?] at clock t, or [] before the first train.
func run_at(t: float) -> Array:
	var tt := t - float(p["first"])
	if tt < 0.0:
		return []
	var period := tm("period")
	var c := int(floor(tt / period))
	return [c, tt - c * period, c % 2 == 0]


## Seconds into a run when the tail has cleared the far side of the road.
func block_end() -> float:
	return tm("warn") + (2.0 * float(p["road_half"]) + _train_len) / float(p["speed"])


## How far car j's centre is along its run (from the end it starts at), seconds `u` in.
func car_along(j: int, u: float, forward: bool) -> float:
	var cross := float(p["cross"]) if forward else _len - float(p["cross"])
	var head := cross - float(p["road_half"]) - float(p["speed"]) * (tm("warn") - u)
	for i in j:
		head -= _cars[i][0] + float(p["gap"])
	return head - _cars[j][0] * 0.5


## Height of the line (the profile the generator measured every 4 m) at distance u from a.
func line_y(u: float) -> float:
	var prof: Array = p["profile"]
	if prof.size() < 2:
		return _a.y
	var f := clampf(u / 4.0, 0.0, prof.size() - 1.001)
	var i := int(f)
	return lerpf(float(prof[i][1]), float(prof[i + 1][1]), f - i)


## Car j on a run: [centre on the rails, out of its tunnels?, forward, side, up], tilted
## with the line.
func car_at(j: int, run: Array) -> Array:
	var forward: bool = run[2]
	var along := car_along(j, float(run[1]), forward)
	var length: float = _cars[j][0]
	var u := along if forward else _len - along
	var half := length * 0.5 * (1.0 if forward else -1.0)
	var f := _dir if forward else -_dir
	var fp := (f * length + Vector3.UP * (line_y(u + half) - line_y(u - half))).normalized()
	var side := Vector3.UP.cross(fp).normalized()
	var origin := _a + _dir * u
	origin.y = line_y(u)
	return [origin, along > -length and along < _len + length, fp, side, fp.cross(side).normalized()]


func snapshot(t: float) -> Array:
	var run := run_at(t)
	if run.is_empty():
		return [-1]
	var out := [run[0], snappedf(run[1], 0.001), run[2]]
	for j in _cars.size():
		var x := car_at(j, run)
		out.append_array([(x[0] as Vector3).snapped(Vector3.ONE * 0.01), x[1]])
	return out


func tick(t: float, _dt: float) -> void:
	var run := run_at(t)
	var u := float(run[1]) if not run.is_empty() else -1.0
	var ringing := u >= 0.0 and u < block_end() + 0.5
	_show_cars(run)
	if visual:
		var flash := int(floor(t / 0.5)) % 2
		for i in _lamps.size():
			var on := ringing and i % 2 == flash
			_lamps[i].light_energy = 5.0 if on else 0.0
			_lamp_glows[i].visible = on
		if _bell and ringing != _bell.playing:
			if ringing:
				_bell.play()
			else:
				_bell.stop()
	if not ringing:
		return
	var start := float(p["first"]) + int(run[0]) * tm("period")
	if crossed(start, t):
		director.note(self, "warn")
	if crossed(start + 1.0, t):
		var engine: Node3D = _cars[0][4]
		play(_snd["horn"], engine.global_position if engine else global_position, 10.0, 70.0)
	if crossed(start + tm("warn"), t):
		director.note(self, "fire")
	_hit_karts(run)


func _show_cars(run: Array) -> void:
	var any := false
	for j in _cars.size():
		var x := car_at(j, run) if not run.is_empty() else []
		var shown: bool = not x.is_empty() and x[1]
		any = any or shown
		var shape: CollisionShape3D = _cars[j][6]
		if shape.disabled == shown:
			shape.set_deferred("disabled", not shown)
		if not shown:
			if _cars[j][4]:
				(_cars[j][4] as Node3D).visible = false
			continue
		var o: Vector3 = x[0]
		var fp: Vector3 = x[2]
		var sd: Vector3 = x[3]
		var up: Vector3 = x[4]
		(_cars[j][5] as AnimatableBody3D).global_transform = Transform3D(Basis(sd, up, fp), o)
		var node: Node3D = _cars[j][4]
		if node:
			# its front along the rails, sitting on its wheels, its middle on the car's centre
			var basis := _car_basis(str(_cars[j][1]), fp, up)
			node.global_transform = Transform3D(basis, o + up * float(_cars[j][2]) - basis * (_cars[j][3] as Vector3))
			node.visible = true
	if _wheels and any != _wheels.playing:
		if any:
			_wheels.play()
		else:
			_wheels.stop()


## A car model's basis with its front axis ("x", "-x", "z" or "-z" in model space) along fp.
func _car_basis(axis: String, fp: Vector3, up: Vector3) -> Basis:
	var f := -fp if axis.begins_with("-") else fp
	if axis.ends_with("x"):
		return Basis(f, up, f.cross(up))
	return Basis(up.cross(f), up, f)


## A local kart inside a car's box is thrown along the rails, off the road.
func _hit_karts(run: Array) -> void:
	for k in local_karts():
		var c := k.global_position + k.grav_up * 0.6
		for j in _cars.size():
			var x := car_at(j, run)
			if not x[1]:
				continue
			var d := c - (x[0] as Vector3)
			var he := Vector3(_cars[j][0] * 0.5, 2.6, float(p["half_w"]) + 0.9)
			var l := Vector3(d.dot(x[2]), d.dot(x[4]) - 2.3, d.dot(x[3]))
			if absf(l.x) > he.x or absf(l.y) > he.y or absf(l.z) > he.z:
				continue
			# the face it is nearest to pushes it out
			var pen := he - l.abs()
			var n: Vector3 = (x[3] as Vector3) * signf(l.z) if pen.z <= pen.x else (x[2] as Vector3) * signf(l.x)
			if hit(k, "tumble", ((x[2] as Vector3) * 0.7 + n * 0.5) * k.mass * 9.0):
				play(_snd["impact"], c, 6.0, 30.0)
			break


func sleep() -> void:
	_show_cars([])
	for g in _lamp_glows:
		g.visible = false
	if _bell:
		_bell.stop()


## Stop at the line when the train will be across the road on arrival, and wait for the tail;
## a kart that ran past the line stops where it is, still clear of the cars. One already on
## the rails gets no advice: on through.
func advice(_k: Kart, at_s: float, speed: float) -> Dictionary:
	var to_cross := ahead(at_s, s)
	if to_cross > 200.0 or to_cross < float(p["half_w"]) + 2.5:
		return {}
	var to_stop := maxf(to_cross - ahead(float(p["stop"][0]), s), 0.0)
	var period := tm("period")
	var tt := director.clock() + to_cross / maxf(speed, 8.0) - float(p["first"])
	var c := floorf(tt / period)
	for cc: float in [c - 1.0, c, c + 1.0]:
		if tt >= cc * period + tm("warn") - 1.0 and tt <= cc * period + block_end() + 0.5 and cc >= 0.0:
			return {"vmax": sqrt(2.0 * BRAKE * to_stop)}
	return {}


func blocks_respawn(at_s: float) -> bool:
	return absf(fposmod(at_s - s + path.length * 0.5, path.length) - path.length * 0.5) <= 14.0


func is_active(t: float) -> bool:
	var run := run_at(t)
	return not run.is_empty() and float(run[1]) < block_end() + 0.5
