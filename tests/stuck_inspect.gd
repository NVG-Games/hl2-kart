extends Node
## Windowed AI race; when a kart stalls, photograph it from nearby.
## usage: godot --path . res://tests/stuck_inspect.tscn -- <out_prefix> <seconds> <time_scale>

var out := "user://stuck"
var seconds := 120.0
var t := 0.0
var race: Node
var cam: Camera3D
var _slow := {}
var _shot := {}
var _n := 0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0] if a.size() > 0 else out
	seconds = float(a[1]) if a.size() > 1 else seconds
	if a.size() > 2:
		Engine.time_scale = float(a[2])
		Engine.max_physics_steps_per_frame = 32
	Game.settings["demo"] = true
	race = load("res://scenes/race.tscn").instantiate()
	get_tree().root.add_child.call_deferred(race)
	cam = Camera3D.new()
	get_tree().root.add_child.call_deferred(cam)


func _process(delta: float) -> void:
	t += delta
	if t > seconds or Time.get_ticks_msec() > 280000:
		get_tree().quit()
		return
	if race == null or race.get("karts") == null or not race.racing:
		return
	for k in race.karts:
		var key: String = k.character_id
		_slow[key] = (_slow.get(key, 0.0) + delta) if k.speed < 3.0 and k.state == Kart.State.NORMAL else 0.0
		if _slow[key] > 2.5 and not _shot.has(key + str(int(k.total_progress / 50))):
			_shot[key + str(int(k.total_progress / 50))] = true
			_photo(k)
			return


func _photo(k: Kart) -> void:
	var p: Vector3 = k.global_position
	cam.current = true
	cam.look_at_from_position(p + Vector3(0, 22, 0.1) + k.global_basis.z * 4.0, p)
	await get_tree().process_frame
	await get_tree().process_frame
	var path := "%s_%02d_%s_%d.png" % [out, _n, k.character_id, int(k.lap_progress)]
	get_viewport().get_texture().get_image().save_png(path)
	print("stuck photo ", path, " pos ", p, " speed ", k.speed, " steer ", k.in_steer, " thr ", k.in_throttle, " brk ", k.in_brake)
	_n += 1
	race.camera.make_current()
