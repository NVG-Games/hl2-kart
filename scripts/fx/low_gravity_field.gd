class_name LowGravityField
extends Node3D
## Low gravity on stretches of road: the track data's "low_gravity" list (tools/track_gen.py
## low_gravity()), each zone {"route": -1 for the main loop or a branch's index, "s0", "s1": its
## start and end in that road's metres, "scale": the share of the game's gravity a kart feels in
## it, "ease": the metres over which it eases in after s0 and back out before s1}.
##
## The physics is the karts' own: a local kart carries the rest of its weight itself in a zone
## (Kart._low_gravity); a proxy is moved by its owner's physics and needs nothing. AIController and
## Kart.run_up_speed count a slope there at the zone's gravity (Kart.gravity_scale_at).
##
## This node shows the zones: green motes rising out of the void along each one, a glowing column
## either side of the road where it starts and up out of the void under each jump in it, a green
## light at each jump and a low hum. None on a headless run or the dedicated server (scale_at needs
## no node).

const MOTE := Color(0.45, 1.0, 0.55)
## the hum: a teleporter's loop pitched down, or Xen's hollow wind where the content lacks it
const HUM := ["ambient/levels/labs/teleport_active_loop1.wav", "hl1src/ambience/alien_hollow.wav"]
## metres of zone each mote emitter covers
const MOTE_EVERY := 30.0

var track: Track
var _columns: Array[MeshInstance3D] = []
var _col_alpha: Array[float] = []
var _t := 0.0


## The zones of track data `d` as [route, s0, s1, scale, ease] for scale_at.
static func zones(d: Dictionary) -> Array:
	var out: Array = []
	for z in d.get("low_gravity", []):
		out.append([int(z.get("route", -1)), float(z["s0"]), float(z["s1"]), clampf(float(z.get("scale", 1.0)), 0.05, 1.0),
			maxf(float(z.get("ease", 15.0)), 0.1)])
	return out


## The share of the game's gravity at metres s along `route` (-1 the main loop, whose zones may run
## over the start line: `length` is the lap's) under the zones `list` (zones()): 1 outside them,
## the zone's scale inside, easing in over its first `ease` metres and back out over its last.
## tools/branches.py gravity_scale is the same for the generator's launch speeds.
static func scale_at(list: Array, route: int, s: float, length := 0.0) -> float:
	var out := 1.0
	for z in list:
		if int(z[0]) != route:
			continue
		var span: float = z[2] - z[1]
		var d: float = s - z[1]
		if route < 0 and length > 0.0:
			span = fposmod(span, length)
			d = fposmod(d, length)
		if d < 0.0 or d > span:
			continue
		var e: float = minf(z[4], span * 0.5)
		var w := smoothstep(0.0, e, d) * smoothstep(0.0, e, span - d)
		out = minf(out, lerpf(1.0, z[3], w))
	return out


## The field's sights and hum for a track with low-gravity zones, or null (none, a BSP map, the
## dedicated server, a headless run).
static func spawn_for(trk: Track) -> LowGravityField:
	if trk.is_bsp or Net.dedicated or DisplayServer.get_name() == "headless":
		return null
	if (trk.data.get("low_gravity", []) as Array).is_empty():
		return null
	var f := LowGravityField.new()
	f.name = "LowGravity"
	trk.add_child(f)
	f.setup(trk)
	return f


func setup(trk: Track) -> void:
	track = trk
	var low := int(Game.settings.get("quality", 2)) == 0
	for z in zones(trk.data):
		var g := trk.path.geo(int(z[0]))
		var s0: float = z[1]
		var s1: float = z[2]
		if s1 < s0:
			s1 += g.length
		# motes over the road and the islands, all along the zone
		var s := s0
		while s < s1:
			_motes(g, minf(s + MOTE_EVERY * 0.5, s1), low)
			s += MOTE_EVERY
		# the gateposts where it starts
		_gate(g, s0 + 4.0)
		# a column up out of the void under every jump in it, its light and its hum
		var i := g.index_at(s0)
		var i1 := g.index_at(s1)
		var guard := 0
		while i != i1 and guard < g.n:
			guard += 1
			var j := g.wi(i + 1)
			if g.gap[j] == 1 and g.gap[i] == 0:
				var k := j
				while g.gap[g.wi(k + 1)] == 1 and k != i1:
					k = g.wi(k + 1)
				_updraft(g, g.u_of(j), g.u_of(k) + g.step, low)
			i = j
		_hum(g.center_at((s0 + s1) * 0.5))


## Green motes rising from 6 m under the road to well over it, over the road and 12 m past its
## edges on a 30 m stretch around metres s.
func _motes(g: TrackPath, s: float, low: bool) -> void:
	var p := CPUParticles3D.new()
	p.amount = 12 if low else 24
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	var i := g.index_at(s)
	p.emission_box_extents = Vector3(g.width[i] * 0.5 + 12.0, 4.0, MOTE_EVERY * 0.5)
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0.0, 0.12, 0.0)
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.9
	p.color_ramp = _fade()
	var q := QuadMesh.new()
	q.size = Vector2(0.7, 0.7)
	q.material = Effects.sprite("materials/sprites/glow01.png", true, MOTE)
	p.mesh = q
	p.visibility_range_end = 320.0
	add_child(p)
	# (the road's own frame: the box lies across it and along it)
	var t := g.transform_at(s)
	p.global_transform = Transform3D(t.basis, t.origin - t.basis.y * 2.0)
	p.emitting = true


## Two glowing columns either side of the road at metres s, from the void to 26 m over the road.
func _gate(g: TrackPath, s: float) -> void:
	var i := g.index_at(s)
	var c := g.center_at(s)
	for sgn: float in [-1.0, 1.0]:
		var at := c + g.right[i] * sgn * (g.width[i] * 0.5 + 7.0)
		_column(at - Vector3.UP * 40.0, at + Vector3.UP * 26.0, 3.0, 0.35)
		_light(at + Vector3.UP * 2.0, 18.0, 1.4)


## The void's updraft under a jump from metres a to b: a wide faint column up through the gap and
## a bright one at each side, motes rising fast out of the void, a green light over the gap.
func _updraft(g: TrackPath, a: float, b: float, low: bool) -> void:
	var s := (a + b) * 0.5
	var i := g.index_at(s)
	var c := g.center_at(s)
	_column(c - Vector3.UP * 70.0, c + Vector3.UP * 16.0, 10.0, 0.18)
	for sgn: float in [-1.0, 1.0]:
		var at := c + g.right[i] * sgn * (g.width[i] * 0.5 + 2.5)
		_column(at - Vector3.UP * 60.0, at + Vector3.UP * 20.0, 2.5, 0.4)
	_light(c + Vector3.UP * 3.0, 24.0, 1.8)
	var p := CPUParticles3D.new()
	p.amount = 16 if low else 32
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(g.width[i] * 0.5 + 3.0, 10.0, (b - a) * 0.5 + 3.0)
	p.direction = Vector3.UP
	p.spread = 6.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.color_ramp = _fade()
	var q := QuadMesh.new()
	q.size = Vector2(0.8, 0.8)
	q.material = Effects.sprite("materials/sprites/glow01.png", true, MOTE)
	p.mesh = q
	p.visibility_range_end = 360.0
	add_child(p)
	p.global_transform = Transform3D(g.transform_at(s).basis, c - Vector3.UP * 30.0)
	p.emitting = true


func _column(a: Vector3, b: Vector3, width: float, alpha: float) -> void:
	var mi := Effects.beam_node(Color(MOTE, alpha), width, "materials/sprites/physbeam.png")
	mi.visibility_range_end = 420.0
	add_child(mi)
	Effects.place_beam(mi, a, b)
	_columns.append(mi)
	_col_alpha.append(alpha)


func _light(at: Vector3, reach: float, energy: float) -> void:
	if int(Game.settings.get("quality", 2)) == 0:
		return
	var l := OmniLight3D.new()
	l.light_color = MOTE
	l.omni_range = reach
	l.light_energy = energy
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 140.0
	l.distance_fade_length = 40.0
	add_child(l)
	l.global_position = at


func _hum(at: Vector3) -> void:
	for path: String in HUM:
		var s := Game.stream(path)
		if s == null:
			continue
		var a := AudioStreamPlayer3D.new()
		a.stream = s
		a.pitch_scale = 0.7
		a.volume_db = -8.0
		a.unit_size = 22.0
		a.max_distance = 260.0
		a.bus = "SFX"
		a.attenuation_filter_cutoff_hz = 6000.0
		add_child(a)
		a.global_position = at
		# a one-shot file standing in for a loop just starts over
		if s is AudioStreamWAV and (s as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
			a.finished.connect(a.play)
		a.play()
		return


## Fades a mote in, holds it, fades it out.
static func _fade() -> Gradient:
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 0))
	gr.set_color(1, Color(1, 1, 1, 0))
	gr.add_point(0.2, Color(1, 1, 1, 1))
	gr.add_point(0.75, Color(1, 1, 1, 0.8))
	return gr


func _process(delta: float) -> void:
	# the columns breathe slowly, each a little out of step with the next
	_t += delta
	for k in _columns.size():
		var a := _col_alpha[k] * (0.75 + 0.25 * sin(_t * 1.3 + k * 1.7))
		_columns[k].set_instance_shader_parameter("col", Color(MOTE, a))
