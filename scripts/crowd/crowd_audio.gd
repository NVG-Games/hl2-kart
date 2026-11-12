class_name CrowdAudio
extends Node3D
## The spectators' voices on a strict budget: three pooled one-shot players, two
## murmur beds following the nearest big groups and two players for the birds.
## Lines come only from near the camera, never back to back, and never over the
## local racer's own voice (which they also duck under when it starts) unless it is an
## easter egg about that racer and the racer's line is a long speech; an easter egg
## wins over an event, an event over a cheer.

enum Prio { IDLE, PASS, EVENT, EGG }

const GAP := 0.9  # seconds between two lines
const RANGE := 45.0  # metres from the camera a line may come from
const VOICE_DB := -3.0
const DUCK := -12.0  # the spectators' voices drop this much while the player's racer talks
## an easter egg about the player's racer waits for the racer's own line only when that ends within
## this many seconds; under a longer one (Breen's Breencasts run 15-48 s) it starts at once, ducked
const RACER_WAIT := 1.5
const BED_LOW := -18.0
const BED_HIGH := -8.0
## voices.json "_crowd" files refugees' and rebels' lines under "citizen" (the same HL2 citizen voices)
const VOICE_ROLE := {"refugee": "citizen", "rebel": "citizen"}

var director: CrowdDirector
var voices: Array[AudioStreamPlayer3D] = []
var beds: Array[AudioStreamPlayer3D] = []
var flap: AudioStreamPlayer3D
var calls: AudioStreamPlayer3D
## why the last line was refused (the director's trace): far, gap, racer, busy, none
var refused := ""
var _rank := [0, 0, 0]  # per voice player: its line's priority, doubled, +1 if about the player
var _last := 0  # the voice player of the latest line
var _bed_key := ["", ""]
var _bed_at: Array = [null, null]  # the group each bed follows
var _quiet_until := 0.0
var _warm: Array[String] = []


func setup(d: CrowdDirector, roles: Array) -> void:
	director = d
	name = "CrowdAudio"
	# the duck below comes before anything else this frame (a racer's line started in the physics
	# step is under it at once)
	process_priority = -1
	for i in 3:
		voices.append(_player("Voice", VOICE_DB, 12.0, 140.0))
	for i in 2:
		var b := _player("SFX", -60.0, 18.0, 160.0)
		b.finished.connect(b.play)  # beds without loop points loop by hand
		beds.append(b)
	flap = _player("SFX", -6.0, 10.0, 90.0)
	flap.finished.connect(flap.play)
	calls = _player("SFX", -4.0, 10.0, 90.0)
	# the first line of a role must not hitch: load its files a few per frame now
	var all: Dictionary = Game.voices.get("_crowd", {})
	var keys := {"beds": true, "birds": true}
	for r in roles:
		keys[voice_role(r)] = true
	for r in keys:
		for cat in all.get(r, {}):
			for p in all[r][cat]:
				_warm.append(str(p))


## The voices.json "_crowd" role whose lines spectators of `role` speak.
static func voice_role(role: Variant) -> String:
	return VOICE_ROLE.get(String(role), String(role))


## Spectators of `role` have lines of `category` (some roles have none: Combine soldiers, the
## cameos; some installs lack Episode Two's).
static func can_say(role: StringName, category: String) -> bool:
	if category == "":
		return false
	var c: Dictionary = Game.voices.get("_crowd", {}).get(voice_role(role), {})
	return not (c.get(category, []) as Array).is_empty()


func _player(bus: String, db: float, unit: float, dist: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = bus
	p.volume_db = db
	p.unit_size = unit
	p.max_distance = dist
	p.attenuation_filter_cutoff_hz = 9000.0
	add_child(p)
	return p


func _process(delta: float) -> void:
	for i in mini(4, _warm.size()):
		Game.stream(_warm.pop_back())
	var me := director.me()
	var talking := me != null and me.audio != null and me.audio.voice.playing
	# down at once when the racer starts talking (a long frame must not leave them on top), back up gently
	for p in voices:
		p.volume_db = VOICE_DB + DUCK if talking else move_toward(p.volume_db, VOICE_DB, delta * 24.0)


## Say a line of `category` for spectators of `role` at `pos`. Returns the file played or
## "" when the budget says no: too far, too soon, the racer is talking, every player busy
## with something as important. `mine`: about the local player's kart (they must hear it).
func say(pos: Vector3, role: StringName, category: String, prio: int, mine := false) -> String:
	var path := Game.crowd_line(voice_role(role), category)
	if path == "":
		_refuse("none")
		return ""
	return path if say_path(pos, path, prio, mine) else ""


## Seconds the line `v` plays still has to run (0 when it is quiet).
static func left(v: AudioStreamPlayer3D) -> float:
	return v.stream.get_length() - v.get_playback_position() if v.playing and v.stream else 0.0


## A line refused, and `why` (kept for the director's trace).
func _refuse(why: String) -> bool:
	refused = why
	return false


## The same budget for one exact file (the n-th "pick up that can").
func say_path(pos: Vector3, path: String, prio: int, mine := false) -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_to(pos) > RANGE:
		return _refuse("far")
	var now := CrowdActor.now()
	# a line about the player outranks the same about anyone else
	var rank := prio * 2 + (1 if mine else 0)
	# inside the gap only an easter egg about the player may come, cutting off the line just
	# begun if that one matters less (two lines never start together)
	var cut := now < _quiet_until
	if cut and not (mine and prio >= Prio.EGG and rank > _rank[_last]):
		return _refuse("gap")
	var me := director.me()
	var talking := me != null and me.audio != null and me.audio.voice.playing
	if talking and not (mine and prio >= Prio.EGG and left(me.audio.voice) > RACER_WAIT):
		return _refuse("racer")
	var slot := _last if cut else -1
	if slot < 0:
		for i in voices.size():
			if not voices[i].playing:
				slot = i
				break
	if slot < 0:
		if not mine:
			return _refuse("busy")
		var low := 0
		for i in voices.size():
			if _rank[i] < _rank[low]:
				low = i
		if _rank[low] >= rank:
			return _refuse("busy")
		slot = low
	var s := Game.stream(path)
	if s == null:
		return _refuse("none")
	refused = ""
	var p := voices[slot]
	p.stream = s
	p.global_position = pos
	p.pitch_scale = randf_range(0.95, 1.05)
	p.volume_db = VOICE_DB + (DUCK if talking else 0.0)
	p.play()
	_rank[slot] = rank
	_last = slot
	_quiet_until = now + GAP
	return true


## A sound that is not a voice (stun baton sparks) through the same budget.
func sfx(path: String, pos: Vector3, db := -6.0) -> void:
	var cam := get_viewport().get_camera_3d()
	if path == "" or cam == null or cam.global_position.distance_to(pos) > RANGE:
		return
	# under this node (gone with the crowds) but where it happens
	var p := Game.play_3d(path, pos, db, 1.0, 8.0, self)
	if p:
		p.global_position = pos


## Murmur beds on the two nearest hot or warm groups of 12 or more with a bed; louder
## with their excitement. `bed_of` gives a group's bed key now (Breen passing: riot).
func update_beds(near: Array, bed_of: Callable, excite_of: Callable) -> void:
	for slot in 2:
		var b := beds[slot]
		var g = near[slot] if slot < near.size() else null
		var key: String = bed_of.call(g) if g != null else ""
		if g == null or key == "":
			b.volume_db = move_toward(b.volume_db, -60.0, 3.0)
			if b.volume_db <= -59.0 and b.playing:
				b.stop()
			_bed_at[slot] = null
			_bed_key[slot] = ""
			continue
		if key != _bed_key[slot]:
			var path := Game.crowd_line("beds", key)
			if path == "":
				continue
			b.stream = Game.stream(path)
			b.volume_db = -40.0
			b.play()
			_bed_key[slot] = key
		_bed_at[slot] = g
		b.global_position = g.center
		var want := lerpf(BED_LOW, BED_HIGH, clampf(excite_of.call(g), 0.0, 1.0))
		b.volume_db = move_toward(b.volume_db, want, 2.0)


## Birds: a call from `species` at `pos`, and the flapping loop while a flock flies.
func bird_call(species: String, pos: Vector3) -> void:
	var path := Game.crowd_line("birds", species)
	if path == "" or calls.playing:
		return
	calls.stream = Game.stream(path)
	calls.global_position = pos
	calls.pitch_scale = randf_range(0.9, 1.1)
	calls.play()


func flapping(pos: Vector3, on: bool) -> void:
	if not on:
		flap.stop()
		return
	flap.global_position = pos
	if not flap.playing:
		var path := Game.crowd_line("birds", "flap")
		if path != "":
			flap.stream = Game.stream(path)
			flap.play()
