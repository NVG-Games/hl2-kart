class_name VortigauntRescue
extends Rescuer
## The White Forest rescue (Rescuer): the vortigaunts pull the kart back with their green energy.
## Where the kart stopped three of them come out of green flashes one after the other, beside it
## and to its front (on the bank where it sank, on the road's edge where it fell off), facing it.
## They rear back with their arms spread as their hands charge, crackling between them, then thrust
## their hands at the kart (their zap, zapattack1) and hold it in lime-green beams that crackle onto
## its body, while a cage of arcs wraps round it and a stuck kart is lifted off the ground in them
## (a sunk one is hauled up out of the water, a falling one caught as it drops). At the kart's
## photo_time they and the kart are gone in a green-yellow flash (the screen of the camera
## following it flashes the same). On the road they come out of green flashes again beside the
## kart's new place with their beams already on it, the kart shows (KartVisual._shown) lifted in
## the glow among them, they set it down on its wheels, lower their hands, one of them says a word
## and they vanish one by one. The kart's body never moves for it: only its look is lifted and set
## down (KartVisual's place under the kart), so the owner and the other players' copies agree.
##
## Unlike the Xen portal (a ball over the kart that swallows it) it is figures standing round the
## kart with beams from their hands, and a yellower green. On an install without the vortigaunt's
## animations (assets/models/vortigaunt.anims.json) their arms are posed by BipedPose; without the
## model the beams come out of the green flashes where they would stand; without the sounds it is
## silent. Nothing of it is built on a dedicated server.

const COL := Color(0.56, 1.0, 0.3)  # the vortigaunts' energy: lime green, yellower than Xen's portal
const CORE := Color(0.9, 1.0, 0.68)  # its bright core
const FLASH := Color(0.76, 1.0, 0.42)  # the screen flash
const VORTS := 3
const APPEAR := [0.0, 0.13, 0.26]  # seconds after it comes each one steps out of its flash
const COME_ROAD := [0.0, 0.05, 0.1]  # the same on the road, after the kart's new place is known
const GONE := [1.45, 1.6, 1.75]  # seconds after the take each one vanishes on the road (LINGER is 2.2)
const MID := 0.7  # metres over the kart's origin its middle is (where the beams meet)
const BEAMS := 0.8  # seconds of beams before the take for a stuck or falling kart
const SINK_BEAMS := 0.1  # seconds before the haul out of the liquid (Kart.SINK_T) a sunk kart's beams come
const LIFT := 1.0  # metres a stuck kart's look is lifted in the beams before the take
const ROAD_REACH := 1.5  # metres off the road's plane a place on the road may be (not a floor under it)
const SET := 0.9  # metres over the road the kart shows in their beams on the road
const SHOW := 0.25  # seconds after the take the kart is hidden (KartVisual._shown)
const DOWN := 0.35  # seconds it takes to set the kart down once it shows
const FADE := 0.22  # seconds the beams take to die away once the kart is down (or let go)
const SEGS := 6  # pieces of each beam
const HAND_SEGS := 3  # pieces of the arc between a vortigaunt's hands while they charge
const WRAP := 10  # pieces of each of the two rings of arcs round the kart
const CRACKLE := 0.05  # seconds between new jags of the arcs
const POP := 0.35  # seconds a flash it comes out of (or vanishes in) lasts
## zapattack1 (the "zap" of the vortigaunt's ANIMS): it rears back with its arms spread (0.4 to
## 1.2 s), thrusts its hands forward at RELEASE and holds them there until about 2.2 s, then
## recovers to its stance by END (frame 0 and the end are its ActionIdle, the "idle")
const RELEASE := 1.35
const HOLD_A := 1.45
const HOLD_B := 2.15
const RECOVER := 2.2
const END := 3.0
## sounds (Rescuer.sounds: the first list of them this install has): the flash each one comes out
## of, their charge (timed to end as they zap), the zap, the hum of the beams holding the kart, the
## dispel blast at the take, the crackle as they set it down, and a word from one of them
const POPS := [["ambient/energy/zap7.wav", "ambient/energy/zap8.wav", "ambient/energy/zap9.wav"], ["ambient/energy/zap1.wav"]]
const CHARGE := [["npc/vort/attack_charge.wav"], ["hl1src/debris/zap1.wav"], ["ambient/energy/zap1.wav"]]
const SHOOT := [["npc/vort/attack_shoot.wav"], ["npc/vort/vort_attack_shoot1.wav"], ["hl1src/weapons/electro4.wav"],
	["ambient/energy/zap5.wav"]]
const HUM := [["npc/vort/vorthealsingle_loop.wav"], ["npc/vort/health_charge.wav"]]
const DISPEL := [["npc/vort/vort_dispell.wav"], ["npc/vort/attack_shoot.wav"], ["ambient/energy/zap5.wav"]]
const ZAPS := [["ambient/energy/zap5.wav", "ambient/energy/zap6.wav"], ["ambient/energy/zap1.wav"]]
const VOICE := [["vo/npc/vortigaunt/yesforward.wav", "vo/npc/vortigaunt/forfreedom.wav", "vo/npc/vortigaunt/prevail.wav",
	"vo/npc/vortigaunt/wellmet.wav", "vo/npc/vortigaunt/vort_excellent.wav", "vo/npc/vortigaunt/ourhonor.wav"]]
const HUM_FADE := 0.25  # seconds the hum takes to fade out


## One of them: where it stands and its nodes.
class Vort:
	var root: Node3D  # at its foot, Y its up, Z towards the kart
	var model: Node3D
	var sk: Skeleton3D
	var hand_l := -1
	var hand_r := -1
	var foot := Vector3.ZERO
	var shown := false
	var gone := false  # vanished (it comes no more until the road)
	var kt0 := 0.0  # the kart's clock as it came
	var a := 0.0  # its zap's time now
	var charge := 0.0  # how bright its hands are, 0..1
	var core: Array[MeshInstance3D] = []  # its beam onto the kart, the thin bright core ...
	var glow: Array[MeshInstance3D] = []  # ... and the wide glow round it
	var arc_core: Array[MeshInstance3D] = []  # the arc between its hands
	var arc_glow: Array[MeshInstance3D] = []
	var jags := PackedVector2Array()  # the jags of its beam and its hands' arc, new every CRACKLE
	var end := Vector3.ZERO  # where on the kart its beam lands (in the kart's space), new every CRACKLE
	var hand_glows: Array[MeshInstance3D] = []
	var light: OmniLight3D


var _vis := true  # false on a dedicated server: nothing is built
var _up := Vector3.UP
var _anims: AnimSet
var _yaw := 0.0  # the model's turn that faces it along its root's Z (its animations face +X)
var _vorts: Array[Vort] = []
var _beam_at := 0.0  # the kart's clock when they zap it
var _fired := false
var _beam := 0.0  # how bright the beams are, 0..1
var _wrap := 0.0  # how bright the cage of arcs and the glow round the kart are, 0..1
var _lift := 0.0  # metres the kart's look is lifted now
var _vis_rest := Vector3.ZERO  # the kart's look's own place under it
var _vis_on := false  # this rescuer has moved the kart's look (and puts it back)
var _out := -1.0  # t it stood on the road, -1 before
var _down := -1.0  # t the kart was set down on the road, -1 before
var _showed := false  # the kart has shown on the road
var _cut := -1.0  # t it was let go before the take, -1 if not
var _crackle_in := 0.0
var _spin := 0.0
var _charge_len := 0.0  # seconds of the charge this install has (0: none)
var _charged := false  # the charge has started
var _wrap_core: Array[MeshInstance3D] = []
var _wrap_glow: Array[MeshInstance3D] = []
var _wrap_jags := PackedVector2Array()
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _hand_mat: StandardMaterial3D
var _light: OmniLight3D
var _hum: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()  # the arcs' jags and where they land (looks only)


func setup(k: Kart) -> void:
	super(k)
	_vis = not Net.dedicated
	if not _vis:
		return
	_rng.randomize()
	# up the way its gravity pulls where it stopped (off a tube's wall too); the sky where it
	# sinks or falls
	if k.rescue == Kart.Rescue.SCAN:
		_up = Rescuer.stuck_up(k)
	if k.visual:
		_vis_rest = k.visual.position
	var take := k.photo_time()
	match k.rescue:
		Kart.Rescue.SINK:
			_beam_at = Kart.SINK_T - SINK_BEAMS
		_:
			_beam_at = take - BEAMS
	_anims = AnimSet.of("vortigaunt")
	if _anims and not _anims.has("zap"):
		_anims = null
	_yaw = _anims.yaw_to(Vector3(0.0, 0.0, 1.0)) if _anims else 0.0
	_hand_mat = Rescuer.glow_material(Color(CORE, 0.0))
	for foot in _spots_where_stopped(k):
		_vorts.append(_new_vort(foot))
	for i in 2 * WRAP:
		var c := Effects.beam_node(Color(CORE, 0.0), 0.07)
		c.extra_cull_margin = 4.0
		add_child(c)
		_wrap_core.append(c)
		var g := Effects.beam_node(Color(COL, 0.0), 0.45, "materials/sprites/physbeam.png")
		g.extra_cull_margin = 4.0
		add_child(g)
		_wrap_glow.append(g)
	_wrap_jags.resize(2 * WRAP)
	_glow_mat = Rescuer.glow_material(Color(COL, 0.0))
	_glow = Rescuer.glow_quad(_glow_mat)
	add_child(_glow)
	_light = OmniLight3D.new()
	_light.light_color = COL
	_light.omni_range = 10.0
	_light.light_energy = 0.0
	add_child(_light)
	var ch := Rescuer.sounds(CHARGE)
	_charge_len = Game.stream(ch[0]).get_length() if not ch.is_empty() else 0.0
	_charged = _charge_len <= 0.0
	_crackle(true)
	_draw()


## A vortigaunt standing at `foot`, not shown yet: its model (none on an install without it), its
## beam, the arc between its hands, their glows and its light.
func _new_vort(foot: Vector3) -> Vort:
	var v := Vort.new()
	v.foot = foot
	v.root = Node3D.new()
	v.root.visible = false
	add_child(v.root)
	if Game.models.has("vortigaunt"):
		v.model = Game.spawn_model("vortigaunt")
		v.model.rotation.y = _yaw
		v.root.add_child(v.model)
		v.sk = AnimSet.skeleton(v.model)
		if v.sk:
			v.hand_l = BipedPose.limb(v.sk, "L_Hand")
			v.hand_r = BipedPose.limb(v.sk, "R_Hand")
	for i in SEGS:
		var c := Effects.beam_node(Color(CORE, 0.0), 0.1)
		c.extra_cull_margin = 8.0
		c.visible = false
		add_child(c)
		v.core.append(c)
		var g := Effects.beam_node(Color(COL, 0.0), 0.6, "materials/sprites/physbeam.png")
		g.extra_cull_margin = 8.0
		g.visible = false
		add_child(g)
		v.glow.append(g)
	for i in HAND_SEGS:
		var c := Effects.beam_node(Color(CORE, 0.0), 0.06)
		c.visible = false
		add_child(c)
		v.arc_core.append(c)
		var g := Effects.beam_node(Color(COL, 0.0), 0.3, "materials/sprites/physbeam.png")
		g.visible = false
		add_child(g)
		v.arc_glow.append(g)
	v.jags.resize(SEGS + HAND_SEGS)
	for i in 2:
		var h := Rescuer.glow_quad(_hand_mat)
		h.visible = false
		add_child(h)
		v.hand_glows.append(h)
	v.light = OmniLight3D.new()
	v.light.light_color = COL
	v.light.omni_range = 5.0
	v.light.light_energy = 0.0
	add_child(v.light)
	return v


# ---------------------------------------------------------------- where they stand
## Where they stand for the kart where it stopped: round a stuck kart (to its front and sides, so
## the camera behind it sees them), on the bank round where it sank, on the road's edge where it
## fell off. Each on ground it can stand on, with room over it and (but where it fell) a clear
## line to the kart; the road beside the kart where nothing round it will do.
func _spots_where_stopped(k: Kart) -> Array[Vector3]:
	var kp := k.global_position
	var g: TrackPath = k.geo() if k.track else null
	var i := k.route_index if g and k.route_index < g.n else -1
	var feet: Array[Vector3] = []
	match k.rescue:
		Kart.Rescue.SINK:
			var at := Vector3(kp.x, maxf(k.liquid.x, kp.y), kp.z)
			var round_it: Array[Vector3] = []
			for r: float in [4.0, 6.0, 8.5, 11.0]:
				for d in _dirs(k, _up, [0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0]):
					round_it.append(at + d * r)
			feet = _pick(round_it, _up, at, at + _up * 0.4, true, 2.5)
			if feet.size() < 2 and i >= 0:
				feet = _pick(_edge(g, i, kp), g.up[i], at, at, false, 0.0, ROAD_REACH)
		Kart.Rescue.FALL:
			if i >= 0:
				feet = _pick(_edge(g, i, kp), g.up[i], kp, kp, false, 0.0, ROAD_REACH)
		_:
			var see := kp + _up * MID
			var round_it: Array[Vector3] = []
			for r: float in [3.6, 4.8, 2.8]:
				for d in _dirs(k, _up, [45.0, -45.0, 115.0, -115.0, 0.0, 80.0, -80.0, 160.0, -160.0]):
					round_it.append(kp + d * r)
			feet = _pick(round_it, _up, kp, see, true, 1.8)
			if feet.size() < 2 and i >= 0:
				feet = _pick(_beside(g, i, kp), g.up[i], kp, see, true, 1.8, ROAD_REACH)
	if feet.size() < 2 and i >= 0:
		# nowhere better: on the road beside the kart's own sample, where there is road
		feet = []
		for p in _beside(g, i, kp).slice(0, VORTS):
			var hit := _ray(p + g.up[i] * 2.2, p - g.up[i] * 3.5)
			feet.append(hit["position"] if not hit.is_empty() else p)
	return feet


## Where they stand beside the kart's new place `kp` on the road (its sample `i`): at its sides a
## little ahead, one of them further back, all on the road.
func _spots_on_road(kp: Vector3) -> Array[Vector3]:
	var g: TrackPath = kart.geo() if kart.track else null
	if g == null:
		var feet: Array[Vector3] = []
		for d in _dirs(kart, _up, [60.0, -60.0, 180.0]):
			feet.append(kp + d * 3.0)
		return feet
	var i := g.closest(kp, kart.route_index)
	var see := kp + _up * (MID + SET)
	var feet := _pick(_beside(g, i, kp), _up, kp, see, true, 1.8, ROAD_REACH)
	if feet.size() < 2:
		feet = []
		for p in _beside(g, i, kp).slice(0, VORTS):
			var hit := _ray(p + _up * 2.2, p - _up * 3.5)
			feet.append(hit["position"] if not hit.is_empty() else p)
	return feet


## Directions round `up` at `angles` (degrees) from the kart's nose, its left at +90.
func _dirs(k: Kart, up: Vector3, angles: Array) -> Array[Vector3]:
	var nose := -k.global_basis.z
	nose -= up * nose.dot(up)
	if nose.length() < 0.1:
		nose = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD)
	nose = nose.normalized()
	var out: Array[Vector3] = []
	for a: float in angles:
		out.append(nose.rotated(up, deg_to_rad(a)))
	return out


## Places on the road at its sample `i` beside the kart at `kp`: at its sides a little ahead, then
## further back and further out (kept on the road, the kart's own lateral clamped in it).
func _beside(g: TrackPath, i: int, kp: Vector3) -> Array[Vector3]:
	var lat := g.lateral(kp, i)
	var along := (kp - g.center[i]).dot(g.fwd[i])
	var out: Array[Vector3] = []
	for o: Vector2 in [Vector2(-2.9, 1.0), Vector2(2.9, 1.0), Vector2(-2.6, -3.0), Vector2(2.6, -3.0),
			Vector2(-4.2, -0.8), Vector2(4.2, -0.8), Vector2(-2.2, 3.4), Vector2(2.2, 3.4)]:
		out.append(_road_at(g, i, lat + o.x, along + o.y))
	return out


## Places on the road's edge at its sample `i` on the side the kart at `kp` went off, along the
## edge either side of it.
func _edge(g: TrackPath, i: int, kp: Vector3) -> Array[Vector3]:
	var lat := g.lateral(kp, i)
	var side := signf(lat) if absf(lat) > 0.3 else 1.0
	var half := g.width[i] * 0.5
	var along := (kp - g.center[i]).dot(g.fwd[i])
	var out: Array[Vector3] = []
	for o: Vector2 in [Vector2(0.0, 0.0), Vector2(0.0, -3.2), Vector2(0.0, 3.2), Vector2(-1.8, -1.6), Vector2(-1.8, 1.6),
			Vector2(0.0, -6.0), Vector2(0.0, 6.0)]:
		out.append(_road_at(g, i, side * (half - 0.9 + o.x), along + o.y))
	return out


## The road surface `lat` metres across and `along` metres on from sample `i`, kept 0.7 m inside
## its edges.
func _road_at(g: TrackPath, i: int, lat: float, along: float) -> Vector3:
	var half := maxf(g.width[i] * 0.5 - 0.7, 0.5)
	return g.center[i] + g.right[i] * clampf(lat, -half, half) + g.fwd[i] * along


## Up to VORTS of `places` they can stand at, in that order, spread round `centre` (each at least
## `near` metres from it and 1.8 m from the others, well apart in angle): ground under the place
## along `up` (within `reach` metres of it) that is flat enough, room over it to stand, not under a
## liquid, and (with `sight`) a clear line from its chest to `see`.
func _pick(places: Array[Vector3], up: Vector3, centre: Vector3, see: Vector3, sight: bool, near: float,
		reach := 3.5) -> Array[Vector3]:
	var feet: Array[Vector3] = []
	var tried := {}
	for apart: float in [55.0, 30.0]:
		for n in places.size():
			if feet.size() >= VORTS:
				break
			if not tried.has(n):
				tried[n] = _foot(places[n], up, see, sight, reach)
			if tried[n] == null:
				continue
			var f: Vector3 = tried[n]
			var d := f - centre
			d -= up * d.dot(up)
			if d.length() < near or feet.has(f):
				continue
			var ok := true
			for q in feet:
				var e := q - centre
				e -= up * e.dot(up)
				if q.distance_to(f) < 1.8 or (d.length() > 0.1 and e.length() > 0.1 and rad_to_deg(d.angle_to(e)) < apart):
					ok = false
					break
			if ok:
				feet.append(f)
		if feet.size() >= VORTS:
			break
	return feet


## The foot of one standing at `p` (see _pick), or null.
func _foot(p: Vector3, up: Vector3, see: Vector3, sight: bool, reach: float) -> Variant:
	var hit := _ray(p + up * minf(2.2, reach), p - up * reach)
	if hit.is_empty() or (hit["normal"] as Vector3).dot(up) < 0.6:
		return null
	var foot: Vector3 = hit["position"]
	if not _ray(foot + up * 0.3, foot + up * 1.9).is_empty():
		return null
	if sight and not _ray(foot + up * 1.15, see).is_empty():
		return null
	if up.y > 0.7 and kart.track and foot.y < kart.track.liquid_at(foot, kart.route_index).x + 0.05:
		return null
	return foot


# ---------------------------------------------------------------- the hooks
func _flash_color() -> Color:
	return FLASH


## It follows the kart's middle (its hum and charge go with it).
## They follow the kart they hold (here, not in _tick: the base skips _approach on a proxy's early
## take, the frame its new place on the road comes in before its photo_time, so the blast is where they
## held it, not 12 m on at the road), and the charge starts so that it ends as they zap.
func _approach(kp: Vector3, _delta: float) -> void:
	if not _vis or _taking():
		return
	global_position = _middle(kp)
	if not _charged and kart.state_time >= _beam_at - _charge_len and _shown_any():
		_charged = true
		var p := _play(CHARGE, global_position, -2.0, 1.0, 16.0, true)
		if p:
			p.seek(clampf(kart.state_time - (_beam_at - _charge_len), 0.0, maxf(_charge_len - 0.05, 0.0)))


## The take: they and the kart are gone in a green-yellow blast where it was (this frame its owner
## may already have it on the road, so it is where they last held it).
func _take() -> void:
	if not _vis:
		return
	var c := global_position
	var world := get_parent()
	Effects.sparks(world, c, 2.2, CORE)
	Effects.shock_ring(world, c - _up * MID, _up, 7.0, Color(COL, 0.9), 0.5)
	Effects.flash_light(world, c, CORE, 9.0, 16.0, 0.45)
	_play(DISPEL, c, 3.0, 1.0, 22.0)
	_pop_burst(c, 3.2)
	for v in _vorts:
		if v.shown and not v.gone:
			_vanish(v, false)
	_stop_hum(0.0)
	_look(0.0)
	_beam = 0.0
	_wrap = 0.0
	_draw()


## On the road: they come out of their flashes again beside the kart's new place (a few
## hundredths of a second apart), their beams on the green glow where the kart will show.
func _arrive(kp: Vector3, _far: bool) -> void:
	if not _vis:
		return
	_up = _road_up()
	_out = t
	global_position = kp + _up * (MID + SET)
	var feet := _spots_on_road(kp)
	for n in _vorts.size():
		var v := _vorts[n]
		v.shown = false
		v.gone = false
		v.root.visible = false
		if n < feet.size():
			v.foot = feet[n]
		else:
			v.gone = true
	# (fewer places on the road than where it stopped: the rest stay away)
	for n in range(_vorts.size(), feet.size()):
		var v := _new_vort(feet[n])
		v.gone = n >= VORTS
		_vorts.append(v)
	_look(SET)
	_beam = 1.0
	_wrap = 0.6
	Effects.shock_ring(get_parent(), kp, _up, 5.0, Color(COL, 0.8), 0.5)
	_hum = _play(HUM, global_position, -6.0, 1.05, 14.0, true)
	_crackle(true)
	_draw()


## Let go before the take: the beams die away, they vanish one after the other and the kart's look
## goes back where it belongs.
func _abandon() -> void:
	if not _vis:
		return
	_cut = t
	_look(0.0)
	_stop_hum(HUM_FADE)


func _after_tick(kp: Vector3, delta: float) -> void:
	if not _vis:
		return
	_spin += delta * 3.0
	var kt := kart.state_time
	if _cut >= 0.0:
		var since_cut := t - _cut
		_beam = maxf(_beam - delta / FADE, 0.0)
		_wrap = maxf(_wrap - delta / FADE, 0.0)
		for n in _vorts.size():
			var v := _vorts[n]
			if v.shown and not v.gone:
				v.a = minf(maxf(v.a, RECOVER) + delta, END)
				v.charge = maxf(v.charge - delta / FADE, 0.0)
				if since_cut >= 0.1 + 0.1 * n:
					_vanish(v, true)
	elif _shot < 0.0:
		_before_take(kp, kt, delta)
	elif _out >= 0.0:
		_on_road_tick(kp, delta)
	else:
		return  # taken, not on the road yet: nothing to see
	_crackle_in -= delta
	if _crackle_in <= 0.0:
		_crackle(false)
	_draw()


## Before the take: each comes out of its flash in turn, rears back charging its hands, then all
## of them zap the kart and hold it; a stuck kart's look rises in the beams.
func _before_take(kp: Vector3, kt: float, delta: float) -> void:
	var take := kart.photo_time()
	for n in _vorts.size():
		var v := _vorts[n]
		if not v.shown and not v.gone and t >= APPEAR[mini(n, APPEAR.size() - 1)]:
			_appear(v, kt)
		if not v.shown:
			continue
		if kt < _beam_at:
			# the wind-up, timed so that the zap comes at _beam_at (sped up when there is little time,
			# its ActionIdle held first when there is a lot)
			var rate := clampf((RELEASE - 0.15) / maxf(_beam_at - v.kt0, 0.05), 1.0, 1.6)
			v.a = maxf(RELEASE - (_beam_at - kt) * rate, 0.0)
			v.charge = clampf((kt - v.kt0) / maxf(_beam_at - v.kt0, 0.1), 0.0, 1.0)
		else:
			v.a = _held(RELEASE + (kt - _beam_at))
			v.charge = 1.0
	if not _fired and kt >= _beam_at:
		_fired = true
		_crackle(true)
		_play(SHOOT, global_position, 2.0, 1.0, 20.0)
		Effects.sparks(get_parent(), global_position, 1.2, CORE)
		_hum = _play(HUM, global_position, -4.0, 1.0, 14.0, true)
	var on := smoothstep(_beam_at - 0.04, _beam_at + 0.12, kt)
	_beam = on
	_wrap = on * (0.55 + 0.45 * smoothstep(_beam_at, take, kt))
	if kart.rescue == Kart.Rescue.SCAN:
		var rise := smoothstep(_beam_at, take, kt)
		_look(LIFT * rise + 0.06 * rise * sin(t * 7.0))
	_spin += delta * 6.0 * on


## On the road: the kart shows lifted in their beams, they set it down, lower their hands and go.
func _on_road_tick(kp: Vector3, delta: float) -> void:
	global_position = kp + _up * (MID + _lift)
	var since := t - _shot
	for n in _vorts.size():
		var v := _vorts[n]
		if not v.shown and not v.gone and t - _out >= COME_ROAD[mini(n, COME_ROAD.size() - 1)]:
			_appear(v, kart.state_time)
			v.a = HOLD_A
			v.charge = 1.0
	# set down on its wheels over DOWN once it shows
	var from := maxf(_out, _shot + SHOW)
	var x := clampf((t - from) / DOWN, 0.0, 1.0)
	if t >= from and x < 1.0:
		_look(SET * (1.0 - smoothstep(0.0, 1.0, x)))
	if _down < 0.0:
		if t >= from and not _showed:
			# the kart shows in a puff of the green
			_showed = true
			Effects.sparks(get_parent(), global_position, 1.0, CORE)
		if x >= 1.0:
			_down = t
			_look(0.0)
			_stop_hum(HUM_FADE)
			_play(ZAPS, kp + _up * 0.6, -4.0, 1.0, 14.0)
			_play(VOICE, kp + _up * 1.5, 2.0, 1.0, 14.0)
			Effects.shock_ring(get_parent(), kp, _up, 3.5, Color(CORE, 0.7), 0.4)
		_beam = 1.0
		_wrap = lerpf(0.6, 1.0, x)
	else:
		_beam = maxf(_beam - delta / FADE, 0.0)
		_wrap = maxf(_wrap - delta / FADE, 0.0)
	for n in _vorts.size():
		var v := _vorts[n]
		if not v.shown or v.gone:
			continue
		if _down < 0.0:
			v.a = _held(HOLD_A + (t - _out))
		else:
			v.a = minf(maxf(v.a, RECOVER) + delta, END)
			v.charge = maxf(v.charge - delta / FADE, 0.0)
		if since >= GONE[mini(n, GONE.size() - 1)]:
			_vanish(v, true)


## The zap's time `a` held in its thrust: on into the hold, then to and fro in it.
func _held(a: float) -> float:
	if a <= HOLD_B:
		return a
	return HOLD_B - pingpong(a - HOLD_B, HOLD_B - HOLD_A)


func _shown_any() -> bool:
	for v in _vorts:
		if v.shown:
			return true
	return false


## It steps out of a green flash.
func _appear(v: Vort, kt: float) -> void:
	v.shown = true
	v.kt0 = kt
	v.a = 0.0
	v.charge = 0.0
	v.root.visible = true
	_pop(v.foot, 1.0)
	_play(POPS, v.foot + _up * 1.0, -6.0, 1.1, 12.0)


## It is gone in a green flash (`quiet`: with a crackle of its own; at the take the blast covers it).
func _vanish(v: Vort, quiet: bool) -> void:
	v.gone = true
	v.shown = false
	v.root.visible = false
	_pop(v.foot, 0.8)
	if quiet:
		_play(POPS, v.foot + _up * 1.0, -9.0, 1.2, 10.0)


## The green flash a vortigaunt comes out of or vanishes in, at its foot.
func _pop(foot: Vector3, size: float) -> void:
	var up := _up
	var world := get_parent()
	Effects.sparks(world, foot + up * 1.0, 0.7 * size, COL)
	Effects.shock_ring(world, foot, up, 2.0 * size, Color(COL, 0.8), POP)
	Effects.flash_light(world, foot + up * 1.1, COL, 3.0, 6.0, POP)
	_pop_burst(foot + up * 1.0, 2.6 * size)


## A glow swelling and fading at `at`, `size` metres across at its widest.
func _pop_burst(at: Vector3, size: float) -> void:
	var m := Rescuer.glow_material(Color(CORE, 1.0))
	var q := Rescuer.glow_quad(m)
	get_parent().add_child(q)
	q.global_position = at
	q.scale = Vector3.ONE * size * 0.3
	var tw := q.create_tween().set_parallel(true)
	tw.tween_property(q, "scale", Vector3.ONE * size, POP).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, POP)
	tw.chain().tween_callback(q.queue_free)


func _stop_hum(fade: float) -> void:
	if not is_instance_valid(_hum):
		_hum = null
		return
	var p := _hum
	_hum = null
	if fade <= 0.0:
		p.stop()
		p.queue_free()
		return
	var tw := p.create_tween()
	tw.tween_property(p, "volume_db", -40.0, fade)
	tw.tween_callback(p.queue_free)


## The kart's middle at `kp` (until the take, on the surface of the liquid while it is under it).
func _middle(kp: Vector3) -> Vector3:
	var m := kp + _up * (MID + _lift)
	if kart.rescue == Kart.Rescue.SINK and _shot < 0.0 and kart.liquid.x > -1e8:
		m.y = maxf(m.y, kart.liquid.x - 0.6)
	return m


## The kart's look lifted `h` metres along this rescuer's up, its body where it is; 0 puts it back.
func _look(h: float) -> void:
	if not is_instance_valid(kart) or kart.visual == null:
		return
	_lift = maxf(h, 0.0)
	if h <= 0.001:
		if _vis_on:
			kart.visual.position = _vis_rest
		_vis_on = false
		return
	_vis_on = true
	kart.visual.position = _vis_rest + kart.global_basis.orthonormalized().inverse() * (_up * h)


# ---------------------------------------------------------------- the look
## New jags for every arc, and new places on the kart for the beams to land (`all`: at once,
## else now and then for some of them).
func _crackle(all: bool) -> void:
	_crackle_in = CRACKLE * _rng.randf_range(0.7, 1.3)
	for v in _vorts:
		for n in v.jags.size():
			v.jags[n] = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))
		if all or _rng.randf() < 0.45:
			v.end = Vector3(_rng.randf_range(-0.8, 0.8), _rng.randf_range(-0.3, 0.45), _rng.randf_range(-1.7, 1.7))
	for n in _wrap_jags.size():
		_wrap_jags[n] = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))


## Lays out the vortigaunts (their poses, beams, hands' arcs and glows), the cage of arcs round
## the kart, its glow and the light, as they are now.
func _draw() -> void:
	var mid := global_position
	var kb := kart.global_basis.orthonormalized() if is_instance_valid(kart) else Basis.IDENTITY
	for v in _vorts:
		var on := v.shown and not v.gone
		var b := _beam if on else 0.0
		var ch := v.charge if on else 0.0
		if on:
			var face := mid - v.foot
			face -= _up * face.dot(_up)
			if face.length() < 0.1:
				face = _up.cross(Vector3.RIGHT if absf(_up.x) < 0.9 else Vector3.FORWARD)
			var z := face.normalized()
			v.root.global_transform = Transform3D(Basis(_up.cross(z).normalized(), _up, z), v.foot)
			_pose(v)
		var hands := _hands(v)
		var from := (hands[0] + hands[1]) * 0.5 + v.root.global_basis.z * 0.15
		var to := mid + kb * v.end
		_jagged(v.core, v.glow, from, to, v.jags, 0, 0.35, b, 0.95, 0.55)
		var arc := ch * (1.0 - 0.6 * b)
		_jagged(v.arc_core, v.arc_glow, hands[0], hands[1], v.jags, SEGS, 0.12, arc, 0.9, 0.5)
		for h in 2:
			var hg := v.hand_glows[h]
			hg.visible = on and ch > 0.01
			hg.global_position = hands[h]
			hg.scale = Vector3.ONE * (0.35 + 0.55 * ch + 0.3 * b)
		v.light.global_position = from
		v.light.light_energy = (1.2 * ch + 2.0 * b) if on else 0.0
	_hand_mat.albedo_color.a = 0.85
	# two rings of arcs round the kart's look, turning, crackling
	var w := 1.0 if not is_instance_valid(kart) or kart.spec == null else kart.spec.width * 0.5 + 0.3
	var l := 2.4 if not is_instance_valid(kart) or kart.spec == null else kart.spec.length * 0.5 + 0.25
	for r in 2:
		var h := (-0.3 if r == 0 else 0.35)
		var ph := _spin * (1.0 if r == 0 else -1.3) + float(r)
		var prev := Vector3.ZERO
		for n in WRAP + 1:
			var u := TAU * float(n) / WRAP + ph
			var j := _wrap_jags[(r * WRAP + n) % _wrap_jags.size()] * (0.0 if n == 0 or n == WRAP else 1.0)
			var p := mid + kb * Vector3(cos(u) * (w + 0.15 * j.x), h + 0.12 * j.y + 0.12 * sin(u * 2.0 + _spin), sin(u) * (l + 0.15 * j.x))
			if n > 0:
				var c := _wrap_core[r * WRAP + n - 1]
				var g := _wrap_glow[r * WRAP + n - 1]
				Effects.place_beam(c, prev, p)
				Effects.place_beam(g, prev, p)
				c.visible = _wrap > 0.01
				g.visible = _wrap > 0.01
				c.set_instance_shader_parameter("col", Color(CORE, 0.8 * _wrap))
				g.set_instance_shader_parameter("col", Color(COL, 0.4 * _wrap * (0.75 + 0.25 * sin(t * 37.0 + n))))
			prev = p
	_glow.visible = _wrap > 0.01
	_glow.global_position = mid
	_glow.scale = Vector3.ONE * maxf(2.5 + 3.0 * _wrap, 0.01)
	_glow_mat.albedo_color.a = 0.5 * _wrap * (0.85 + 0.15 * sin(t * 23.0))
	_light.global_position = mid
	_light.light_energy = 4.5 * _wrap


## A jagged arc from a to b drawn with `cores` and `glows` (one piece each), its jags from `jags`
## at `first`, `jitter` metres at most (more on a longer arc), `alpha` bright.
func _jagged(cores: Array[MeshInstance3D], glows: Array[MeshInstance3D], a: Vector3, b: Vector3, jags: PackedVector2Array,
		first: int, jitter: float, alpha: float, core_a: float, glow_a: float) -> void:
	var show := alpha > 0.01
	for n in cores.size():
		cores[n].visible = show
		glows[n].visible = show
	if not show:
		return
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var dn := d / len
	var side := dn.cross(Vector3.UP if absf(dn.y) < 0.95 else Vector3.RIGHT).normalized()
	var up2 := side.cross(dn)
	var amp := jitter * clampf(len / 3.0, 0.6, 1.8)
	var prev := a
	var segs := cores.size()
	for n in segs:
		var u := float(n + 1) / segs
		var p := a + d * u
		if n < segs - 1:
			var j := jags[(first + n) % jags.size()]
			p += (side * j.x + up2 * j.y) * amp * sin(u * PI)
		Effects.place_beam(cores[n], prev, p)
		Effects.place_beam(glows[n], prev, p)
		cores[n].set_instance_shader_parameter("col", Color(CORE, core_a * alpha))
		glows[n].set_instance_shader_parameter("col", Color(COL, glow_a * alpha * (0.8 + 0.2 * sin(t * 41.0 + n))))
		prev = p


## Its two hands (world), from its skeleton; without a model, where they would be.
func _hands(v: Vort) -> Array[Vector3]:
	if v.sk and v.hand_l >= 0 and v.hand_r >= 0 and v.root.visible:
		return [v.sk.global_transform * v.sk.get_bone_global_pose(v.hand_l).origin,
			v.sk.global_transform * v.sk.get_bone_global_pose(v.hand_r).origin]
	var b := v.root.global_basis
	var c := v.foot + _up * (1.0 + 0.25 * v.charge) + b.z * 0.5
	return [c + b.x * 0.25, c - b.x * 0.25]


## Its pose now: its zap at v.a (the animations), or the arms posed like it (BipedPose) on an
## install without them.
func _pose(v: Vort) -> void:
	if v.sk == null:
		return
	if _anims:
		if v.a <= 0.0:
			_anims.pose(v.sk, "idle" if _anims.has("idle") else "zap", t if _anims.has("idle") else 0.0)
		else:
			_anims.pose(v.sk, "zap", v.a, 1.0, AnimSet.CLAMP)
		return
	v.sk.reset_bone_poses()
	BipedPose.standing(v.sk)
	# rear back with the arms spread and the hands up (0.4 to 1.2 s of the zap), thrust forward
	# (its release and hold), then lowered (its recovery)
	var spread := smoothstep(0.3, 1.2, v.a) * (1.0 - smoothstep(RELEASE - 0.15, RELEASE, v.a))
	var thrust := smoothstep(RELEASE - 0.15, RELEASE + 0.05, v.a) * (1.0 - smoothstep(RECOVER, END, v.a))
	if spread + thrust <= 0.01:
		return
	var F := BipedPose.F
	var U := BipedPose.U
	var L := BipedPose.L
	for side in [["L", 1.0], ["R", -1.0]]:
		var sg: float = side[1]
		var ua := (L * sg * 0.75 + U * 0.55 - F * 0.2) * spread + (F * 0.9 + U * 0.2 + L * sg * 0.15) * thrust \
			+ (-U) * (1.0 - spread - thrust)
		var fa := (U * 0.85 + L * sg * 0.3 + F * 0.15) * spread + (F + U * 0.05 - L * sg * 0.15) * thrust \
			+ (-U * 0.9 + F * 0.2) * (1.0 - spread - thrust)
		BipedPose.aim(v.sk, side[0] + "_UpperArm", side[0] + "_Forearm", ua)
		BipedPose.aim(v.sk, side[0] + "_Forearm", side[0] + "_Hand", fa)


## Freed (or the race is gone): the kart's look goes back where it belongs.
func _exit_tree() -> void:
	_look(0.0)
