class_name KartAudio
extends Node3D
## Engine audio following HL2's vehicle_sounds script (jeep_test.txt):
## per-gear rev one-shots then the cruise loop, throttle-off loops, turbo,
## skids, impacts and the driver's voice. Each vehicle has its own sound set
## (paths relative to assets/sound/).

const V8 := "vehicles/v8/"
const GEAR_SPEEDS := [0.27, 0.5, 0.75, 0.95]
const SETS := {
	"v8": {"gears": [V8 + "first.wav", V8 + "second.wav", V8 + "third.wav"], "cruise": V8 + "fourth_cruise_loop2.wav",
		"idle": V8 + "v8_idle_loop1.wav", "off_fast": V8 + "v8_throttle_off_fast_loop1.wav",
		"off_slow": V8 + "v8_throttle_off_slow_loop2.wav", "turbo": V8 + "v8_turbo_on_loop1.wav",
		"skid": V8 + "skid_normalfriction.wav"},
	"junker": {"gears": ["vehicles/junker/jnk_first.wav", "vehicles/junker/jnk_second.wav", "vehicles/junker/jnk_third.wav"],
		"cruise": "vehicles/junker/jnk_fourth_cruise_loop2.wav", "idle": "vehicles/junker/jnk_idle_loop1.wav",
		"off_fast": "vehicles/junker/jnk_throttle_off_fast_loop1.wav",
		"off_slow": "vehicles/junker/jnk_throttle_off_slow_loop2.wav", "turbo": "vehicles/junker/jnk_turbo_on_loop1.wav",
		"skid": "vehicles/junker/skid_normalfriction_nostartdelay.wav"},
	"apc": {"gears": ["vehicles/apc/apc_firstgear_loop1.wav"], "cruise": "vehicles/apc/apc_cruise_loop3.wav",
		"idle": "vehicles/apc/apc_idle1.wav", "off_fast": "vehicles/apc/apc_slowdown_fast_loop5.wav",
		"off_slow": "vehicles/apc/apc_slowdown_fast_loop5.wav", "turbo": "vehicles/apc/apc_start_loop3.wav",
		"skid": V8 + "skid_highfriction.wav"},
	"dog": {"gears": [], "cruise": "npc/dog/dog_combatmode_loop1.wav", "idle": "npc/dog/dog_idlemode_loop1.wav",
		"off_fast": "npc/dog/dog_combatmode_loop1.wav", "off_slow": "npc/dog/dog_idlemode_loop1.wav",
		"turbo": "npc/dog/dog_playfull1.wav", "skid": V8 + "skid_lowfriction.wav"},
	"tub": {"gears": [], "cruise": "physics/metal/metal_box_scrape_rough_loop1.wav", "idle": "",
		"off_fast": "physics/metal/metal_box_scrape_smooth_loop1.wav",
		"off_slow": "physics/metal/metal_box_scrape_smooth_loop1.wav", "turbo": "items/suitchargeok1.wav",
		"skid": V8 + "skid_highfriction.wav"},
}

var kart: Kart
var engine: AudioStreamPlayer3D
var engine_b: AudioStreamPlayer3D
var skid: AudioStreamPlayer3D
var turbo_p: AudioStreamPlayer3D
var voice: AudioStreamPlayer3D
var snd: Dictionary = SETS["v8"]
var _gear := -1
var _mode := ""
var _voice_cd := 0.0
var _was_air := 0.0
var _impact_cd := 0.0


func setup(k: Kart) -> void:
	kart = k
	name = "Audio"
	if k.spec:
		snd = SETS.get(k.spec.def.get("sound", "v8"), SETS["v8"])
	engine = _player(0.0, 14.0)
	engine_b = _player(-80.0, 14.0)
	skid = _player(-80.0, 10.0)
	skid.stream = Game.stream(snd["skid"])
	turbo_p = _player(0.0, 14.0)
	voice = _player(2.0, 18.0)
	voice.bus = "Voice"
	if not k.is_player:
		engine.unit_size = 9.0
		engine_b.unit_size = 9.0
	_set_loop(engine, snd["idle"], "idle")


func _player(vol: float, unit: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.volume_db = vol
	p.unit_size = unit
	p.max_distance = unit * 30.0
	p.bus = "SFX"
	p.panning_strength = 0.8
	add_child(p)
	return p


func _set_loop(p: AudioStreamPlayer3D, file: String, mode: String) -> void:
	if _mode == mode and p.playing:
		return
	_mode = mode
	if file == "":
		p.stop()
		return
	p.stream = Game.stream(file)
	p.play()


func _process(delta: float) -> void:
	if kart == null:
		return
	_voice_cd -= delta
	_impact_cd -= delta
	var frac := clampf(absf(kart.fwd_speed) / maxf(kart.max_speed, 1.0), 0.0, 1.4)
	var throttle := kart.in_throttle > 0.1 and kart.state == Kart.State.NORMAL
	var g := 0
	for i in GEAR_SPEEDS.size():
		if frac > GEAR_SPEEDS[i]:
			g = i + 1
	g = mini(g, 3)
	if kart.state == Kart.State.RESPAWN:
		engine.volume_db = lerpf(engine.volume_db, -40.0, delta * 3.0)
	elif throttle and frac > 0.04:
		var gears: Array = snd["gears"]
		if g != _gear or (_mode != "gear" and _mode != "cruise"):
			_gear = g
			if g < gears.size():
				_mode = "gear"
				engine.stream = Game.stream(gears[g])
				# start the rev sample part-way in, matching where we are inside the gear
				var lo: float = 0.0 if g == 0 else GEAR_SPEEDS[g - 1]
				var hi: float = GEAR_SPEEDS[g]
				var t := clampf((frac - lo) / maxf(hi - lo, 0.01), 0.0, 0.9)
				var len := engine.stream.get_length() if engine.stream else 1.0
				engine.play(t * len * 0.6)
			else:
				_set_loop(engine, snd["cruise"], "cruise")
		elif _mode == "gear" and not engine.playing:
			_set_loop(engine, snd["cruise"], "cruise")
		engine.pitch_scale = lerpf(engine.pitch_scale, 0.9 + frac * 0.25 + (0.12 if kart.boost_time > 0.0 else 0.0), delta * 4.0)
		engine.volume_db = lerpf(engine.volume_db, 0.0, delta * 6.0)
	else:
		_gear = -1
		if frac > 0.45:
			_set_loop(engine, snd["off_fast"], "off_fast")
		elif frac > 0.08:
			_set_loop(engine, snd["off_slow"], "off_slow")
		else:
			_set_loop(engine, snd["idle"], "idle")
		engine.pitch_scale = lerpf(engine.pitch_scale, 0.95 + frac * 0.2, delta * 3.0)
		engine.volume_db = lerpf(engine.volume_db, -3.0, delta * 4.0)
	# skid while drifting or sliding sideways
	var sliding := kart.drifting and kart.grounded
	if sliding and not skid.playing:
		skid.play()
	skid.volume_db = lerpf(skid.volume_db, -4.0 if sliding else -60.0, delta * 8.0)
	if not sliding and skid.volume_db < -50.0 and skid.playing:
		skid.stop()
	# landing thump (jeep rollover / suspension slam)
	if kart.grounded:
		if _was_air > 0.45:
			Game.play_3d([V8 + "vehicle_rollover1.wav", V8 + "vehicle_rollover2.wav"], global_position, -4.0, 1.0, 10.0)
		_was_air = 0.0
	else:
		_was_air = kart.air_time


func turbo() -> void:
	turbo_p.stream = Game.stream(snd["turbo"])
	turbo_p.volume_db = -2.0
	turbo_p.play()


## Dog's footfalls, called from the gait in KartVisual.
func footstep() -> void:
	Game.play_3d("npc/dog/dog_footstep_run%02d.wav" % (randi() % 9 + 1), global_position,
		-4.0 if kart.is_player else -10.0, randf_range(0.95, 1.05), 9.0)


func hop() -> void:
	pass


func drift_level(lvl: int) -> void:
	if kart.is_player and lvl > 0:
		Game.play_3d("res://assets/sound/buttons/button17.wav" if lvl == 1 else "res://assets/sound/buttons/button14.wav",
			global_position, -6.0, 1.0 + lvl * 0.1, 6.0, self)


func impact(strength: float) -> void:
	if _impact_cd > 0.0:
		return
	_impact_cd = 0.25
	var heavy := strength > 14.0
	var n := randi() % 4 + 1
	Game.play_3d(V8 + ("vehicle_impact_heavy%d.wav" if heavy else "vehicle_impact_medium%d.wav") % n,
		global_position, linear_to_db(clampf(strength / 20.0, 0.3, 1.0)), 1.0, 12.0)


func hurt() -> void:
	Game.play_3d("res://assets/sound/physics/metal/metal_solid_impact_hard4.wav", global_position, 0.0, 1.0, 12.0)
	say("hurt", true)


## Speak a line from the character's set (hit / hurt / win / start).
func say(category: String, force := false) -> void:
	if _voice_cd > 0.0 and not force:
		return
	var line := Game.voice_line(kart.character_id, category)
	if line == "":
		return
	voice.stream = Game.stream(line)
	voice.play()
	_voice_cd = 4.0
