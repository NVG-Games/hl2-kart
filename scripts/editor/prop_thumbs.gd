class_name PropThumbs
extends Node
## Catalog thumbnails (4.1): each model is loaded with ResourceLoader.load_threaded_request (two
## cold load() calls a frame stutter, C1 N23) and, once loaded, rendered in a 128 x 128 SubViewport
## with its own World3D and a transparent background, framed by its AABB from a 30 deg 3/4 view;
## one render per frame, only while the node processes (the catalog drawer is open). Saved to
## user://cache/prop_thumbs/<content>/<key with / -> __>.png and read from there next time.
## Headless: never (no window to render in; `enabled()` is false and nothing is queued). P17.

signal thumb_ready(key: String, tex: Texture2D)

const SIZE := 128
const DIR := "user://cache/prop_thumbs"
const LOADS := 3                # threaded loads in flight at most
const GAP := 3                  # frames between two renders (a big model's first render costs a frame)
const FOV := 30.0
const PITCH := 30.0
const YAW := 35.0

var _cache := {}                # key -> Texture2D
var _failed := {}               # key -> true (no model file, a failed load)
var _queue: Array[String] = []  # waiting for a load slot
var _loading := {}              # key -> resource path
var _loaded: Array = []         # [key, PackedScene] waiting for a render
var _stage := {}                # the render in flight {key, node, frames}
var _gap := 0                   # frames to wait before the next render
var _saves: Array[int] = []     # PNG writes on workers (waited for when they are done)
var _vp: SubViewport
var _cam: Camera3D
var _root: Node3D


func _exit_tree() -> void:
	for id in _saves:
		WorkerThreadPool.wait_for_task_completion(id)
	_saves.clear()


## Thumbnails need a window to render in.
static func enabled() -> bool:
	return DisplayServer.get_name() != "headless"


## The PNG of a key for this content version.
static func file_of(key: String) -> String:
	var g := Engine.get_main_loop() as SceneTree
	var game: Node = g.root.get_node_or_null("Game") if g != null else null
	var ver := int(game.get("content_version")) if game != null else 0
	return "%s/%d/%s.png" % [DIR, ver, key.replace("/", "__")]


## The thumbnail of a model: from memory or the cache folder, else queued (null until
## thumb_ready). Headless: always null, nothing queued.
func get_thumb(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	if not enabled() or _failed.has(key) or key == "":
		return null
	var f := file_of(key)
	if FileAccess.file_exists(f):
		var img := Image.load_from_file(f)
		if img != null and not img.is_empty():
			var tex := ImageTexture.create_from_image(img)
			_cache[key] = tex
			return tex
	if not _loading.has(key) and not (key in _queue) and not _is_loaded(key) and _stage.get("key", "") != key:
		_queue.append(key)
	return null


## Forget what is waiting (a new tab, a new search): renders already loaded stay.
func clear_queue() -> void:
	_queue.clear()


## How many thumbnails wait (queued, loading, loaded or rendering).
func pending() -> int:
	return _queue.size() + _loading.size() + _loaded.size() + (0 if _stage.is_empty() else 1)


func _is_loaded(key: String) -> bool:
	for e in _loaded:
		if e[0] == key:
			return true
	return false


func _process(_delta: float) -> void:
	if not enabled():
		return
	_poll_loads()
	while _loading.size() < LOADS and not _queue.is_empty():
		_start_load(_queue.pop_front())
	while not _saves.is_empty() and WorkerThreadPool.is_task_completed(_saves[0]):
		WorkerThreadPool.wait_for_task_completion(_saves.pop_front())
	if _gap > 0:
		_gap -= 1
	elif _stage.is_empty():
		if not _loaded.is_empty():
			var e: Array = _loaded.pop_front()
			_render(str(e[0]), e[1])
	else:
		_stage.frames = int(_stage.frames) + 1
		if int(_stage.frames) >= 2:
			_finish()


func _start_load(key: String) -> void:
	var info = Game.models.get(key, {})
	var path: String = str(info.get("gltf", "res://assets/models/%s.gltf" % key)) if info is Dictionary else ""
	if path == "" or not ResourceLoader.exists(path):
		_failed[key] = true
		return
	if ResourceLoader.load_threaded_request(path, "", false) != OK:
		_failed[key] = true
		return
	_loading[key] = path


func _poll_loads() -> void:
	for key in _loading.keys():
		var path: String = _loading[key]
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_loading.erase(key)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			var res := ResourceLoader.load_threaded_get(path)
			if res is PackedScene:
				_loaded.append([key, res])
				continue
		_failed[key] = true


func _ensure_viewport() -> void:
	if _vp != null:
		return
	_vp = SubViewport.new()
	_vp.name = "ThumbViewport"
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.light_energy = 1.3
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.current = true
	_vp.add_child(_cam)
	_root = Node3D.new()
	_vp.add_child(_root)


## Puts one model in the viewport, framed by its AABB, and asks for one render.
func _render(key: String, scene: PackedScene) -> void:
	_ensure_viewport()
	var inst := scene.instantiate() as Node3D
	if inst == null:
		_failed[key] = true
		return
	SourceMaterials.apply_to(inst, "", {})
	_root.add_child(inst)
	var box := Game.model_aabb(key)
	var c := box.get_center()
	var radius := maxf(box.size.length() * 0.5, 0.1)
	var dist := radius / sin(deg_to_rad(FOV) * 0.5) * 1.02
	var p := deg_to_rad(PITCH)
	var y := deg_to_rad(YAW)
	var eye := c + Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * dist
	_cam.near = maxf(dist - radius * 1.5, 0.01)
	_cam.far = dist + radius * 2.0
	_cam.global_transform = Transform3D(Basis.looking_at((c - eye).normalized(), Vector3.UP), eye)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_stage = {"key": key, "node": inst, "frames": 0}


## Reads the render back, saves it and hands it out.
func _finish() -> void:
	var key := str(_stage.key)
	var node: Node = _stage.node
	_stage = {}
	var img := _vp.get_texture().get_image()
	if is_instance_valid(node):
		node.queue_free()
	if img == null or img.is_empty():
		_failed[key] = true
		return
	var f := file_of(key)
	DirAccess.make_dir_recursive_absolute(f.get_base_dir())
	# the PNG is encoded and written on a worker (a few ms a picture on the main thread)
	var shot := img.duplicate() as Image
	_saves.append(WorkerThreadPool.add_task(func() -> void: shot.save_png(f), false, "PropThumbs save"))
	_gap = GAP
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	thumb_ready.emit(key, tex)
