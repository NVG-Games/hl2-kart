extends Node3D
## Race scene: builds the track, eight racers, camera, HUD; runs countdown,
## laps, standings, finish and results. Online (Net.active) the grid comes
## from the server, other players' karts are proxies and the server calls
## the start (net_begin) and the results (net_results).

signal standings_changed


var track: Track
var karts: Array[Kart] = []
var player: Kart
var camera: RaceCamera
var hud: Hud
var racing := false
var finished_count := 0
var race_time := 0.0
var laps := 3
var _countdown := 0.0
var _phase := "intro"
var _final_lap_announced := false
var _rocket_window := false
var _rocket_ok := false
var _results_shown := false
var demo := false  # attract mode: all karts AI
var online := false
var input_blocked := false  # online: pause menu / chat open (the race goes on)


func _ready() -> void:
	PlayerController.setup_input_map()
	online = Net.active and Net.state == "race"
	laps = int(Game.race_setting("laps"))
	demo = Game.settings.get("demo", false) and not online
	track = Track.new()
	add_child(track)
	track.build(str(Game.race_setting("track")))
	if online:
		_spawn_net_karts()
	else:
		_spawn_karts()
	_countdown = 0.0
	_phase = "wait" if online else "intro"
	if Net.dedicated:
		Net.race_ready(self)
		return
	camera = RaceCamera.new()
	add_child(camera)
	camera.target = player
	camera.make_current()
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	Game.race_pool = track.data.get("music", [])
	Game.play_music_mode("race")
	if online:
		hud.big_text("WAITING FOR PLAYERS", 30.0)
		Net.race_ready(self)


## Online grid: my kart, the server's bots, everyone else as proxies.
func _spawn_net_karts() -> void:
	for e in Net.grid:
		var slot := int(e["slot"])
		var mine: bool = not e["bot"] and int(e["peer"]) == Net.my_id()
		var k := Kart.new()
		add_child(k)
		k.setup(e["character"], slot, track, mine, e["vehicle"])
		k.net_slot = slot
		k.nick = e["nick"]
		k.is_bot = e["bot"]
		k.race = self
		k.global_transform = track.spawn_transform(slot)
		k.last_valid = k.global_transform
		k.add_to_group("karts")
		k._last_s = track.path.progress(k.global_position, track.path.closest(k.global_position))
		k.lap = 0 if k._last_s < track.path.length * 0.5 else -1
		k._crossed_half = k.lap == -1
		k.total_progress = k.lap * track.path.length + k._last_s
		if mine:
			k.controller = AIController.new(0.95, 7) if Net.autodrive else PlayerController.new()
			player = k
		elif e["bot"] and Net.is_server:
			k.controller = AIController.new(float(e["skill"]), slot * 101 + 7)
		else:
			k.make_remote()
			if not e["bot"]:
				_add_name_tag(k)
		k.got_hit.connect(_on_kart_hit)
		karts.append(k)
	if player == null and not karts.is_empty():
		player = karts[0]


func _add_name_tag(k: Kart) -> void:
	var l := Label3D.new()
	l.text = k.nick
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font_size = 28
	l.outline_size = 8
	l.modulate = Hl2Style.BRIGHT
	l.no_depth_test = true
	l.position = Vector3(0, k.spec.height + 0.9, 0)
	l.name = "NameTag"
	k.add_child(l)


func kart_by_slot(slot: int) -> Kart:
	return karts[slot] if slot >= 0 and slot < karts.size() else null


## The server says everyone has loaded: fly-by, then the countdown.
func net_begin() -> void:
	if _phase != "wait":
		return
	_phase = "intro"
	_countdown = 0.0
	if hud:
		hud.big_text("", 0.0)


## Something happened on another peer (see Net.send_event).
func net_event(kind: String, args: Array) -> void:
	match kind:
		"item":
			var k := kart_by_slot(int(args[0]))
			if k and k.remote:
				Items.use_remote(k, str(args[1]), args[2], args[4])
		"box":
			var i := int(args[0])
			if i >= 0 and i < track.item_boxes.size():
				track.item_boxes[i].net_smash()
		"trap":
			Items.net_remove(get_tree(), str(args[0]), true)
		"proj":
			Items.net_remove(get_tree(), str(args[0]))
		"finish":
			var k2 := kart_by_slot(int(args[0]))
			if k2 and k2.remote and not k2.finished:
				k2.finished = true
				k2.finish_time = float(args[1])
				finished_count += 1
		"bot":
			var k3 := kart_by_slot(int(args[0]))
			if k3 == null:
				return
			k3.is_bot = true
			if k3.has_node("NameTag"):
				(k3.get_node("NameTag") as Label3D).text = "%s (BOT)" % k3.nick
			if Net.is_server and k3.remote:
				var diff: Dictionary = Game.DIFFICULTIES[clampi(int(Game.race_setting("difficulty")), 0, 2)]
				k3.make_local_bot(float(diff["ai_skill"]))


## Final order from the server: show it until everyone goes back to the lobby.
func net_results(order: Array, seconds: float) -> void:
	_results_shown = true
	if hud:
		hud.show_net_results(order, seconds)


func _spawn_karts() -> void:
	var me: String = Game.settings.get("character", "alyx")
	var order: Array = Game.CHARACTERS.map(func(c: Dictionary) -> String: return c["id"])
	order.erase(me)
	order.shuffle()
	# AI rivals get a spread of vehicles, one of each before any repeats
	var rides: Array = []
	while rides.size() < 7:
		var batch: Array = Game.VEHICLES.map(func(v: Dictionary) -> String: return v["id"])
		batch.shuffle()
		rides.append_array(batch)
	# player starts at the back of the grid like Mario Kart's 150cc
	var roster: Array = order.slice(0, 7)
	roster.append(me)
	var diff: Dictionary = Game.DIFFICULTIES[clampi(Game.settings["difficulty"], 0, 2)]
	for i in roster.size():
		var k := Kart.new()
		add_child(k)
		var is_player: bool = roster[i] == me and not demo
		var ride: String = Game.settings.get("vehicle", "buggy") if roster[i] == me else rides[i]
		k.setup(roster[i], i, track, is_player, ride)
		k.race = self
		k.global_transform = track.spawn_transform(i)
		k.last_valid = k.global_transform
		k.add_to_group("karts")
		if is_player:
			k.controller = PlayerController.new()
			player = k
		else:
			var sk: float = diff["ai_skill"] * randf_range(0.93, 1.03)
			k.controller = AIController.new(sk, i * 101 + 7)
		k._last_s = track.path.progress(k.global_position, track.path.closest(k.global_position))
		k.lap = 0 if k._last_s < track.path.length * 0.5 else -1
		k._crossed_half = k.lap == -1
		k.got_hit.connect(_on_kart_hit)
		karts.append(k)
	if player == null:
		player = karts[-1]


func _physics_process(delta: float) -> void:
	_bump_karts()
	if _phase == "intro" or _phase == "count":
		_update_standings()
	match _phase:
		"wait":
			pass
		"intro":
			_countdown += delta
			if _countdown > 0.4 and not has_meta("intro_voice") and player:
				set_meta("intro_voice", true)
				player.audio.say("start", true)
			if _countdown > 3.6 or (Input.is_action_just_pressed("use_item") and not online):
				_phase = "count"
				_countdown = 0.0
				if camera:
					camera.mode = RaceCamera.Mode.CHASE
				Game.play_ui("res://assets/sound/npc/overwatch/radiovoice/on1.wav", -2.0)
		"count":
			var prev := _countdown
			_countdown += delta
			for i in 3:
				var t := 0.6 + i * 1.0
				if prev < t and _countdown >= t:
					var word: String = ["three", "two", "one"][i]
					Game.play_ui("res://assets/sound/npc/overwatch/radiovoice/%s.wav" % word, 0.0)
					Game.play_ui("res://assets/sound/hl1/fvox/beep.wav", -8.0)
					if hud:
						hud.big_text(str(3 - i), 0.9)
			# rocket start: hold accelerate during the last count
			if _countdown > 2.0 and _countdown < 3.6:
				if Input.get_action_strength("accelerate") > 0.5 and not input_blocked:
					_rocket_ok = _countdown > 2.75
				else:
					_rocket_ok = false
			if _countdown >= 3.6:
				_phase = "race"
				racing = true
				race_time = 0.0
				Game.play_ui("res://assets/sound/npc/overwatch/radiovoice/off4.wav", -2.0)
				Game.play_ui("res://assets/sound/buttons/combine_button7.wav", 0.0)
				if hud:
					hud.big_text("GO!", 1.0)
				for k in karts:
					k._lap_start = 0.0
					if k.remote:
						continue
					if k == player and k.is_player and _rocket_ok:
						k.boost(1.2, 1.0)
					elif not k.is_player and randf() < 0.6:
						k.boost(0.8, 0.8)
		"race":
			race_time += delta
			_update_standings()
		"done":
			race_time += delta
			_update_standings()


## Kart-vs-kart contact is a soft, momentum-sharing bump on the ground plane
## (kart racer style) instead of a rigid-body crash: no spin-outs, no dead stops.
## Each kart is two circles (front/back) sized from its vehicle, in plan view.
var _bump_cd := {}


func _bump_karts() -> void:
	var n := karts.size()
	for i in n:
		var a := karts[i]
		if a.state == Kart.State.RESPAWN:
			continue
		for j in range(i + 1, n):
			var b := karts[j]
			if b.state == Kart.State.RESPAWN:
				continue
			var pa := a.global_position
			var pb := b.global_position
			if absf(pa.y - pb.y) > 1.8 or Vector2(pa.x - pb.x, pa.z - pb.z).length() > 6.0:
				continue
			var best := 0.0
			var normal := Vector3.ZERO
			var fa := -a.global_basis.z
			var fb := -b.global_basis.z
			var oa := a.spec.bump_off
			var ob := b.spec.bump_off
			for sa: float in [-oa, oa]:
				var ca := pa + fa * sa
				for sb: float in [-ob, ob]:
					var cb := pb + fb * sb
					var d := Vector3(ca.x - cb.x, 0.0, ca.z - cb.z)
					var overlap := a.spec.bump_r + b.spec.bump_r - d.length()
					if overlap > best:
						best = overlap
						normal = d.normalized() if d.length() > 0.01 else a.global_basis.x
			if best <= 0.0:
				continue
			if a.remote and b.remote:
				continue
			var mu := a.mass * b.mass / (a.mass + b.mass)
			var vrel := (a.velocity() - b.velocity()).dot(normal)
			var imp := 0.0
			if vrel < 0.0:
				imp = -vrel * 1.15 * mu
			# push apart smoothly (positional correction as velocity)
			imp += mu * minf(best * 5.0, 3.0)
			imp = minf(imp, mu * 7.0)
			# each peer pushes only the karts it drives; the other side does the same
			if not a.remote:
				a.apply_central_impulse(normal * imp)
			if not b.remote:
				b.apply_central_impulse(-normal * imp)
			var key := "%d_%d" % [i, j]
			if -vrel > 3.0 and Time.get_ticks_msec() > int(_bump_cd.get(key, 0)):
				_bump_cd[key] = Time.get_ticks_msec() + 400
				a.audio.impact(-vrel * 1.5)
			# HEV overcharge flattens whoever it touches
			if a.star_time > 0.0 and b.star_time <= 0.0:
				b.tumble(a, -normal * b.mass * 6.0)
			elif b.star_time > 0.0 and a.star_time <= 0.0:
				a.tumble(b, normal * a.mass * 6.0)


func _update_standings() -> void:
	var sorted := karts.duplicate()
	sorted.sort_custom(func(a: Kart, b: Kart) -> bool:
		if a.finished != b.finished:
			return a.finished
		if a.finished and b.finished:
			return a.finish_time < b.finish_time
		return a.total_progress > b.total_progress)
	for i in sorted.size():
		(sorted[i] as Kart).place = i + 1
	standings_changed.emit()


func on_lap(k: Kart) -> void:
	if not racing and _phase != "done":
		return
	if k.lap <= 0:
		return
	var lap_time := race_time - k._lap_start
	k._lap_start = race_time
	k.lap_times.append(lap_time)
	if k.lap >= laps:
		_finish(k)
		return
	if k == player and hud:
		if k.lap == laps - 1:
			hud.big_text("FINAL LAP", 2.0)
			Game.play_ui("res://assets/sound/ambient/alarms/warningbell1.wav", -4.0)
			Game.play_ui("res://assets/sound/npc/overwatch/radiovoice/attention.wav", -2.0)
		else:
			hud.big_text("LAP %d/%d" % [k.lap + 1, laps], 1.5)
			Game.play_ui("res://assets/sound/buttons/button9.wav", -4.0)


func _finish(k: Kart) -> void:
	if k.finished:
		return
	k.finished = true
	k.finish_time = race_time
	finished_count += 1
	k.state = Kart.State.FINISHED
	if online:
		Net.send_event("finish", [k.net_slot, k.finish_time])
	if k.controller is PlayerController:
		k.controller = AIController.new(0.8, 99)
	if k == player and k.is_player and camera:
		_phase = "done"
		camera.mode = RaceCamera.Mode.ORBIT
		var place := finished_count
		hud.big_text("FINISH!" if place > 1 else "1ST PLACE!", 3.0)
		Game.play_ui("res://assets/sound/friends/friend_join.wav", 0.0)
		k.audio.say("win" if place <= 3 else "hurt", true)
		Game.stop_music()
		Game.play_track("hl2_song23_suitsong3" if place <= 3 else "hl2_song26", "once")
		if not online:
			get_tree().create_timer(6.0).timeout.connect(_show_results)
	if finished_count == karts.size() and not online:
		_show_results()


func _show_results() -> void:
	if _results_shown:
		return
	_results_shown = true
	# finish everyone still racing by projected order
	_update_standings()
	hud.show_results(karts)


func _on_kart_hit(k: Kart, by: Kart) -> void:
	if by and is_instance_valid(by) and by != k:
		by.audio.say("hit")


func restart() -> void:
	if online:
		return
	get_tree().paused = false
	get_tree().reload_current_scene()


func to_menu() -> void:
	get_tree().paused = false
	Game.stop_music()
	if online:
		Net.leave()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
