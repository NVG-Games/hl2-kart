class_name Hazard
extends Node3D
## One track hazard, built from a data["hazards"] entry (tools/hazards.py).
## Every hazard follows these rules:
## - its state is a function of the shared hazard clock (Race.hazard_clock) wherever
##   possible, so every peer shows the same thing with no network traffic;
## - it only hurts karts this peer drives (local_karts()); a remote kart's owner
##   decides, and that kart's streamed state shows the spin to everyone else;
## - it warns before it hurts: a sound and a visual on the exact danger area;
## - one pass costs at most one hit: a kart it hit is left alone by every hazard of its group
##   (HazardDirector.GROUP_GAP, data key "group") until the kart has driven out of the group.

var id := -1
var type := ""
var def := {}
var p := {}                  # defaults() overlaid with def["p"]
var track: Track
var path: TrackPath
var director: HazardDirector
var s := 0.0                 # where it sits on the lap (m)
var span := Vector2.ZERO     # lap range where it can hurt (m, may wrap)
var seed_v := 0              # this hazard's seed: rnd() is the same on every peer
var visual := true           # false on a dedicated server: logic only
var awake := false           # set by the director: a local kart or the camera is near
var aims_all := false        # the server aims it at any kart (tier B): it wakes for remote karts too
var group := -1              # its group (HazardDirector.groups), set by the director
var _last_t := -1e9          # clock at the previous tick (edge detection)


## Subclasses return their parameters with default values (see the data contract).
func defaults() -> Dictionary:
	return {}


func setup(d: Dictionary, trk: Track, dir: HazardDirector) -> void:
	def = d
	id = int(d.get("id", -1))
	type = str(d.get("type", ""))
	track = trk
	path = trk.path
	director = dir
	s = float(d.get("s", 0.0))
	var sp: Array = d.get("span", [s - 20.0, s + 20.0])
	span = Vector2(float(sp[0]), float(sp[1]))
	seed_v = int(d.get("seed", id * 7919 + 1))
	p = defaults()
	p.merge(d.get("p", {}), true)
	visual = not Net.dedicated
	name = "Hazard%d_%s" % [id, type]
	var pos: Array = d.get("pos", [])
	if pos.size() == 3:
		position = Vector3(pos[0], pos[1], pos[2])  # the director sits at the origin
	rotation.y = float(d.get("yaw", 0.0))
	build()


# ---------------------------------------------------------------- helpers
## A timing parameter at this race's difficulty (warn, lock, period, cool, every, stale...).
func tm(key: String) -> float:
	return float(p[key]) * director.scale(key)


func local_karts() -> Array[Kart]:
	return director.local_karts


func all_karts() -> Array[Kart]:
	return director.karts


## Deterministic 0..1 from (seed, a, b): the same on every peer and every run.
func rnd(a: int, b := 0) -> float:
	return HazardDirector.hash01(seed_v, a, b)


## A point `lat` metres right of the centre line and `h` above the road at lap position at_s.
func road_point(at_s: float, lat: float, h := 0.0) -> Vector3:
	var i := path.index_at(at_s)
	return path.center_at(at_s) + path.right[i] * lat + path.up[i] * h


func half_width(at_s: float) -> float:
	return path.width[path.index_at(at_s)] * 0.5


func kart_lat(k: Kart) -> float:
	return path.lateral(k.global_position, k.path_index)


## A kart on the main loop at lap metres a..b (may wrap): the road a hazard stands on, so a
## kart on a branch beside it is not picked as a target.
func on_road(k: Kart, a: float, b: float) -> bool:
	return k.route < 0 and director.in_span(k.lap_progress, a, b)


## Lap metres from a to b going forward (0 .. lap length).
func ahead(a: float, b: float) -> float:
	return fposmod(b - a, path.length)


## A kart a hazard may aim at: racing, upright, not charged, not already down or immune (just
## hit, or hit by this group on this pass).
func targetable(k: Kart) -> bool:
	return is_instance_valid(k) and not k.finished and k.state == Kart.State.NORMAL and k.star_time <= 0.0 \
		and k.hazard_grace <= 0.0 and not director.immune(k, self)


## Hits a kart this peer drives with an effect (Kart.hazard_hit) unless this hazard's group
## already hit it on this pass; a hit is noted and leaves it immune to the rest of the group.
## True if it took effect.
func hit(k: Kart, effect: String, impulse := Vector3.ZERO) -> bool:
	if director.immune(k, self) or not k.hazard_hit(effect, impulse):
		return false
	director.on_hit(k, self)
	return true


## True once, on the tick where the clock passes `when`.
func crossed(when: float, t: float) -> bool:
	return _last_t < when and t >= when


## Explosion-style damage to the karts this peer drives (Effects draws the blast).
func blast(pos: Vector3, radius: float, effect := "tumble", push := 1.0, lift := 0.4) -> void:
	for k in local_karts():
		var d := k.global_position - pos
		var dist := d.length()
		if dist >= radius:
			continue
		var f := 1.0 - dist / radius
		var flat := d - k.grav_up * d.dot(k.grav_up)
		var dir := flat.normalized() if flat.length() > 0.1 else -k.global_basis.z
		hit(k, effect, (dir * push + k.grav_up * lift) * k.mass * 9.0 * f)


## Applies an event here and asks every other peer to replay it (tiers B and D).
func send(kind: String, args: Array) -> void:
	director.broadcast(self, kind, args)


func play(snd, pos: Vector3, vol := 0.0, unit := 16.0, pitch := 1.0) -> void:
	if visual and snd != null and not (snd is Array and snd.is_empty()):
		Game.play_3d(snd, pos, vol, pitch, unit)


## The first of these sound lists that has been extracted (paths under assets/sound/; the
## newer hazard sounds fall back to ones every install already has).
static func sounds(lists: Array) -> Array:
	for l in lists:
		var have: Array = (l as Array).filter(func(f: String) -> bool: return Game.stream(f) != null)
		if not have.is_empty():
			return have
	return []


## The first of these models that has been extracted ("" if none).
static func pick_model(keys: Array) -> String:
	for k in keys:
		if str(k) != "" and Game.models.has(str(k)):
			return str(k)
	return ""


## A looping sound on `host` (the first file of `files` that exists); stopped until played.
func loop(files: Array, host: Node3D, unit := 16.0, vol := 0.0) -> AudioStreamPlayer3D:
	var have := sounds([files])
	if not visual or have.is_empty():
		return null
	var a := AudioStreamPlayer3D.new()
	a.stream = Game.stream(have[0])
	a.unit_size = unit
	a.max_distance = unit * 25.0
	a.volume_db = vol
	a.bus = "SFX"
	a.attenuation_filter_cutoff_hz = 9000.0
	host.add_child(a)
	# a one-shot file standing in for a missing loop just starts over
	if a.stream is AudioStreamWAV and (a.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
		a.finished.connect(a.play)
	return a


## A point light for a hazard (no shadows, faded with distance). LOW quality has none,
## except lamps that carry information (`always`).
func light(color: Color, rng: float, energy: float, always := false) -> OmniLight3D:
	if not visual or (not always and int(Game.settings.get("quality", 2)) == 0):
		return null
	var l := OmniLight3D.new()
	l.light_color = color
	l.omni_range = rng
	l.light_energy = energy
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 90.0
	l.distance_fade_length = 40.0
	add_child(l)
	return l


## A billboard glow sprite (redglow1, blueglow1, glow01...), on this hazard or on `host`.
func glow(tex: String, size: float, color := Color.WHITE, host: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = SourceMaterials.tex(tex)
	m.albedo_color = color
	m.disable_receive_shadows = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(host if host else self).add_child(mi)
	return mi


## A model of this hazard, placed so it stands on its base (Source models are origin-centred).
func stand(key: String, scale := 1.0) -> Node3D:
	var m := Game.spawn_model(key)
	add_child(m)
	m.scale = Vector3.ONE * scale
	m.position.y = -Game.model_aabb(key).position.y * scale
	return m


# ---------------------------------------------------------------- virtuals
func build() -> void:
	pass


func tick(_t: float, _dt: float) -> void:
	pass


func on_event(_kind: String, _args: Array) -> void:
	pass


## Steering / speed advice for a computer driver at lap position at_s doing `speed`:
## {"lat": metres from the centre line, "w": urgency 0..1, "vmax": m/s}; {} for none.
func advice(_k: Kart, _at_s: float, _speed: float) -> Dictionary:
	return {}


## True when a kart dropped at at_s by the scanner would land in the danger zone.
func blocks_respawn(_at_s: float) -> bool:
	return false


## A local kart or the camera came near: start loops and lights.
func wake() -> void:
	pass


## No local kart near any more: hide lasers, stop loops, reset reactive states.
func sleep() -> void:
	pass


## True while it is doing something dangerous right now (minimap blink).
func is_active(_t: float) -> bool:
	return false


## Models it spawns mid-race (a rocket per salvo...): Effects.prewarm draws them at load.
func spawns() -> Array:
	return []


## What a timer hazard shows at clock t, as plain numbers (determinism checks): the same
## on every peer for the same t.
func snapshot(_t: float) -> Array:
	return []
