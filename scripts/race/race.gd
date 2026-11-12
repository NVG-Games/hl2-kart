extends Node3D
## Race scene: builds the track, eight racers, camera, HUD; runs countdown,
## laps, standings, finish and results. Online (Net.active) the grid comes
## from the server, other players' karts are proxies and the server calls
## the start (net_begin) and the results (net_results).

signal standings_changed

const INTRO_TIME := 3.6  # the fly-by before the countdown
const COUNT_TIME := 3.6  # 3-2-1 and GO
## frames drawn behind the loading card before the race shows: the first one compiles the
## circuit's shaders and pipelines (1-2 s on the outdoor maps, more with a cold shader cache),
## the rest look along the intro's fly-by so it does not stutter on what comes into view
const WARMUP_FRAMES := 5

var track: Track
var karts: Array[Kart] = []
var player: Kart
var camera: RaceCamera
var hud: Hud
var racing := false
var _leader: Kart = null  # who led at the last standings (the spectators' "lead" event)
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
var net_t0 := -1.0  # online: the server's clock at GO (the start, the race time and the hazards run on it)
var _net_begun := false  # online: the server has started the race (net_begin)
var _card: CanvasLayer  # the loading card over the first frames (WARMUP_FRAMES)
var _warm := 0


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
	if online:
		# the server's snapshots and events reach the race from now on; it hears the race is ready
		# once its first frames are drawn (_warmed)
		Net.race = self
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
	if online:
		hud.big_text("WAITING FOR PLAYERS", 600.0)
	if DisplayServer.get_name() == "headless":
		_warmed()
	else:
		if not online:
			_phase = "load"
		_card = _loading_card()
	if online and Net.begin_t0 > 0.0:
		net_begin(Net.begin_t0)  # heard before this scene was up


## Black with LOADING... in the corner, as the menu leaves the screen (Menu._go_race).
func _loading_card() -> CanvasLayer:
	var c := CanvasLayer.new()
	c.layer = 50
	add_child(c)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(root)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(black)
	var l := UiKit.label("LOADING...", 28, Color(1, 1, 1, 0.9), true)
	l.anchor_left = 1.0
	l.anchor_right = 1.0
	l.anchor_top = 1.0
	l.anchor_bottom = 1.0
	l.offset_left = -260
	l.offset_top = -80
	root.add_child(l)
	return c


func _process(_delta: float) -> void:
	if _card == null:
		return
	_warm += 1
	if _warm < WARMUP_FRAMES:
		return
	var tw := create_tween()
	tw.tween_property(_card.get_child(0), "modulate:a", 0.0, 0.3)
	tw.tween_callback(_card.queue_free)
	_card = null
	_warmed()


## The first frames are drawn: the race shows and its music starts; offline the intro starts,
## online the server hears this peer is ready (and the start goes on if it was already heard).
func _warmed() -> void:
	Game.play_music_mode("race")
	if not online:
		if _phase == "load":
			_phase = "intro"
		return
	Net.race_ready(self)
	if _net_begun and _phase == "wait":
		_start_intro()


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
		_place_on_grid(k)
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
		# counted and streamed: its viewers react to every hit, one while it spins too
		k.got_hit.connect(func(kk: Kart, _by: Kart) -> void: kk.net_hits += 1)
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


## The server says everyone has loaded: fly-by, then the countdown. `t0` is the server's
## clock as it said so: GO comes INTRO_TIME + COUNT_TIME later on every peer, by that clock,
## so a peer that hears it late (a long load) skips what it missed and starts at once.
func net_begin(t0 := -1.0) -> void:
	if _phase != "wait" or _net_begun:
		return
	_net_begun = true
	if t0 > 0.0:
		net_t0 = t0 + INTRO_TIME + COUNT_TIME
	if _card == null:
		_start_intro()


func _start_intro() -> void:
	_phase = "intro"
	_countdown = 0.0
	if hud:
		hud.big_text("", 0.0)


## Seconds since GO on a clock every peer shares (negative before GO): the track hazards'
## timetables run on it. Online it is the server's clock from the GO it announced; offline,
## and online until this peer's clock has synchronised, it is the race time.
func hazard_clock() -> float:
	if online and net_t0 > 0.0 and Net.clock_synced():
		return Net.now() - net_t0
	match _phase:
		"race", "done":
			return race_time
		"count":
			return _countdown - COUNT_TIME
	return -100.0


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
		"hz":
			if track.hazards:
				track.hazards.net_event(args)
		"branch":
			var kb := kart_by_slot(int(args[0]))
			if kb and kb.remote:
				on_branch(kb, int(args[1]), bool(args[2]))
		"finish":
			var k2 := kart_by_slot(int(args[0]))
			if k2 and k2.remote and not k2.finished:
				k2.finished = true
				k2.finish_time = float(args[1])
				finished_count += 1
				CrowdDirector.notify(get_tree(), &"finish", k2.global_position, k2, null, finished_count)
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
		_place_on_grid(k)
		k.got_hit.connect(_on_kart_hit)
		karts.append(k)
	if player == null:
		player = karts[-1]


## Lap state of a kart on its grid slot (the grid is on the main road, before the line).
func _place_on_grid(k: Kart) -> void:
	k.route = -1
	k.route_index = track.path.closest(k.global_position)
	k.path_index = k.route_index
	k._last_s = track.path.progress(k.global_position, k.route_index)
	k.lap = 0 if k._last_s < track.path.length * 0.5 else -1
	k._crossed_half = k.lap == -1


func _physics_process(delta: float) -> void:
	_bump_karts()
	if _phase == "intro" or _phase == "count":
		_update_standings()
	# online the start and the race time follow the server's clock (seconds from GO, the same on
	# every peer whatever its frame rate or how late it heard the start); offline they count steps
	var shared := online and net_t0 > 0.0 and Net.clock_synced()
	var clock := Net.now() - net_t0 if shared else 0.0
	match _phase:
		"load", "wait":
			# behind the loading card the fly-by is shown from its end back to its start, then it
			# holds its first shot until the intro starts
			if camera:
				camera.intro_t = INTRO_TIME * (1.0 - float(_warm + 1) / WARMUP_FRAMES) if _card else 0.0
		"intro":
			_countdown = clock + INTRO_TIME + COUNT_TIME if shared else _countdown + delta
			if camera and shared:
				camera.intro_t = _countdown
			if _countdown > 0.4 and _countdown < INTRO_TIME and not has_meta("intro_voice") and player:
				set_meta("intro_voice", true)
				player.audio.say("start", true)
			if _countdown > INTRO_TIME or (Input.is_action_just_pressed("use_item") and not online):
				_phase = "count"
				_countdown = clock + COUNT_TIME if shared else 0.0
				if camera:
					camera.mode = RaceCamera.Mode.CHASE
				Game.play_ui("res://assets/sound/npc/overwatch/radiovoice/on1.wav", -2.0)
		"count":
			var prev := _countdown
			_countdown = clock + COUNT_TIME if shared else _countdown + delta
			for i in 3:
				var t := 0.6 + i * 1.0
				if prev < t and _countdown >= t:
					var word: String = ["three", "two", "one"][i]
					Game.play_ui("res://assets/sound/npc/overwatch/radiovoice/%s.wav" % word, 0.0)
					Game.play_ui("res://assets/sound/hl1/fvox/beep.wav", -8.0)
					if hud:
						hud.big_text(str(3 - i), 0.9)
			# rocket start: hold accelerate during the last count
			if _countdown > 2.0 and _countdown < COUNT_TIME:
				if Input.get_action_strength("accelerate") > 0.5 and not input_blocked:
					_rocket_ok = _countdown > 2.75
				else:
					_rocket_ok = false
			if _countdown >= COUNT_TIME:
				_phase = "race"
				racing = true
				race_time = maxf(clock, 0.0) if shared else 0.0
				CrowdDirector.notify(get_tree(), &"start", track.path.center[0])
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
		"race", "done":
			race_time = maxf(clock, 0.0) if shared else race_time + delta
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
	if racing and not sorted.is_empty() and sorted[0] != _leader:
		if _leader != null:
			CrowdDirector.notify(get_tree(), &"lead", (sorted[0] as Kart).global_position, sorted[0], _leader)
		_leader = sorted[0]
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
	if k.lap == laps - 1:
		CrowdDirector.notify(get_tree(), &"final_lap", k.global_position, k)
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
	CrowdDirector.notify(get_tree(), &"finish", k.global_position, k, null, finished_count)
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


## Branch passes per kart: kart -> {branch index: Vector2i(passes, completed)}.
var branch_log := {}


## A kart left branch `b` of the track (Kart._leave_branch); `done`: it got through to the merge.
## A jump or ledge shortcut the player completes without falling off earns a cheer.
func on_branch(k: Kart, b: int, done: bool) -> void:
	var rec: Dictionary = branch_log.get_or_add(k, {})
	rec[b] = rec.get(b, Vector2i.ZERO) + Vector2i(1, 1 if done else 0)
	# online every peer logs the passes as the kart's owner saw them (the SHORTCUTS column)
	if online and not k.remote:
		Net.send_event("branch", [k.net_slot, b, done])
	var br := track.path.branches[b]
	if done and k == player and k.is_player and hud and br.kind in ["jump", "ledge"] \
			and int(k._branch_fails.get(b, 0)) == 0:
		hud.big_text("SHORTCUT!", 1.0)
		Game.play_ui("res://assets/sound/buttons/button9.wav", -6.0)


func _on_kart_hit(k: Kart, by: Kart) -> void:
	CrowdDirector.notify(get_tree(), &"hit", k.global_position, k, by if is_instance_valid(by) else null)
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
