class_name Kart
extends RigidBody3D
## Arcade raycast-suspension vehicle on the HL2 jeep (prop_vehicle_jeep):
## mass/suspension/steering cone/turbo from scripts/vehicles/jeep_test.txt,
## plus kart-racer drifting with mini-turbos.

signal item_changed(kart: Kart)
signal got_hit(kart: Kart, by: Kart)

enum State { NORMAL, SPIN, TUMBLE, RESPAWN, FINISHED }
## How the scanner gets a kart back (start_respawn): SCAN photographs it where it stopped,
## SINK lets it splash into a liquid and fishes it out, FALL lets it drop out of sight first.
enum Rescue { SCAN, SINK, FALL }
## A computer driver stuck on a wall or a prop (AIController): TRYING while it backs off and turns
## away (the stall rescue waits for that try), GAVE_UP once its tries failed (the scanner comes at once).
enum Unstick { NONE, TRYING, GAVE_UP }
const SINK_T := 1.5  # under the surface before the scanner hauls it out
const HAUL_T := 1.0  # pulled up out of the liquid
const SINK_DONE := 3.0  # back on the road
const FALL_T := 1.1  # dropping out of sight before the scanner brings it back
const DROP_DONE := 2.6  # hanging under the scanner over the road, then let go
const CRAB_IMMUNE := 6.0  # seconds after a headcrab lets go before another can land
## Tube exits: from TUBE_EXIT metres before a tube ends (and anywhere in one while spun or
## tumbling) a kart further round the pipe than its lane comes back down to it, closing in at up
## to TUBE_SLIDE m/s on top of the lane's own roll; over the last TUBE_LAND metres gravity turns
## from the wall to the lane's own
const TUBE_EXIT := 75.0
const TUBE_SLIDE := 24.0
const TUBE_LAND := 20.0
## airborne this far below the road it is tracked on: falling (over a deck's wall, into the void)
const DROP_FALL := 8.0
## seconds out past its road's edge with a wall between it and the road before the scanner comes
const BEHIND_WALL := 2.0
## put back less than RUN_UP metres in front of a jump's gap: it lands past the gap instead
const RUN_UP := 30.0
## a branch's jump is retried only when a standstill run-up reaches its need_speed plus this (the
## drop from the scanner, steering and the kicker's curve cost about that much on the way)
const RETRY_MARGIN := 1.5
## a tumble throws a kart at most TUMBLE_UP m/s up and TUMBLE_FLAT along the ground, of that at
## most TUMBLE_SIDE across its road: dramatic, but it comes down on its deck
const TUMBLE_UP := 7.0
const TUMBLE_FLAT := 9.0
const TUMBLE_SIDE := 4.0
## touching anything (a pile-up, a squeeze against a wall, the chassis caught on a kerb or driven up
## a steep bank) a kart leaves its road no faster than a tumble's hop (TUMBLE_UP), except this many
## metres either side of a jump's gap, where its kicker and landing are
const JUMP_NEAR := 45.0
## slower than this (m/s) up a pipe's wall: stalled there, it slides back down to its lane
const TUBE_STALL := 3.0

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

# race progress: path_index, lap_progress and total_progress are always on the main lap
# (a kart on a branch counts as the lap metres its branch position maps to)
var path_index := 0
var lap := 0
var lap_progress := 0.0
var total_progress := 0.0
## the road under the kart: -1 the main loop, else an index into track.path.branches
var route := -1
## sample on that road (== path_index on the main loop)
var route_index := 0
## metres along the current branch
var route_u := 0.0
var _route_check := 0.0
var _branch_fails := {}  # branch index -> falls on this pass (respawn policy)
var _level_time := 0.0
var place := 1
var finished := false
var finish_time := 0.0
var last_valid := Transform3D.IDENTITY
var _last_s := 0.0
var _crossed_half := false
var lap_times: Array[float] = []
var respawns := 0
var _lap_start := 0.0
var rescue := Rescue.SCAN
var liquid := Vector2(-1e9, 0.0)  # SINK: (surface y, kind 1 water / 2 slime)
var fall_floor := 0.0  # FALL: height of the edge it went over (the camera stays up there)
var _sink_from := Transform3D.IDENTITY
var _sink_vel := Vector3.ZERO
var _sink_glide := Vector3.ZERO  # SINK: how far it glides on under the surface (short of any wall)
var _scanned := false
var _dripping := false
var _branch_entry := 0.0  # route_u where it joined the branch it is on (_leave_branch credits from the fork)
# round a pipe back to its lane (_tube_gravity): the way along the pipe and round it, the
# speed round it, how hard it is drawn (0..1) and how far round from the lane it is (radians)
var _tube_ax := Vector3.ZERO
var _tube_round := Vector3.ZERO
var _tube_slide := 0.0
var _tube_pull := 0.0
var _tube_off := 0.0
var _tube_stall := false  # stalled up a pipe's wall (TUBE_STALL)
var _throw_frame := -1  # physics frame of the last tumble's throw ...
var _thrown := Vector3.ZERO  # ... and what the throws of that frame added (linear_velocity shows them a step later)
var unstick := Unstick.NONE

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
## which way is up for this kart: the sky, or inside a tube the pipe's axis
var grav_up := Vector3.UP

var drifting := false
var drift_dir := 0
var drift_charge := 0.0
var drift_level := 0
var hop_time := 0.0
var boost_time := 0.0
var boost_power := 1.0
var star_time := 0.0  # invulnerable "charged suit"
var blind_time := 0.0  # a headcrab on the face
var crab_immune := 0.0  # no new headcrab until this runs out (set when one lets go)
var face_crab: Node = null  # the FaceCrab on its way to / sitting on this driver
var hazard_grace := 0.0  # immune to track hazards (no chain hits from one burst or blast)
var hazard_lock := 0.0  # > 0 while a hazard's gun has locked on: seconds until it fires (HUD, AI)
var hazard_lock_from := Vector3.ZERO  # where that gun is
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
const NET_FLOATS := 30
var net_slot := -1
var nick := ""
var is_bot := false
var remote := false
var net_hits := 0  # hits its owner took (Race counts them online)
var _net_t := -1.0
var _net_pos := Vector3.ZERO
var _net_rot := Quaternion.IDENTITY
var _net_vel := Vector3.ZERO
var _net_avel := Vector3.ZERO
var _net_route := -1  # the road its owner is on (route, route_u)
var _net_route_u := 0.0
var _net_tp := 0.0  # its owner's total_progress at _net_t


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
	# touching anything away from a jump (a pile-up, a squeeze against a wall, the chassis caught on a
	# kerb or driven up a steep bank) it leaves its road no faster than a tumble's hop: Jolt pushes
	# bodies out of each other as fast as it must, and that threw karts 5-20 m up and over walls
	if st.get_contact_count() > 0:
		var road_up := _lift_up()
		var lift := vel.dot(road_up)
		if lift > TUMBLE_UP:
			vel -= road_up * (lift - TUMBLE_UP)
			st.linear_velocity = vel

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
	ground_normal = nsum.normalized() if wheels_on_ground > 0 else grav_up
	_tube_gravity(st, dt)
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
			if rescue == Rescue.FALL:
				return  # only gravity: no engine, grip or air control while it drops away
			st.linear_velocity = Vector3.ZERO
			st.angular_velocity = Vector3.ZERO
			return
		State.FINISHED:
			pass

	# on the grid until GO!: the handbrake is on, so nothing (a boost pad, a bump, a slope,
	# the drop from the spawn height) rolls a kart off its slot during the countdown; on a banked
	# grid it does not creep down the bank either (no slide, and gravity's pull along it cancelled)
	if race != null and not race.get("racing") and state == State.NORMAL:
		boost_time = 0.0
		if grounded:
			st.linear_velocity = ground_normal * vel.dot(ground_normal)
			var pull := st.total_gravity
			st.apply_central_force(-(pull - ground_normal * pull.dot(ground_normal)) * mass)
			var spin_v := st.angular_velocity
			st.angular_velocity = spin_v - ground_normal * spin_v.dot(ground_normal) * minf(1.0, dt * 15.0)
		return

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
		if _tube_pull > 0.0 and fwd_speed > 2.0:
			# drawn back to its lane in a pipe (_tube_gravity): it heads along the pipe and round it
			# at the slide's speed, so it neither stays up the wall nor shoots across the lane and up
			# the other side; on the lane and pointing along it the driver still steers
			var head := _tube_ax * fwd_speed + _tube_round * _tube_slide
			head -= ground_normal * head.dot(ground_normal)
			var turn := gfwd.signed_angle_to(head, ground_normal)
			var hold := _tube_pull * clampf(maxf(_tube_off, absf(turn)) / 0.35, 0.0, 1.0)
			target = lerpf(target, clampf(turn * 6.0, -3.0, 3.0), hold)
		var av := st.angular_velocity
		var yaw := av.dot(ground_normal)
		av += ground_normal * (target - yaw) * minf(1.0, dt * 9.0)
		# damp roll/pitch wobble while the tyres are planted
		var tilt := av - ground_normal * av.dot(ground_normal)
		av -= tilt * minf(1.0, dt * 4.0)
		st.angular_velocity = av

		# ---- tyre grip: kill lateral velocity (lower while drifting / spinning)
		var lat := vel.dot(gright)
		if state == State.SPIN or _tube_stall:
			# spun round in a pipe it can not head anywhere, or stalled up its wall: it slides down the
			# wall to its lane
			lat -= _tube_round.dot(gright) * _tube_slide * _tube_pull
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
		var yaw := av.dot(grav_up)
		av += grav_up * (-steer * 1.2 - yaw) * minf(1.0, dt * 2.0)
		var axis := up.cross(grav_up)
		av += axis * 3.0 * dt * 4.0
		av *= 1.0 - minf(1.0, dt * 1.2)
		st.angular_velocity = av

	# self-right when flipped on the ground
	if up.dot(grav_up) < 0.3 and speed < 6.0 and state != State.RESPAWN:
		var axis2 := up.cross(grav_up).normalized()
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


## Inside a tube gravity pulls towards the pipe wall (the surface under the wheels,
## or straight out from the axis in the air), so a kart can drive up the wall and
## along the ceiling. Towards the tube's end (TUBE_EXIT), and anywhere in it while spun,
## tumbling or stalled (TUBE_STALL), a kart further round from the pipe's bottom than its lane (any
## kart, once the lane runs along the bottom) is drawn back to the lane: on the wall it is turned
## to head round the pipe as fast as the lane rolls plus a closing speed that eases off as it gets
## there (_tube_round, _tube_slide; spun or stalled it slides round instead), in the air it falls
## towards the lane rather than the nearest wall; over the last TUBE_LAND metres gravity turns into
## the lane's own, so a kart leaves the mouth on the road. Elsewhere grav_up eases back to the sky.
func _tube_gravity(st: PhysicsDirectBodyState3D, dt: float) -> void:
	_tube_pull = 0.0
	_tube_stall = false
	var road: TrackPath = geo() if track else null
	var i := route_index
	var r: float = road.mag[i] if road and road.mag.size() > i else 0.0
	if r <= 0.0:
		grav_up = ease_up(grav_up, Vector3.UP, dt * 4.0)
		return
	var ax := _tube_axis(road, i)
	var out := st.transform.origin - (road.center[i] + road.up[i] * r)
	var along := out.dot(ax)
	out -= ax * along
	# the tube's last sample, and the metres to its end
	var j := i
	while j - i < 24 and (road.closed or j < road.n - 1) and road.mag[road.wi(j + 1)] > 0.0:
		j += 1
	var to_end := (j - i + 0.5) * road.step - along
	_tube_stall = state == State.NORMAL and speed < TUBE_STALL
	var hurt := state == State.SPIN or state == State.TUMBLE or _tube_stall
	var pull := 1.0 if hurt else smoothstep(TUBE_EXIT, TUBE_EXIT - 15.0, to_end)
	var lane := -road.up[i] + ax * road.up[i].dot(ax)
	if pull > 0.0 and out.length() > 0.5 and lane.length() > 0.1:
		# while the lane is still rolled up the wall only from further round than it is (left up
		# there as it rolls back down, or thrown off it): a kart nearer the bottom is left alone
		var bottom := -road.up[j] + ax * road.up[j].dot(ax)
		var low := lane.angle_to(bottom)
		if hurt or low < 0.45 or out.angle_to(bottom) > low + 0.1:
			var a := out.signed_angle_to(lane, ax)
			# the lane's own speed round the pipe at this kart's pace along it (it rolls back down)
			var k := road.wi(i + 1)
			var roll := 0.0
			if road.mag[k] > 0.0:
				var ahead := -road.up[k] + ax * road.up[k].dot(ax)
				roll = lane.signed_angle_to(ahead, ax) / road.step * r * st.linear_velocity.dot(ax)
			_tube_ax = ax
			_tube_round = ax.cross(out.normalized()) * signf(a)
			_tube_slide = clampf(roll * signf(a) + minf(TUBE_SLIDE, absf(a) * r * 3.0), 0.0, TUBE_SLIDE * 2.0)
			_tube_pull = pull
			_tube_off = absf(a)
		else:
			pull = 0.0
	var want: Vector3
	if grounded:
		want = ground_normal
	else:
		want = -out.normalized() if out.length() > 0.5 else road.up[i]
		if pull > 0.0:
			want = ease_up(want, road.up[i], pull)
	var land := smoothstep(TUBE_LAND, 0.0, to_end)
	if land > 0.0:
		want = ease_up(want, road.up[i], land)
	grav_up = ease_up(grav_up, want, dt * 10.0)
	var g := st.total_gravity
	st.apply_central_force(-g * mass - grav_up * mass * g.length() * 1.25)


## The up of the road the kart is tracked on, for the contact lift cap in _integrate_forces;
## ZERO (no cap) in a tube and within JUMP_NEAR metres of a jump's gap on that road.
func _lift_up() -> Vector3:
	if track == null:
		return Vector3.ZERO
	var g := geo()
	var i := route_index
	if g.mag[i] > 0.0:
		return Vector3.ZERO
	var near := int(JUMP_NEAR / g.step) + 1
	for j in range(i - near, i + near + 1):
		if g.gap[g.wi(j)] == 1:
			return Vector3.ZERO
	return g.up[i]


## Which way a tube's axis runs at sample i (the lane winds round it, so its own fwd does not).
func _tube_axis(road: TrackPath, i: int) -> Vector3:
	var a := road.wi(i - 1)
	var b := road.wi(i + 1)
	if road.mag[a] <= 0.0:
		a = i
	if road.mag[b] <= 0.0:
		b = i
	var d := road.center[b] + road.up[b] * road.mag[b] - road.center[a] - road.up[a] * road.mag[a]
	return d.normalized() if d.length() > 0.01 else road.fwd[i]


## Turns an up vector towards another (opposite vectors included) and keeps it unit length.
static func ease_up(from: Vector3, to: Vector3, t: float) -> Vector3:
	var v := from.lerp(to, clampf(t, 0.0, 1.0))
	if v.length() < 0.2:
		v = from.lerp(to, 0.5) + from.cross(to).normalized() * 0.5 if from.cross(to).length() > 0.01 else to
	return v.normalized() if v.length() > 0.0001 else to


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
	_update_progress(delta)
	_update_items(delta)
	blind_time = maxf(blind_time - delta, 0.0)
	crab_immune = maxf(crab_immune - delta, 0.0)
	hazard_grace = maxf(hazard_grace - delta, 0.0)
	hazard_lock = maxf(hazard_lock - delta, 0.0)
	if (state == State.NORMAL or state == State.SPIN or state == State.TUMBLE) and not finished:
		_check_respawn(delta)
	if state == State.RESPAWN:
		if freeze:
			state_time += delta  # a frozen body gets no _integrate_forces to count it
		_respawn_tick(delta)


var _stuck_time := 0.0
var _flip_time := 0.0
var _behind_time := 0.0
var _watch_progress := 0.0
var _watch_time := 0.0


func _check_respawn(delta: float) -> void:
	# the road the kart is tracked on (a branch, or the main loop) decides pits and edges
	var g := geo()
	var ri := route_index
	# into a liquid (sea, canal, river, lake, slime pit, coolant pool): splash and sink.
	# Water lets a kart wade in a little; slime and coolant have no floor to wade on
	var liq := track.liquid_at(global_position, ri, g)
	if liq.y > 0.0 and global_position.y < liq.x - (0.6 if liq.y == 1.0 else 0.0):
		# the stall watchdog starts afresh, as for the scanner's own rescues below (it is put
		# back behind the furthest point it had reached)
		_watch_time = 0.0
		_watch_progress = total_progress
		start_respawn(Rescue.SINK, liq)
		return
	# in the air over a liquid: keep falling until the splash (but not for ever)
	var to_liquid := liq.y > 0.0 and not grounded and global_position.y - liq.x < 30.0 and air_time < 4.0
	# thrown over a deck's wall into the void (tumbling or not): falling once it is airborne well
	# below its road, wherever that road is (not first all the way down at kill_y)
	if not grounded and air_time > 0.3 and g.mag[ri] <= 0.0 and global_position.y < g.center[ri].y - DROP_FALL \
			and not to_liquid:
		_watch_time = 0.0
		_watch_progress = total_progress
		_behind_time = 0.0
		start_respawn(Rescue.FALL)
		return
	if state != State.NORMAL:
		return  # (a spinning / tumbling kart is only checked for liquids and drops)
	var out := false
	var fall := false
	if global_basis.y.dot(grav_up) < 0.2:
		_flip_time += delta
	else:
		_flip_time = 0.0
	if global_position.y < float(track.data.get("kill_y", -1e9)):
		fall = true
	if not track.has_sea and global_position.y < track.sea_level - 1.5:
		fall = true  # below a converted map's floor
	# into the pit under a jump or off an open edge (a bridge without railings):
	# let it drop out of sight instead of freezing it in mid-air
	if g.pit[ri] == 1 and global_position.y < g.center[ri].y - 5.0 and not to_liquid:
		fall = true
	var lat := absf(g.lateral(global_position, ri))
	var off := maxf(float(track.data.get("offtrack", 60.0)), 30.0)
	if route >= 0 and (g as TrackBranch).offtrack > 0.0:
		off = maxf((g as TrackBranch).offtrack, 20.0)
	if lat > g.width[ri] * 0.5 + off and not to_liquid:
		if grounded:
			out = true
		else:
			fall = true
	# thrown over a barrier (a wall, a jersey, a railing) and still behind it after a moment: the
	# scanner comes (out on an open verge nothing stands between it and the road: that is legal)
	if lat > g.width[ri] * 0.5 + 1.0 and g.mag[ri] <= 0.0 and g.gap[ri] == 0 and _behind_wall(g, ri):
		_behind_time += delta
	else:
		_behind_time = 0.0
	if _behind_time > BEHIND_WALL:
		out = true
	# wrong level: on another road well above / below the one it is tracked on, for half a
	# second (off a flyover onto the street below; the route tracker found no road there)
	if grounded and not offroad and g.mag[ri] <= 0.0 and g.gap[ri] == 0 and absf(global_position.y - g.center[ri].y) > 6.0:
		_level_time += delta
	else:
		_level_time = 0.0
	if _level_time > 0.5:
		out = true
	if speed < 1.0 and in_throttle > 0.5:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	# no forward progress for a while (wedged on a wall / prop) -> rescue
	# bots that stop gaining ground are lost; a player only when they are also
	# barely moving (driving back for a crate or exploring is their call)
	# (a computer driver backing off a wall gets to finish that try, and the time it takes does not
	# count; once it gave up the scanner comes)
	var racing_now: bool = race == null or race.racing
	if racing_now and (not is_player or speed < 3.0) and unstick != Unstick.TRYING:
		_watch_time += delta
	if total_progress > _watch_progress + 8.0:
		_watch_progress = total_progress
		_watch_time = 0.0
	var stalled := _watch_time > (6.0 if is_player else 5.0) and unstick != Unstick.TRYING
	if fall or out or _flip_time > 2.0 or _stuck_time > 4.0 or stalled or unstick == Unstick.GAVE_UP:
		_watch_time = 0.0
		_watch_progress = total_progress
		_behind_time = 0.0
		start_respawn(Rescue.FALL if fall else Rescue.SCAN)


## Is a wall (a barrier, a jersey, a railing, a building) between the kart and the road it is
## tracked on? A ray from just inside the road's edge, level with the kart, to the kart.
func _behind_wall(g: TrackPath, i: int) -> bool:
	var lat := g.lateral(global_position, i)
	var edge := global_position - g.right[i] * (lat - signf(lat) * (g.width[i] * 0.5 - 0.5))
	edge += g.up[i] * ((g.center[i] - edge).dot(g.up[i]) + 0.6)
	var q := PhysicsRayQueryParameters3D.create(edge, global_position + grav_up * 0.4, Game.LAYER_WORLD, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit["collider"] is Node and (hit["collider"] as Node).get_meta("surface", "road") == "wall"


## Combine scanner fishes the kart out (Lakitu, City 17 style). SCAN: photographed where it
## stopped and put back; SINK: splash, sink, hauled out dripping; FALL: drops out of sight,
## then a scanner lowers it back onto the road. `liq` is the liquid for SINK (Track.liquid_at).
func start_respawn(mode := Rescue.SCAN, liq := Vector2(-1e9, 0.0)) -> void:
	if state == State.RESPAWN or remote:
		return
	CrowdDirector.notify(get_tree(), &"fall", global_position, self, null, mode)
	state = State.RESPAWN
	state_time = 0.0
	respawns += 1
	rescue = mode
	unstick = Unstick.NONE
	_scanned = false
	_dripping = false
	drifting = false
	boost_time = 0.0
	match mode:
		Rescue.SINK:
			liquid = liq
			_sink_from = global_transform
			_sink_vel = linear_velocity
			freeze = true
			# it glides on a few metres under the surface, never into the bank or wall ahead
			_sink_glide = _clear_glide(Vector3(_sink_vel.x, 0.0, _sink_vel.z) / (5.0 if liq.y == 2.0 else 3.0))
			var at := Vector3(global_position.x, liq.x, global_position.z)
			Effects.splash(get_parent(), at, int(liq.y), _sink_vel.length())
			# bubbles boil up where it settles
			Effects.bubbles(get_parent(), at + _sink_glide, int(liq.y), SINK_T)
			if is_player and race and race.get("hud"):
				race.hud.liquid_flash(int(liq.y))
		Rescue.FALL:
			fall_floor = geo().center[route_index].y
		_:
			freeze = true
			_scanned = true
			Scanner.rescue(self)


func _respawn_tick(_delta: float) -> void:
	match rescue:
		Rescue.SINK:
			if state_time > 0.25 and not _scanned:
				_scanned = true
				Scanner.rescue(self)
			_sink_tick()
			if state_time > SINK_DONE:
				_put_back(1.2)
		Rescue.FALL:
			if not freeze and state_time > FALL_T:
				# out of sight: hang it under a scanner above the road, then let go
				freeze = true
				_put_back(2.6, false)
				_scanned = true
				Scanner.rescue(self)
			elif freeze and state_time > DROP_DONE:
				freeze = false
				state = State.NORMAL
				state_time = 0.0
				star_time = maxf(star_time, 1.2)
		_:
			if state_time > 2.2:
				_put_back(1.2)


## SINK: under the surface the kart glides on a little, noses down and sinks slowly
## (slime is thicker than water); after SINK_T the scanner hauls it up, dripping.
func _sink_tick() -> void:
	var t := state_time
	var slime := liquid.y == 2.0
	var drag := 5.0 if slime else 3.0
	var e := 1.0 - exp(-drag * minf(t, SINK_T))
	var plunge := clampf(-_sink_vel.y / drag, 0.5, 1.8)
	var pos := _sink_from.origin + _sink_glide * e
	pos.y = minf(_sink_from.origin.y, liquid.x - plunge * e) - (0.35 if slime else 0.7) * minf(t, SINK_T)
	var b := _sink_from.basis.orthonormalized()
	var flat := Vector3(-b.z.x, 0.0, -b.z.z)
	var level := Basis.looking_at(flat.normalized() if flat.length() > 0.1 else Vector3.FORWARD, Vector3.UP)
	var nose := Basis(level.x, -0.45 * e) * level  # pitched nose-down
	var bob := Basis(-level.z, sin(t * 2.3) * 0.08 * e) * nose  # rocked by the liquid
	var rot := b.slerp(bob, minf(1.0, t * 3.0))
	if t > SINK_T:
		# hauled up under the scanner, out of the liquid to ~2.6 m above it, levelling out
		var h := clampf((t - SINK_T) / HAUL_T, 0.0, 1.0)
		h = h * h * (3.0 - 2.0 * h)
		var rise := maxf(0.0, t - SINK_T - HAUL_T) * 0.6
		pos = pos.lerp(Vector3(pos.x, liquid.x + 2.6 + rise, pos.z), h)
		rot = rot.slerp(level, h)
		if not _dripping and pos.y > liquid.x - 0.3:
			_dripping = true
			Effects.splash(get_parent(), Vector3(pos.x, liquid.x, pos.z), int(liquid.y), 3.0)
			Effects.drips(self, int(liquid.y), 3.5)
			visual.wet(int(liquid.y))
	global_transform = Transform3D(rot, pos)


## How far a sinking kart glides on under the surface: `glide`, cut short a kart's length before
## whatever stands in its way (a landing's abutment, a canyon wall, a bank).
func _clear_glide(glide: Vector3) -> Vector3:
	var reach := glide.length()
	if reach < 0.1:
		return glide
	var dir := glide / reach
	var space := get_world_3d().direct_space_state
	var go := reach
	for drop: float in [-0.5, 1.5]:
		var from := global_position - Vector3.UP * drop
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * (reach + 2.5), Game.LAYER_WORLD, [get_rid()])
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			go = minf(go, from.distance_to(hit["position"]) - 2.5)
	return dir * maxf(go, 0.0)


## Back on the road a bit behind where it left (never into a jump gap, nor so close in front of
## one that it could not get up to speed: past_gap), `lift` metres up. `release` drops it straight
## away; FALL keeps it hanging under the scanner first. On a branch its respawn policy decides:
## "before" retries the jump it missed with a run-up when that run-up is winnable from a
## standstill (retry_winnable), "after" lands it past the gap, "main" (also for an unwinnable
## retry, and any second fall on one pass) gives up on it.
func _put_back(lift: float, release := true) -> void:
	var p := track.path
	var r := route
	var s := fposmod(total_progress - 12.0, p.length)
	var retry := false
	if r >= 0:
		var br := p.branches[r]
		var fails: int = _branch_fails.get(r, 0) + 1
		_branch_fails[r] = fails
		s = route_u - 12.0
		var give_up := br.respawn == "main" or fails >= 2 or s < br.fork_nose_u
		if not give_up and br.respawn != "after":
			var gs := br.gap_start_at_or_ahead(s, br.retry_back)
			if gs < INF:
				s = gs - br.retry_back
			s = maxf(s, br.fork_nose_u + 5.0)
			retry = gs == INF or retry_winnable(br, s, gs)
			give_up = not retry
		if give_up:
			# back on the main road, a little behind the lap position it had reached
			s = fposmod(br.main_s(maxf(route_u, 0.0)) - (12.0 if fails < 2 else 30.0), p.length)
			_leave_branch(false)
			r = -1
	if r < 0 and track.hazards:
		s = track.hazards.safe_respawn(fposmod(s, p.length))  # never into a level crossing, a gate...
	var g := p.geo(r)
	if not retry:
		s = past_gap(g, s, p.branches[r].need_speed if r >= 0 else 0.0)
		if r >= 0 and s > g.length - 2.0:
			# past the end of the branch: out on the main road after its merge
			s = fposmod(p.branches[r].merge_s + s - g.length, p.length)
			_leave_branch(true)
			r = -1
			g = p
		elif r < 0:
			s = fposmod(s, p.length)
	var t := g.transform_at(s)
	var half := g.width[g.index_at(s)] * 0.5
	var lane := clampf(geo().lateral(global_position, route_index), -minf(3.0, half - 2.0), minf(3.0, half - 2.0))
	global_transform = Transform3D(t.basis, t.origin + t.basis.y * lift + t.basis.x * lane)
	route = r
	route_index = g.index_at(s)
	route_u = s if r >= 0 else 0.0
	path_index = p.index_at(p.branches[r].main_s(s)) if r >= 0 else route_index
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if release:
		freeze = false
		state = State.NORMAL
		state_time = 0.0
		star_time = maxf(star_time, 1.2)


## Metres to put a kart back at instead of s on road g: past the gap of a jump ahead that it could
## not get up to speed for from a standstill (less than RUN_UP metres off, or on a branch too
## short a run-up for its `need` m/s), else s itself.
func past_gap(g: TrackPath, s: float, need := 0.0) -> float:
	var look := 0.0
	while look < 90.0:
		if g.gap[g.index_at(s + look)] == 1:
			if look >= RUN_UP and (need <= 0.0 or run_up_speed(g, s, s + look) >= need + RETRY_MARGIN):
				return s
			var over := 0.0
			while g.gap[g.index_at(s + look + over)] == 1 and over < 200.0:
				over += 3.0
			return s + look + over + 10.0
		look += 3.0
	return s


## Can this kart win a retry of branch br's jump from a standstill at u0, its gap starting at u1:
## does it get up to the jump's need_speed (plus RETRY_MARGIN) by then?
func retry_winnable(br: TrackBranch, u0: float, u1: float) -> bool:
	return run_up_speed(br, u0, u1) >= br.need_speed + RETRY_MARGIN


## The speed this kart reaches driving flat out from a standstill at u0 to u1 on road g: its
## engine up to its top speed against the slope, with a boost it holds fired straight away.
func run_up_speed(g: TrackPath, u0: float, u1: float) -> float:
	var grav := absf(float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)))
	var boosted := roulette <= 0.0 and item in AIController.BOOSTS
	var v := 0.0
	var t := 0.0
	var u := u0
	while u < u1:
		var fired := boosted and t < 1.4
		var top := max_speed * (1.32 if fired else 1.0)
		var a := -grav * g.fwd[g.index_at(u)].y + (22.0 if fired else 0.0)
		if v < top:
			a += 15.0 * accel_mult * (0.25 + 0.75 * clampf(1.0 - pow(v / top, 2.2), 0.0, 1.0))
		else:
			a -= minf((v - top) * 2.5, 30.0)
		var du := minf(1.0, u1 - u)
		var v1 := sqrt(maxf(v * v + 2.0 * a * du, 0.0))
		t += du / maxf((v + v1) * 0.5, 0.5)
		v = v1
		u += du
	return v


## The road under the kart: the main loop or the branch it is on.
func geo() -> TrackPath:
	return track.path if route < 0 else track.path.branches[route]


## Metres along the current route (lap metres on the main loop, branch metres on a branch).
func route_pos() -> float:
	return lap_progress if route < 0 else route_u


func _update_progress(delta := 0.0) -> void:
	var p := track.path
	_track_route(delta)
	var s: float
	if route < 0:
		s = p.progress(global_position, route_index)
		path_index = route_index
	else:
		var br := p.branches[route]
		route_u = br.progress(global_position, route_index)
		s = br.main_s(route_u)
		var w := br.shared(route_u)
		if w > 0.0:
			# where the branch still shares the main road the kart counts that road's lap metres
			path_index = p.closest(global_position, path_index)
			s = lerpf(s, p.progress(global_position, path_index), w)
		else:
			path_index = p.index_at(s)
	# lap crossing: s jumps from near length back to ~0 (only ever on the main loop: no branch
	# contains the line)
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


## Keeps `route` on the road the kart is driving on. Near a fork or a merge it switches only
## when the kart is on exactly one of the two surfaces (with some hysteresis), so the switch
## lands where both roads count the same lap metres. Anywhere else a slow check catches karts
## that ended up on another road (dropped off a ledge, landed short of a jump). Never while it
## falls or the scanner has it: dropping past another road is not driving on it.
func _track_route(delta: float) -> void:
	var p := track.path
	var g := geo()
	route_index = g.closest(global_position, route_index)
	if p.branches.is_empty() or state == State.RESPAWN:
		return
	if not grounded and global_position.y < g.center[route_index].y - 3.0:
		return
	var pos := global_position
	var here := g.on_road(pos, route_index)
	if route < 0:
		for b in p.junctions_near(route_index):
			var br := p.branches[b]
			# fork zone: search the branch from its start; merge zone (driving the wrong way): its end
			var at_fork := absi(route_index - br.fork_i) < absi(route_index - br.merge_i)
			var k := br.closest(pos, 0 if at_fork else br.n - 1)
			if br.on_road(pos, k) + 0.75 < here:
				_set_route(b, k)
				return
	else:
		var br := p.branches[route]
		var near_end := route_u > br.merge_nose_u - 12.0
		if near_end or route_u < br.fork_nose_u + 12.0:
			var i := p.closest(pos, br.merge_i - 4 if near_end else br.fork_i - 4)
			var past_end := near_end and route_index >= br.n - 1 and (pos - br.center[br.n - 1]).dot(br.fwd[br.n - 1]) > 0.0
			if past_end or p.on_road(pos, i) + 0.75 < here:
				_set_route(-1, i)
				return
	_route_check -= delta
	if here > 3.0 and _route_check <= 0.0:
		_route_check = 0.25
		var best := _road_under()
		if best.z < 1.0:
			_set_route(int(best.x), int(best.y))


## The road under the kart among the other routes that cover its lap position (never more
## than 80 lap metres from it, so no road far along the lap can be "found"):
## Vector3(route, index, metres off it), z = INF when there is none.
func _road_under() -> Vector3:
	var p := track.path
	var pos := global_position
	var best := Vector3(-1, 0, INF)
	if route >= 0:
		var i := p.closest(pos, p.index_at(lap_progress) - 4)
		var ds := absf(wrapf(p.progress(pos, i) - lap_progress, -p.length * 0.5, p.length * 0.5))
		if ds < 80.0:
			best = Vector3(-1, i, p.on_road(pos, i))
	for b in p.branches.size():
		var br := p.branches[b]
		if b == route or lap_progress < br.fork_s - 10.0 or lap_progress > br.merge_s + 10.0:
			continue
		var j := br.closest(pos, br.index_at(br.u_at_main(lap_progress)) - 4)
		var d := br.on_road(pos, j)
		if d < best.z and absf(br.main_s(br.progress(pos, j)) - lap_progress) < 80.0:
			best = Vector3(b, j, d)
	return best


func _set_route(r: int, i: int) -> void:
	if route >= 0 and r != route:
		_leave_branch(route_u >= track.path.branches[route].merge_nose_u - 5.0)
	route = r
	route_index = i
	if r >= 0:
		route_u = track.path.branches[r].progress(global_position, i)
		_branch_entry = route_u


## The kart leaves its branch (`done`: through to the merge): stats and HUD (Race.on_branch) for
## a pass that took the branch at its fork (joined it no more than 15 m past the fork nose: a
## kart thrown or dropped onto it further on has not taken it), then the branch's respawn
## policy starts afresh for the next pass.
func _leave_branch(done: bool) -> void:
	if route < 0:
		return
	if race and race.has_method("on_branch") and _branch_entry <= track.path.branches[route].fork_nose_u + 15.0:
		race.on_branch(self, route, done)
	_branch_fails.erase(route)


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


## Can a headcrab land on this driver now? One at a time, none while charged, rescued or
## done, and none for CRAB_IMMUNE seconds after the last one let go.
func can_take_crab() -> bool:
	if star_time > 0.0 or state == State.RESPAWN or finished or crab_immune > 0.0:
		return false
	return face_crab == null or not is_instance_valid(face_crab)


## A headcrab lands on the driver's face after `delay` seconds (see FaceCrab).
## Returns false when it can not (see can_take_crab).
func blind(seconds: float, delay := 0.0) -> bool:
	if not can_take_crab():
		return false
	var crab := FaceCrab.new()
	add_child(crab)
	crab.attach(self, seconds, delay)
	face_crab = crab
	return true


## Out of a Xen portal `metres` further down the road, at speed, never into a jump gap. It
## follows the road it is on: along a branch (out past its merge), never into one.
func teleport_ahead(metres: float) -> void:
	var p := track.path
	var w := p.walk(route, route_pos(), metres, {})
	var r := int(w.x)
	var g := p.geo(r)
	var s := w.y
	var guard := 0
	while (g.gap[g.index_at(s)] == 1 or g.gap[g.index_at(s + 12.0)] == 1 or (r < 0 and _in_hazard(s))) and guard < 60:
		s += g.step
		guard += 1
		if r >= 0 and s > g.length - 2.0:
			s = p.branches[r].merge_s + s - g.length
			r = -1
			g = p
	var t := g.transform_at(s)
	var half := g.width[g.index_at(s)] * 0.5
	var lane := clampf(geo().lateral(global_position, route_index), -minf(3.0, half - 2.0), minf(3.0, half - 2.0))
	var v := maxf(linear_velocity.length(), 22.0)
	global_transform = Transform3D(t.basis, t.origin + t.basis.y * 1.0 + t.basis.x * lane)
	linear_velocity = -t.basis.z * v
	angular_velocity = Vector3.ZERO
	if r != route:
		route_u = geo().length  # it left its branch forwards, through the merge
		_set_route(r, g.index_at(s))
	route_index = g.index_at(s)
	route_u = s if r >= 0 else 0.0
	path_index = p.index_at(p.branches[r].main_s(s)) if r >= 0 else route_index
	boost(1.0, 1.0)
	star_time = maxf(star_time, 0.8)


## A level crossing, a force-field gate, a tentacle's band...: nowhere to drop a kart (the
## hazards stand on the main loop).
func _in_hazard(s: float) -> bool:
	var at := fposmod(s, track.path.length)
	return track.hazards != null and track.hazards.safe_respawn(at) != at


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
	# the hop counts what the kart already rises at: a second blast while it is in the air (a mortar
	# and the barrel it sets off) lifts it no higher than one. linear_velocity is the last physics
	# step's, so blasts within one step (a chain of barrels) also count this step's earlier throws,
	# and together push it no further along the ground than one
	var frame := Engine.get_physics_frames()
	if frame != _throw_frame:
		_throw_frame = frame
		_thrown = Vector3.ZERO
	var throw := _throw(impulse / mass)
	var up := throw.dot(grav_up)
	var rise := maxf((linear_velocity + _thrown).dot(grav_up), 0.0)
	if up > 0.0 and up > TUMBLE_UP - rise:
		throw -= grav_up * (up - maxf(TUMBLE_UP - rise, 0.0))
	var flat_was := _thrown - grav_up * _thrown.dot(grav_up)
	var flat := throw - grav_up * throw.dot(grav_up)
	throw += (flat_was + flat).limit_length(TUMBLE_FLAT) - flat_was - flat
	_thrown += throw
	apply_central_impulse(throw * mass)
	apply_torque_impulse(global_basis.z * mass * 3.0 * (1.0 if _rng.randf() > 0.5 else -1.0))
	visual.spin()
	audio.hurt()
	_drop_trailing()
	got_hit.emit(self, by)


## The velocity a tumble gives: the hit's own push `dv` and a hop, kept dramatic but on the deck
## (at most TUMBLE_UP up, TUMBLE_FLAT along the ground and TUMBLE_SIDE of that across the road),
## so an explosion or a punt never throws a kart over its wall or off the deck it is on.
func _throw(dv: Vector3) -> Vector3:
	dv += grav_up * 7.0
	var up_v := clampf(dv.dot(grav_up), -TUMBLE_UP, TUMBLE_UP)
	var flat := dv - grav_up * dv.dot(grav_up)
	if track:
		var across := geo().right[route_index]
		across -= grav_up * across.dot(grav_up)
		if across.length() > 0.1:
			across = across.normalized()
			var side := flat.dot(across)
			flat += across * (clampf(side, -TUMBLE_SIDE, TUMBLE_SIDE) - side)
	return flat.limit_length(TUMBLE_FLAT) + grav_up * up_v


## A track hazard hit this kart (scripts/hazards). Only the kart's owner decides (never on a
## remote proxy); a kart already down, charged, being rescued or just hit is left alone.
## kind: "spin" | "tumble" | "shock" | "bounce". Returns true if it took effect.
func hazard_hit(kind: String, impulse := Vector3.ZERO) -> bool:
	if remote or finished or star_time > 0.0 or hazard_grace > 0.0 or state != State.NORMAL:
		return false
	match kind:
		"tumble":
			tumble(null, impulse)
			hazard_grace = 2.4
		"bounce":
			# a force field: thrown back the way it came at a third of its speed, spinning
			var f := -global_basis.z
			linear_velocity -= f * linear_velocity.dot(f) * 1.35
			spin_out(null)
			hazard_grace = 1.6
		"shock":
			spin_out(null)
			Effects.sparks(get_parent(), global_position + grav_up, 1.4, Color(0.55, 0.8, 1.0))
			hazard_grace = 1.6
		_:
			spin_out(null)
			apply_central_impulse(impulse)
			hazard_grace = 1.6
	return true


func _drop_trailing() -> void:
	if trailing and is_instance_valid(trailing):
		trailing.queue_free()
	trailing = null


func _on_body_entered(other: Node) -> void:
	var impact := linear_velocity.length()
	# a watermelon left on the road: slip and spin
	if other is PhysProp and (other as PhysProp).model_key == Items.MELON and (other as PhysProp).is_in_group("traps"):
		var melon := other as PhysProp
		if not remote:
			var by = melon.get_meta("trap_owner", null)
			spin_out(by as Kart if is_instance_valid(by) else null)
			if melon.has_meta("nid"):
				Net.send_event("trap", [melon.get_meta("nid")])
		melon.smash(linear_velocity * 0.4)
		return
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
	# a trash can knocked over by a metrocop spectator: "pick up that can"
	CrowdDirector.notify(get_tree(), &"knock", body.global_position, self, null, key)
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
	var at := track.path.locate(global_position)
	route = at.x
	route_index = at.y
	if route >= 0:
		route_u = track.path.branches[route].progress(global_position, route_index)
	if _net_t < 0.0:
		# its owner dropped before streaming a state: still on its grid slot (Race._place_on_grid)
		lap_progress = _last_s
	_last_s = lap_progress
	_crossed_half = lap_progress > track.path.length * 0.5
	total_progress = lap * track.path.length + lap_progress
	_best_lap = lap
	# the stall watchdog counts from the takeover
	_watch_progress = total_progress
	_watch_time = 0.0
	if state == State.RESPAWN:
		_put_back(1.2)  # its owner's rescue does not carry over: on the road at once


## What the viewers draw this kart from, stamped `t` (Net.stamp): pose and motion, inputs,
## flags, lap and progress, suspension, then its road, hits so far and held item.
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
	if state == State.RESPAWN and rescue == Rescue.SINK:
		flags |= 64
	elif state == State.RESPAWN and rescue == Rescue.FALL:
		flags |= 128
	var vals := [t, p.x, p.y, p.z, q.x, q.y, q.z, q.w, v.x, v.y, v.z, w.x, w.y, w.z, in_steer, in_throttle,
		flags, drift_dir, drift_level, state, lap, total_progress,
		wheel_compress[0], wheel_compress[1], wheel_compress[2], wheel_compress[3],
		route, route_u, net_hits, Items.INFO.keys().find(item)]
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
		state = st
		state_time = 0.0
		if st == State.RESPAWN:
			_net_rescue(f)
	# every hit its owner took, a second one while it still spins too
	if int(d[28]) != net_hits:
		net_hits = int(d[28])
		if not first and visual:
			visual.spin()
			audio.hurt()
			CrowdDirector.notify(get_tree(), &"hit", _net_pos, self)
	# into the final lap (Race.on_lap only hears of the karts this peer drives)
	if not first and race and int(d[20]) > maxi(lap, 0) and int(d[20]) == int(race.get("laps")) - 1:
		CrowdDirector.notify(get_tree(), &"final_lap", _net_pos, self)
	lap = int(d[20])
	_net_tp = d[21]
	total_progress = _net_tp
	lap_progress = total_progress - lap * track.path.length
	for i in 4:
		wheel_compress[i] = d[22 + i]
	_net_route = int(d[26]) if int(d[26]) < track.path.branches.size() else -1
	_net_route_u = d[27]
	var ii := int(d[29])
	item = Items.INFO.keys()[ii] if ii >= 0 and ii < Items.INFO.size() else ""
	if first:
		global_transform = Transform3D(Basis(_net_rot), _net_pos)


## The owner's kart started a rescue: the same splash / scanner here (Kart.start_respawn).
func _net_rescue(flags: int) -> void:
	rescue = Rescue.SINK if flags & 64 else (Rescue.FALL if flags & 128 else Rescue.SCAN)
	CrowdDirector.notify(get_tree(), &"fall", _net_pos, self, null, rescue)
	match rescue:
		Rescue.SINK:
			liquid = track.liquid_at(_net_pos, route_index, geo())
			if liquid.y <= 0.0:
				liquid = Vector2(_net_pos.y, 1.0)
			var at := Vector3(_net_pos.x, liquid.x, _net_pos.z)
			Effects.splash(get_parent(), at, int(liquid.y), _net_vel.length())
			Effects.bubbles(get_parent(), at, int(liquid.y), SINK_T)
			get_tree().create_timer(0.25).timeout.connect(func():
				if is_instance_valid(self) and state == State.RESPAWN:
					Scanner.rescue(self))
		Rescue.FALL:
			fall_floor = geo().center[route_index].y
			get_tree().create_timer(FALL_T).timeout.connect(func():
				if is_instance_valid(self) and state == State.RESPAWN:
					Scanner.rescue(self))
		_:
			Scanner.rescue(self)


## Dead reckoning: show the proxy where its owner is now (latest state moved on
## by its velocity for the age of that state), converging smoothly.
func _net_follow(delta: float) -> void:
	state_time += delta
	air_time = 0.0 if grounded else air_time + delta
	if _net_t < 0.0:
		return
	var age := clampf(Net.stamp() - _net_t, 0.0, 0.35)
	var target_pos := _net_pos + _net_vel * age
	var target_rot := _net_rot
	if _net_avel.length() > 0.01:
		target_rot = (Quaternion(_net_avel.normalized(), _net_avel.length() * age) * _net_rot).normalized()
	# coming down from a jump the reckoning carries the fall on: never down through the road
	var up := Basis(_net_rot).y
	var landing := state != State.RESPAWN and _net_vel.dot(up) < -1.0
	if landing:
		target_pos = _above_road(_net_pos + up * 0.5, target_pos, up)
	var pos := global_position + _net_vel * delta
	var err := target_pos - pos
	if err.length() > 8.0 or state == State.RESPAWN:
		pos = target_pos
	else:
		pos += err * minf(1.0, delta * 10.0)
	if landing:
		pos = _above_road(pos + up, pos, up)
	var rot := global_basis.get_rotation_quaternion().slerp(target_rot, minf(1.0, delta * 12.0))
	global_transform = Transform3D(Basis(rot), pos)
	speed = _net_vel.length()
	fwd_speed = _net_vel.dot(-global_basis.z)
	# the standings see where it is by now: its progress carried on at its speed along the road (on a
	# branch times the lap metres a branch metre counts for)
	var g := geo()
	var along := _net_vel.dot(g.fwd[route_index]) if state != State.RESPAWN else 0.0
	if route >= 0:
		along *= (track.path.branches[route].main_s(route_u + 1.0) - track.path.branches[route].main_s(route_u - 1.0)) * 0.5
	total_progress = _net_tp + along * age
	# the owner streams its lap, progress and road (its branch passes reach every peer as Race
	# "branch" events, so a peer never counts one of its own)
	if _net_route != route:
		route = _net_route
		route_index = geo().closest(global_position, geo().index_at(lap_progress if route < 0 else _net_route_u))
	else:
		route_index = geo().closest(global_position, route_index)
	if route >= 0:
		route_u = track.path.branches[route].progress(global_position, route_index)
		path_index = track.path.index_at(lap_progress)
	else:
		path_index = route_index


## Where a proxy coming down may be drawn: at `to`, or lifted out of the ground a line from
## `from` (above the ground) down to it goes through.
func _above_road(from: Vector3, to: Vector3, up: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(from, to - up * 0.1, Game.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or (hit["normal"] as Vector3).dot(up) < 0.5:
		return to
	return to + up * ((hit["position"] - to).dot(up) + 0.1)
