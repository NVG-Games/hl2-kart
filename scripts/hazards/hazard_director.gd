class_name HazardDirector
extends Node3D
## Spawns a circuit's hazards (data["hazards"]) and drives them with the shared
## hazard clock. It routes their "hz" network events and answers the computer
## drivers (advice) and the scanner (safe_respawn).

## Something a hazard did: "fire", "warn", "hit", "near" (tests and race statistics).
signal noted(h: Hazard, what: String, k: Kart)

## EASY / NORMAL / HARD multiplier per timing key: longer warnings and slower cadence on EASY
const SCALE := {
	"warn": [1.25, 1.0, 0.85], "lock": [1.25, 1.0, 0.85], "charge": [1.2, 1.0, 0.85],
	"period": [1.25, 1.0, 0.85], "cycle": [1.25, 1.0, 0.85], "every": [1.3, 1.0, 0.85],
	"cool": [1.3, 1.0, 0.8], "stale": [1.3, 1.0, 0.85], "rearm": [1.2, 1.0, 0.8], "step": [1.3, 1.0, 0.85],
}
const WAKE_AHEAD := 220.0
const WAKE_BEHIND := 40.0
const WAKE_CAMERA := 260.0
## Hazards whose lap spans lie closer than this form one group (a gauntlet: the checkpoint's
## three turrets, a hall's two ceiling guns), unless their data names a "group" of their own.
const GROUP_GAP := 60.0
## A kart a group's hazard hit is left alone by the whole group until it has driven out of the
## group's stretch: past its end, or this far back before its start.
const GROUP_BACK := 40.0

var track: Track
var race: Node
var list: Array[Hazard] = []
var karts: Array[Kart] = []
var local_karts: Array[Kart] = []
var hits := {}             # hazard id -> hits on karts this peer drives
var groups: Array[Vector2] = []  # lap stretch of each group (x start, y end, may run past the lap length)
var _by_id := {}
var _diff := 1
var _own_t := -3.0         # clock when there is no race (tour, tests)
var _immune := {}          # kart -> the group that hit it on this pass


func setup(trk: Track, defs: Array) -> void:
	track = trk
	name = "Hazards"
	var parent := trk.get_parent()
	race = parent if parent and parent.has_method("hazard_clock") else null
	_diff = clampi(int(Game.race_setting("difficulty")), 0, 2)
	var rule = Game.race_setting("hazards")
	if rule == null or int(rule) != 0:
		for d in defs:
			var cls := script_for(str(d.get("type", "")))
			if cls == null:
				push_warning("unknown hazard type %s" % d.get("type"))
				continue
			var h: Hazard = cls.new()
			add_child(h)
			h.setup(d, trk, self)
			list.append(h)
			_by_id[h.id] = h
	_group()
	set_physics_process(not list.is_empty())


## Puts every hazard in a group (Hazard.group): the ones named alike in their data ("group":
## any string) together, the rest by lap position, one after another while the gap between a
## hazard's span and the group's stretch so far is under GROUP_GAP.
func _group() -> void:
	var L := track.path.length
	var by_s := list.duplicate()
	by_s.sort_custom(func(a: Hazard, b: Hazard) -> bool: return fposmod(a.span.x, L) < fposmod(b.span.x, L))
	var named := {}
	var chain := -1
	for h: Hazard in by_s:
		var a := fposmod(h.span.x, L)
		var b := a + fposmod(h.span.y - h.span.x, L)
		var key := str(h.p.get("group", ""))
		if key != "" and named.has(key):
			h.group = named[key]
		elif key == "" and chain >= 0 and a - groups[chain].y < GROUP_GAP:
			h.group = chain
		else:
			h.group = groups.size()
			groups.append(Vector2(a, b))
			if key != "":
				named[key] = h.group
			else:
				chain = h.group
		groups[h.group].y = maxf(groups[h.group].y, b)


## True while kart k is still in the stretch of h's group after one of its hazards hit it.
func immune(k: Kart, h: Hazard) -> bool:
	return _immune.has(k) and _immune[k] == h.group


## A hazard hit kart k: the rest of its group leaves it alone on this pass.
func on_hit(k: Kart, h: Hazard) -> void:
	_immune[k] = h.group
	note(h, "hit", k)


## Forgets the passes karts have driven out of (forwards past a group's end, or back before it).
func _expire_immunity() -> void:
	for k in _immune.keys():
		var g: Vector2 = groups[_immune[k]]
		if not is_instance_valid(k) or not in_span((k as Kart).lap_progress, g.x - GROUP_BACK, g.y):
			_immune.erase(k)


## The script of a hazard type (data["hazards"][i]["type"]), null for an unknown one.
static func script_for(kind: String) -> GDScript:
	match kind:
		"turret":
			return TurretHazard
		"vortigaunt":
			return VortigauntHazard
		"strider":
			return StriderHazard
		"apache":
			return ApacheHazard
		"train":
			return TrainHazard
		"tripmine":
			return TripmineHazard
		"field_gate":
			return FieldGateHazard
		"strike_zone":
			return StrikeZoneHazard
		"air_strafe":
			return AirStrafeHazard
		"houndeyes":
			return HoundeyeHazard
		"tentacle":
			return TentacleHazard
		"minefield":
			return MinefieldHazard
	return null


func clock() -> float:
	return race.hazard_clock() if race else _own_t


func authority() -> bool:
	return not Net.active or Net.is_server


func scale(key: String) -> float:
	var a: Array = SCALE.get(key, [1.0, 1.0, 1.0])
	return float(a[_diff])


## 0..1 from (seed, a, b) with 31-bit integer steps only: identical on every machine.
static func hash01(sd: int, a: int, b := 0) -> float:
	var h := (sd ^ (a * 73856093) ^ (b * 19349663)) & 0x7fffffff
	for _r in 3:
		h ^= h >> 15
		h = (h * 0x2c1b3c6d + 12345) & 0x7fffffff
	return float(h) / 2147483648.0


func in_span(x: float, a: float, b: float) -> bool:
	var L := track.path.length
	return fposmod(x - a, L) <= fposmod(b - a, L)


func _physics_process(dt: float) -> void:
	if race == null:
		_own_t += dt
	step(clock(), dt)


## One tick of every hazard at clock t (tests drive this with a clock of their own).
func step(t: float, dt: float) -> void:
	karts.assign(get_tree().get_nodes_in_group("karts"))
	local_karts.assign(karts.filter(func(k: Kart) -> bool: return not k.remote))
	_expire_immunity()
	var cam := get_viewport().get_camera_3d() if not Net.dedicated else null
	for h in list:
		var near := _near(h, cam)
		if near != h.awake:
			h.awake = near
			if near:
				h.wake()
			else:
				h.sleep()
		if near:
			h.tick(t, dt)
		h._last_t = maxf(h._last_t, t)


func _near(h: Hazard, cam: Camera3D) -> bool:
	for k in karts if h.aims_all and authority() else local_karts:
		if in_span(k.lap_progress, h.span.x - WAKE_AHEAD, h.span.y + WAKE_BEHIND):
			return true
	return cam != null and cam.global_position.distance_to(h.global_position) < WAKE_CAMERA


func broadcast(h: Hazard, kind: String, args: Array) -> void:
	h.on_event(kind, args)
	if Net.active:
		Net.send_event("hz", [h.id, kind] + args)


## Race.net_event("hz", [id, kind, args...]) from another peer. Malformed events are dropped.
func net_event(args: Array) -> void:
	if args.size() < 2 or not (args[0] is int or args[0] is float) or not args[1] is String:
		return
	for a in args.slice(2):
		if (a is float and not is_finite(a)) or not (a is float or a is int or a is String):
			return
	var h: Hazard = _by_id.get(int(args[0]))
	if h:
		h.on_event(str(args[1]), args.slice(2))


func note(h: Hazard, what: String, k: Kart = null) -> void:
	if what == "hit":
		hits[h.id] = int(hits.get(h.id, 0)) + 1
	noted.emit(h, what, k)


## Network slot of a kart (its index in the race's kart list offline).
func slot_of(k: Kart) -> int:
	return k.net_slot if k.net_slot >= 0 else k.racer_index


func kart_at(slot: int) -> Kart:
	for k in karts:
		if slot_of(k) == slot:
			return k
	return null


## The most urgent steering advice and the lowest speed cap of the hazards ahead. The hazards
## stand on the main loop, so one only advises a kart that will be on the main loop where it
## is: TrackPath.walk along `plan` (the AI's fork decisions) from where the kart is now, so a
## kart on a branch, or turning into one round the hazard, gets nothing from it.
func advice(k: Kart, at_s: float, speed: float, plan := {}) -> Dictionary:
	var out := {"lat": NAN, "w": 0.0, "id": -1, "vmax": INF, "vid": -1}
	var L := track.path.length
	for h in list:
		if not in_span(at_s, h.span.x - 170.0, h.span.y):
			continue
		var to := 0.0 if in_span(at_s, h.span.x, h.span.y) else fposmod(h.span.x - at_s, L)
		if int(track.path.walk(k.route, k.route_pos(), to, plan).x) >= 0:
			continue
		var a: Dictionary = h.advice(k, at_s, speed)
		if a.is_empty():
			continue
		if float(a.get("vmax", INF)) < out["vmax"]:
			out["vmax"] = float(a["vmax"])
			out["vid"] = h.id
		if a.has("lat") and float(a.get("w", 0.5)) > out["w"]:
			out["lat"] = float(a["lat"])
			out["w"] = float(a.get("w", 0.5))
			out["id"] = h.id
	return out


## Where the scanner drops a kart: never inside a train crossing, a gate, a tentacle band...
func safe_respawn(at_s: float) -> float:
	for _pass in 4:
		var moved := false
		for h in list:
			if h.blocks_respawn(at_s):
				at_s = fposmod(h.span.x - 15.0, track.path.length)
				moved = true
		if not moved:
			break
	return at_s


## Every model the hazards spawn mid-race (Hazard.spawns).
func spawns() -> Array:
	var out := []
	for h in list:
		out.append_array(h.spawns())
	return out


func has_type(t: String) -> bool:
	for h in list:
		if h.type == t:
			return true
	return false
