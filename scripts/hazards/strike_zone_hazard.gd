class_name StrikeZoneHazard
extends Hazard
## Strikes that land on a stretch of road on a schedule of the shared clock: the HECU
## mortar barrage on the dam (a red flare burns where each shell will land) or the Lambda
## core discharging into the spiral (cyan rings on the core side). Where and when each
## strike lands is a hash of (seed, cycle), the same on every peer; each owner judges
## its own karts.

const MORTAR := Color(1.0, 0.2, 0.12)
const ARC := Color(0.3, 0.95, 1.0)

var _arc := false
var _core := Vector3.ZERO
var _markers: Array = []     # pooled [ring, glow] per strike that is coming
var _flash: OmniLight3D
var _snd := {}


func defaults() -> Dictionary:
	return {"style": "mortar", "zone": [s - 90.0, s + 90.0], "lat": [-0.85, 0.85], "core": [], "core_r": 14.3,
		"every": 2.2, "count": 1, "warn": 1.8, "radius": 5.5, "effect": "tumble", "first": 0.0, "push": 0.8,
		"lift": 0.5}


func build() -> void:
	_arc = str(p["style"]) == "arc"
	var c: Array = p["core"]
	_core = Vector3(c[0], c[1], c[2]) if c.size() == 3 else global_position
	if _arc:
		_snd["warn"] = sounds([["ambient/energy/zap2.wav"], ["ambient/energy/zap1.wav"]])
		_snd["near"] = sounds([["ambient/energy/newspark04.wav", "ambient/energy/newspark08.wav"],
			["ambient/energy/spark1.wav", "ambient/energy/spark2.wav"]])
		_snd["hit"] = sounds([["ambient/levels/labs/electric_explosion1.wav", "ambient/levels/labs/electric_explosion2.wav",
			"ambient/levels/labs/electric_explosion4.wav"]])
		_snd["zap"] = sounds([["ambient/energy/zap6.wav", "ambient/energy/zap7.wav", "ambient/energy/zap8.wav",
			"ambient/energy/zap9.wav"], ["ambient/energy/zap5.wav"]])
	else:
		_snd["warn"] = sounds([["hl1src/ambience/distantmortar1.wav", "hl1src/ambience/distantmortar2.wav"],
			["npc/env_headcrabcanister/launch.wav"]])
		_snd["near"] = sounds([["weapons/mortar/mortar_shell_incomming1.wav"], ["npc/env_headcrabcanister/incoming.wav"]])
		_snd["hit"] = sounds([["weapons/mortar/mortar_explode1.wav", "weapons/mortar/mortar_explode2.wav",
			"weapons/mortar/mortar_explode3.wav"]])
	if not visual:
		return
	for k in maxi(int(p["count"]), 1) * 3:
		var ring := Effects.ground_ring(self, global_position, Vector3.UP, float(p["radius"]), Color(ARC if _arc else MORTAR, 0.0))
		var g := glow("materials/sprites/redglow1.png" if not _arc else "materials/sprites/blueglow1.png", 1.6,
			ARC if _arc else MORTAR)
		_markers.append([ring, g])
	_flash = light(ARC, 30.0, 0.0)
	if _flash:
		_flash.global_position = _core + Vector3.UP * 2.0


## Strike j of cycle n: [t_hit, lap s, metres from the centre line].
func strike(n: int, j: int) -> Array:
	var every := tm("every")
	var count := maxi(int(p["count"]), 1)
	var z: Array = p["zone"]
	var t_hit := float(p["first"]) + n * every + every * 0.5 * j / count + tm("warn")
	var at_s := fposmod(float(z[0]) + rnd(n, 2 * j) * ahead(float(z[0]), float(z[1])), path.length)
	var hw := half_width(at_s)
	var u := rnd(n, 2 * j + 1)
	var lat: float
	if _arc:
		# the core side of the spiral, from the middle out to its broken edge
		var side := signf((_core - path.center_at(at_s)).dot(path.right[path.index_at(at_s)]))
		lat = side * lerpf(1.0, hw - 0.8, u)
	else:
		var l: Array = p["lat"]
		lat = lerpf(float(l[0]), float(l[1]), u) * hw
	return [t_hit, at_s, lat]


## Strikes landing between clock times t0 and t1: [[t_hit, lap s, lat], ...].
func strikes(t0: float, t1: float) -> Array:
	var out := []
	var every := tm("every")
	var base := float(p["first"]) + tm("warn")
	for n in range(maxi(int(floor((t0 - base) / every)) - 1, 0), int(floor((t1 - base) / every)) + 1):
		for j in maxi(int(p["count"]), 1):
			var e := strike(n, j)
			if e[0] >= t0 and e[0] <= t1:
				out.append(e)
	return out


func snapshot(t: float) -> Array:
	var out := []
	for e in strikes(t, t + tm("warn")):
		out.append([snappedf(e[0], 0.001), snappedf(e[1], 0.01), snappedf(e[2], 0.01)])
	return out


func spot(e: Array) -> Vector3:
	return road_point(float(e[1]), float(e[2]))


func tick(t: float, dt: float) -> void:
	if t < 0.0:
		return
	var warn := tm("warn")
	for e in strikes(_last_t, t + warn):
		var t_hit: float = e[0]
		if crossed(t_hit - warn, t):
			director.note(self, "warn")
			play(_snd["warn"], spot(e) + (Vector3.UP * 60.0 if not _arc else Vector3.ZERO), -6.0 if _arc else 2.0,
				12.0 if _arc else 200.0)
			if not _arc and visual:
				# a HECU signal flare burns where the shell will land
				Effects.flare(get_parent(), spot(e), warn)
		if crossed(t_hit - 0.95, t):
			play(_snd["near"], spot(e), 0.0, 30.0 if not _arc else 14.0)
			if _arc and visual:
				var at := spot(e)
				var r := float(p["radius"])
				Effects.lightning(get_parent(), at + Vector3(r, 0.3, 0.0), at + Vector3(0.0, 0.3, r), ARC, 0.15, 5, 0.3)
		if not _arc and visual and crossed(t_hit - 0.12, t):
			# the shell streaks down onto its flare
			Effects.tracer(get_parent(), spot(e) + Vector3.UP * 60.0, spot(e), Color(1.0, 0.8, 0.5))
		if crossed(t_hit, t):
			_impact(e)
	if visual:
		_show_markers(t, warn)
		if _flash:
			_flash.light_energy = maxf(_flash.light_energy - dt * 30.0, 0.0)


func _impact(e: Array) -> void:
	var at := spot(e)
	director.note(self, "fire")
	if visual:
		if _arc:
			var d := Vector3(at.x - _core.x, 0.0, at.z - _core.z).normalized()
			var from := Vector3(_core.x, at.y + 3.0, _core.z) + d * float(p["core_r"])
			Effects.lightning(get_parent(), from, at, ARC, 0.25, 10, 1.2)
			Effects.sparks(get_parent(), at, 1.2, ARC)
			play(_snd["zap"], at, 2.0, 20.0)
			if _flash:
				_flash.light_energy = 8.0
		else:
			Effects.explosion(get_parent(), at, 0.8, null, false)
		play(_snd["hit"], at, 6.0, 40.0)
	blast(at, float(p["radius"]), str(p["effect"]), float(p["push"]), float(p["lift"]) if not _arc else 0.0)


## The strikes still to come within `warn` seconds, each on a pooled marker that pulses
## faster as it nears.
func _show_markers(t: float, warn: float) -> void:
	var coming := strikes(t, t + warn)
	for m in _markers.size():
		var mk: Array = _markers[m]
		var ring: MeshInstance3D = mk[0]
		var g: MeshInstance3D = mk[1]
		if m >= coming.size():
			ring.visible = false
			g.visible = false
			continue
		var e: Array = coming[m]
		var at := spot(e)
		var u := clampf(1.0 - (float(e[0]) - t) / warn, 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(t * TAU * (2.0 + 8.0 * u))
		ring.visible = true
		Effects.place_ring(ring, at, path.up[path.index_at(float(e[1]))], float(p["radius"]))
		ring.set_instance_shader_parameter("col", Color(ARC if _arc else MORTAR, 0.25 + 0.6 * pulse * (0.4 + 0.6 * u)))
		g.visible = true
		g.global_position = at + Vector3.UP * 0.4
		g.scale = Vector3.ONE * (0.6 + 0.8 * pulse)


func sleep() -> void:
	for mk in _markers:
		(mk[0] as Node3D).visible = false
		(mk[1] as Node3D).visible = false


## Steer clear of a strike that lands about when the kart gets there (the spiral's outer
## half when the core is discharging).
func advice(k: Kart, at_s: float, speed: float) -> Dictionary:
	var t := director.clock()
	var r := float(p["radius"]) + 2.0
	for e in strikes(t, t + 2.5):
		var left := float(e[0]) - t
		var there := fposmod(at_s + speed * left - float(e[1]) + path.length * 0.5, path.length) - path.length * 0.5
		if absf(there) > r or absf(kart_lat(k) - float(e[2])) > r:
			continue
		var hw := half_width(float(e[1])) - 2.0
		var lat := float(e[2])
		return {"lat": clampf(lat - (r + 0.5) if lat > 0.0 else lat + r + 0.5, -hw, hw), "w": 0.9}
	return {}


func is_active(t: float) -> bool:
	return t >= 0.0 and not strikes(t, t + tm("warn")).is_empty()
