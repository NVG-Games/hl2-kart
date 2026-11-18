class_name Rescuer
extends Node3D
## Whoever brings a kart back to the road when it sinks, falls off or gets stuck
## (Kart.start_respawn). Each track has its own (Game.TRACKS "rescue"): the Combine scanner's photo
## in City 17 (Scanner), a Black Mesa teleport (TeleportRescue), a Xen portal (XenPortal), the
## rebels' crane on Highway 17's coast (CraneRescue), a Combine teleport at Nova Prospekt (CombineTeleport),
## the vortigaunts' green energy in White Forest (VortigauntRescue).
##
## Every kind keeps the kart's own clock, so the owner and the other players' copies agree: over
## the AIM seconds before the kart's photo_time it gets ready, at photo_time it takes the kart (in
## that moment the kart is put back on the road, Kart._respawn_tick, and hidden for a moment,
## KartVisual._shown) and flashes the screen of the camera that follows it (RaceCamera.photo_flash),
## then it sees the kart off at its new place and is gone LINGER seconds after the take. The kind
## only decides how that looks and sounds, through the hooks below. It is in the "rescuers" group.

const AIM := 0.6  # seconds before the take: taking aim, the effect building up
const MOVED := 2.5  # metres further in a frame than its own motion carries it: the kart was put on the road
const STILL := 8.0  # m/s: a kart just put on the road is slower (it only drops onto its wheels)
const WAIT_MOVE := 0.4  # seconds after the take it waits for that (a proxy's new place comes late)
const LINGER := 2.2  # seconds after the take before it is gone

var kart: Kart
var t := 0.0  # seconds since it came
var _aimed := false
var _shot := -1.0  # t of the take (the scanner's photo), -1 before it
var _at := Vector3.ZERO  # where the kart was just before the take
var _moved := false  # the kart has been put on the road since the take
var _last_kp := Vector3.ZERO  # the kart's place last frame (it may be put on the road before this frame's take)
static var _quad: QuadMesh
## A kind every track sends instead of its own while this is set ("" for none): the rescue tests
## try any kind on any track.
static var kind_override := ""


## Sends the rescuer of the track `k` races on to it (Kart.start_respawn; on another player's
## copy of the kart, Kart._net_rescue).
static func rescue(k: Kart) -> void:
	var r: Rescuer
	match kind_of(k.track):
		"teleport":
			r = TeleportRescue.new()
		"xen_portal":
			r = XenPortal.new()
		"crane":
			r = CraneRescue.new()
		"combine_teleport":
			r = CombineTeleport.new()
		"vortigaunt":
			r = VortigauntRescue.new()
		_:
			r = Scanner.new()
	r.add_to_group("rescuers")
	k.get_parent().add_child(r)
	r.setup(k)


## Which rescuer this track sends (Game.TRACKS "rescue"; the scanner where none is named). Every
## player races the same track, so every peer picks the same one.
static func kind_of(track: Track) -> String:
	if kind_override != "":
		return kind_override
	var id: String = track.id if track and track.id != "" else str(Game.race_setting("track"))
	return str(Game.track(id).get("rescue", "scanner"))


## The models the rescuer of `track` spawns (Effects.prewarm draws them while the race loads, so
## the first rescue does not stall on their shaders).
static func models_of(track: Track) -> Array:
	if kind_of(track) == "vortigaunt" and Game.models.has("vortigaunt"):
		return ["vortigaunt"]
	return []


## A soft glow sprite's material, its own for each user so it can fade on its own: unshaded,
## added to the scene, turned to the camera and sized by its node's scale (the scanner's eye has
## the same kind, so Effects.prewarm draws one of these while the race loads).
static func glow_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	m.albedo_texture = SourceMaterials.tex("materials/sprites/glow01.png")
	return m


## A glow sprite 1 m across drawn with `mat` (glow_material); its scale sizes it.
static func glow_quad(mat: Material) -> MeshInstance3D:
	if _quad == null:
		_quad = QuadMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The sounds of the first of `lists` this install has any of (the newer files fall back to
## ones every install already has).
static func sounds(lists: Array) -> Array:
	for l: Array in lists:
		var have := l.filter(func(p: String) -> bool: return Game.stream(p) != null)
		if not have.is_empty():
			return have
	return []


## Up the way the gravity of kart `k` pulls where it stopped: off a tube's wall too. Another
## player's copy runs no physics of its own (its grav_up stays the sky), so there, inside a tube,
## it is from the kart towards the pipe's axis, as the owner's grav_up is.
static func stuck_up(k: Kart) -> Vector3:
	if not k.remote:
		return k.grav_up.normalized() if k.grav_up.length() > 0.5 else Vector3.UP
	var g: TrackPath = k.geo() if k.track else null
	var i := k.route_index
	if g == null or i >= g.mag.size() or g.mag[i] <= 0.0:
		return Vector3.UP
	var ax := k._tube_axis(g, i)
	var out := k.global_position - (g.center[i] + g.up[i] * g.mag[i])
	out -= ax * out.dot(ax)
	return -out.normalized() if out.length() > 0.5 else Vector3.UP


## A basis whose Y is `up` (any turn round it).
static func up_basis(up: Vector3) -> Basis:
	var y := up.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.95 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))


func setup(k: Kart) -> void:
	kart = k
	_last_kp = k.global_position


func _process(delta: float) -> void:
	t += delta
	if not is_instance_valid(kart) or t > 10.0:
		queue_free()
		return
	var kp := kart.global_position
	var jumped := _jumped(kp, delta)
	_tick(kp, delta)
	if _shot < 0.0:
		if kart.state != Kart.State.RESPAWN:
			# let go before it took the kart (a proxy, an owner who left): it just goes
			_shot = t
			_at = kp
			_moved = true
			_abandon()
		else:
			var take := kart.photo_time()
			# another player's kart, whose clock may lag its owner's by a packet: its new place on
			# the road can come in a moment before its own photo_time. That jump is the take, from
			# where it was (not a rescuer following it there first).
			var early := kart.remote and kart.state_time >= take - AIM and jumped
			if not early:
				_approach(kp, delta)
			if not _aimed and kart.state_time >= take - AIM:
				_aimed = true
				_aim()
			if kart.state_time >= take or early:
				_shot = t
				_at = _last_kp
				_take()
				_flash()
	if _shot >= 0.0:
		var since := t - _shot
		# out with the kart once it has been put on the road (on the owner's kart as it is taken, or
		# a physics step later; on a proxy when its new place comes in, a packet or so either side of
		# its photo_time). Put back only a few metres off it never jumps: then out where it is
		# WAIT_MOVE on, unless it is still dropping fast (a proxy whose new place is late yet), not
		# on any road.
		if not _moved and (jumped or (since > WAIT_MOVE and kart.velocity().length() < STILL)):
			_moved = true
			_arrive(kp, kp.distance_to(_at) > MOVED)
		_leave(kp, delta, since)
		if since > LINGER:
			queue_free()
	_after_tick(kp, delta)
	_last_kp = kp


## Was the kart put somewhere else this frame (on the road, by its rescue)? It is then more than
## MOVED from where its own motion since last frame would have carried it, and slower than STILL.
## Not just MOVED from where it was: a kart dropping away covers that in a few frames (a proxy's
## dead reckoning keeps it dropping until its new place comes in), and in one long frame. Nor
## while it goes fast: a proxy whose states stalled and then came on jumps too, but still
## dropping. On a proxy its velocity is its owner's (Kart.velocity), stopped by _put_back.
func _jumped(kp: Vector3, delta: float) -> bool:
	var v := kart.velocity()
	return v.length() < STILL and kp.distance_to(_last_kp + v * delta) > MOVED


## Is the take this frame? (Before it, a rescuer follows the kart; in that frame the owner's kart
## may already be on the road, so it stays where it was last frame.)
func _taking() -> bool:
	return _shot < 0.0 and kart.state == Kart.State.RESPAWN and kart.state_time >= kart.photo_time()


## For the kart the camera follows, the screen flashes (RaceCamera.photo_flash).
func _flash() -> void:
	var cam = kart.race.get("camera") if kart.race else null
	if cam is RaceCamera and (cam as RaceCamera).target == kart:
		(cam as RaceCamera).photo_flash(_flash_color())


## Plays the first of `lists` this install has (sounds) at `pos`, or on this rescuer as it moves
## with `follow`. Null when there is none.
func _play(lists: Array, pos: Vector3, volume_db := 0.0, pitch := 1.0, unit_size := 16.0, follow := false) -> AudioStreamPlayer3D:
	var have := sounds(lists)
	if have.is_empty():
		return null
	return Game.play_3d(have, pos, volume_db, pitch, unit_size, self if follow else null)


## The first thing of the world on the way from a to b (the kart itself left out), else empty.
func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, Game.LAYER_WORLD, [kart.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q)


## Up from the road the kart is on (where it was put back), the sky without one.
func _road_up() -> Vector3:
	var g := kart.geo() if kart.track else null
	if g == null or kart.route_index >= g.up.size():
		return Vector3.UP
	return g.up[kart.route_index].normalized()


# ---------------------------------------------------------------- the hooks (each kind its own)
## The colour of the screen flash at the take.
func _flash_color() -> Color:
	return RaceCamera.FLASH_WHITE


## Every frame, first.
func _tick(_kp: Vector3, _delta: float) -> void:
	pass


## Every frame before the take, while the kart is being rescued: on its way to it, with it.
func _approach(_kp: Vector3, _delta: float) -> void:
	pass


## Once, AIM seconds before the take.
func _aim() -> void:
	pass


## The take, at the kart's photo_time (the flash follows).
func _take() -> void:
	pass


## Once after the take, when the kart is at its new place `kp` (`far` from where it was taken),
## or WAIT_MOVE seconds on without it being put anywhere (nor dropping fast).
func _arrive(_kp: Vector3, _far: bool) -> void:
	pass


## Every frame from the take on (`since` seconds after it; the kart may not have moved yet).
func _leave(_kp: Vector3, _delta: float, _since: float) -> void:
	pass


## The kart was let go before the take: there is no take, it only goes.
func _abandon() -> void:
	pass


## Every frame, last.
func _after_tick(_kp: Vector3, _delta: float) -> void:
	pass
