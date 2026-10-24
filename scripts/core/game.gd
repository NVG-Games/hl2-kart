extends Node
## Autoload "Game": settings, roster, Half-Life 2 asset database and audio helpers.

signal settings_changed
signal music_changed(id: String)

const CHARACTERS := [
	{"id": "alyx", "short": "Alyx", "name": "Alyx Vance", "model": "alyx", "color": Color(0.85, 0.35, 0.2), "accel": 1.05, "speed": 0.98, "weight": 0.9},
	{"id": "barney", "short": "Barney", "name": "Barney Calhoun", "model": "barney", "color": Color(0.25, 0.45, 0.85), "accel": 1.0, "speed": 1.0, "weight": 1.0},
	{"id": "kleiner", "short": "Kleiner", "name": "Dr. Kleiner", "model": "kleiner", "color": Color(0.9, 0.9, 0.85), "accel": 1.07, "speed": 0.97, "weight": 0.85},
	{"id": "eli", "short": "Eli", "name": "Eli Vance", "model": "eli", "color": Color(0.35, 0.65, 0.3), "accel": 0.96, "speed": 1.03, "weight": 1.15},
	{"id": "monk", "short": "Grigori", "name": "Father Grigori", "model": "monk", "color": Color(0.15, 0.15, 0.15), "accel": 1.0, "speed": 1.01, "weight": 1.05},
	{"id": "breen", "short": "Breen", "name": "Dr. Breen", "model": "breen", "color": Color(0.55, 0.55, 0.6), "accel": 0.95, "speed": 1.04, "weight": 1.2},
	{"id": "gman_high", "short": "G-Man", "name": "G-Man", "model": "gman_high", "color": Color(0.25, 0.3, 0.45), "accel": 1.02, "speed": 1.01, "weight": 1.0},
	{"id": "police", "short": "Metrocop", "name": "Civil Protection", "model": "police", "color": Color(0.2, 0.55, 0.65), "accel": 1.0, "speed": 1.0, "weight": 1.1},
	{"id": "vortigaunt", "short": "Vortigaunt", "name": "Vortigaunt", "model": "vortigaunt", "color": Color(0.45, 0.6, 0.25), "accel": 1.04, "speed": 0.99, "weight": 0.95},
	{"id": "zombie", "short": "Zombie", "name": "Zombie", "model": "zombie/classic", "color": Color(0.6, 0.1, 0.08), "accel": 0.94, "speed": 1.02, "weight": 1.1},
	{"id": "gordon", "short": "Gordon", "name": "Gordon Freeman", "model": "hl1/gordon", "color": Color(0.95, 0.5, 0.1), "accel": 1.03, "speed": 1.02, "weight": 1.0},
	{"id": "shephard", "short": "Shephard", "name": "Adrian Shephard", "model": "hl1/shephard", "color": Color(0.3, 0.38, 0.22), "accel": 1.01, "speed": 1.01, "weight": 1.05},
]

## Rideable vehicles. Positions are in model space (the model's front is +Z).
## rig: how wheels animate (buggy/apc bones, separate prop wheels, Dog's legs).
## Stats multiply the racer's: speed, accel, weight, handling.
const VEHICLES := [
	{"id": "buggy", "name": "Scout Car", "model": "buggy", "rig": "buggy", "sound": "v8", "scale": 1.0,
		"wheels": "attachments", "radius": [0.457, 0.559], "eyes": "vehicle_driver_eyes", "eye_adjust": Vector3(0, 0.05, 0.08),
		"tint": "models/buggy/buggy001", "speed": 1.0, "accel": 1.0, "weight": 1.0, "handling": 1.0,
		"desc": "The jeep from Highway 17. Balanced in everything."},
	{"id": "jalopy", "name": "Muscle Car", "model": "vehicle", "rig": "buggy", "sound": "junker", "scale": 1.0,
		"wheels": "attachments", "radius": [0.4, 0.5], "eyes": "vehicle_driver_eyes", "eye_adjust": Vector3(0, 0.14, 0.05),
		"speed": 1.04, "accel": 0.93, "weight": 1.08, "handling": 0.94,
		"desc": "Gordon's car from Episode Two. Fast on the straights, wide in the bends."},
	{"id": "apc", "name": "Combine APC", "model": "combine_apc", "rig": "apc", "sound": "apc", "scale": 0.74,
		"wheels": "attachments", "radius": [0.71, 0.71], "eye_pos": Vector3(0.0, 3.45, -0.9),
		"speed": 0.98, "accel": 0.9, "weight": 1.55, "handling": 0.86,
		"desc": "Overwatch armour. Slow to get going, but nothing pushes it around."},
	{"id": "btr", "name": "Military APC", "model": "props_vehicles/apc001", "rig": "props", "sound": "apc", "scale": 0.58,
		"wheel_model": "props_vehicles/apc_tire001", "wheel_scale": 0.62, "radius": [0.5, 0.5],
		"wheel_pos": [Vector3(1.5, 0.0, 3.0), Vector3(-1.5, 0.0, 3.0), Vector3(1.5, 0.0, -2.6), Vector3(-1.5, 0.0, -2.6)],
		"extra_wheels": [Vector3(1.5, 0.0, 1.1), Vector3(-1.5, 0.0, 1.1), Vector3(1.5, 0.0, -0.8), Vector3(-1.5, 0.0, -0.8)],
		"hull_lift": 0.62, "eye_pos": Vector3(0.0, 3.25, -1.2),
		"speed": 0.99, "accel": 0.9, "weight": 1.45, "handling": 0.9,
		"desc": "An abandoned army transport found on the coast road, back on eight wheels."},
	{"id": "dog", "name": "Dog", "model": "dog", "rig": "dog", "sound": "dog", "scale": 0.82,
		"wheels": "virtual", "radius": [0.35, 0.35],
		"wheel_pos": [Vector3(0.55, 0.35, 0.6), Vector3(-0.55, 0.35, 0.6), Vector3(0.55, 0.35, -0.6), Vector3(-0.55, 0.35, -0.6)],
		"speed": 1.02, "accel": 1.08, "weight": 1.3, "handling": 1.06,
		"desc": "Alyx's robot pal carries you on his shoulders. Quick off the line."},
	{"id": "tub", "name": "Bathtub", "model": "props_c17/furniturebathtub001a", "rig": "props", "sound": "tub", "scale": 1.45,
		"yaw": 90.0, "wheel_model": "props_vehicles/carparts_wheel01a", "wheel_scale": 0.71, "radius": [0.3, 0.3],
		"wheel_pos": [Vector3(-0.6, 0.0, 0.42), Vector3(-0.6, 0.0, -0.42), Vector3(0.6, 0.0, 0.42), Vector3(0.6, 0.0, -0.42)],
		"hull_lift": 0.42, "eye_pos": Vector3(0.3, 0.43, 0.0),
		"speed": 0.97, "accel": 1.12, "weight": 0.72, "handling": 1.16,
		"desc": "A clawfoot bathtub on four wheels. Light, twitchy and very, very fast to turn."},
]

## Circuits, all built by the track tools from Half-Life / Half-Life 2 content:
## Highway 17 by tools/build_track.py, the others by tools/track_gen.py.
const TRACKS := [
	{"id": "city17_circuit", "name": "Highway 17", "short": "HIGHWAY 17", "weather": true,
		"desc": "City 17 streets, the Combine checkpoint, the coast road and the canal. Built from HL2 parts."},
	{"id": "ct17", "name": "CT17", "short": "CT17", "weather": false,
		"desc": "Combine-held City 17: the station plaza under the Breencasts, the old town, a checkpoint, the canal jump, the rail yard and an underpass."},
	{"id": "xen", "name": "Xen", "short": "XEN", "weather": false,
		"desc": "Floating islands in the border world: light stalks, crystals, two jumps over the void and a glowing cave."},
	{"id": "black_mesa", "name": "Black Mesa", "short": "BLACK MESA", "weather": false,
		"desc": "Indoors through the Research Facility: Sector C lobby, labs, the tram tunnel, waste processing and a spiral around the Lambda core."},
	{"id": "surface_tension", "name": "Surface Tension", "short": "SURFACE TENSION", "weather": false,
		"desc": "The desert outside Black Mesa: red-rock canyons, cactus, the river gorge bridge, the HECU camp and the dam."},
]

const DIFFICULTIES := [
	{"name": "EASY", "max_speed": 27.0, "ai_skill": 0.82},
	{"name": "NORMAL", "max_speed": 31.0, "ai_skill": 0.92},
	{"name": "HARD", "max_speed": 35.0, "ai_skill": 1.0},
]

const RACE_MUSIC := ["hl2_song12_long", "hl2_song14", "hl2_song16", "hl2_song20_submix0", "hl2_song29",
	"hl2_song31", "hl2_song3", "hl2_song4", "hl2_song15", "vlvx_song27", "vlvx_song28", "vlvx_song22"]
const MENU_MUSIC := ["hl2_song2", "hl2_song25_teleporter", "hl2_song23_suitsong3", "hl2_song1"]

## HL2 skyboxes offered as race "weather" (name shown in the menu).
const SKIES := [
	["sky_day01_01", "CITY 17 OVERCAST"],
	["sky_day01_05", "HIGHWAY 17 DAY"],
	["sky_day02_09", "COASTAL STORM"],
	["sky_day01_08", "DUSK"],
	["sky_day03_06", "EVENING"],
]

const LAYER_WORLD := 1
const LAYER_KART := 2
const LAYER_PROP := 4
const LAYER_ITEM := 8
const LAYER_TRIGGER := 16
const LAYER_KNOCK := 32  # street furniture a kart flattens instead of stopping on

var models := {}
var materials_db := {}
var surfaceprops := {}
var voices := {}
var skies := {}
var settings := {
	"character": "alyx",
	"vehicle": "buggy",
	"difficulty": 1,
	"laps": 3,
	"track": "city17_circuit",
	"sky": "sky_day01_01",
	"master_volume": 1.0,
	"music_volume": 0.7,
	"sfx_volume": 1.0,
	"voice_volume": 1.0,
	"fullscreen": false,
	"vsync": true,
	"quality": 2,
	"race_music": "random",
	"menu_music": "random",
	"show_minimap": true,
	"tutorial_seen": false,
	"check_updates": true,
	# multiplayer
	"nickname": "",
	"master_server": "",
	"favorites": [],
	"history": [],
	"host_name": "",
	"host_port": 27015,
	"host_max_players": 8,
	"host_bots": true,
	"host_grid": 8,
	"host_password": "",
	"host_lan_only": false,
	"host_upnp": true,
}

## Race rules forced by a multiplayer server (laps, difficulty, sky, track);
## empty in single player. Read race rules through race_setting().
var session := {}

## This build (version.json) and the game content it needs (assets/data/build.json,
## written by tools/setup_assets.py).
var version := ""
var content_version := 0
var repo := "NVG-Games/hl2-kart"

var music: AudioStreamPlayer
var music_library: Array = []  # [{id, album, title}] from assets/data/music.json
var now_playing := ""
var _music_mode := ""
var _scenes := {}
var _streams := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var v: Dictionary = load_json("res://version.json")
	version = str(v.get("version", ""))
	content_version = int(v.get("content", 0))
	repo = str(v.get("repo", repo))
	# the Half-Life content (absent until the first-start setup has built it)
	if FileAccess.file_exists("res://assets/data/models.json"):
		models = load_json("res://assets/data/models.json")
		materials_db = load_json("res://assets/data/materials.json")
		surfaceprops = load_json("res://assets/data/surfaceprops.json")
		voices = load_json("res://assets/data/voices.json")
		skies = load_json("res://assets/data/skies.json")
		var ml = load_json("res://assets/data/music.json")
		music_library = ml if ml is Array else []
	_rng.randomize()
	# the bundled Godot is an editor build, which marks the window "(DEBUG)"
	get_tree().create_timer(0.05).timeout.connect(func():
		get_window().title = str(ProjectSettings.get_setting("application/config/name")))
	_setup_buses()
	_load_settings()
	music = AudioStreamPlayer.new()
	music.bus = "Music"
	add_child(music)
	music.finished.connect(_on_music_finished)
	apply_settings()


## The Half-Life content has been built on this machine for this version of the game.
func content_ready() -> bool:
	if not FileAccess.file_exists("res://assets/data/build.json"):
		# built before build.json existed: fine as long as the data is there
		return FileAccess.file_exists("res://assets/data/models.json") and content_version <= 1 \
			and FileAccess.file_exists("res://assets/track/ct17.json")
	var b = load_json("res://assets/data/build.json")
	return b is Dictionary and int(b.get("content", 0)) >= content_version


func load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("missing " + path)
		return {}
	return JSON.parse_string(f.get_as_text())


func track(id: String) -> Dictionary:
	for t in TRACKS:
		if t["id"] == id:
			return t
	return TRACKS[0]


## Menu picture of a track (tools/render_ui_assets), null until it is rendered.
func track_thumb(id: String) -> Texture2D:
	var path := "res://assets/ui/tracks/%s.png" % id
	return load(path) if ResourceLoader.exists(path) else null


## Names of the HL2 skies offered as weather, for dropdowns.
func sky_names() -> Array:
	return SKIES.map(func(k: Array) -> String: return k[1])


func sky_index(id: String) -> int:
	for i in SKIES.size():
		if SKIES[i][0] == id:
			return i
	return 0


func track_index(id: String) -> int:
	for i in TRACKS.size():
		if TRACKS[i]["id"] == id:
			return i
	return 0


func race_setting(key: String) -> Variant:
	return session.get(key, settings.get(key))


func nickname() -> String:
	var n: String = str(settings.get("nickname", "")).strip_edges()
	if n == "":
		n = OS.get_environment("USERNAME").strip_edges()
	return n.left(24) if n != "" else "Player"


func vehicle(id: String) -> Dictionary:
	for v in VEHICLES:
		if v["id"] == id:
			return v
	return VEHICLES[0]


func character(id: String) -> Dictionary:
	for c in CHARACTERS:
		if c["id"] == id:
			return c
	return CHARACTERS[0]


# ---------------------------------------------------------------- models
func model_scene(key: String) -> PackedScene:
	if _scenes.has(key):
		return _scenes[key]
	var info: Dictionary = models.get(key, {})
	var path: String = info.get("gltf", "res://assets/models/%s.gltf" % key)
	var s: PackedScene = load(path) if ResourceLoader.exists(path) else null
	_scenes[key] = s
	return s


## Instance an HL2 model with Source materials. Returns a Node3D (model root).
func spawn_model(key: String, variant := "", skin := 0) -> Node3D:
	var scn := model_scene(key)
	if scn == null:
		push_warning("model not found: " + key)
		return Node3D.new()
	var inst: Node3D = scn.instantiate()
	var skin_map := {}
	if skin > 0:
		var meta: Dictionary = load_json("res://assets/models/%s.json" % key)
		var skins: Array = meta.get("skins", [])
		if skin < skins.size():
			for i in skins[0].size():
				skin_map[skins[0][i]] = skins[skin][i]
	SourceMaterials.apply_to(inst, variant, skin_map)
	return inst


func model_info(key: String) -> Dictionary:
	return models.get(key, {})


func model_aabb(key: String) -> AABB:
	var info := model_info(key)
	if not info.has("aabb_min"):
		return AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	var a := Vector3(info["aabb_min"][0], info["aabb_min"][1], info["aabb_min"][2])
	var b := Vector3(info["aabb_max"][0], info["aabb_max"][1], info["aabb_max"][2])
	return AABB(a, b - a)


# ---------------------------------------------------------------- audio
func _setup_buses() -> void:
	for b in ["Music", "SFX", "Voice", "UI"]:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")


func stream(path: String) -> AudioStream:
	if path == "":
		return null
	if not path.begins_with("res://"):
		path = "res://assets/sound/" + path
	if _streams.has(path):
		return _streams[path]
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_streams[path] = s
	return s


func pick(list: Array) -> Variant:
	if list.is_empty():
		return null
	return list[_rng.randi() % list.size()]


## Fire-and-forget positional sound (Source soundlevel ~ unit_size).
func play_3d(path_or_list, pos: Vector3, volume_db := 0.0, pitch := 1.0, unit_size := 12.0, parent: Node = null) -> AudioStreamPlayer3D:
	var path: String = pick(path_or_list) if path_or_list is Array else path_or_list
	var s := stream(path)
	if s == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch * _rng.randf_range(0.97, 1.03)
	p.unit_size = unit_size
	p.max_distance = unit_size * 25.0
	p.bus = "SFX"
	p.attenuation_filter_cutoff_hz = 9000.0
	var host: Node = parent if parent else get_tree().current_scene
	if host == null:
		return null
	host.add_child(p)
	if parent == null:
		p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)
	return p


func play_ui(path: String, volume_db := 0.0) -> void:
	var s := stream(path)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = volume_db
	p.bus = "UI"
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func music_title(id: String) -> String:
	for m in music_library:
		if m["id"] == id:
			return "%s  ·  %s" % [m["album"], m["title"]]
	return id


## mode: "menu" / "race" use the player's choice in Options (or a random pick
## from the curated pool); "jukebox" walks the whole soundtrack; "once" plays one track.
## Songs a circuit asks for when race music is on "random" (Half-Life 1 for Black Mesa, Xen, the desert).
var race_pool: Array = []


func play_music_mode(mode: String) -> void:
	var choice: String = settings.get(mode + "_music", "random")
	if choice != "random" and choice != "":
		play_track(choice, mode)
	elif mode == "race" and not race_pool.is_empty():
		play_track(pick(race_pool), mode)
	else:
		play_track(pick(RACE_MUSIC if mode == "race" else MENU_MUSIC), mode)


func play_track(id: String, mode := "jukebox") -> void:
	var s := stream("res://assets/sound/music/%s.mp3" % id)
	if s == null:
		return
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = false
	_music_mode = mode
	now_playing = id
	music.stream = s
	music.volume_db = -4.0 if mode != "race" else -6.0
	music.play()
	music_changed.emit(id)


## Next / previous track in the full soundtrack.
func music_skip(dir: int) -> void:
	var idx := 0
	for i in music_library.size():
		if music_library[i]["id"] == now_playing:
			idx = i
	var next: Dictionary = music_library[posmod(idx + dir, music_library.size())]
	play_track(next["id"], "jukebox" if _music_mode != "race" else "race")


func stop_music() -> void:
	_music_mode = ""
	music.stop()
	now_playing = ""
	music_changed.emit("")


func _on_music_finished() -> void:
	match _music_mode:
		"jukebox":
			music_skip(1)
		"menu", "race":
			play_music_mode(_music_mode)
		_:
			now_playing = ""
			music_changed.emit("")


func voice_line(char_id: String, category: String) -> String:
	var v: Dictionary = voices.get(char_id, {})
	var l: Array = v.get(category, [])
	return pick(l) if not l.is_empty() else ""


# ---------------------------------------------------------------- settings
## Test scenes (res://tests/...) keep their own settings file, so running them
## never changes the player's nickname, servers or race choices.
func settings_path() -> String:
	for a in OS.get_cmdline_args():
		if a.begins_with("res://tests/"):
			return "user://settings_test.cfg"
	return "user://settings.cfg"


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path()) == OK:
		for k in settings.keys():
			settings[k] = cfg.get_value("settings", k, settings[k])


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in settings.keys():
		cfg.set_value("settings", k, settings[k])
	cfg.save(settings_path())


func apply_settings() -> void:
	var vol := {"Master": "master_volume", "Music": "music_volume", "SFX": "sfx_volume", "UI": "sfx_volume",
		"Voice": "voice_volume"}
	for bus in vol:
		var i := AudioServer.get_bus_index(bus)
		var v: float = float(settings[vol[bus]])
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)
	if settings["fullscreen"]:
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings["vsync"] else DisplayServer.VSYNC_DISABLED)
	settings_changed.emit()
