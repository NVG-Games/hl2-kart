class_name Kart
extends RigidBody3D
## Arcade raycast-suspension vehicle on the HL2 jeep (prop_vehicle_jeep):
## mass/suspension/steering cone/turbo from scripts/vehicles/jeep_test.txt,
## plus kart-racer drifting with mini-turbos.

signal item_changed(kart: Kart)
signal got_hit(kart: Kart, by: Kart)

enum State { NORMAL, SPIN, TUMBLE, RESPAWN, FINISHED }

# --- jeep_test.txt: massoverride 1000, wheel radius 18"/22", steering 50deg slow -> 18deg fast
const JEEP_MASS := 1000.0
## wheel layout comes from the chosen vehicle (VehicleSpec): [{pos, r, front}]
var wheels: Array = []
var spec: VehicleSpec
var spring_k := 26000.0
var damp_comp := 3800.0
var damp_reb := 4800.0
var accel_mult := 1.0
var handling := 1.0
const MOUNT_UP := 0.35
const TRAVEL := 0.30
const SPRING_K := 26000.0
const DAMP_COMP := 3800.0
const DAMP_REB := 4800.0

var character_id := "alyx"
var char_data := {}
var racer_index := 0
var is_player := false
var controller: Object = null
var track: Track
var race: Node = null

var state := State.NORMAL
var state_time := 0.0

# input (filled by controller each physics frame)
var in_throttle := 0.0
var in_brake := 0.0
var in_steer := 0.0
var in_drift := false
var in_item := false
var in_look_back := false

# race progress
var path_index := 0
var lap := 0
var lap_progress := 0.0
var total_progress := 0.0
var place := 1
var finished := false
var finish_time := 0.0
var last_valid := Transform3D.IDENTITY
var _last_s := 0.0
var _crossed_half := false
var lap_times: Array[float] = []
var respawns := 0
var _lap_start := 0.0

# dynamics state
var max_speed := 31.0
var speed := 0.0
var fwd_speed := 0.0
var grounded := false
var wheels_on_ground := 0
var offroad := false
var wheel_compress := [0.0, 0.0, 0.0, 0.0]
var wheel_contact := [false, false, false, false]
var wheel_spin := 0.0
var steer_visual := 0.0
var air_time := 0.0
var ground_normal := Vector3.UP

var drifting := false
var drift_dir := 0
var drift_charge := 0.0
var drift_level := 0
var hop_time := 0.0
var boost_time := 0.0
var boost_power := 1.0
var star_time := 0.0  # invulnerable "charged suit"
var shrink_time := 0.0
var _drift_held := false
var _item_held := false

# items
var item := ""
var item_count := 0
var roulette := 0.0
var trailing: Node3D = null  # item held behind the kart

var visual: KartVisual
var audio: KartAudio
var _rng := RandomNumberGenerator.new()

# multiplayer: a remote kart is a kinematic proxy that follows the state its
# owner streams (pack_state / apply_net_state), dead-reckoned to "now"
const NET_FLOATS := 26
var net_slot := -1
var nick := ""
var is_bot := false
var remote := false
var _net_t := -1.0
var _net_pos := Vector3.ZERO
var _net_rot := Quaternion.IDENTITY
var _net_vel := Vector3.ZERO
var _net_avel := Vector3.ZERO


func setup(char_id: String, idx: int, trk: Track, player: bool, vehicle_id := "buggy") -> void:
	character_id = char_id
	char_data = Game.character(char_id)
	spec = VehicleSpec.get_spec(vehicle_id)
	wheels = spec.wheels
	racer_index = idx
	track = trk
	is_player = player
	name = "Kart_%s" % char_id
	_rng.seed = idx * 7919 + 13
	mass = JEEP_MASS * float(char_data.get("weight", 1.0)) * float(spec.def.get("weight", 1.0))
	# springs scale with the load so every vehicle rides at the same height
	spring_k = SPRING_K * mass / JEEP_MASS
	damp_comp = DAMP_COMP * mass / JEEP_MASS
	damp_reb = DAMP_REB * mass / JEEP_MASS
	accel_mult = float(char_data.get("accel", 1.0)) * float(spec.def.get("accel", 1.0))
	handling = float(spec.def.get("handling", 1.0))
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.38, 0.05)
	gravity_scale = 1.0
	can_sleep = false
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 6
	angular_damp = 0.6
	linear_damp = 0.0
	collision_layer = Game.LAYER_KART
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PROP
	var pm := PhysicsMaterial.new()
	pm.friction = 0.0
	pm.bounce = 0.25
	physics_material_override = pm
	# chassis box sized from the vehicle, a rounded top so it rolls off walls, a nose ball
	var body := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = spec.box_size
	body.shape = box
	body.position = spec.box_center
	add_child(body)
	var cage := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = clampf(spec.box_size.x * 0.36, 0.5, 0.9)
	cap.height = maxf(spec.box_size.z * 0.62, cap.radius * 2.0 + 0.1)
	cage.shape = cap
	cage.rotation_degrees = Vector3(90, 0, 0)
	cage.position = spec.box_center + Vector3(0, spec.box_size.y * 0.5 + cap.radius * 0.35, 0.3)
	add_child(cage)
	var nose := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = clampf(spec.box_size.x * 0.3, 0.45, 0.8)
	nose.shape = sph
	nose.position = Vector3(0, spec.box_center.y, spec.box_center.z - spec.box_size.z * 0.5 + sph.radius * 0.4)
	add_child(nose)
	var diff: Dictionary = Game.DIFFICULTIES[clampi(int(Game.race_setting("difficulty")), 0, 2)]
	max_speed = diff["max_speed"] * float(char_data.get("speed", 1.0)) * float(spec.def.get("speed", 1.0))
	visual = KartVisual.new()
	add_child(visual)
	visual.setup(self)
	audio = KartAudio.new()
	add_child(audio)
	audio.setup(self)
	body_entered.connect(_on_body_entered)
	# front sensor: flattens lamp posts / signs / benches before the chassis touches them
	var sensor := Area3D.new()
	sensor.collision_layer = 0
	sensor.collision_mask = Game.LAYER_KNOCK
	var ss := CollisionShape3D.new()
	var sb := BoxShape3D.new()
	sb.size = Vector3(2.8, 2.4, 5.6)
	ss.shape = sb
	ss.position = Vector3(0, 1.1, -0.3)
	sensor.add_child(ss)
	add_child(sensor)
	sensor.body_entered.connect(func(b: Node):
		if b is StaticBody3D and b.has_meta("knockable"):
			_knock_over(b as StaticBody3D))


# ---------------------------------------------------------------- physics
func _integrate_forces(st: PhysicsDirectBodyState3D) -> void:
	if remote:
		return
	var dt := st.step
	var xf := st.transform
	var b := xf.basis
	var up := b.y
	var fwd := -b.z
	var right := b.x
	var vel := st.linear_velocity
	var space := st.get_space_state()

	# ---- suspension rays (jeep_test springConstant/damping, scaled to metres)
	wheels_on_ground = 0
	var nsum := Vector3.ZERO
	var off_count := 0
	for i in 4:
		var w: Dictionary = wheels[i]
		var mount_local: Vector3 = w["pos"] + Vector3.UP * MOUNT_UP
		var origin := xf * mount_local
		var r: float = w["r"]
		var rest := MOUNT_UP + r + TRAVEL * 0.5
		var max_len := MOUNT_UP + r + TRAVEL
		var q := PhysicsRayQueryParameters3D.create(origin, origin - up * max_len, Game.LAYER_WORLD, [get_rid()])
		var hit := space.intersect_ray(q)
		# tyres never ride walls/barriers/kerb faces: only the chassis touches those
		if not hit.is_empty() and hit["collider"] is Node and (hit["collider"] as Node).get_meta("surface", "road") == "wall":
			q.exclude = [get_rid(), (hit["collider"] as CollisionObject3D).get_rid()]
			hit = space.intersect_ray(q)
			if not hit.is_empty() and hit["collider"] is Node and (hit["collider"] as Node).get_meta("surface", "road") == "wall":
				hit = {}
		if hit.is_empty():
			wheel_contact[i] = false
			wheel_compress[i] = lerpf(wheel_compress[i], -TRAVEL * 0.5, minf(1.0, dt * 10.0))
			continue
		var dist := origin.distance_to(hit["position"])
		var x := rest - dist
		var rel: Vector3 = hit["position"] - xf.origin
		var pv := vel + st.angular_velocity.cross(rel)
		var comp_vel := -pv.dot(up)
		var damp := damp_comp if comp_vel > 0.0 else damp_reb
		var f := spring_k * x + damp * comp_vel
		f = clampf(f, 0.0, mass * 60.0)
		st.apply_force(up * f, hit["position"] - xf.origin)
		wheel_compress[i] = x
		wheel_contact[i] = true
		wheels_on_ground += 1
		nsum += hit["normal"]
		var col = hit.get("collider")
		if col is Node and (col as Node).has_meta("surface") and (col as Node).get_meta("surface") == "offroad":
			off_count += 1
	grounded = wheels_on_ground >= 2
	offroad = off_count >= 3
	# anti-roll bars (jeep_test stabilizerConstant): resist left/right compression difference
	for pair in [[0, 1], [2, 3]]:
		var a: int = pair[0]
		var c: int = pair[1]
		if wheel_contact[a] or wheel_contact[c]:
			var ca: float = wheel_compress[a] if wheel_contact[a] else 0.0
			var cc: float = wheel_compress[c] if wheel_contact[c] else 0.0
			var fa: float = spring_k * 0.8 * (ca - cc)
			var pa: Vector3 = xf.basis * (wheels[a]["pos"] as Vector3)
			var pc: Vector3 = xf.basis * (wheels[c]["pos"] as Vector3)
			if wheel_contact[a]:
				st.apply_force(up * fa, pa)
			if wheel_contact[c]:
				st.apply_force(-up * fa, pc)
	ground_normal = nsum.normalized() if wheels_on_ground > 0 else Vector3.UP
	if grounded:
		air_time = 0.0
	else:
		air_time += dt

	var gfwd := (fwd - ground_normal * fwd.dot(ground_normal)).normalized()
	var gright := gfwd.cross(ground_normal).normalized()
	fwd_speed = vel.dot(gfwd)
	speed = vel.length()

	# ---- input / state gating
	var throttle := in_throttle
	var brake := in_brake
	var steer := in_steer
	state_time += dt
	match state:
		State.SPIN, State.TUMBLE:
			throttle = 0.0
			brake = 0.0
			steer = 0.0
			var lim := 1.2 if state == State.SPIN else 1.6
			if state_time > lim:
				state = State.NORMAL
		State.RESPAWN:
			st.linear_velocity = Vector3.ZERO
			st.angular_velocity = Vector3.ZERO
			return
		State.FINISHED:
			pass

	if boost_time > 0.0:
		boost_time -= dt
	if star_time > 0.0:
		star_time -= dt
	if hop_time > 0.0:
		hop_time -= dt

	var top := max_speed
	if offroad and boost_time <= 0.0 and star_time <= 0.0:
		top *= 0.55
	if boost_time > 0.0:
		top *= 1.0 + 0.32 * boost_power
	if star_time > 0.0:
		top *= 1.18
	if state == State.SPIN:
		top = 6.0

	if grounded:
		# ---- engine (350hp, auto transmission) as a speed-limited thrust
		var accel := 15.0 * accel_mult
		if throttle > 0.0 and fwd_speed < top:
			var k := clampf(1.0 - pow(maxf(fwd_speed, 0.0) / top, 2.2), 0.0, 1.0)
			st.apply_central_force(gfwd * mass * accel * throttle * (0.25 + 0.75 * k))
		if boost_time > 0.0:
			st.apply_central_force(gfwd * mass * 22.0 * boost_power * (1.0 if fwd_speed < top else 0.2))
		# over the limit (offroad / end of boost): ease back like the jeep autobrake
		if fwd_speed > top:
			st.apply_central_force(-gfwd * mass * minf((fwd_speed - top) * 2.5, 30.0))
		if brake > 0.0:
			if fwd_speed > 1.0:
				st.apply_central_force(-gfwd * mass * 24.0 * brake)
			elif fwd_speed > -10.0:
				st.apply_central_force(-gfwd * mass * 10.0 * brake)
		if throttle <= 0.0 and brake <= 0.0:
			st.apply_central_force(-gfwd * mass * signf(fwd_speed) * minf(absf(fwd_speed) * 2.0, 3.0))

		# ---- drifting
		_update_drift(dt, steer, st)

		# ---- steering: steering cone narrows with speed (degreesSlow 50 -> degreesFast 18)
		var sp := absf(fwd_speed)
		var turn_rate := clampf(sp / 6.0, 0.0, 1.0) * lerpf(2.6, 1.55, clampf((sp - 8.0) / 26.0, 0.0, 1.0)) * handling
		var target := 0.0
		if drifting:
			var into := steer * drift_dir
			var amt := remap(into, -1.0, 1.0, 0.4, 1.2)
			target = -drift_dir * amt * 1.45
		else:
			target = -steer * turn_rate
		if fwd_speed < -0.5:
			target = -target
		var av := st.angular_velocity
		var yaw := av.dot(ground_normal)
		av += ground_normal * (target - yaw) * minf(1.0, dt * 9.0)
		# damp roll/pitch wobble while the tyres are planted
		var tilt := av - ground_normal * av.dot(ground_normal)
		av -= tilt * minf(1.0, dt * 4.0)
		st.angular_velocity = av

		# ---- tyre grip: kill lateral velocity (lower while drifting / spinning)
		var lat := vel.dot(gright)
		var grip := 11.0
		if drifting:
			grip = 6.0
		elif offroad:
			grip = 7.0
		if state == State.SPIN:
			grip = 5.0
		st.linear_velocity = vel - gright * lat * minf(1.0, grip * dt)
		# speed-scaled downforce keeps the jeep planted over crests
		st.apply_central_force(-ground_normal * mass * clampf(sp * 0.25, 0.0, 6.0))
	else:
		drifting = false if air_time > 0.6 else drifting
		# light air control + self-righting (the jeep's countertorquefactor)
		var av := st.angular_velocity
		var yaw := av.dot(Vector3.UP)
		av += Vector3.UP * (-steer * 1.2 - yaw) * minf(1.0, dt * 2.0)
		var axis := up.cross(Vector3.UP)
		av += axis * 3.0 * dt * 4.0
		av *= 1.0 - minf(1.0, dt * 1.2)
		st.angular_velocity = av

	# self-right when flipped on the ground
	if up.dot(Vector3.UP) < 0.3 and speed < 6.0 and state != State.RESPAWN:
		var axis2 := up.cross(Vector3.UP).normalized()
		if axis2.length() < 0.1:
			axis2 = fwd
		st.apply_torque(axis2 * mass * 12.0)

	# spin-out visual handled in KartVisual; keep physics yaw calm while spinning
	if state == State.SPIN:
		st.angular_velocity = st.angular_velocity.lerp(Vector3.ZERO, minf(1.0, dt * 3.0))


func _update_drift(dt: float, steer: float, st: PhysicsDirectBodyState3D) -> void:
	var sp := absf(fwd_speed)
	if in_drift and not _drift_held and grounded and hop_time <= 0.0:
		# hop
		hop_time = 0.25
		st.apply_central_impulse(ground_normal * mass * 2.4)
		audio.hop()
	if in_drift and not drifting and absf(steer) > 0.3 and sp > 10.0 and state == State.NORMAL:
		drifting = true
		drift_dir = 1 if steer > 0.0 else -1
		drift_charge = 0.0
		drift_level = 0
	if drifting:
		if not in_drift or sp < 7.0 or state != State.NORMAL:
			_end_drift()
		else:
			var into := steer * drift_dir
			drift_charge += dt * (0.7 + 0.6 * clampf(into, 0.0, 1.0))
			var lvl := 0
			if drift_charge > 1.0:
				lvl = 1
			if drift_charge > 2.2:
				lvl = 2
			if lvl != drift_level:
				drift_level = lvl
				audio.drift_level(lvl)
	_drift_held = in_drift


func _end_drift() -> void:
	if drift_level >= 1:
		boost(0.75 if drift_level == 1 else 1.4, 0.8 if drift_level == 1 else 1.0)
	drifting = false
	drift_dir = 0
	drift_level = 0
	drift_charge = 0.0


func boost(seconds: float, power := 1.0) -> void:
	boost_time = maxf(boost_time, seconds)
	boost_power = maxf(power, boost_power if boost_time > 0.0 else 0.0)
	audio.turbo()


# ---------------------------------------------------------------- per-frame
func _physics_process(delta: float) -> void:
	if remote:
		_net_follow(delta)
		return
	if controller and state != State.FINISHED:
		controller.drive(self, delta)
	elif state == State.FINISHED and controller:
		controller.drive(self, delta)
	_update_progress()
	_update_items(delta)
	if state == State.NORMAL and not finished:
		_check_respawn(delta)
	if state == State.RESPAWN:
		state_time += delta
		_respawn_tick(delta)


var _stuck_time := 0.0
var _flip_time := 0.0
var _watch_progress := 0.0
var _watch_time := 0.0


func _check_respawn(delta: float) -> void:
	var out := global_position.y < track.sea_level - 1.5
	if global_basis.y.dot(Vector3.UP) < 0.2:
		_flip_time += delta
	else:
		_flip_time = 0.0
	if global_position.y < float(track.data.get("kill_y", -1e9)):
		out = true
	# fell into the pit under a jump: fish them out before they reach the bottom
	if track.path.gap[path_index] == 1 and global_position.y < track.path.center[path_index].y - 5.0:
		out = true
	var lat := absf(track.path.lateral(global_position, path_index))
	if lat > track.path.width[path_index] * 0.5 + maxf(float(track.data.get("offtrack", 60.0)), 30.0):
		out = true
	if speed < 1.0 and in_throttle > 0.5:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	# no forward progress for a while (wedged on a wall / prop) -> rescue
	# bots that stop gaining ground are lost; a player only when they are also
	# barely moving (driving back for a crate or exploring is their call)
	var racing_now: bool = race == null or race.racing
	if racing_now and (not is_player or speed < 3.0):
		_watch_time += delta
	if total_progress > _watch_progress + 8.0:
		_watch_progress = total_progress
		_watch_time = 0.0
	if out or _flip_time > 2.0 or _stuck_time > 4.0 or _watch_time > (6.0 if is_player else 5.0):
		_watch_time = 0.0
		_watch_progress = total_progress
		start_respawn()


## Combine scanner fishes the kart out (Lakitu, City 17 style).
func start_respawn() -> void:
	if state == State.RESPAWN or remote:
		return
	state = State.RESPAWN
	state_time = 0.0
	respawns += 1
	freeze = true
	drifting = false
	boost_time = 0.0
	Scanner.rescue(self)


func _respawn_tick(_delta: float) -> void:
	if state_time > 2.2:
		var s := fposmod(total_progress - 12.0, track.path.length)
		var p := track.path
		for look in range(0, 90, 6):
			if p.gap[p.index_at(s + look)] == 1:
				# land them on the far side of the gap instead
				var k2 := 0
				while p.gap[p.index_at(s + look + k2)] == 1 and k2 < 200:
					k2 += 3
				s = fposmod(s + look + k2 + 10.0, p.length)
				break
		var t := track.path.transform_at(s)
		var lane := clampf(track.path.lateral(global_position, path_index), -3.0, 3.0)
		global_transform = Transform3D(t.basis, t.origin + t.basis.y * 1.2 + t.basis.x * lane)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		freeze = false
		state = State.NORMAL
		state_time = 0.0
		star_time = maxf(star_time, 1.2)


func _update_progress() -> void:
	var p := track.path
	path_index = p.closest(global_position, path_index)
	var s := p.progress(global_position, path_index)
	# lap crossing: s jumps from near length back to ~0
	if _last_s > p.length * 0.75 and s < p.length * 0.25:
		if _crossed_half:
			_crossed_half = false
			_complete_lap()
	elif _last_s < p.length * 0.25 and s > p.length * 0.75:
		# drove backwards over the line
		lap -= 1
	if s > p.length * 0.4 and s < p.length * 0.6:
		_crossed_half = true
	_last_s = s
	lap_progress = s
	total_progress = lap * p.length + s


var _best_lap := -99


func _complete_lap() -> void:
	lap += 1
	if lap <= _best_lap:
		return
	_best_lap = lap
	if race and race.has_method("on_lap"):
		race.on_lap(self)


func _update_items(delta: float) -> void:
	if roulette > 0.0:
		roulette -= delta
		if roulette <= 0.0:
			item_changed.emit(self)
	if in_item and not _item_held and item != "" and roulette <= 0.0 and state == State.NORMAL:
		Items.use(self)
	_item_held = in_item


func give_item(id: String, count := 1) -> void:
	item = id
	item_count = count
	roulette = 1.6 if is_player else 0.8
	item_changed.emit(self)


# ---------------------------------------------------------------- damage
func spin_out(by: Kart = null) -> void:
	# in multiplayer only the kart's owner decides it was hit
	if star_time > 0.0 or state == State.RESPAWN or remote:
		return
	state = State.SPIN
	state_time = 0.0
	drifting = false
	boost_time = 0.0
	visual.spin()
	audio.hurt()
	_drop_trailing()
	got_hit.emit(self, by)


func tumble(by: Kart = null, impulse := Vector3.ZERO) -> void:
	if star_time > 0.0 or state == State.RESPAWN or remote:
		return
	state = State.TUMBLE
	state_time = 0.0
	drifting = false
	boost_time = 0.0
	apply_central_impulse(impulse + Vector3.UP * mass * 7.0)
	apply_torque_impulse(global_basis.z * mass * 3.0 * (1.0 if _rng.randf() > 0.5 else -1.0))
	visual.spin()
	audio.hurt()
	_drop_trailing()
	got_hit.emit(self, by)


func _drop_trailing() -> void:
	if trailing and is_instance_valid(trailing):
		trailing.queue_free()
	trailing = null


func _on_body_entered(other: Node) -> void:
	var impact := linear_velocity.length()
	if other is PhysProp:
		var pp := other as PhysProp
		if impact > 5.0:
			pp.hit(linear_velocity * minf(mass * 0.02, pp.mass * 0.8))
			if pp.model_key in PhysProp.GIBS and impact > 8.0:
				pp.call_deferred("smash", linear_velocity)
	else:
		if impact > 9.0:
			audio.impact(impact)


## Turn a static street prop into a physics prop flying off the bonnet.
func _knock_over(body: StaticBody3D) -> void:
	var key: String = body.get_meta("knockable")
	body.remove_meta("knockable")
	var xf := body.global_transform
	var vel := linear_velocity
	var parent := body.get_parent()
	body.queue_free()
	var p := PhysProp.new()
	parent.add_child(p)
	p.setup(key)
	p.global_transform = xf
	p.mass = minf(p.mass, 60.0)
	p.linear_velocity = vel * 1.1 + Vector3.UP * (2.0 + vel.length() * 0.15)
	p.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-2, 2), randf_range(-4, 4))
	p.lifetime = 20.0
	# the debris flies off on its own: it never pushes karts around
	p.collision_layer = 0
	p.collision_mask = Game.LAYER_WORLD
	linear_velocity = vel * 0.95
	if vel.length() > 4.0:
		audio.impact(vel.length() * 0.7)


# ---------------------------------------------------------------- multiplayer
## Velocity for kart-vs-kart bumps (a proxy's body is kinematic).
func velocity() -> Vector3:
	return _net_vel if remote else linear_velocity


## Turn this kart into a proxy driven by another peer's state.
func make_remote() -> void:
	remote = true
	controller = null
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	_net_pos = global_position
	_net_rot = global_basis.get_rotation_quaternion()


## The owner left: the server takes the kart over with an AI driver.
func make_local_bot(skill: float) -> void:
	remote = false
	is_bot = true
	is_player = false
	freeze = false
	linear_velocity = _net_vel
	angular_velocity = _net_avel
	controller = AIController.new(skill, net_slot * 101 + 7)
	_last_s = lap_progress
	_crossed_half = lap_progress > track.path.length * 0.5
	_best_lap = lap


func pack_state(t: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(NET_FLOATS)
	var p := global_position
	var q := global_basis.get_rotation_quaternion()
	var v := linear_velocity
	var w := angular_velocity
	var flags := 0
	if grounded:
		flags |= 1
	if offroad:
		flags |= 2
	if drifting:
		flags |= 4
	if boost_time > 0.0:
		flags |= 8
	if star_time > 0.0:
		flags |= 16
	if finished:
		flags |= 32
	var vals := [t, p.x, p.y, p.z, q.x, q.y, q.z, q.w, v.x, v.y, v.z, w.x, w.y, w.z, in_steer, in_throttle,
		flags, drift_dir, drift_level, state, lap, total_progress,
		wheel_compress[0], wheel_compress[1], wheel_compress[2], wheel_compress[3]]
	for i in NET_FLOATS:
		a[i] = vals[i]
	return a


func apply_net_state(d: PackedFloat32Array) -> void:
	if d.size() < NET_FLOATS or d[0] < _net_t:
		return
	var first := _net_t < 0.0
	_net_t = d[0]
	_net_pos = Vector3(d[1], d[2], d[3])
	_net_rot = Quaternion(d[4], d[5], d[6], d[7]).normalized()
	_net_vel = Vector3(d[8], d[9], d[10])
	_net_avel = Vector3(d[11], d[12], d[13])
	in_steer = d[14]
	in_throttle = d[15]
	var f := int(d[16])
	grounded = f & 1 != 0
	offroad = f & 2 != 0
	drifting = f & 4 != 0
	boost_time = 0.25 if f & 8 else 0.0
	star_time = 0.25 if f & 16 else 0.0
	drift_dir = int(d[17])
	drift_level = int(d[18])
	var st := int(d[19]) as State
	if st != state:
		var hit_now := (st == State.SPIN or st == State.TUMBLE) and state != State.SPIN and state != State.TUMBLE
		if hit_now and visual:
			visual.spin()
			audio.hurt()
		if st == State.RESPAWN:
			Scanner.rescue(self)
		state = st
		state_time = 0.0
	lap = int(d[20])
	total_progress = d[21]
	lap_progress = total_progress - lap * track.path.length
	for i in 4:
		wheel_compress[i] = d[22 + i]
	if first:
		global_transform = Transform3D(Basis(_net_rot), _net_pos)


## Dead reckoning: show the proxy where its owner is now (latest state moved on
## by its velocity for the age of that state), converging smoothly.
func _net_follow(delta: float) -> void:
	state_time += delta
	air_time = 0.0 if grounded else air_time + delta
	if _net_t < 0.0:
		return
	var age := clampf(Net.now() - _net_t, 0.0, 0.35)
	var target_pos := _net_pos + _net_vel * age
	var target_rot := _net_rot
	if _net_avel.length() > 0.01:
		target_rot = (Quaternion(_net_avel.normalized(), _net_avel.length() * age) * _net_rot).normalized()
	var pos := global_position + _net_vel * delta
	var err := target_pos - pos
	if err.length() > 8.0 or state == State.RESPAWN:
		pos = target_pos
	else:
		pos += err * minf(1.0, delta * 10.0)
	var rot := global_basis.get_rotation_quaternion().slerp(target_rot, minf(1.0, delta * 12.0))
	global_transform = Transform3D(Basis(rot), pos)
	speed = _net_vel.length()
	fwd_speed = _net_vel.dot(-global_basis.z)
	path_index = track.path.closest(global_position, path_index)
