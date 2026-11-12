class_name CrowdEggs
extends Node3D
## The easter eggs the track generator placed ("crowd_eggs"): G-Man sightings, the
## Hazard Course hologram, Lamarr, shambling zombies, Gnome Chompski, the spot the
## Nihilanth laughs from; and the start arch's remarks on the race (the Breencast,
## the Black Mesa announcer, the HECU radio).

const HOLO_SHADER := preload("res://shaders/hologram.gdshader")
const REACTOR_VOX := "vox:doctor freeman _comma please report to the lambda reactor core immediately"
## the G-Man shows only between these camera distances (metres; further off he is a few pixels)
## and in view, counts as seen once he stands this share of the view's height (40 px of 900),
## stays at least GMAN_STAY seconds (unless the camera comes within GMAN_NEAR) and at most GMAN_MAX
const GMAN_NEAR := 15.0
const GMAN_SHOW := Vector2(25.0, 70.0)
const GMAN_SEEN := 40.0 / 900.0
const GMAN_STAY := 3.0
const GMAN_MAX := 8.0
const GMAN_HEIGHT := 1.8

var director: CrowdDirector
var _gman: Dictionary = {}  # {actor, look, window, route, armed, shown, seen, seen_px, done, skip}
var _holos: Array = []  # [{actor, pos, gap, lap}]
var _lamarr: Dictionary = {}  # {node, path, i, next, busy_until, kleiner_t}
var _zombies: Array = []  # [{actor, a, b, next_moan, recoil}]
var _zombie_alarm := 0.0
var _nihilanth: Variant = null
var _gnome: Node3D
var _said := {}  # remarks made once a race


func setup(d: CrowdDirector, list: Array) -> void:
	director = d
	name = "CrowdEggs"
	for e in list:
		match str(e.get("kind", "")):
			"gman":
				_add_gman(e)
			"holo":
				_add_holo(e)
			"lamarr":
				_add_lamarr(e)
			"zombies":
				_add_zombies(e)
			"gnome":
				_gnome = Game.spawn_model("props_junk/gnome")
				add_child(_gnome)
				_gnome.position = _v(e["pos"])
				_gnome.rotation.y = float(e.get("yaw", 0.0))
			"nihilanth":
				_nihilanth = _v(e["pos"])


## The eggs' spectators animating now (the director moves them with the crowd's).
func moving() -> Array[CrowdActor]:
	var all: Array = [_gman.get("actor")]
	for h in _holos:
		all.append(h["actor"])
	for z in _zombies:
		all.append(z["actor"])
	var out: Array[CrowdActor] = []
	for a in all:
		if a != null and (a as CrowdActor).player and (a as CrowdActor).player.active:
			out.append(a)
	return out


## [kind, node] of every egg placed (the crowd tests photograph them).
func nodes() -> Array:
	var out := []
	if not _gman.is_empty():
		out.append(["gman", _gman["actor"]])
	for h in _holos:
		out.append(["holo", h["actor"]])
	if not _lamarr.is_empty():
		out.append(["lamarr", _lamarr["node"]])
	for z in _zombies:
		out.append(["zombies", z["actor"]])
	if _gnome:
		out.append(["gnome", _gnome])
	return out


static func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _actor(m: Dictionary, key: String, vis := 200.0) -> CrowdActor:
	var a := CrowdActor.new()
	add_child(a)
	a.setup(m, key, vis)
	if a.skel:
		a.animate(CrowdPoses.library(key, a.skel, a.model))
	return a


static func _model(e: Dictionary, default: String, fallback: String) -> String:
	var k := str(e.get("model", default))
	if Game.models.has(k):
		return k
	return default if Game.models.has(default) else fallback


# ---------------------------------------------------------------- the G-Man
## Once a race (by chance), from the second lap, while the camera's kart is in the egg's
## window and he is in view 25-70 m off: he stands there fixing his tie, watching you, a faint
## light on him. Seen once he is big enough on screen; gone when you come within 15 m, after
## eight seconds, or when he is out of view once he has stood there three seconds (and three
## since you saw him).
func _add_gman(e: Dictionary) -> void:
	var key := _model(e, "gman_high", "gman_high")
	var a := _actor({"pos": e["pos"], "yaw": e.get("yaw", 0.0), "role": "cameo", "seed": 31}, key, 0.0)
	a.visible = false
	# over his shoulder, in front of him (he faces the road): he stands out in dark places too
	var light := OmniLight3D.new()
	light.light_color = Color(0.85, 0.9, 1.0)
	light.omni_range = 4.0
	light.light_energy = 1.3
	light.shadow_enabled = false
	light.position = Vector3(0.0, 2.2, 0.9)
	a.add_child(light)
	var w: Array = e.get("window", [0.0, 0.0])
	# the invisible city walls hide nobody
	var skip: Array[RID] = []
	for b in director.track.find_children("col_colonly*", "StaticBody3D", true, false):
		skip.append((b as StaticBody3D).get_rid())
	_gman = {"actor": a, "look": null, "window": Vector2(w[0], w[1]), "route": director.route_of(e),
		"armed": randf() < float(e.get("chance", 0.4)), "shown": -1.0, "seen": -1.0, "seen_px": 0.0, "done": false,
		"skip": skip}
	if a.skel:
		var l := CrowdLook.new()
		if l.setup(a.skel):
			a.skel.add_child(l)
			l.active = false
			a.look = l  # its head turns in the skeleton updates the director gives it
			_gman["look"] = l


func _tick_gman(now: float, cam: Camera3D) -> void:
	if _gman.is_empty() or not _gman["armed"] or _gman["done"]:
		return
	var a: CrowdActor = _gman["actor"]
	var me := director.me()
	var cp := cam.global_position
	var d := a.global_position.distance_to(cp)
	if float(_gman["shown"]) < 0.0:
		# the window is on the road he is seen from (a branch's, or the main loop's)
		if me == null or me.lap < 1 or d < GMAN_SHOW.x or d > GMAN_SHOW.y \
				or not director.in_stretch(me, _gman["route"], _gman["window"]) or gman_size(cam) <= 0.0:
			return
		_gman["shown"] = now
		a.visible = true
		a.set_active(true)
		# playing the G-Man yourself: your double nods to you
		a.play(&"bow" if me.character_id == "gman_high" else &"tie", 0.0)
		if _gman["look"]:
			(_gman["look"] as CrowdLook).active = true
		if director.trace:
			director.decisions.append("egg gman shown")
		if me.lap == director.laps() - 1 and randf() < 0.2:
			director.audio.say(a.global_position + Vector3.UP * 1.6, &"gman",
				"hl1" if director.world() != "combine" else "hl2", CrowdAudio.Prio.EGG, true)
		return
	if _gman["look"]:
		(_gman["look"] as CrowdLook).target = cp
	a.update(now)
	var size := gman_size(cam)
	_gman["seen_px"] = maxf(float(_gman["seen_px"]), size)
	if size >= GMAN_SEEN and float(_gman["seen"]) < 0.0:
		_gman["seen"] = now
		if director.trace:
			director.decisions.append("egg gman seen")
	var t := now - float(_gman["shown"])
	var seen: float = _gman["seen"]
	var stay := t < GMAN_STAY or (seen >= 0.0 and now - seen < GMAN_STAY)
	if d < GMAN_NEAR or t > GMAN_MAX or (size <= 0.0 and not stay):
		a.visible = false
		a.set_active(false)
		_gman["done"] = true
		if director.trace:
			director.decisions.append("egg gman gone")


## The share of `cam`'s view height the G-Man stands (0 off screen or behind something solid).
func gman_size(cam: Camera3D) -> float:
	var feet: Vector3 = (_gman["actor"] as CrowdActor).global_position
	var chest := feet + Vector3.UP * GMAN_HEIGHT * 0.75
	if not cam.is_position_in_frustum(chest):
		return 0.0
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, chest, Game.LAYER_WORLD, _gman["skip"])
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return 0.0
	var h := cam.get_viewport().get_visible_rect().size.y
	return absf(cam.unproject_position(feet).y - cam.unproject_position(feet + Vector3.UP * GMAN_HEIGHT).y) / h


# ---------------------------------------------------------------- the hologram
## The Hazard Course trainer at a jump: tells you to jump the gap as you come up to it,
## that you fell short when you do, nice job on a clean landing.
func _add_holo(e: Dictionary) -> void:
	if not Game.models.has("hl1/holo"):
		return
	var a := _actor({"pos": e["pos"], "yaw": e.get("yaw", 0.0), "role": "cameo", "seed": 5}, "hl1/holo", 180.0)
	for mi in a.model.find_children("*", "MeshInstance3D", true, false):
		var m := ShaderMaterial.new()
		m.shader = HOLO_SHADER
		var src := (mi as MeshInstance3D).get_surface_override_material(0)
		if src is ShaderMaterial:
			m.set_shader_parameter("albedo_tex", (src as ShaderMaterial).get_shader_parameter("albedo_tex"))
		(mi as GeometryInstance3D).material_override = m
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.35, 0.6, 1.0)
	glow.omni_range = 6.0
	glow.light_energy = 1.2
	glow.position = Vector3(0, 1.2, 0)
	a.add_child(glow)
	var g: Array = e.get("gap", [0.0, 0.0])
	_holos.append({"actor": a, "gap": Vector2(g[0], g[1]), "route": director.route_of(e), "lap": -99})


func _tick_holos(now: float, cp: Vector3) -> void:
	var me := director.me()
	for h in _holos:
		var a: CrowdActor = h["actor"]
		a.set_active(a.global_position.distance_to(cp) < 90.0)
		a.update(now)
		# its jump is on one road (a branch's, or the main loop's): only racers on that road
		var r: int = h["route"]
		if me == null or me.route != r:
			continue
		var gap: Vector2 = h["gap"]
		var before := director.route_delta(r, gap.x - CrowdDirector.along(me, r))
		if before > 30.0 and before < 90.0 and int(h["lap"]) != me.lap \
				and me.global_position.distance_to(a.global_position) < 110.0:
			h["lap"] = me.lap
			a.queue(&"point", now, director.track.path.geo(r).center_at(gap.x))
			_holo_say(a, "approach")


func _holo_say(a: CrowdActor, cat: String) -> void:
	if director.trace:
		director.decisions.append("line egg holo %s" % cat)
	director.audio.say(a.global_position + Vector3.UP * 1.6, &"holo", cat, CrowdAudio.Prio.EGG, true)


## The holo nearest `p` within `r` metres (null if none).
func _holo_near(p: Vector3, r: float) -> CrowdActor:
	for h in _holos:
		var a: CrowdActor = h["actor"]
		if a.global_position.distance_to(p) < r:
			return a
	return null


# ---------------------------------------------------------------- Lamarr
## Kleiner's pet hops along the lab floor between the scientists; when Kleiner drives
## by she leaps at his kart and he is delighted.
func _add_lamarr(e: Dictionary) -> void:
	var key := _model(e, "lamarr", "headcrabclassic")
	var pts: Array = []
	for p in e.get("path", []):
		pts.append(_v(p))
	if pts.size() < 2:
		return
	var n := Game.spawn_model(key)
	add_child(n)
	n.position = pts[0]
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lamarr = {"node": n, "path": pts, "i": 0, "dir": 1, "next": CrowdActor.now() + 2.0, "kleiner_t": 0.0}


func _tick_lamarr(now: float, cp: Vector3) -> void:
	if _lamarr.is_empty():
		return
	var n: Node3D = _lamarr["node"]
	if n.global_position.distance_to(cp) > 120.0:
		return
	for k in director.karts:
		if k.character_id == "kleiner" and k.global_position.distance_to(n.global_position) < 12.0 \
				and now > float(_lamarr["kleiner_t"]):
			_lamarr["kleiner_t"] = now + 25.0
			_lamarr["next"] = now + 2.5
			_hop(n, k.global_position + Vector3.UP * 1.4, 1.6, 0.45, true)
			var line := Game.crowd_line("lamarr", "kleiner")
			if line != "" and k.audio:
				k.audio.voice.stream = Game.stream(line)
				k.audio.voice.play()
			if director.trace:
				director.decisions.append("egg lamarr kleiner")
			director.on_event(&"headcrab", n.global_position, k)
			return
	if now < float(_lamarr["next"]):
		return
	_lamarr["next"] = now + randf_range(2.0, 4.0)
	var pts: Array = _lamarr["path"]
	var i: int = _lamarr["i"] + _lamarr["dir"]
	if i < 0 or i >= pts.size():
		_lamarr["dir"] = -_lamarr["dir"]
		i = _lamarr["i"] + _lamarr["dir"]
	_lamarr["i"] = i
	var to: Vector3 = (n.position as Vector3).lerp(pts[i], clampf(3.0 / maxf(n.position.distance_to(pts[i]), 0.1), 0.0, 1.0))
	_hop(n, to, 0.7, 0.4, false)
	if n.global_position.distance_to(cp) < 30.0:
		director.audio.sfx(Game.crowd_line("lamarr", "hop"), n.global_position, -10.0)


## A headcrab's leap: an arc to `to`, `h` metres up, in `secs`; `back` returns to the floor.
func _hop(n: Node3D, to: Vector3, h: float, secs: float, back: bool) -> void:
	var from := n.position
	var d := to - from
	if Vector2(d.x, d.z).length() > 0.1:
		n.rotation.y = atan2(d.x, d.z)
	var tw := create_tween()
	tw.tween_method(func(u: float): n.position = from.lerp(to, u) + Vector3.UP * h * 4.0 * u * (1.0 - u), 0.0, 1.0, secs)
	if back:
		tw.tween_method(func(u: float): n.position = to.lerp(from, u) + Vector3.UP * h * 2.0 * u * (1.0 - u), 0.0, 1.0,
			secs * 1.4)


# ---------------------------------------------------------------- zombies
## A few zombies shamble up and down a path behind a wall, moaning; Father Grigori going
## by makes them recoil.
func _add_zombies(e: Dictionary) -> void:
	var path: Array = e.get("path", [])
	if path.size() < 2:
		return
	var key := _model(e, "zombie/classic", "zombie/classic")
	var a0 := _v(path[0])
	var a1 := _v(path[path.size() - 1])
	for k in int(e.get("count", 3)):
		var u := (float(k) + 0.5) / float(e.get("count", 3))
		var p := a0.lerp(a1, u) + (a1 - a0).cross(Vector3.UP).normalized() * randf_range(-0.8, 0.8)
		var z := _actor({"pos": [p.x, p.y, p.z], "yaw": 0.0, "role": "zombie", "seed": 101 + k * 17}, key, 160.0)
		z.play(&"shamble", 0.0)
		_zombies.append({"actor": z, "a": a0, "b": a1, "next_moan": CrowdActor.now() + randf_range(2.0, 8.0),
			"walking": false, "recoil": 0.0, "moan": _moan(z) if k == 0 else null})


## The pack's moan, a loop that follows its first zombie while the camera is near.
func _moan(z: CrowdActor) -> AudioStreamPlayer3D:
	var path := Game.crowd_line("zombie", "moan")
	if path == "":
		return null
	var m := AudioStreamPlayer3D.new()
	m.stream = Game.stream(path)
	m.bus = "SFX"
	m.volume_db = -10.0
	m.unit_size = 6.0
	m.max_distance = 40.0
	m.position = Vector3.UP * 1.5
	z.add_child(m)
	m.finished.connect(m.play)  # a moan without loop points loops by hand
	return m


func _tick_zombies(now: float, cp: Vector3) -> void:
	for z in _zombies:
		var a: CrowdActor = z["actor"]
		var d := a.global_position.distance_to(cp)
		var moan: AudioStreamPlayer3D = z["moan"]
		if moan and (d < 30.0) != moan.playing:
			if d < 30.0:
				moan.play()
			else:
				moan.stop()
		a.set_active(d < 70.0)
		if d >= 70.0:
			continue
		a.update(now)
		if not z["walking"]:
			_walk(z)
		if now > float(z["next_moan"]) and d < 30.0:
			z["next_moan"] = now + randf_range(6.0, 12.0)
			director.audio.say(a.global_position + Vector3.UP * 1.5, &"zombie", "idle", CrowdAudio.Prio.IDLE)
		for k in director.karts:
			var dk := k.global_position.distance_to(a.global_position)
			if k.character_id == "monk" and dk < 15.0 and now > float(z["recoil"]):
				z["recoil"] = now + 6.0
				a.play(&"flinch", 0.1)
				if director.trace:
					director.decisions.append("egg zombies recoil")
	# scientists and citizens nearby panic now and then
	if now > _zombie_alarm and not _zombies.is_empty():
		var a: CrowdActor = _zombies[0]["actor"]
		if a.global_position.distance_to(cp) < 40.0:
			_zombie_alarm = now + 30.0
			director.on_event(&"zombie", a.global_position)


## Back and forth along the path at a shuffle (0.4-0.6 m/s).
func _walk(z: Dictionary) -> void:
	var a: CrowdActor = z["actor"]
	z["walking"] = true
	var to: Vector3 = z["b"] if a.position.distance_to(z["b"]) > a.position.distance_to(z["a"]) else z["a"]
	to += (to - a.position).cross(Vector3.UP).normalized() * randf_range(-0.6, 0.6)
	var d := to - a.position
	a.rotation.y = atan2(d.x, d.z)
	a.play(&"shamble", 0.3)
	var tw := create_tween()
	tw.tween_property(a, "position", to, d.length() / randf_range(0.4, 0.6))
	tw.tween_callback(func(): z["walking"] = false)


# ---------------------------------------------------------------- remarks and events
func tick(now: float, cam: Camera3D) -> void:
	_tick_gman(now, cam)
	_tick_holos(now, cam.global_position)
	_tick_lamarr(now, cam.global_position)
	_tick_zombies(now, cam.global_position)
	# Gordon under the arch for the first time: "Dr. Freeman, at last"
	if director.gantry and not _said.has("at_last") and director.racing():
		for k in director.karts:
			if k.character_id == "gordon" and k.global_position.distance_to(director.gantry.global_position) < 20.0:
				_said["at_last"] = true
				_remark(Game.crowd_line("breen", "at_last"), 2, "combine")


## The start arch comments: `path` (or a VOX sentence) on worlds in `worlds` only.
func _remark(path: String, prio: int, worlds: String) -> void:
	if director.gantry == null or path == "" or not worlds.contains(director.world()):
		return
	var ok := director.gantry.comment(path, prio)
	if director.trace:
		director.decisions.append("remark %s %s" % [path.get_file().get_basename(), "played" if ok else "skipped"])


func on_event(kind: StringName, pos: Vector3, a: Kart, _b: Kart, info: Variant) -> void:
	var me := director.me()
	match kind:
		&"lead":
			if a == null:
				return
			if a.character_id == "gordon":
				_remark(Game.crowd_line("breen", "to_freeman"), 2, "combine")
				_remark(REACTOR_VOX, 2, "blackmesa")
				_remark(Game.crowd_line("hecu", "freeman"), 2, "military")
			elif a.character_id == "breen":
				var l := Game.crowd_line("breen", "rabble")
				_remark(l if l != "" else Game.voice_line("breen", "start"), 1, "combine")
			elif a.character_id == "shephard":
				_remark(Game.crowd_line("hecu", "salute"), 1, "military")
		&"fall":
			if a and a.character_id == "gordon":
				_remark(Game.crowd_line("breen", "mock"), 2, "combine")
			var h := _holo_near(pos, 70.0)
			if h:
				_holo_say(h, "fall")
			if _nihilanth is Vector3 and (info == null or int(info) == Kart.Rescue.FALL) and randf() < 0.3:
				var cam := get_viewport().get_camera_3d()
				if cam:
					var dir := ((_nihilanth as Vector3) - cam.global_position).normalized()
					Game.play_3d(Game.crowd_line("nihilanth", "laugh"), cam.global_position + dir * 40.0, 0.0, 1.0, 40.0)
					if director.trace:
						director.decisions.append("egg nihilanth laugh")
		&"land":
			if a and a == me:
				var h := _holo_near(pos, 80.0)
				if h:
					h.set_active(true)
					h.queue(&"clap", CrowdActor.now())
					_holo_say(h, "good")
		&"start":
			if not _holos.is_empty():
				_remark(Game.crowd_line("holo", "start"), 1, "blackmesa")
		&"final_lap":
			if a and a == me and not _said.has("final_lap"):
				_said["final_lap"] = true
				_remark(Game.crowd_line("breen", "disruptor"), 1, "combine")
		&"finish":
			var place := int(info) if info != null else 1
			if a and a.character_id == "gordon" and place == 1:
				_remark(Game.crowd_line("breen", "lose"), 3, "combine")
			if a and a == me and place == 1 and not _holos.is_empty():
				_remark(Game.crowd_line("holo", "win"), 3, "blackmesa")
