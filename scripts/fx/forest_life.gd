class_name ForestLife
extends Node
## The forest's own sounds on a track whose background is "forest" (White Forest): the wind in the
## pines all the time, and now and then a distant bird or a woodpecker somewhere round the camera.
## Built on a player's machine only, never on the dedicated server or in a headless run. A sound the
## player's content lacks (the forest's sounds came with phase D's content) just stays silent.

const WIND := ["ambient/levels/forest/treewind1.wav", "ambient/levels/forest/treewind2.wav"]
const BIRDS := ["ambient/levels/forest/dist_birds1.wav", "ambient/levels/forest/dist_birds2.wav",
	"ambient/levels/forest/dist_birds3.wav", "ambient/levels/forest/peckr1.wav"]
## seconds between two bird calls (a random wait in this range)
const BIRD_GAP := Vector2(6.0, 15.0)

var _wind: AudioStreamPlayer
var _winds: Array[AudioStream] = []
var _birds: Array[String] = []
var _next := 0
var _bird_t := 4.0


## The forest's sounds for a track with the "forest" background, or null (any other track, a BSP
## map, the dedicated server, a headless run).
static func spawn_for(trk: Track) -> ForestLife:
	if trk.is_bsp or Net.dedicated or DisplayServer.get_name() == "headless":
		return null
	if str(trk.data.get("background", "")) != "forest":
		return null
	var f := ForestLife.new()
	f.name = "ForestLife"
	trk.add_child(f)
	f.setup()
	return f


func setup() -> void:
	for p in WIND:
		var s := Game.stream(p)
		if s:
			_winds.append(s)
	for p in BIRDS:
		if Game.stream(p):
			_birds.append(p)
	# the wind: one recording after the other, all race long (neither loops by itself)
	_wind = AudioStreamPlayer.new()
	_wind.bus = "SFX"
	_wind.volume_db = -15.0
	add_child(_wind)
	_wind.finished.connect(_play_wind)
	_play_wind()


func _play_wind() -> void:
	if _winds.is_empty():
		return
	_wind.stream = _winds[_next % _winds.size()]
	_next += 1
	_wind.play()


func _process(delta: float) -> void:
	if _birds.is_empty():
		return
	_bird_t -= delta
	if _bird_t > 0.0:
		return
	_bird_t = randf_range(BIRD_GAP.x, BIRD_GAP.y)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# up in the trees 25-60 m off, any way round the camera
	var a := randf() * TAU
	var r := randf_range(25.0, 60.0)
	var at := cam.global_position + Vector3(cos(a) * r, randf_range(6.0, 16.0), sin(a) * r)
	Game.play_3d(_birds[randi() % _birds.size()], at, -9.0, randf_range(0.93, 1.07), 40.0)
