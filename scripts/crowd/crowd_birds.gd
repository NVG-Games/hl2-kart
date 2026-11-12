class_name CrowdBirds
extends Node3D
## The flocks of the "birds" eggs: pigeons, crows and seagulls peck and hop on the
## ground, scatter calling when a kart comes within 9 m or something explodes within
## 40 m, and drift back 20-35 s later; HL1 boids circle high over the canyon.

const MODELS := {"pigeon": "pigeon", "crow": "crow", "seagull": "seagull", "boid": "hl1/boid"}
const SCARE := 9.0
const BLAST := 40.0
const NEAR := 90.0  # metres from the camera a flock is looked after
const HZ := 30.0  # updates a second of the wings and of the circling boids, whatever the frame rate

var director: CrowdDirector
var flocks: Array = []  # [{species, center, radius, air, birds: [{node, skel, wings, home}], state, back_at}]
var _flying := 0  # birds in the air that flap (per-frame wing beats)
var _t := 0.0
var _acc := 0.0


func setup(d: CrowdDirector, eggs: Array) -> void:
	director = d
	name = "CrowdBirds"
	for e in eggs:
		if str(e.get("kind", "")) != "birds":
			continue
		var sp := str(e.get("species", "pigeon"))
		var key: String = MODELS.get(sp, sp)
		if not Game.models.has(key):
			key = "crow" if Game.models.has("crow") else ""
		if key == "":
			continue
		var c := CrowdEggs._v(e["center"])
		var f := {"species": sp, "center": c, "radius": float(e.get("radius", 6.0)), "air": sp == "boid",
			"birds": [], "state": "ground", "back_at": 0.0}
		for k in int(e.get("count", 8)):
			var n := Game.spawn_model(key)
			add_child(n)
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				(mi as GeometryInstance3D).visibility_range_end = 120.0
			var a := randf() * TAU
			var home: Vector3 = c + Vector3(cos(a), 0.0, sin(a)) * float(f["radius"]) * sqrt(randf())
			n.position = home + (Vector3.UP * randf_range(14.0, 24.0) if f["air"] else Vector3.ZERO)
			n.rotation.y = randf() * TAU
			var sks := n.find_children("*", "Skeleton3D", true, false)
			var sk: Skeleton3D = sks[0] if sks.size() > 0 else null
			var wings: Array = []
			if sk:
				for b in ["Crow.Humerus_L", "Crow.Humerus_R"]:
					var bi := sk.find_bone(b)
					if bi >= 0:
						wings.append([bi, sk.get_bone_pose_rotation(bi), 1.0 if b.ends_with("L") else -1.0])
			(f["birds"] as Array).append({"node": n, "skel": sk, "wings": wings, "home": home,
				"phase": randf() * TAU, "next": randf_range(0.5, 3.0)})
		flocks.append(f)
	set_process(false)
	for f in flocks:
		if f["air"]:
			set_process(true)


## [species, first bird] of every flock (the crowd tests photograph them).
func nodes() -> Array:
	return flocks.map(func(f: Dictionary) -> Array: return [str(f["species"]), f["birds"][0]["node"]])


## Every 0.1 s from the director: hopping, pecking and karts that come too close.
func tick(now: float, cp: Vector3) -> void:
	for f in flocks:
		var c: Vector3 = f["center"]
		if c.distance_to(cp) > NEAR + float(f["radius"]):
			continue
		match str(f["state"]):
			"ground":
				for k in director.karts:
					if k.global_position.distance_to(c) < SCARE + float(f["radius"]):
						_scatter(f, now)
						break
				if str(f["state"]) == "ground":
					_peck(f)
			"away":
				if now > float(f["back_at"]):
					_return(f)


func on_event(kind: StringName, pos: Vector3) -> void:
	if kind != &"explosion":
		return
	for f in flocks:
		if (f["center"] as Vector3).distance_to(pos) < BLAST and str(f["state"]) == "ground":
			_scatter(f, CrowdActor.now())


func _peck(f: Dictionary) -> void:
	for b in f["birds"]:
		b["next"] = float(b["next"]) - 0.1
		if float(b["next"]) > 0.0:
			continue
		b["next"] = randf_range(1.0, 3.0)
		var n: Node3D = b["node"]
		var tw := n.create_tween()
		if randf() < 0.5:
			# a peck: nose down and up again
			tw.tween_property(n, "rotation:x", 0.5, 0.12)
			tw.tween_property(n, "rotation:x", 0.0, 0.18)
		else:
			# a hop: a little arc, never far from home
			var home: Vector3 = b["home"]
			var to := home + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
			var from := n.position
			n.rotation.y = atan2(to.x - from.x, to.z - from.z)
			tw.tween_method(func(u: float): n.position = from.lerp(to, u) + Vector3.UP * 0.15 * 4.0 * u * (1.0 - u),
				0.0, 1.0, 0.25)


## Off they go, up and away from the flock's middle, calling.
func _scatter(f: Dictionary, now: float) -> void:
	f["state"] = "flying"
	f["back_at"] = now + randf_range(20.0, 35.0)
	var c: Vector3 = f["center"]
	director.audio.bird_call(str(f["species"]), c)
	director.audio.flapping(c, true)
	if director.trace:
		director.decisions.append("egg birds scatter %s" % f["species"])
	var left: Array = [f["birds"].size()]
	for b in f["birds"]:
		var n: Node3D = b["node"]
		var a := randf() * TAU
		var to := c + Vector3(cos(a) * randf_range(30.0, 60.0), randf_range(15.0, 25.0), sin(a) * randf_range(30.0, 60.0))
		n.rotation = Vector3(0.0, atan2(to.x - n.position.x, to.z - n.position.z), 0.0)
		_flying += 1
		set_process(true)
		var tw := n.create_tween()
		tw.tween_property(n, "position", to, randf_range(2.5, 4.0)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			n.visible = false
			_flying -= 1
			left[0] -= 1
			if left[0] == 0:
				f["state"] = "away"
				director.audio.flapping(c, false))


## Back down, gliding in to their spots.
func _return(f: Dictionary) -> void:
	f["state"] = "landing"
	var left: Array = [f["birds"].size()]
	for b in f["birds"]:
		var n: Node3D = b["node"]
		var home: Vector3 = b["home"]
		var a := randf() * TAU
		n.position = home + Vector3(cos(a) * 40.0, 20.0, sin(a) * 40.0)
		n.rotation = Vector3(0.0, atan2(home.x - n.position.x, home.z - n.position.z), 0.0)
		n.visible = true
		_flying += 1
		set_process(true)
		var tw := n.create_tween()
		tw.tween_property(n, "position", home, randf_range(3.0, 4.5)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func():
			_flying -= 1
			_rest_wings(b)
			left[0] -= 1
			if left[0] == 0:
				f["state"] = "ground")


func _rest_wings(b: Dictionary) -> void:
	var sk: Skeleton3D = b["skel"]
	for w in b["wings"]:
		sk.set_bone_pose_rotation(w[0], w[1])


## Wing beats for birds in the air; the boids circling over the canyon.
func _process(delta: float) -> void:
	_acc += delta
	if _acc < 1.0 / HZ:
		return
	_t += _acc
	_acc = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var busy := _flying > 0
	for f in flocks:
		var c: Vector3 = f["center"]
		var air: bool = f["air"]
		if c.distance_to(cp) > NEAR + 60.0 or not (air or str(f["state"]) == "flying" or str(f["state"]) == "landing"):
			continue
		for b in f["birds"]:
			var n: Node3D = b["node"]
			var ph: float = b["phase"]
			if air:
				busy = true
				var a := _t * 0.35 + ph
				var r := float(f["radius"]) + 4.0 * sin(_t * 0.5 + ph)
				var p := c + Vector3(cos(a) * r, 18.0 + 3.0 * sin(_t * 0.8 + ph), sin(a) * r)
				n.rotation.y = atan2(-sin(a), cos(a))
				n.position = p
			var sk: Skeleton3D = b["skel"]
			for w in b["wings"]:
				var beat := sin(_t * 22.0 + ph) * 0.8
				sk.set_bone_pose_rotation(w[0], (w[1] as Quaternion) * Quaternion(Vector3.FORWARD, beat * float(w[2])))
	if not busy:
		set_process(false)
