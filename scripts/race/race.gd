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
## The editor's TEST DRIVE (Game.test_drive, 5.4): alone on the track or from "here" the kart gets
## GO after QUICK_GO seconds (no 3-2-1); from "here" it is a free drive of FREE_LAPS laps (no
## finish); the trail takes the driven kart's position and speed every TRAIL_DT race seconds.
const QUICK_GO := 1.0
const FREE_LAPS := 99
const TRAIL_DT := 0.2
const TRAIL_MAX := 3000
const FAST_FORWARD := 4.0  # WATCH A BOT LAP while Tab / RT is held
## WATCH A BOT LAP: a bot that gains less than STUCK_M lap metres in STUCK_S race seconds is stuck
const STUCK_S := 15.0
const STUCK_M := 5.0
const WATCH_BACK := 1.5  # seconds from the bot's finish back to the editor
const EDITOR_SCENE := "res://scenes/editor.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"

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
var drive_card: DriveCard  # HOW TO DRIVE, from the first frame to GO (null after, or when turned off)
var _warm := 0
var _phys_frame := -1  # the physics frame of the last _physics_process (a pause leaves a gap)
## The editor's test drive while one runs (a copy of Game.test_drive: {track, laps, bots, hazards,
## difficulty, from, route, s, lat, errors}), else {}. Never online.
var test_drive := {}
## Why the track could not be built ("" = fine): nothing is spawned then (Track.build_failed).
var failed := ""
## WATCH A BOT LAP goes back to the editor after the bot's lap (tests turn it off).
var auto_return := true
var _quick_go := false  # GO after QUICK_GO s, no 3-2-1
var _trail := PackedVector3Array()
var _speeds := PackedFloat32Array()
var _rescue_pos := PackedVector3Array()
var _trail_t := 0.0
var _was_rescued := false
var _time_scale0 := 1.0  # Engine.time_scale when the race began (fast forward goes back to it)
var _fast := false
var _stuck_at := -1.0
var _watch_t := 0.0
var _watch_best := -INF
var _watch_done := false
var _leaving := false


func _ready() -> void:
	online = Net.active and Net.state == "race"
	_time_scale0 = Engine.time_scale
	test_drive = take_test_drive()
	laps = int(Game.race_setting("laps"))
	if is_test_drive():
		laps = FREE_LAPS if test_from() == "here" else (1 if test_from() == "watch" else maxi(laps, 1))
	demo = Game.settings.get("demo", false) and not online
	track = Track.new()
	add_child(track)
	track.build(str(Game.race_setting("track")))
	# a track that could not be built never reaches the karts (a null path): offline back to
	# the menu (a test drive: to the editor), online the server hears why (Net.track_failed)
	if track.build_failed != "" or track.path == null:
		_build_failed(track.build_failed)
		return
	if online:
		_spawn_net_karts()
	else:
		_spawn_karts()
	_countdown = 0.0
	_phase = "wait" if online else "intro"
	if is_test_drive():
		# no fly-by: alone on the track or from "here" GO comes after 1 s, with bots the 3-2-1 runs
		_phase = "count"
		_quick_go = test_from() != "start" or int(test_drive.get("bots", 0)) <= 0
		_countdown = COUNT_TIME - QUICK_GO if _quick_go else 0.0
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
	if is_test_drive():
		camera.mode = RaceCamera.Mode.CHASE
	camera.make_current()
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	if DriveCard.wanted(self) and not is_test_drive():
		drive_card = DriveCard.new()
		add_child(drive_card)
		drive_card.setup(self)
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
	root.add_child(UiKit.loading_word(loading_text()))
	return c


## The loading card's words: "LOADING..." for a circuit, "LOADING... CANAL RUN by <author>" for
## a custom track (5.5).
func loading_text() -> String:
	var id := str(Game.race_setting("track"))
	if not CustomTracks.is_custom(id):
		return "LOADING..."
	var e: Dictionary = Game.track(id)
	var nm := str(e.get("name", "")).strip_edges()
	if nm == "" or bool(e.get("unknown", false)):
		return "LOADING..."
	var by := str(e.get("author", "")).strip_edges()
	return "LOADING... %s%s" % [nm, " by " + by if by != "" else ""]


func _process(_delta: float) -> void:
	if is_test_drive() and not _leaving:
		_fast_forward(test_from() == "watch" and _phase in ["count", "race"] and _ff_held())
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
			_phase = "count" if is_test_drive() else "intro"
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
	if is_test_drive():
		_spawn_test_karts()
		return
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
	var diff: Dictionary = Game.DIFFICULTIES[clampi(int(Game.race_setting("difficulty")), 0, 2)]
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


## A test drive's karts (5.4): `bots` computer drivers on the front of the grid and the player at
## its back (slot 7), or from "here" on the road the editor pointed at; WATCH A BOT LAP: one
## computer driver in the player's character and vehicle and no player kart (the camera on it).
func _spawn_test_karts() -> void:
	var me: String = Game.settings.get("character", "alyx")
	var mine: String = Game.settings.get("vehicle", "buggy")
	var diff: Dictionary = Game.DIFFICULTIES[clampi(int(Game.race_setting("difficulty")), 0, 2)]
	var from := test_from()
	var order: Array = Game.CHARACTERS.map(func(c: Dictionary) -> String: return c["id"])
	order.erase(me)
	order.shuffle()
	var rides: Array = Game.VEHICLES.map(func(v: Dictionary) -> String: return v["id"])
	rides.shuffle()
	var bots := 0 if from == "watch" else clampi(int(test_drive.get("bots", 0)), 0, 7)
	for i in bots:
		var b := _add_kart(str(order[i % order.size()]), i, false, str(rides[i % rides.size()]))
		b.controller = AIController.new(float(diff["ai_skill"]) * randf_range(0.93, 1.03), i * 101 + 7)
	if from == "watch":
		player = _add_kart(me, 0, false, mine)
		player.controller = AIController.new(float(diff["ai_skill"]), 7)
		return
	var human := not demo
	player = _add_kart(me, 7, human, mine)
	if human:
		player.controller = PlayerController.new()
	else:
		player.controller = AIController.new(float(diff["ai_skill"]), 7 * 101 + 7)
	if from == "here":
		_place_here(player)


## One kart on grid slot `slot` with its lap state (_place_on_grid); the caller gives it a driver.
func _add_kart(character: String, slot: int, is_player: bool, ride: String) -> Kart:
	var k := Kart.new()
	add_child(k)
	k.setup(character, slot, track, is_player, ride)
	k.race = self
	k.global_transform = track.spawn_transform(slot)
	k.last_valid = k.global_transform
	k.add_to_group("karts")
	_place_on_grid(k)
	k.got_hit.connect(_on_kart_hit)
	karts.append(k)
	return k


## FROM HERE: the kart on route `route` (-1 the main loop, else a branch) at its metres `s`,
## moved `lat` sideways (+-3 m) and 0.6 m up, facing the road. Its laps are timed from the first
## time it crosses the line (lap -1 until then).
func _place_here(k: Kart) -> void:
	var p := track.path
	var route := int(test_drive.get("route", -1))
	if route >= p.branches.size() or route < -1:
		route = -1
	var g := p.geo(route)
	var s := float(test_drive.get("s", 0.0))
	s = fposmod(s, p.length) if route < 0 else clampf(s, 0.0, maxf(g.length - 1.0, 0.0))
	var xf := g.transform_at(s)
	xf.origin += xf.basis.x * clampf(float(test_drive.get("lat", 0.0)), -3.0, 3.0) + xf.basis.y * 0.6
	k.global_transform = xf
	k.last_valid = xf
	k.route = route
	k.route_index = g.closest(xf.origin)
	if route >= 0:
		var br := p.branches[route]
		k.route_u = br.progress(xf.origin, k.route_index)
		k._branch_entry = k.route_u  # (a pass that did not start at the fork is not credited)
		k._last_s = br.main_s(k.route_u)
		k.path_index = p.index_at(k._last_s)
	else:
		k.path_index = k.route_index
		k._last_s = p.progress(xf.origin, k.route_index)
	k.lap = -1
	k._crossed_half = true
	k.lap_progress = k._last_s
	k.total_progress = k.lap * p.length + k._last_s


func _physics_process(delta: float) -> void:
	if failed != "":
		return
	# back from a pause (physics frames went by without this): the press that closed the pause
	# menu (A, Enter, B) is not a press for the race
	var frame := Engine.get_physics_frames()
	var resumed := _phys_frame >= 0 and frame - _phys_frame > 1
	_phys_frame = frame
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
			# offline the intro skips on confirm (A / Enter, the HUD's prompt) or use item
			if _countdown > INTRO_TIME or (not online and not resumed and (Input.is_action_just_pressed("ui_accept") \
					or Input.is_action_just_pressed("use_item"))):
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
				if prev < t and _countdown >= t and not _quick_go:
					var word: String = ["three", "two", "one"][i]
					Game.play_ui("res://assets/sound/npc/overwatch/radiovoice/%s.wav" % word, 0.0)
					Game.play_ui("res://assets/sound/hl1/fvox/beep.wav", -8.0)
					if hud:
						hud.big_text(str(3 - i), 0.9)
					if player:
						player.rumble(0.15, 0.0, 0.08)
			# rocket start: hold accelerate during the last count
			if _countdown > 2.0 and _countdown < COUNT_TIME:
				if Input.get_action_strength("accelerate") > 0.5 and not input_blocked:
					_rocket_ok = _countdown > 2.75
				else:
					_rocket_ok = false
			if _countdown >= COUNT_TIME:
				_phase = "race"
				racing = true
				if drive_card:
					drive_card.leave()
					drive_card = null
				race_time = maxf(clock, 0.0) if shared else 0.0
				CrowdDirector.notify(get_tree(), &"start", track.path.center[0])
				Game.play_ui("res://assets/sound/npc/overwatch/radiovoice/off4.wav", -2.0)
				Game.play_ui("res://assets/sound/buttons/combine_button7.wav", 0.0)
				if hud:
					hud.big_text("GO!", 1.0)
				if player:
					player.rumble(0.35, 0.35, 0.2)
				for k in karts:
					k._lap_start = 0.0
					if k.remote:
						continue
					if k == player and k.is_player and _rocket_ok:
						k.boost(1.2, 1.0)
						k.rumble(0.5, 0.6, 0.35)
					elif not k.is_player and randf() < 0.6:
						k.boost(0.8, 0.8)
		"race", "done":
			race_time = maxf(clock, 0.0) if shared else race_time + delta
			_update_standings()
			if is_test_drive():
				_record_drive(delta)


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
				var buzz := clampf(-vrel / 12.0, 0.15, 0.5)
				a.rumble(0.2, buzz, 0.1)
				b.rumble(0.2, buzz, 0.1)
			# HEV overcharge flattens whoever it touches, once: a kart it has already sent tumbling is
			# not thrown again on each physics step the two still touch (each throw added its own
			# push, and a kart held against it was flung on at up to 47 m/s, off a rail-less island)
			if a.star_time > 0.0 and b.star_time <= 0.0 and b.state != Kart.State.TUMBLE:
				b.tumble(a, -normal * b.mass * 6.0)
			elif b.star_time > 0.0 and a.star_time <= 0.0 and a.state != Kart.State.TUMBLE:
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
		# a test drive from "here": its first lap is timed from the line
		if k.lap == 0 and test_from() == "here":
			k._lap_start = race_time
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
	if k == player and test_from() == "watch":
		_end_watch()
		return
	if k == player and k.is_player and camera:
		_phase = "done"
		camera.mode = RaceCamera.Mode.ORBIT
		var place := finished_count
		hud.big_text("FINISH!" if place > 1 else "1ST PLACE!", 3.0)
		InputPrompts.rumble(0.6 if place == 1 else 0.4, 0.6 if place == 1 else 0.4, 0.6 if place == 1 else 0.4)
		Game.play_ui("res://assets/sound/friends/friend_join.wav", 0.0)
		k.audio.say("win" if place <= 3 else "hurt", true)
		Game.stop_music()
		Game.play_track("hl2_song23_suitsong3" if place <= 3 else "hl2_song26", "once")
		if not online:
			# (not while paused: the results wait for the pause menu to close)
			get_tree().create_timer(6.0, false).timeout.connect(_show_results)
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
## Falls into a cave per kart (kind "cave": not a shortcut, so kept out of branch_log):
## kart -> {branch index: Vector2i(falls in, drove out)}.
var cave_log := {}


## A kart left branch `b` of the track (Kart._leave_branch); `done`: it got through to the merge.
## A jump or ledge shortcut the player completes without falling off earns a cheer; the player
## driving out of a cave hears of its bonus (Kart.cave_bonus).
func on_branch(k: Kart, b: int, done: bool) -> void:
	var br := track.path.branches[b]
	var cave := br.kind == "cave"
	var rec: Dictionary = (cave_log if cave else branch_log).get_or_add(k, {})
	rec[b] = rec.get(b, Vector2i.ZERO) + Vector2i(1, 1 if done else 0)
	# online every peer logs the passes as the kart's owner saw them (the SHORTCUTS column)
	if online and not k.remote:
		Net.send_event("branch", [k.net_slot, b, done])
	if done and k == player and k.is_player and hud and br.kind in ["jump", "ledge"] \
			and int(k._branch_fails.get(b, 0)) == 0:
		hud.big_text("SHORTCUT!", 1.0)
		Game.play_ui("res://assets/sound/buttons/button9.wav", -6.0)
	if done and cave and k == player and k.is_player and hud:
		hud.big_text("OUT OF THE CAVES!", 1.4)
		Game.play_ui("res://assets/sound/items/suitchargeok1.wav", -4.0)


## The player's kart fell into a cave (Kart._set_route): the way out lies ahead, down there.
func on_cave(k: Kart, _b: int) -> void:
	if k == player and k.is_player and hud and racing:
		hud.big_text("ANTLION CAVES: DRIVE OUT!", 1.6)
		# (the cave's own growl is in the newer content; the older has the rumble)
		var growl := "ambient/levels/caves/dist_growl1.wav"
		Game.play_ui("res://assets/sound/" + (growl if Game.stream(growl) else "ambient/atmosphere/cave_hit1.wav"), -6.0)


func _on_kart_hit(k: Kart, by: Kart) -> void:
	CrowdDirector.notify(get_tree(), &"hit", k.global_position, k, by if is_instance_valid(by) else null)
	if by and is_instance_valid(by) and by != k:
		by.audio.say("hit")


## RESTART (RACE AGAIN; a test drive's RESTART HERE / DRIVE AGAIN: Game.test_drive is kept).
func restart() -> void:
	if online:
		return
	InputPrompts.stop_rumble()
	get_tree().paused = false
	_fast_forward(false)
	get_tree().reload_current_scene()


func to_menu() -> void:
	if _leaving:
		return
	_leaving = true
	InputPrompts.stop_rumble()
	get_tree().paused = false
	Game.stop_music()
	_fast_forward(false)
	Game.test_drive = {}
	if online:
		Net.leave()
	get_tree().change_scene_to_file(MAIN_SCENE)


## Back to the editor from a test drive (F5, BACK TO EDITOR, X on a pad in the pause menu, the
## results, the end of a bot's lap): the drive's report goes to EditorSession.last_drive
## (the editor toasts it and draws the trail), Game.test_drive is cleared.
func to_editor() -> void:
	if _leaving:
		return
	_leaving = true
	InputPrompts.stop_rumble()
	get_tree().paused = false
	Game.stop_music()
	_fast_forward(false)
	Engine.time_scale = _time_scale0
	EditorSession.current().last_drive = _test_drive_report()
	Game.test_drive = {}
	get_tree().change_scene_to_file(EDITOR_SCENE)


## The editor's test drive for this race: Game.test_drive, or {} (cleared) whenever Net is
## active, so an editor drive never reaches an online race (C1 S19).
static func take_test_drive() -> Dictionary:
	if Net.active:
		Game.test_drive = {}
		return {}
	var td = Game.test_drive
	return (td as Dictionary).duplicate(true) if td is Dictionary else {}


func is_test_drive() -> bool:
	return not test_drive.is_empty()


## "start" | "here" | "watch" during a test drive, else "".
func test_from() -> String:
	return str(test_drive.get("from", "start")) if is_test_drive() else ""


## A free drive: no lap count, no finish (a test drive from "here").
func free_drive() -> bool:
	return is_test_drive() and laps >= FREE_LAPS


## The compiler's validation errors the test drive runs with (HUD: "TEST DRIVE · 2 ERRORS").
func test_errors() -> int:
	return int(test_drive.get("errors", 0)) if is_test_drive() else 0


## WATCH A BOT LAP is playing at FAST_FORWARD.
func fast_forward() -> bool:
	return _fast


## What the test drive did (EditorSession.last_drive, 5.4): laps, times, rescues and where, the
## trail of the driven kart (the bot's when watching) at 5 Hz with its speeds.
func _test_drive_report() -> Dictionary:
	var k := player
	var times: Array = []
	var best := 0.0
	if k:
		for x in k.lap_times:
			times.append(x)
			if best <= 0.0 or x < best:
				best = x
	return {"from": test_from(), "laps_done": times.size(), "best_lap": best, "lap_times": times,
		"rescues": k.respawns if k else 0, "rescue_pos": _rescue_pos.duplicate(), "finished": k != null and k.finished,
		"stuck_at_s": _stuck_at, "trail": _trail.duplicate(), "speeds": _speeds.duplicate(),
		"errors": test_errors(), "failed": failed}


## The trail (TRAIL_DT, at most TRAIL_MAX points), the rescues' places and, watching a bot, whether
## it is stuck (STUCK_M lap metres in STUCK_S seconds).
func _record_drive(delta: float) -> void:
	var k := player
	if k == null or k.finished or _leaving:
		return
	var rescued := k.state == Kart.State.RESPAWN
	if rescued and not _was_rescued:
		_rescue_pos.append(k.global_position)
	_was_rescued = rescued
	_trail_t += delta
	if _trail_t >= TRAIL_DT and _trail.size() < TRAIL_MAX:
		_trail_t = fmod(_trail_t, TRAIL_DT)
		_trail.append(k.global_position)
		_speeds.append(absf(k.speed))
	if test_from() != "watch" or _watch_done:
		return
	if k.total_progress > _watch_best + STUCK_M:
		_watch_best = k.total_progress
		_watch_t = 0.0
		return
	_watch_t += delta
	if _watch_t > STUCK_S:
		_stuck_at = maxf(k.lap_progress, 0.0)
		_end_watch()


## The watched bot finished its lap (or got stuck): back to the editor shortly.
func _end_watch() -> void:
	if _watch_done:
		return
	_watch_done = true
	if hud:
		hud.big_text("BOT LAP" if _stuck_at < 0.0 else "STUCK", 1.2)
	if auto_return:
		get_tree().create_timer(WATCH_BACK, false).timeout.connect(to_editor)


## Tab or RT is held (WATCH A BOT LAP's FAST FORWARD).
static func _ff_held() -> bool:
	if Input.is_physical_key_pressed(KEY_TAB):
		return true
	for d in Input.get_connected_joypads():
		if Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT) > 0.5:
			return true
	return false


func _fast_forward(on: bool) -> void:
	if on == _fast:
		return
	_fast = on
	Engine.time_scale = _time_scale0 * FAST_FORWARD if on else _time_scale0


## The track could not be built: nothing is spawned. Online the server hears why
## (Net.track_failed: back to the lobby, never a stop); offline a test drive goes back to the
## editor with the reason, a race to the menu with a message.
func _build_failed(reason: String) -> void:
	failed = reason if reason != "" else "The track could not be built."
	_phase = "failed"
	racing = false
	if Net.active:
		Net.track_failed.call_deferred(failed)
		return
	if is_test_drive():
		to_editor.call_deferred()
		return
	if DisplayServer.get_name() == "headless":
		to_menu.call_deferred()
		return
	var c := CanvasLayer.new()
	c.layer = 60
	add_child(c)
	var root := Control.new()
	root.theme = UiKit.theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(root)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(black)
	var m := MessageBox.new("TRACK NOT READY", failed)
	root.add_child(m)
	m.closed.connect(to_menu)


func _exit_tree() -> void:
	if _fast:
		Engine.time_scale = _time_scale0
	InputPrompts.stop_rumble()
