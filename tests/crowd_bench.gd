extends Node3D
## Spectator cost: flies a chase camera at race speed over the start and the stretches where
## the most spectators are in view, once without crowds and once with them, at each graphics
## quality (LOW with FEW, MEDIUM and HIGH with FULL). Prints what the crowds add: draw calls,
## GPU time, the CPU time of their processing per stretch, render CPU and frame time while
## flying, and the most actors animated and looking; exits 1 when the worst place exceeds the
## budget (crowds design, section 10).
## usage: godot --path . res://tests/crowd_bench.tscn -- <track> [crowd.json|-] [speed]

## [quality, crowds setting, max extra draw calls, max extra GPU ms, max extra CPU ms, animated, lookers]
const RUNS := [[2, 2, 1100, 1.0, 0.8, 70, 16], [1, 2, 800, 0.7, 0.5, 45, 10], [0, 1, 450, 0.4, 0.3, 20, 0]]
const BIN := 10.0  # metres of lap per measurement

var trk: Track
var cam: Camera3D
var data := {}
var speed := 30.0
var failures := 0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var tid: String = a[0]
	var src: String = a[1] if a.size() > 1 else "-"
	speed = float(a[2]) if a.size() > 2 else 30.0
	trk = Track.new()
	add_child(trk)
	trk.build(tid)
	# the spectators the track spawns itself make way for the ones under test
	if trk.crowd:
		trk.crowd.free()
		trk.crowd = null
	if src != "-":
		data = Game.load_json(src)
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 9000.0
	add_child(cam)
	cam.current = true
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var route := _route()
	print("route: %s" % [route])
	Game.settings["vsync"] = false
	for r in RUNS:
		Game.settings["quality"] = r[0]
		Game.apply_settings()
		Game.settings["crowds"] = 0
		# every flight goes twice: the first compiles the shaders for what comes into view
		await _fly(route, null, 3.0)
		var base := await _fly(route, null)
		Game.settings["crowds"] = r[1]
		var crowd := CrowdDirector.spawn_for(trk, data)
		while crowd and not crowd.ready_all():
			await get_tree().process_frame
		await _fly(route, crowd, 3.0)
		var with := await _fly(route, crowd)
		var cpu := []
		for w in route:
			cpu.append(await _cpu_cost(crowd, (w[0] + w[1]) * 0.5))
		_compare(r, base, with, cpu)
		if crowd:
			crowd.queue_free()
			await get_tree().process_frame
	print("bench budget failures: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## Lap stretches to fly: the start, then around the three places where a chase camera
## sees the most spectators.
func _route() -> Array:
	var people: Array = data.get("crowds", trk.data.get("crowds", []))
	var p := trk.path
	var score := []
	for i in range(0, p.n, 2):
		var c := p.center[i] - p.fwd[i] * 8.6 + Vector3.UP * 3.3
		var n := 0
		for m in people:
			var dv := Vector3(m["pos"][0], m["pos"][1], m["pos"][2]) - c
			if dv.length() < 150.0 and dv.dot(p.fwd[i]) > -0.25 * dv.length():
				n += 1
		score.append([n, i * p.step])
	score.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	var out := [[-80.0, 160.0]]
	for e in score:
		if out.size() >= 4:
			break
		if out.all(func(w: Array) -> bool: return absf(_wrap(e[1] - (w[0] + w[1]) * 0.5)) > 150.0):
			out.append([e[1] - 60.0, e[1] + 60.0])
	return out


func _wrap(d: float) -> float:
	var len := trk.path.length
	return fposmod(d + len * 0.5, len) - len * 0.5


## Fly the route (`faster` times race speed); per BIN metres of lap: [frames, frame ms,
## render cpu ms, gpu ms, draw calls, primitives, animated, lookers] (times summed, the rest
## the most in a frame).
func _fly(route: Array, crowd: CrowdDirector, faster := 1.0) -> Dictionary:
	var vp := get_viewport().get_viewport_rid()
	var bins := {}
	for w in route:
		var s: float = w[0]
		_place(s)
		for f in 20:
			await get_tree().process_frame
		while s < w[1]:
			var t0 := Time.get_ticks_usec()
			await get_tree().process_frame
			var frame := (Time.get_ticks_usec() - t0) / 1000.0
			var dt := get_process_delta_time()
			s += speed * faster * dt
			_place(s)
			var key := int(floor(s / BIN))
			var b: Array = bins.get(key, [0, 0.0, 0.0, 0.0, 0, 0, 0, 0])
			b[0] += 1
			b[1] += frame
			b[2] += RenderingServer.viewport_get_measured_render_time_cpu(vp)
			b[3] += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			b[4] = maxi(b[4], int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			b[5] = maxi(b[5], int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
			if crowd:
				var on := _busy(crowd)
				b[6] = maxi(b[6], on.x)
				b[7] = maxi(b[7], on.y)
			bins[key] = b
	return bins


## Spectators animating now (x) and turning their heads (y).
static func _busy(crowd: CrowdDirector) -> Vector2i:
	var on := Vector2i.ZERO
	for x in crowd.actors:
		if x.player and x.player.active:
			on.x += 1
		if x.look and x.look.active:
			on.y += 1
	return on


## CPU time the crowds take with the camera held at lap metres s, as milliseconds of a 60 fps
## frame: what one clip update costs (a player's advance and the skeleton and skin update it
## causes: frames advancing every spectator animated there against frames advancing none, the 3D
## view rendered small so the frame is CPU-bound, in pairs so a load drifting on the machine
## cancels out) times the updates a second the director gives them, plus its own logic (every
## group once, the budget, the eggs and the birds, timed in place) at the 10 Hz it runs at.
func _cpu_cost(crowd: CrowdDirector, s: float) -> float:
	if crowd == null:
		return 0.0
	_place(s)
	for f in 30:
		await get_tree().process_frame
	var vp := get_viewport()
	var res := vp.scaling_3d_scale
	vp.scaling_3d_scale = 0.25
	crowd.set_process(false)
	var hot: Array = crowd._moving.duplicate()
	var warm: Array = crowd._moving_far.duplicate()
	var all := hot + warm
	var unit := 0.0
	if not all.is_empty():
		var diffs := []
		for pair in 16:
			var mean := []
			for on in [true, false]:
				await get_tree().process_frame
				var t0 := Time.get_ticks_usec()
				for f in 30:
					if on:
						for a: CrowdActor in all:
							a.player.advance(0.05)
							if a.look:
								a.skel.advance(0.05)
					await get_tree().process_frame
				mean.append((Time.get_ticks_usec() - t0) / 30.0)
			diffs.append((mean[0] - mean[1]) / all.size())
		diffs.sort()
		unit = diffs[diffs.size() / 2]
	var now := CrowdActor.now()
	var t1 := Time.get_ticks_usec()
	for g in crowd.groups:
		crowd._tick_group(g, now, cam.global_position, -cam.global_basis.z)
	crowd._budget(cam.global_position)
	crowd.eggs.tick(now, cam)
	crowd.birds.tick(now, cam.global_position)
	var logic := float(Time.get_ticks_usec() - t1)
	crowd.set_process(true)
	vp.scaling_3d_scale = res
	var per_s := (hot.size() * CrowdDirector.HOT_HZ + warm.size() * CrowdDirector.WARM_HZ) * unit + 10.0 * logic
	return per_s / 60.0 / 1000.0


func _place(s: float) -> void:
	var tr := trk.path.transform_at(s - 8.6)
	cam.global_position = tr.origin + Vector3.UP * 3.3
	cam.look_at(trk.path.center_at(s + 5.0) + Vector3.UP * 1.4, Vector3.UP)


## What the crowds add per bin against the run without them: the worst bin (draw calls,
## counts) and the 90th percentile (GPU time, which jitters) must stay within the budget, and
## so must the CPU time of their processing in the worst stretch (`cpu`: one per stretch).
func _compare(r: Array, base: Dictionary, with: Dictionary, cpu: Array) -> void:
	var dc := []
	var gpu := []
	var rcpu := []
	var frame := []
	var anim := 0
	var look := 0
	for k in with:
		if not base.has(k):
			continue
		var a: Array = base[k]
		var b: Array = with[k]
		dc.append(b[4] - a[4])
		frame.append(b[1] / b[0] - a[1] / a[0])
		rcpu.append(b[2] / b[0] - a[2] / a[0])
		gpu.append(b[3] / b[0] - a[3] / a[0])
		anim = maxi(anim, b[6])
		look = maxi(look, b[7])
	if dc.is_empty():
		return
	for l in [dc, gpu, rcpu, frame]:
		l.sort()
	var p90 := func(l: Array) -> float: return float(l[int(l.size() * 0.9)])
	var worst: float = cpu.max() if not cpu.is_empty() else 0.0
	var ok: bool = dc[-1] <= r[2] and p90.call(gpu) <= r[3] and worst <= r[4] and anim <= r[5] and look <= r[6]
	print("%s quality %d crowds %d: extra draw calls max %d (budget %d), gpu p90 +%.2f ms (%.1f), cpu +%.2f ms of a 60 fps frame (%.1f; per stretch %s; flying: render cpu p90 +%.2f, frame p90 +%.2f), animated %d (%d), lookers %d (%d)" % [
		"OK  " if ok else "OVER", r[0], r[1], dc[-1], r[2], p90.call(gpu), r[3], worst, r[4],
		"/".join(cpu.map(func(x: float) -> String: return "%.2f" % x)), p90.call(rcpu), p90.call(frame), anim, r[5],
		look, r[6]])
	if not ok:
		failures += 1
