class_name TrainHazard
extends Hazard
## A train on its own line, running a timetable that is a pure function of the shared clock, so
## every peer sees the same train with no network traffic. Its "mode" (data p["mode"]) says what
## it is to the race:
## - "level" (no mode: the CT17 Combine train): a straight line across the road. The crossing
##   lamps flash and the bell rings `warn` seconds before the engine reaches the road; each owner
##   tests its own karts against the cars' boxes. Computer drivers stop at the line (most of them).
## - "cross": the same level crossing made fair for a race (the forest), on a straight line like
##   the Combine one or along a polyline ("line": a whole railway out of one portal, across the road
##   `cross` metres along it, then on beside or over the road and into the other portal; its run
##   starts as the engine leaves the line's first end): a long warning (lamps,
##   bell, the horn as it comes and again near the road), barrier arms that come down before the
##   engine arrives and go up as the tail clears, a short train fast across, a timetable with long
##   open gaps between trains (and a seeded jitter, so a lap time never meets the same train lap
##   after lap). Every computer driver stops for the arms. Its guard: a kart the arms held never
##   meets the next train on its next lap. The server watches who waited at the arms and, just
##   before each run, calls it off while a kart held last time is within GUARD_REACH metres of the
##   crossing: one "skip" event to every peer (without one, a run goes as the timetable says). To
##   see those karts coming it wakes GUARD_WAKE metres (or more) before its stretch (wake_span).
## - "pass": a train on a line beside the road or over it (a railway bridge), never across its
##   surface. It runs its timetable along the whole line, never tests a kart and the bots ignore it.
## Where a polyline runs over a road (data "over") its wheels drum overhead while the train is on it.
## A train's cars are models named in its data (a locomotive first), spaced by their own length.

const LAMP := Color(1.0, 0.12, 0.08)
const BRAKE := 12.0         # m/s2: how hard the computer drivers brake for the stop line
const GATE_MOVE := 1.5      # seconds a crossing's arm takes to come down or to go up
const GATE_UP := 1.45       # radians an arm stands up from level when the road is open
const STOP_BRAKE := 5.0     # m/s2: how gently the bots brake for a crossing's arms (they stop from far enough)
const DECIDE := 1.5         # "cross": seconds before a run starts that the server decides whether it runs
const GUARD_REACH := 340.0  # metres before the crossing within which a kart held last time calls a run off
const GUARD_WAKE := 140.0   # metres before its line a guarded crossing's wake stretch starts (it wakes 220 m before that)
const HELD_SPEED := 3.0     # m/s under which a kart waiting before the arms while they move or are down is held
const CONSIST_MAX := 80.0   # metres of train a timetable allows for (Episode Two's freight is 63 m)
const STOP_BEFORE := 4.0    # "cross": metres before its first arm a computer driver's middle stops
const QUEUE_GAP := 6.5      # metres between the middles of two karts queued at the arms
const QUEUE_LANE := 2.6     # metres apart across the road within which a waiting kart is in a kart's lane
## The forest's consists: a crossing gets a short one (locomotive + 3 wagons, 63 m), a line beside
## the road a long freight (locomotive + 6 wagons, 106 m). All their cars are 15 m on their z axis.
const EP2_CROSS := ["props_trainstation/train_engine", "props_trainstation/train_boxcar",
	"props_trainstation/train_orecar", "props_trainstation/train_boxcar_damaged"]
const EP2_PASS := ["props_trainstation/train_engine", "props_trainstation/train_boxcar",
	"props_trainstation/train_orecar", "props_trainstation/train_orecar", "props_trainstation/train003",
	"props_trainstation/train_boxcar", "props_trainstation/train_orecar"]
## Each kind of train's sounds (files under assets/sound/; a list of lists is tried list by list,
## a plain list file by file): the horn, the crossing bell, the engine's loop, the wheels' loop on
## the last car and the wheels heard from under a bridge it crosses. Episode Two's files fall back
## to ones every install has.
const SOUNDS := {
	"combine": {"horn": [["ambient/alarms/razortrain_horn1.wav"], ["ambient/alarms/klaxon1.wav"]],
		"bell": ["ambient/alarms/train_crossing_bell_loop1.wav", "ambient/alarms/warningbell1.wav"],
		"engine": ["ambient/machines/razor_train_wheels_loop1.wav", "vehicles/apc/apc_cruise_loop3.wav"],
		"wheels": [], "over": []},
	"ep2": {"horn": [["ambient/alarms/train_horn_distant1.wav"], ["ambient/alarms/train_horn2.wav"],
			["ambient/alarms/razortrain_horn1.wav"]],
		"bell": ["ambient/alarms/train_crossing_bell_loop1.wav", "ambient/alarms/warningbell1.wav"],
		"engine": ["ambient/machines/train_freight_loop1.wav", "ambient/machines/train_wheels_loop1.wav",
			"ambient/machines/razor_train_wheels_loop1.wav"],
		"wheels": ["ambient/machines/train_wheels_loop1.wav", "ambient/machines/razor_train_wheels_loop1.wav"],
		"over": ["ambient/machines/train_wheels_overhead_loop1.wav", "ambient/machines/train_wheels_loop1.wav"]},
}

var _a := Vector3.ZERO
var _b := Vector3.ZERO
var _dir := Vector3.FORWARD
var _len := 260.0           # the line a..b (or the polyline's length)
var _mode := "level"
var _poly := PackedVector3Array()  # a polyline ("pass", a "cross" with "line"): where the wheels roll
var _cum := PackedFloat32Array()   # ... and the metres along it at each point
var _cars: Array = []       # [length, front axis ("x", "-x", "z", "-z"), lift, centre offset, model, body, shape]
var _arriving := {}         # car index -> true: shown again this frame, its box comes on next frame (_show_cars)
var _train_len := 0.0
var _lamps: Array[OmniLight3D] = []
var _lamp_glows: Array[MeshInstance3D] = []
var _gates: Array[Node3D] = []     # "cross": each arm's hinge (its local +X arm turned up about z)
var _bell: AudioStreamPlayer3D
var _wheels: AudioStreamPlayer3D
var _tail: AudioStreamPlayer3D
var _over: Array = []       # a polyline's [line metres from, to, player] where it runs over a road
var _snd := {}
var _skip := {}             # "cross" with its guard: the runs the server called off (index -> true)
var _decided := {}          # (server) the runs it has decided on
var _held_now := {}         # (server) kart -> the arms held it on this approach
var _held_last := {}        # (server) kart -> the arms held it on its last pass
var _before := {}           # (server) kart -> metres before the crossing on the previous frame
var _passed := {}           # (server) kart -> clock it last drove over the line
var _stop_s := NAN          # "cross" with arms: this game's lap metres of the stop line (p["stop"][0] without)
var _rail_off := 0.0        # "cross" with arms: metres from the rails (this game's lap metres) on to s
var _rail_k := 0.0          # ... and how much further on the rails lie per metre right of the road's middle


func defaults() -> Dictionary:
	var d := {"a": [], "b": [], "cross": 130.0, "road_half": 16.0, "profile": [], "speed": 28.0, "period": 26.0,
		"first": 50.0, "warn": 4.5, "half_w": 1.8, "gap": 0.8, "lamps": [], "stop": [s - 16.0, s + 16.0],
		"cars": ["props_combine/combinetrain01a", "props_combine/combine_train02a", "props_combine/combine_train02b"],
		"car_axis": ["-x", "z", "z"], "fallback": [["props_combine/combine_train02a", "z"]], "sound": "combine",
		"jitter": 0.0, "dirs": "both"}
	var mode := str((def.get("p", {}) as Dictionary).get("mode", "level"))
	if mode == "level":
		return d
	# Episode Two's freight (a missing model falls back to Half-Life 2's cars)
	d.merge({"mode": mode, "sound": "ep2", "gap": 0.4, "line": [], "over": [],
		"fallback": [["props_trainstation/train001", "z"], ["props_combine/combine_train02a", "z"]]}, true)
	if mode == "cross":
		d.merge({"cars": EP2_CROSS, "car_axis": ["z", "z", "z", "z"], "speed": 30.0, "period": 55.0, "first": 30.0,
			"warn": 6.0, "jitter": 12.0, "gates": [], "gate_lead": 3.0, "gate_after": 0.5, "guard": true}, true)
	else:
		d.merge({"cars": EP2_PASS, "car_axis": ["z", "z", "z", "z", "z", "z", "z"], "speed": 25.0, "period": 70.0,
			"first": 10.0, "horn": [40.0], "dirs": "ab"}, true)
	return d


func build() -> void:
	_mode = str(p.get("mode", "level"))
	if _mode == "pass" or (_mode == "cross" and not (p["line"] as Array).is_empty()):
		_build_line()
	else:
		var a: Array = p["a"]
		var b: Array = p["b"]
		_a = Vector3(a[0], a[1], a[2]) if a.size() == 3 else global_position - global_basis.z * 130.0
		_b = Vector3(b[0], b[1], b[2]) if b.size() == 3 else global_position + global_basis.z * 130.0
		_len = _a.distance_to(_b)
		_dir = (_b - _a).normalized()
	var cars: Array = p["cars"]
	var axes: Array = p["car_axis"]
	var keys_fb: Array = []
	var axis_fb := {}
	for f in p["fallback"]:
		keys_fb.append(str(f[0]))
		axis_fb[str(f[0])] = str(f[1])
	for j in cars.size():
		var key := pick_model([cars[j]] + keys_fb)
		var axis := str(axes[j]) if j < axes.size() and key == str(cars[j]) else str(axis_fb.get(key, "z"))
		var box := Game.model_aabb(key) if key != "" else AABB(Vector3(-1.6, 0.0, -8.0), Vector3(3.2, 6.0, 16.0))
		var length := box.size.x if axis.ends_with("x") else box.size.z
		var c := box.get_center()
		var node: Node3D = null
		if visual and key != "":
			node = Game.spawn_model(key)
			add_child(node)
			node.visible = false
		var body: AnimatableBody3D = null
		var shape: CollisionShape3D = null
		# a train beside the road never touches a kart: no body (unless its data asks for one)
		if _mode != "pass" or bool(p.get("solid", false)):
			body = AnimatableBody3D.new()
			body.collision_layer = Game.LAYER_WORLD
			body.collision_mask = 0
			body.set_meta("surface", "wall")
			shape = CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(float(p["half_w"]) * 2.0, 4.6, length)
			shape.shape = bs
			shape.position = Vector3(0.0, 2.3, 0.0)
			shape.disabled = true
			body.add_child(shape)
			add_child(body)
		_cars.append([length, axis, -box.position.y, Vector3(c.x, 0.0, c.z), node, body, shape])
		_train_len += length + (float(p["gap"]) if j > 0 else 0.0)
	# awake for the whole stretch its line runs beside ("wake": a crossing on a whole railway), and for
	# the guard (the server watches every kart, remote ones too) from far enough to see who is coming
	var wk: Array = p.get("wake", [])
	if wk.size() == 2:
		wake_span = Vector2(float(wk[0]), float(wk[1]))
	if _guarded():
		aims_all = true
		var w := span if wake_span == Vector2.ZERO else wake_span
		var sx := s if s >= w.x else s + path.length
		wake_span = Vector2(minf(w.x, sx - maxf(GUARD_WAKE, _reach() - 200.0)), w.y)
	if _mode == "cross" and not (p["gates"] as Array).is_empty():
		# the stop line STOP_BEFORE metres before the first arm a kart comes to, found from where the arms
		# stand: late in a lap this game's lap metres run up to 4 m behind the generator's, and the data's
		# stop line (lap metres) fell under White Forest's arms, so a bot stopped with its nose past them
		var first := 0.0
		for g in p["gates"]:
			var q := Vector3(float(g[0]), float(g[1]), float(g[2]))
			var d := ahead(path.progress(q, path.closest(q)), s)
			if d < 60.0:
				first = maxf(first, d)
		_stop_s = fposmod(s - first - STOP_BEFORE, path.length)
		# ... and the rails themselves lie that drift short of s: the bounds measured from s ("on through",
		# the queue, the guard's "waiting") count from the rails, or a kart stopped just short of them sat
		# inside the cars' box (White Forest: s lies 4.3 m past the rails)
		var ro := ahead(path.progress(global_position, path.closest(global_position)), s)
		_rail_off = ro if ro < 20.0 else 0.0
		# a skewed crossing (White Forest's: 82 degrees) has its rails further along the road on one side
		# of it than on the other (0.7 m at the edge of the road): the bounds follow a kart's lane
		var dr := _dir
		if not _poly.is_empty():
			var cm := float(p.get("cross", 0.0))
			dr = line_point(cm + 2.0) - line_point(cm - 2.0)
		dr.y = 0.0
		var ci := path.closest(global_position)
		var dr_r := dr.normalized().dot(path.right[ci])
		_rail_k = dr.normalized().dot(path.fwd[ci]) / dr_r if absf(dr_r) > 0.3 else 0.0
	var snd: Dictionary = SOUNDS.get(str(p["sound"]), SOUNDS["combine"])
	_snd["horn"] = sounds(snd["horn"])
	_snd["impact"] = sounds([["vehicles/v8/vehicle_impact_heavy1.wav", "vehicles/v8/vehicle_impact_heavy2.wav",
		"vehicles/v8/vehicle_impact_heavy3.wav", "vehicles/v8/vehicle_impact_heavy4.wav"]])
	if not visual:
		return
	if _mode == "pass":
		_build_pass_sounds(snd)
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
	_bell = loop(snd["bell"], host, 25.0, -2.0)
	if _cars[0][4]:
		_wheels = loop(snd["engine"], _cars[0][4], 40.0, 2.0)
	if _mode == "cross":
		if _cars.size() > 2 and _cars[-1][4] and not (snd["wheels"] as Array).is_empty():
			_tail = loop(snd["wheels"], _cars[-1][4], 20.0, -2.0)
		_build_gates()
		_build_over(snd)


## A polyline from the data ("line") and the metres along it.
func _build_line() -> void:
	for q in p["line"]:
		_poly.append(Vector3(q[0], q[1], q[2]))
	if _poly.size() < 2:
		# (a line too short to run on: a stub along the hazard's own forward)
		_poly = PackedVector3Array([global_position - global_basis.z * 50.0, global_position + global_basis.z * 50.0])
	_cum.resize(_poly.size())
	_cum[0] = 0.0
	for i in range(1, _poly.size()):
		_cum[i] = _cum[i - 1] + _poly[i].distance_to(_poly[i - 1])
	_len = _cum[_poly.size() - 1]
	_a = _poly[0]
	_b = _poly[_poly.size() - 1]
	_dir = (_b - _a).normalized()


func _build_pass_sounds(snd: Dictionary) -> void:
	if _cars[0][4]:
		_wheels = loop(snd["engine"], _cars[0][4], 40.0, 2.0)
	if _cars.size() > 2 and _cars[-1][4] and not (snd["wheels"] as Array).is_empty():
		_tail = loop(snd["wheels"], _cars[-1][4], 20.0, -2.0)
	_build_over(snd)


## The wheels drumming overhead where a polyline runs over a road (data "over": line metres from, to).
func _build_over(snd: Dictionary) -> void:
	if (snd["over"] as Array).is_empty() or _poly.is_empty():
		return
	for o in p["over"]:
		var host := Node3D.new()
		add_child(host)
		host.global_position = line_point((float(o[0]) + float(o[1])) * 0.5) - Vector3.UP * 2.0
		var a := loop(snd["over"], host, 18.0, 3.0)
		if a:
			_over.append([float(o[0]), float(o[1]), a])


## A crossing's barrier arms (visual only, no collision): a post on the road's edge and a striped
## arm on a hinge at its top, data [x, y, z, yaw, length, post height] each, its arm along the
## post's local +X across the road when down.
func _build_gates() -> void:
	var post_m := StandardMaterial3D.new()
	post_m.albedo_color = Color(0.22, 0.22, 0.22)
	post_m.roughness = 0.8
	# red and white stripes a metre long each, in the arm's own space (triplanar, nearest filter)
	var img := Image.create_empty(2, 1, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, Color(0.85, 0.08, 0.06))
	img.set_pixel(1, 0, Color(0.92, 0.92, 0.9))
	var arm_m := StandardMaterial3D.new()
	arm_m.albedo_texture = ImageTexture.create_from_image(img)
	arm_m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	arm_m.uv1_triplanar = true
	arm_m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	arm_m.roughness = 0.6
	for g in p["gates"]:
		var root := Node3D.new()
		add_child(root)
		root.global_position = Vector3(g[0], g[1], g[2])
		root.global_rotation = Vector3(0.0, float(g[3]), 0.0)
		var h := float(g[5]) if (g as Array).size() > 5 else 1.3
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.22, h, 0.22)
		post.mesh = pm
		post.material_override = post_m
		post.position.y = h * 0.5
		root.add_child(post)
		var hinge := Node3D.new()
		hinge.position = Vector3(0.0, h - 0.2, 0.18)
		root.add_child(hinge)
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(float(g[4]), 0.12, 0.08)
		arm.mesh = am
		arm.material_override = arm_m
		arm.position.x = float(g[4]) * 0.5
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hinge.add_child(arm)
		hinge.rotation.z = GATE_UP
		_gates.append(hinge)


# ---------------------------------------------------------------- the timetable (pure)
## Clock at which run c starts: every `period` seconds from `first`, each one up to `jitter`
## seconds late (seeded per run, the same on every peer).
func _start(c: int) -> float:
	var st := float(p["first"]) + c * tm("period")
	var jit := _jitter()
	return st + rnd(c) * jit if jit > 0.0 else st


## Seconds a run may start late: p["jitter"], but never so much that the next run could start before
## this one has left its line (HARD's shorter period: a train still short of its far portal would
## vanish as the next one came out of the near one). Worked out from the data alone (a train of
## CONSIST_MAX metres), not from the cars' models, so a peer with other content keeps the same
## timetable.
func _jitter() -> float:
	var jit := minf(float(p["jitter"]), tm("period") * 0.5)
	if jit > 0.0 and _mode != "level":
		jit = minf(jit, maxf(tm("period") - (_len + CONSIST_MAX) / float(p["speed"]) - 2.0, 0.0))
	return jit


## Which way run c goes: a -> b?
func _forward(c: int) -> bool:
	match str(p["dirs"]):
		"ab":
			return true
		"ba":
			return false
	return c % 2 == 0


## [cycle, seconds into it, a -> b?] at clock t, or [] before the first train (and while a run the
## guard called off would be on).
func run_at(t: float) -> Array:
	var run := _timetable(t)
	if run.is_empty() or _skip.is_empty():
		return run
	return [] if _skip.has(int(run[0])) else run


## A fair crossing with its guard on: the server may call a run off (a "skip" event).
func _guarded() -> bool:
	return _mode == "cross" and bool(p.get("guard", false))


## The timetable alone: [cycle, seconds into it, a -> b?] at clock t, or [] before the first train.
func _timetable(t: float) -> Array:
	var tt := t - float(p["first"])
	if tt < 0.0:
		return []
	var period := tm("period")
	var c := int(floor(tt / period))
	if float(p["jitter"]) <= 0.0:
		return [c, tt - c * period, _forward(c)]
	# a late start: until it, the clock is still in the run before
	if t < _start(c):
		c -= 1
	if c < 0:
		return []
	return [c, t - _start(c), _forward(c)]


## Seconds from a run's start to the start of its crossing's warning: 0 for a straight line (its
## run starts with the warning); a polyline's run starts as the engine leaves the line's first end.
func _w0(forward: bool) -> float:
	if _poly.is_empty() or _mode != "cross":
		return 0.0
	var cm := float(p["cross"]) if forward else _len - float(p["cross"])
	return (cm - float(p["road_half"])) / float(p["speed"]) - tm("warn")


## Seconds into the crossing's own sequence (from its warning) on a run, or -1 for no run.
func _seq(run: Array) -> float:
	return float(run[1]) - _w0(run[2]) if not run.is_empty() else -1.0


## Clock at which run c's crossing starts to warn.
func _warn_at(c: int) -> float:
	if _mode == "level":
		return float(p["first"]) + c * tm("period")
	return _start(c) + _w0(_forward(c))


## Seconds into a crossing's sequence when the tail has cleared the far side of the road (a train on
## a line beside the road: seconds into a run when it has left the far end of the line).
func block_end() -> float:
	if _mode == "pass":
		return (_len + _train_len) / float(p["speed"])
	return tm("warn") + (2.0 * float(p["road_half"]) + _train_len) / float(p["speed"])


## "cross": seconds into the crossing's sequence when the arms start down, and when they start back up.
func gate_times() -> Vector2:
	return Vector2(tm("warn") - float(p["gate_lead"]), block_end() + float(p["gate_after"]))


## "cross": how far down the arms are, seconds `u` into the crossing's sequence (0 up .. 1 down).
func gate_down(u: float) -> float:
	var g := gate_times()
	if u < g.x or u > g.y + GATE_MOVE:
		return 0.0
	if u < g.x + GATE_MOVE:
		return smoothstep(0.0, 1.0, (u - g.x) / GATE_MOVE)
	if u <= g.y:
		return 1.0
	return smoothstep(0.0, 1.0, 1.0 - (u - g.y) / GATE_MOVE)


## Seconds into the crossing's sequence while it warns (lamps and bell) and can hurt.
func _ring_end() -> float:
	return gate_times().y + GATE_MOVE if _mode == "cross" else block_end() + 0.5


## How far car j's centre is along its run (from the end it starts at), seconds `u` in.
func car_along(j: int, u: float, forward: bool) -> float:
	var head: float
	if not _poly.is_empty():
		# the engine's nose leaves the line's first end as the run starts
		head = float(p["speed"]) * u
	else:
		var cross := float(p["cross"]) if forward else _len - float(p["cross"])
		head = cross - float(p["road_half"]) - float(p["speed"]) * (tm("warn") - u)
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


## A polyline's point d metres along it (straight on past either end).
func line_point(d: float) -> Vector3:
	var n := _poly.size()
	if d <= 0.0:
		return _poly[0] + (_poly[1] - _poly[0]).normalized() * d
	if d >= _len:
		return _poly[n - 1] + (_poly[n - 1] - _poly[n - 2]).normalized() * (d - _len)
	var i := clampi(_cum.bsearch(d) - 1, 0, n - 2)
	var seg := maxf(_cum[i + 1] - _cum[i], 0.001)
	return _poly[i].lerp(_poly[i + 1], (d - _cum[i]) / seg)


## Car j on a run: [centre on the rails, out of its tunnels?, forward, side, up], tilted
## with the line.
func car_at(j: int, run: Array) -> Array:
	var forward: bool = run[2]
	var along := car_along(j, float(run[1]), forward)
	var length: float = _cars[j][0]
	if not _poly.is_empty():
		# a rigid car on a bending line: its two bogies on the rails, its body along the chord
		var d := along if forward else _len - along
		var half := length * 0.4 * (1.0 if forward else -1.0)
		var front := line_point(d + half)
		var rear := line_point(d - half)
		var fwd := (front - rear).normalized()
		var sd := Vector3.UP.cross(fwd).normalized()
		return [(front + rear) * 0.5, along > -length and along < _len + length, fwd, sd, fwd.cross(sd).normalized()]
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
	if _mode == "cross":
		out.append(snappedf(gate_down(_seq(run)), 0.001))
	return out


func tick(t: float, _dt: float) -> void:
	var run := run_at(t)
	if _mode == "pass":
		_tick_pass(t, run)
		return
	if _guarded() and director.authority():
		_guard(t, run)
	var u := _seq(run)
	var ringing := u >= 0.0 and u < _ring_end()
	_show_cars(run)
	_over_tick(run)
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
		if not _gates.is_empty():
			var down := gate_down(u) if u >= 0.0 else 0.0
			for g in _gates:
				g.rotation.z = GATE_UP * (1.0 - down)
	if not ringing:
		return
	var start := _warn_at(int(run[0]))
	if crossed(start, t):
		director.note(self, "warn")
	if _mode == "level":
		if crossed(start + 1.0, t):
			var engine: Node3D = _cars[0][4]
			play(_snd["horn"], engine.global_position if engine else global_position, 10.0, 70.0)
	# the horn as the train comes (far off down the line) and again near the road
	elif crossed(start + 0.6, t) or crossed(start + tm("warn") - 2.0, t):
		play(_snd["horn"], car_at(0, run)[0], 10.0, 70.0)
	if crossed(start + tm("warn"), t):
		director.note(self, "fire")
	_hit_karts(run)


## "pass": the cars, the horn at its spots along the line, the wheels overhead on a bridge.
func _tick_pass(t: float, run: Array) -> void:
	_show_cars(run)
	_over_tick(run)
	if run.is_empty() or not visual:
		return
	var forward: bool = run[2]
	var start := _start(int(run[0]))
	for m in p["horn"]:
		if crossed(start + float(m) / float(p["speed"]), t):
			play(_snd["horn"], line_point(float(m) if forward else _len - float(m)), 10.0, 70.0)


## The wheels overhead: each bridge's loop plays while the train is on it.
func _over_tick(run: Array) -> void:
	if _over.is_empty():
		return
	var forward: bool = run[2] if not run.is_empty() else true
	# the train covers line metres [tail, head] (from the end it left)
	var head := float(p["speed"]) * float(run[1]) if not run.is_empty() else -1e9
	var tail := head - _train_len
	for o in _over:
		var a: float = o[0] if forward else _len - float(o[1])
		var b: float = o[1] if forward else _len - float(o[0])
		var on := head > a - 8.0 and tail < b + 8.0
		var pl: AudioStreamPlayer3D = o[2]
		if on != pl.playing:
			if on:
				pl.play()
			else:
				pl.stop()


func _show_cars(run: Array) -> void:
	var any := false
	for j in _cars.size():
		var x := car_at(j, run) if not run.is_empty() else []
		var shown: bool = not x.is_empty() and x[1]
		any = any or shown
		var shape: CollisionShape3D = _cars[j][6]
		if not shown:
			_arriving.erase(j)
			if shape and not shape.disabled:
				shape.set_deferred("disabled", true)
			if _cars[j][4]:
				(_cars[j][4] as Node3D).visible = false
			continue
		var o: Vector3 = x[0]
		var fp: Vector3 = x[2]
		var sd: Vector3 = x[3]
		var up: Vector3 = x[4]
		if _cars[j][5]:
			(_cars[j][5] as AnimatableBody3D).global_transform = Transform3D(Basis(sd, up, fp), o)
		# a car's box comes on a frame after it shows again: hidden (between runs, or the hazard asleep) its
		# body stays where it was last, at the far portal or mid-line, and its first move here is a single
		# kinematic step of up to a kilometre, which Jolt sweeps with its box: on, it touched karts by the
		# line as a run began. The box comes on once the body is here.
		if shape and shape.disabled:
			if _arriving.has(j):
				_arriving.erase(j)
				shape.set_deferred("disabled", false)
			else:
				_arriving[j] = true
		var node: Node3D = _cars[j][4]
		if node:
			# its front along the rails, sitting on its wheels, its middle on the car's centre
			var basis := _car_basis(str(_cars[j][1]), fp, up)
			node.global_transform = Transform3D(basis, o + up * float(_cars[j][2]) - basis * (_cars[j][3] as Vector3))
			node.visible = true
	for a: AudioStreamPlayer3D in [_wheels, _tail]:
		if a and any != a.playing:
			if any:
				a.play()
			else:
				a.stop()


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
	for o in _over:
		(o[2] as AudioStreamPlayer3D).stop()


## Stop at the line when the train will be across the road on arrival, and wait for the tail;
## a kart that ran past the line stops where it is, still clear of the cars. One already on
## the rails gets no advice: on through. A crossing with arms: stop while they are coming down,
## down or about to rise, every driver ("must"). A train beside the road: nothing to do.
func advice(k: Kart, at_s: float, speed: float) -> Dictionary:
	if _mode == "pass":
		return {}
	var to_cross := ahead(at_s, s)
	if to_cross > 200.0 or to_cross < float(p["half_w"]) + 2.5 + _rails_off(k):
		return {}
	var to_stop := maxf(to_cross - ahead(stop_s(), s), 0.0)
	if _mode == "cross":
		to_stop = maxf(to_stop - _queue_back(k, to_cross), 0.0)
	var period := tm("period")
	var tt := director.clock() + to_cross / maxf(speed, 8.0) - float(p["first"])
	var c := floorf(tt / period)
	if _mode == "cross":
		# (told from 1.5 s before the arms move, braking gently: no bot reaches them going too fast to stop;
		# held until it would reach the line after they are up again, and one waiting at the stop line until
		# they are up: released while they were still down, a waiting bot drove under them as they rose)
		var g := gate_times()
		var arrive := tt + float(p["first"])
		var at_line := to_stop < 6.0
		for cc: float in [c - 2.0, c - 1.0, c, c + 1.0]:
			if cc < 0.0 or not _will_run(int(cc)):
				continue
			var w := _warn_at(int(cc))
			var up := w + g.y + GATE_MOVE
			if arrive >= w + g.x - 1.5 and (arrive <= up + 0.3 or (at_line and director.clock() < up and director.clock() >= w)):
				return {"vmax": sqrt(2.0 * STOP_BRAKE * to_stop), "must": true}
		return {}
	for cc: float in [c - 1.0, c, c + 1.0]:
		if tt >= cc * period + tm("warn") - 1.0 and tt <= cc * period + block_end() + 0.5 and cc >= 0.0:
			return {"vmax": sqrt(2.0 * BRAKE * to_stop)}
	return {}


## Metres short of the stop line kart k stops: QUEUE_GAP behind the last kart waiting before the arms
## in its lane ahead of it (a bot coming up behind one held at the arms bumped it on under them).
func _queue_back(k: Kart, to_cross: float) -> float:
	if k == null or not is_instance_valid(k):
		return 0.0
	var line := ahead(stop_s(), s)
	var lat := path.lateral(k.global_position, path.index_at(k.lap_progress))
	var back := 0.0
	for o in all_karts():
		if o == k or not is_instance_valid(o) or o.route >= 0 or o.speed > HELD_SPEED or o.state == Kart.State.RESPAWN:
			continue
		var before := ahead(o.lap_progress, s)
		if before >= to_cross or before > line + 30.0 or before < float(p["half_w"]) + 2.0 + _rails_off(o):
			continue
		if absf(path.lateral(o.global_position, path.index_at(o.lap_progress)) - lat) > QUEUE_LANE:
			continue
		back = maxf(back, before + QUEUE_GAP - line)
	return back


## Metres from the rails on to s, along the road in kart k's lane (_rail_off on the road's middle).
func _rails_off(k: Kart) -> float:
	if k == null or not is_instance_valid(k) or _rail_k == 0.0:
		return _rail_off
	return _rail_off - _rail_k * path.lateral(k.global_position, path.index_at(k.lap_progress))


## Lap metres of the line a computer driver stops at.
func stop_s() -> float:
	return _stop_s if is_finite(_stop_s) else float(p["stop"][0])


func blocks_respawn(at_s: float) -> bool:
	if _mode == "pass":
		return false
	return absf(fposmod(at_s - s + path.length * 0.5, path.length) - path.length * 0.5) <= 14.0


func is_active(t: float) -> bool:
	if _mode == "pass":
		return false
	var u := _seq(run_at(t))
	return u >= 0.0 and u < _ring_end() - (GATE_MOVE if _mode == "cross" else 0.0)


## A train beside the road is scenery to the race: no mark on the minimap.
func on_map() -> bool:
	return _mode != "pass"


# ---------------------------------------------------------------- the crossing's guard
## (The server) who the arms hold on this approach and who they held on each kart's last pass, and
## just before each run whether to call it off.
func _guard(t: float, run: Array) -> void:
	var u := _seq(run)
	var g := gate_times()
	var shut := u >= g.x and u <= g.y + GATE_MOVE
	for k in all_karts():
		if not is_instance_valid(k):
			continue
		var before := ahead(k.lap_progress, s)
		var prev: float = _before.get(k, before)
		_before[k] = before
		if k.route >= 0:
			continue
		# waiting before the arms (not on the rails) while they move or are down
		if shut and before < 45.0 and before > float(p["half_w"]) + 2.0 + _rails_off(k) and k.speed < HELD_SPEED:
			_held_now[k] = true
		# over the line: this approach becomes its last pass (pushed back over it in a pack and on
		# again a moment later, a kart it held stays held)
		if prev < 20.0 and before > path.length - 20.0:
			var again := t - float(_passed.get(k, -1e9)) < 10.0
			_held_last[k] = bool(_held_now.get(k, false)) or (again and bool(_held_last.get(k, false)))
			_held_now.erase(k)
			_passed[k] = t
	var next := _timetable(t + DECIDE)
	if next.is_empty():
		return
	var c := int(next[0])
	if t >= _start(c) - DECIDE and t < _start(c) and not _decided.has(c):
		_decided[c] = true
		for old in _decided.keys():
			if int(old) < c - 3:
				_decided.erase(old)
		if not _would_go():
			send("skip", [c])


## Metres before the crossing a kart may be as a run is decided and still reach the arms while they
## are down: GUARD_REACH, more on a polyline whose train runs a while before its crossing warns.
func _reach() -> float:
	# (only the ways its trains run: one that always comes from its a end never has the b end's lead)
	var lead := _w0(true) if str(p["dirs"]) == "ab" else (_w0(false) if str(p["dirs"]) == "ba" else maxf(_w0(true), _w0(false)))
	# (at the race's top speed, a fast character in a fast kart, up to when a bot told to stop is let go:
	# the arms up again, + 0.3 s)
	var d := clampi(int(Game.race_setting("difficulty")), 0, Game.DIFFICULTIES.size() - 1)
	var top := maxf(31.0, float(Game.DIFFICULTIES[d]["max_speed"]) * 1.04 * 1.04)
	return maxf(GUARD_REACH, top * (DECIDE + lead + gate_times().y + GATE_MOVE + 0.3))


## The guard: no run while a kart the arms held last time is within _reach() metres of the crossing.
func _would_go() -> bool:
	for k in _held_last.keys():
		if not is_instance_valid(k):
			_held_last.erase(k)
			_held_now.erase(k)
			_before.erase(k)
			_passed.erase(k)
			continue
		var kk := k as Kart
		# (on a branch a kart's lap metres are already the main loop's beside it)
		if bool(_held_last[k]) and not kk.finished and ahead(kk.lap_progress, s) < _reach():
			return false
	return true


## Will run c go, as far as this peer knows: not if the server called it off; before it has
## decided, the server's own guess, and everyone else's "yes".
func _will_run(c: int) -> bool:
	if not _guarded():
		return true
	if _skip.has(c):
		return false
	if director.authority() and not _decided.has(c) and director.clock() < _start(c):
		return _would_go()
	return true


## "skip" [run]: the server called that run off (only a run about to start or just started counts:
## a stale or forged one is dropped).
func on_event(kind: String, args: Array) -> void:
	if kind != "skip" or args.is_empty() or not _guarded():
		return
	var c := int(args[0])
	var now := _timetable(maxf(director.clock(), _last_t) + DECIDE)
	if now.is_empty() or absi(c - int(now[0])) > 1:
		return
	_skip[c] = true
	for old in _skip.keys():
		if int(old) < c - 3:
			_skip.erase(old)
