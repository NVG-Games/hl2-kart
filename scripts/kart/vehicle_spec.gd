class_name VehicleSpec
extends RefCounted
## Layout of one rideable vehicle in kart space (front = -Z), derived from its
## Game.VEHICLES entry and the converted model's metadata (wheel attachments,
## driver eyes, bounds). Model space has the front at +Z, so it is turned 180°.

var id := "buggy"
var def := {}
var meta := {}
var scale := 1.0
var yaw := 0.0  # extra model turn for props whose long side is not along Z (bathtub)
var model_pos := Vector3.ZERO  # kart-local position of the model root (model yawed 180°)
var wheels: Array = []  # [{pos (kart-local centre), r, front, model}]
var extra_wheels: Array = []  # visual-only wheel centres (kart-local)
var eye := Vector3(-0.24, 1.44, 0.4)  # where the driver's eyes go (kart-local); unused for Dog
var has_eye := true
var box_size := Vector3(2.1, 0.75, 4.2)
var box_center := Vector3(0, 0.85, 0)
var width := 2.6
var length := 4.5
var height := 2.5
var bump_r := 1.3
var bump_off := 1.05
var mid_z := 0.0
var model_y := 0.0

static var _cache := {}


static func get_spec(vid: String) -> VehicleSpec:
	if not _cache.has(vid):
		_cache[vid] = VehicleSpec.new(vid)
	return _cache[vid]


## model-space point -> kart-local (yaw 180°, scaled, centred on the axles)
func to_kart(p: Vector3) -> Vector3:
	var q := p.rotated(Vector3.UP, yaw)
	return Vector3(-q.x * scale, q.y * scale + model_y, -q.z * scale - mid_z)


func _att(name: String) -> Variant:
	var a: Dictionary = meta.get("attachments", {})
	if a.has(name):
		var o: Array = a[name]["origin"]
		return Vector3(o[0], o[1], o[2])
	return null


func _init(vid: String) -> void:
	def = Game.vehicle(vid)
	id = def["id"]
	meta = Game.load_json("res://assets/models/%s.json" % def["model"])
	scale = float(def.get("scale", 1.0))
	yaw = deg_to_rad(float(def.get("yaw", 0.0)))
	var mlo := Vector3(meta["aabb_min"][0], meta["aabb_min"][1], meta["aabb_min"][2])
	var mhi := Vector3(meta["aabb_max"][0], meta["aabb_max"][1], meta["aabb_max"][2])
	# bounds after the extra yaw, still in (unscaled) model units
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for i in 8:
		var c := Vector3(mhi.x if i & 1 else mlo.x, mhi.y if i & 2 else mlo.y, mhi.z if i & 4 else mlo.z).rotated(Vector3.UP, yaw)
		lo = lo.min(c)
		hi = hi.max(c)
	var radius: Array = def.get("radius", [0.45, 0.45])
	if def.has("hull_lift"):
		model_y = float(def["hull_lift"]) - lo.y * scale
	# wheel centres in model space
	var wm := []
	if def.get("wheels", "") == "attachments":
		for n in ["wheel_fl", "wheel_fr", "wheel_rl", "wheel_rr"]:
			var p = _att(n)
			wm.append({"p": p if p != null else Vector3.ZERO, "front": n.contains("_f")})
	else:
		var wp: Array = def.get("wheel_pos", [])
		for i in wp.size():
			wm.append({"p": wp[i], "front": i < 2})
	var zf := 0.0
	var zr := 0.0
	for w in wm:
		if w["front"]:
			zf += to_kart(w["p"]).z * 0.5
		else:
			zr += to_kart(w["p"]).z * 0.5
	mid_z = (zf + zr) * 0.5
	for w in wm:
		var r: float = radius[0] if w["front"] else radius[1]
		var p: Vector3 = w["p"]
		var k := to_kart(p)
		if def.get("wheels", "") != "attachments":
			k.y = r  # prop / virtual wheels sit on the ground
		wheels.append({"pos": k, "r": r, "front": w["front"], "model": p})
	for p in def.get("extra_wheels", []):
		var k2 := to_kart(p)
		k2.y = radius[1]
		extra_wheels.append(k2)
	# driver eyes
	if def.has("eyes"):
		var e = _att(def["eyes"])
		if e != null:
			eye = to_kart((e as Vector3) + def.get("eye_adjust", Vector3.ZERO))
	elif def.has("eye_pos"):
		eye = to_kart(def["eye_pos"])
	else:
		has_eye = false
	# body extents (kart space)
	width = (hi.x - lo.x) * scale
	length = (hi.z - lo.z) * scale
	height = hi.y * scale + model_y
	if def.get("rig", "") == "dog":
		width = 1.7
		length = 1.9
	var bottom := 0.6  # wheels carry the car; the chassis only stops walls, not 0.5 m kerbs
	var top := clampf(height * 0.75, bottom + 0.5, bottom + 1.25)
	box_size = Vector3(clampf(width * 0.85, 1.2, 3.0), top - bottom, clampf(length * 0.9, 1.6, 5.4))
	var cz := -((hi.z + lo.z) * 0.5) * scale - mid_z
	if def.get("rig", "") == "dog":
		cz = 0.0
	# long overhangs (army APC) dig the chassis corners into kerbs and verge slopes:
	# keep the box within ~0.45 m of the axles and let the round nose cover the rest
	var wheelbase := absf(rear_axle_z() - front_axle_z())
	if box_size.z > wheelbase + 0.9:
		box_size.z = wheelbase + 0.9
		cz = (rear_axle_z() + front_axle_z()) * 0.5
	box_center = Vector3(0, (top + bottom) * 0.5, cz)
	bump_r = clampf(box_size.x * 0.5 + 0.15, 0.9, 1.6)
	bump_off = maxf(0.0, box_size.z * 0.5 - bump_r)


func front_axle_z() -> float:
	return (wheels[0]["pos"] as Vector3).z


func rear_axle_z() -> float:
	return (wheels[2]["pos"] as Vector3).z


func rear_end_z() -> float:
	return box_center.z + box_size.z * 0.5
