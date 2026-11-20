class_name LevelView
extends Node3D
## The editor's live preview world (7.7): the environment and sun (Track.make_environment), the
## road buckets ("Geometry", LevelBuild nodes + Track.dress), the terrain chunks and collision tiles,
## the props, lights, fires and screens of the document (by uid, all static, meta level_uid), the
## item crates and boost pads of the bake, a silent start gantry and the water. P7.
##
## show_build applies a bake as a diff: only the buckets, chunks, tiles and items whose hash or
## signature changed are rebuilt, time-sliced at <= 8 ms per frame (C1 S9). show_roads swaps the
## segment groups of a drag preview at once; update_terrain rebuilds the chunks (and tiles) of a
## rectangle of the live terrain; sync_props adds, moves and removes single document items.

signal applied(revision: int)

## Time-slice budget of show_build per frame.
const SLICE_MS := 8.0
## The document sections shown as nodes by uid.
const NODE_SECTIONS := ["props", "lights", "fires", "screens"]
## Items per job when the crates and pads are rebuilt.
const ITEMS_PER_JOB := 8

var editor: TrackEditor
var doc: LevelDoc                 # the document the props come from (editor.doc)
var build: LevelBuild             # the bake shown (or being applied)
var terrain_live: LevelTerrain    # the live terrain: the shown bake's, carved locally since
var world_env: WorldEnvironment
var env: Environment
var sun: DirectionalLight3D
var gantry: StartGantry
## The crowds' members as stand-ins (capsules of the CROWDS tool's colour), one MultiMesh rebuilt
## when a bake's members change; the race makes the people.
var crowd_mm: MultiMeshInstance3D
## What the last show_build changed (tests, the status line): meshes, removed, chunks, tiles,
## props, env, water, items, gantry, skirt; "preview" counts show_roads' nodes.
var counts := {}

var _env_root: Node3D
var _geo: Node3D
var _terrain_root: Node3D
var _chunks_root: Node3D
var _tiles_root: Node3D
var _props_root: Node3D
var _fx_root: Node3D
var _items_root: Node3D
var _gantry_root: Node3D
var _water_root: Node3D
var _meshes := {}                 # bucket name -> MeshInstance3D
var _chunks := {}                 # chunk name -> MeshInstance3D
var _tiles := {}                  # tile name -> StaticBody3D
var _skirt: MeshInstance3D
var _nodes := {}                  # uid -> Node3D (props, lights, fires, screens)
var _sigs := {}                   # uid -> signature of what its node shows
var _shapeless := {}              # uid -> true: props without a collision shape (picked by their box)
var _parts := {}                  # env / water / items / gantry / skirt / terrain_mat -> signature
var _jobs: Array = []             # [{fn, road, group}]
var _ji := 0
var _terrain_mat: Material
var _shapes := {}                 # Track.prop_node's shape cache
var _mats := {}                   # placeholder materials of one apply
var _hidden := {}


func _ready() -> void:
	_ensure()


func setup(ed: TrackEditor) -> void:
	editor = ed
	if ed != null:
		doc = ed.doc
	_ensure()


## Diff by hash, time-sliced <= 8 ms per frame.
func show_build(b: LevelBuild) -> void:
	if b == null:
		return
	_ensure()
	build = b
	_jobs.clear()
	_ji = 0
	_mats = {}
	counts = {"meshes": 0, "removed": 0, "chunks": 0, "tiles": 0, "props": 0, "env": 0, "water": 0, "items": 0,
		"gantry": 0, "skirt": 0}
	var d: Dictionary = b.data
	var es := hash([str(d.get("sky", "")), d.get("env", {})])
	if _parts.get("env") != es:
		_parts["env"] = es
		_queue(func() -> void: set_env(d))
	var ws := hash([d.get("sea_level", -1000.0), d.get("water", {}), d.get("sea_center", []), d.get("sea_size", 0.0), d.get("waters", [])])
	if _parts.get("water") != ws:
		_parts["water"] = ws
		_queue(func() -> void: _make_water(d))
	# road buckets (a preview node is always replaced by the bake's)
	var want := {}
	if b.meshes != null:
		for e in b.meshes.meshes():
			var nm := str(e.name)
			want[nm] = true
			var cur: MeshInstance3D = _meshes.get(nm)
			if cur != null and is_instance_valid(cur) and not cur.has_meta("preview") \
					and int(cur.get_meta("level_hash", 0)) == int(e.hash):
				continue
			_queue(_job_mesh.bind(e, d), int(e.road), str(e.group))
	for nm in _meshes.keys():
		if not want.has(nm):
			_queue(_drop_mesh.bind(nm, true))
	_diff_terrain(b)
	_diff_nodes()
	var its := hash([d.get("item_boxes", []), d.get("boost_pads", []), _barrels(d), _tunnel_lights(d)])
	if _parts.get("items") != its:
		_parts["items"] = its
		_queue_items(d)
	var cs := hash(d.get("crowds", []))
	if _parts.get("crowd") != cs:
		_parts["crowd"] = cs
		_queue(func() -> void: _make_crowd(d))
	var gs := _gantry_sig(d)
	if _parts.get("gantry") != gs:
		_parts["gantry"] = gs
		_queue(func() -> void: _make_gantry(d))
	var rev := b.revision
	_queue(func() -> void:
		if editor != null and editor.session != null:
			keep_resources(editor.session)
		applied.emit(rev))


## Swap only these road groups (a partial build): at once, without collision (settle adds it).
func show_roads(b: LevelBuild, changed: PackedStringArray) -> void:
	if b == null or b.meshes == null:
		return
	_ensure()
	var key := b.roads[0].key if not b.roads.is_empty() else -1
	var mkey := LevelMeshSet.meta_road(key)
	var groups := {}
	for g in changed:
		groups[g] = true
	# a bake still being applied must not put the old shape of these groups back
	var keep: Array = []
	for k in range(_ji, _jobs.size()):
		var j: Dictionary = _jobs[k]
		if int(j.road) != -9999 and LevelMeshSet.meta_road(int(j.road)) == mkey and groups.has(str(j.group)):
			continue
		keep.append(j)
	_jobs = keep
	_ji = 0
	for nm in _meshes.keys():
		var mi: MeshInstance3D = _meshes[nm]
		if mi == null or not is_instance_valid(mi):
			_meshes.erase(nm)
			continue
		if int(mi.get_meta("level_road", -2)) == mkey and groups.has(str(mi.get_meta("level_group", ""))):
			_drop_mesh(nm, false)
	var made := 0
	var mats := {}
	for e in b.meshes.meshes():
		if not groups.has(str(e.group)):
			continue
		var mi := LevelBuild.mesh_node(e, false, mats)
		mi.set_meta("preview", true)
		_dress_into(mi, {}, _geo)
		_meshes[str(e.name)] = mi
		made += 1
	counts["preview"] = made


func update_terrain(rect: Rect2i, collision: bool, lods := 2) -> void:
	var t := terrain_live
	if t == null or rect.size.x <= 0 or rect.size.y <= 0:
		return
	_ensure()
	_ensure_terrain_mat()
	for c in t.chunks_in(rect):
		update_chunk(c, lods)
	if collision:
		for c in t.tiles_in(rect):
			_make_tile(t, c.x, c.y, t.tile_hash(c.x, c.y))


## One render chunk rebuilt from the live terrain: LOD 0 only while a stroke or a drag runs (lods
## 1, half the work; the far LOD follows at the gesture's end), else both.
func update_chunk(c: Vector2i, lods := 2) -> void:
	var t := terrain_live
	if t == null:
		return
	_ensure()
	_ensure_terrain_mat()
	var h := t.chunk_hash(c.x, c.y)
	for lod in clampi(lods, 1, 2):
		var nm := ("terrain_lod_%d_%d" if lod >= 1 else "terrain_%d_%d") % [c.x, c.y]
		_drop_chunk(nm)
		var mi := t.chunk_node(c.x, c.y, lod)
		if mi == null:
			continue
		mi.set_meta("level_hash", h)
		mi.set_surface_override_material(0, _terrain_mat)
		_chunks_root.add_child(mi)
		_chunks[nm] = mi


## Add / move / remove prop, light, fire, screen nodes.
func sync_props(uids: PackedInt32Array) -> void:
	_ensure()
	for u in uids:
		_sync_one(u)


func set_env(data: Dictionary) -> void:
	_ensure()
	if world_env != null and is_instance_valid(world_env):
		world_env.get_parent().remove_child(world_env)
		world_env.free()
	if sun != null and is_instance_valid(sun):
		sun.get_parent().remove_child(sun)
		sun.free()
	var parts := Track.make_environment(data)
	world_env = parts[0]
	sun = parts[1]
	env = parts[2]
	_env_root.add_child(world_env)
	_env_root.add_child(sun)
	Track.apply_quality_to(env, sun, get_viewport() if is_inside_tree() else null, data)
	counts["env"] = int(counts.get("env", 0)) + 1


func set_hidden(uids: PackedInt32Array) -> void:
	_hidden.clear()
	for u in uids:
		_hidden[u] = true
	for u in _nodes:
		var n: Node3D = _nodes[u]
		if n != null and is_instance_valid(n):
			n.visible = not _hidden.has(u)


func busy() -> bool:
	return _ji < _jobs.size()


# ---------------------------------------------------------------- additions (P7)

## Runs every queued job of show_build now (tests, save, a test drive).
func flush() -> void:
	while _ji < _jobs.size():
		_run_job()


## Gesture end: gives the preview nodes of these groups their collision (3.11 settle).
func collide_groups(road_key: int, changed: PackedStringArray) -> int:
	var mkey := LevelMeshSet.meta_road(road_key)
	var groups := {}
	for g in changed:
		groups[g] = true
	var n := 0
	for nm in _meshes:
		var mi: MeshInstance3D = _meshes[nm]
		if mi == null or not is_instance_valid(mi) or not mi.has_meta("preview") or not mi.has_meta("no_collision"):
			continue
		if int(mi.get_meta("level_road", -2)) != mkey or not groups.has(str(mi.get_meta("level_group", ""))):
			continue
		mi.remove_meta("no_collision")
		_geo.remove_child(mi)
		_dress_into(mi, {}, _geo)
		n += 1
	return n


## The node showing a document item (prop, light, fire, screen), or null.
func node_of(uid: int) -> Node3D:
	var n: Node3D = _nodes.get(uid)
	return n if n != null and is_instance_valid(n) else null


func node_count() -> int:
	return _nodes.size()


## The road bucket nodes by name (tests, the hover strip).
func mesh_nodes() -> Dictionary:
	return _meshes


func chunk_nodes() -> Dictionary:
	return _chunks


func tile_nodes() -> Dictionary:
	return _tiles


## The world box of a document item's node (props: the model's box, scaled and turned; others a
## 2 m box), or an empty AABB.
func item_aabb(uid: int) -> AABB:
	var n := node_of(uid)
	if n == null:
		return AABB()
	if str(n.get_meta("level_section", "")) == "props":
		var box := _model_box(str(n.get_meta("level_model", "")), float(n.get_meta("level_scale", 1.0)))
		return n.global_transform * box if n.is_inside_tree() else n.transform * box
	var p := n.global_position if n.is_inside_tree() else n.position
	return AABB(p - Vector3.ONE, Vector3.ONE * 2.0)


## The nearest prop without a collision shape (grass, far and deco props) under a ray, by its box:
## {uid, pos} or {}.
func pick_shapeless(from: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for u in _shapeless:
		var n := node_of(u)
		if n == null or not n.visible or _hidden.has(u):
			continue
		var xf := n.global_transform if n.is_inside_tree() else n.transform
		var inv := xf.affine_inverse()
		var box := _model_box(str(n.get_meta("level_model", "")), float(n.get_meta("level_scale", 1.0)))
		var hit = box.intersects_ray(inv * from, inv.basis * dir)
		if hit == null:
			continue
		var wp: Vector3 = xf * (hit as Vector3)
		var d := wp.distance_to(from)
		if d < best_d:
			best_d = d
			best = {"uid": u, "pos": wp}
	return best


## Hands the models, materials and textures the view loaded to the session (kept across the test
## drive's scene changes, 1.7). Returns how many it handed over.
func keep_resources(s: EditorSession) -> int:
	if s == null:
		return 0
	var n := 0
	var seen := {}
	for u in _nodes:
		var key := str((_nodes[u] as Node).get_meta("level_model", "")) if is_instance_valid(_nodes[u]) else ""
		if key != "" and not seen.has(key) and Game.models.has(key):
			seen[key] = true
			var sc := Game.model_scene(key)
			if sc != null:
				s.keep(sc)
				n += 1
	for nm in _meshes:
		var mi: MeshInstance3D = _meshes[nm]
		if mi == null or not is_instance_valid(mi) or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i)
			if m != null and not seen.has(m.get_instance_id()):
				seen[m.get_instance_id()] = true
				s.keep(m)
				n += 1
	if _terrain_mat != null:
		s.keep(_terrain_mat)
	return n


# ---------------------------------------------------------------- the time slicer

func _process(_delta: float) -> void:
	if _ji >= _jobs.size():
		return
	var t0 := Time.get_ticks_usec()
	_run_job()   # at least one a frame
	while _ji < _jobs.size() and (Time.get_ticks_usec() - t0) < SLICE_MS * 1000.0:
		_run_job()
	if _ji >= _jobs.size():
		_jobs.clear()
		_ji = 0


func _run_job() -> void:
	var j: Dictionary = _jobs[_ji]
	_ji += 1
	(j.fn as Callable).call()


func _queue(fn: Callable, road := -9999, group := "") -> void:
	_jobs.append({"fn": fn, "road": road, "group": group})


# ---------------------------------------------------------------- jobs

func _job_mesh(e: Dictionary, d: Dictionary) -> void:
	var nm := str(e.name)
	_drop_mesh(nm, false)
	var mi := LevelBuild.mesh_node(e, true, _mats)
	_dress_into(mi, d, _geo)
	_meshes[nm] = mi
	counts["meshes"] = int(counts.get("meshes", 0)) + 1


func _drop_mesh(nm: String, counted: bool) -> void:
	var mi: MeshInstance3D = _meshes.get(nm)
	_meshes.erase(nm)
	if mi != null and is_instance_valid(mi):
		if mi.get_parent() != null:
			mi.get_parent().remove_child(mi)
		mi.queue_free()
		if counted:
			counts["removed"] = int(counts.get("removed", 0)) + 1


## Track.dress for one node (its world materials and, unless meta no_collision, its trimesh body).
func _dress_into(mi: MeshInstance3D, d: Dictionary, parent: Node3D) -> void:
	var holder := Node3D.new()
	holder.add_child(mi)
	Track.dress(holder, d)
	holder.remove_child(mi)
	holder.free()
	parent.add_child(mi)


func _diff_terrain(b: LevelBuild) -> void:
	var t := b.terrain
	terrain_live = t
	var wantc := {}
	var wantt := {}
	if t != null:
		var tl := hash(b.data.get("terrain_layers", {}))
		if _terrain_mat == null or _parts.get("terrain_mat") != tl:
			_parts["terrain_mat"] = tl
			_terrain_mat = Track.terrain_material(b.data)
			for nm in _chunks:
				var mi: MeshInstance3D = _chunks[nm]
				if mi != null and is_instance_valid(mi):
					mi.set_surface_override_material(0, _terrain_mat)
		if not b.chunks.is_empty():
			for c in b.chunks:
				var nm := str(c.name)
				wantc[nm] = true
				var cur: MeshInstance3D = _chunks.get(nm)
				if cur != null and is_instance_valid(cur) and int(cur.get_meta("level_hash", 0)) == int(c.hash):
					continue
				_queue(_job_chunk.bind(b, c))
		else:
			var cc := t.chunk_count()
			for cz in cc:
				for cx in cc:
					var h := t.chunk_hash(cx, cz)
					for lod in 2:
						var nm := ("terrain_lod_%d_%d" if lod >= 1 else "terrain_%d_%d") % [cx, cz]
						wantc[nm] = true
						var cur: MeshInstance3D = _chunks.get(nm)
						if cur != null and is_instance_valid(cur) and int(cur.get_meta("level_hash", 0)) == h:
							continue
						_queue(_job_chunk_live.bind(t, cx, cz, lod, h))
		var tc := t.tile_count()
		for tz in tc:
			for tx in tc:
				var nm := "col_terrain_%d_%d" % [tx, tz]
				wantt[nm] = true
				var h := t.tile_hash(tx, tz)
				var cur: StaticBody3D = _tiles.get(nm)
				if cur != null and is_instance_valid(cur) and int(cur.get_meta("level_hash", 0)) == h:
					continue
				_queue(_make_tile.bind(t, tx, tz, h))
	var ss := hash([t.res, t.cell, str(t.layers.get("base", ""))]) if t != null else 0
	if _parts.get("skirt") != ss:
		_parts["skirt"] = ss
		_queue(_job_skirt.bind(b))
	for nm in _chunks.keys():
		if not wantc.has(nm):
			_queue(_drop_chunk.bind(nm))
	for nm in _tiles.keys():
		if not wantt.has(nm):
			_queue(_drop_tile.bind(nm))


func _ensure_terrain_mat() -> void:
	if _terrain_mat == null:
		_terrain_mat = Track.terrain_material(build.data if build != null else {})


func _job_chunk(b: LevelBuild, c: Dictionary) -> void:
	var nm := str(c.name)
	_drop_chunk(nm)
	var mi := b.chunk_node(c)
	_ensure_terrain_mat()
	mi.set_surface_override_material(0, _terrain_mat)
	_chunks_root.add_child(mi)
	_chunks[nm] = mi
	counts["chunks"] = int(counts.get("chunks", 0)) + 1


func _job_chunk_live(t: LevelTerrain, cx: int, cz: int, lod: int, h: int) -> void:
	var nm := ("terrain_lod_%d_%d" if lod >= 1 else "terrain_%d_%d") % [cx, cz]
	_drop_chunk(nm)
	var mi := t.chunk_node(cx, cz, lod)
	if mi == null:
		return
	_ensure_terrain_mat()
	mi.set_meta("level_hash", h)
	mi.set_surface_override_material(0, _terrain_mat)
	_chunks_root.add_child(mi)
	_chunks[nm] = mi
	counts["chunks"] = int(counts.get("chunks", 0)) + 1


func _drop_chunk(nm: String) -> void:
	var mi: MeshInstance3D = _chunks.get(nm)
	_chunks.erase(nm)
	if mi != null and is_instance_valid(mi):
		mi.get_parent().remove_child(mi)
		mi.queue_free()


func _make_tile(t: LevelTerrain, tx: int, tz: int, h: int) -> void:
	var nm := "col_terrain_%d_%d" % [tx, tz]
	_drop_tile(nm)
	var body := t.tile_body(tx, tz)
	if body == null:
		return
	body.set_meta("level_hash", h)
	_tiles_root.add_child(body)
	_tiles[nm] = body
	counts["tiles"] = int(counts.get("tiles", 0)) + 1


func _drop_tile(nm: String) -> void:
	var body: StaticBody3D = _tiles.get(nm)
	_tiles.erase(nm)
	if body != null and is_instance_valid(body):
		body.get_parent().remove_child(body)
		body.queue_free()


func _job_skirt(b: LevelBuild) -> void:
	if _skirt != null and is_instance_valid(_skirt):
		_skirt.get_parent().remove_child(_skirt)
		_skirt.queue_free()
	_skirt = null
	if b.terrain == null:
		return
	var mi := b.terrain.edge_skirt_node()
	if mi == null:
		return
	_dress_into(mi, b.data, _terrain_root)
	_skirt = mi
	counts["skirt"] = 1


func _make_water(d: Dictionary) -> void:
	for c in _water_root.get_children():
		_water_root.remove_child(c)
		c.queue_free()
	var level := float(d.get("sea_level", -1000.0))
	if d.has("water") or level > -500.0:
		var c = d.get("sea_center", [0.0, 0.0])
		var center := Vector2(float(c[0]), float(c[1])) if c is Array and (c as Array).size() >= 2 else Vector2.ZERO
		var sz := float(d.get("sea_size", 6000.0))
		_water_root.add_child(Track.water_plane(level, center, Vector2(sz, sz)))
	for w in d.get("waters", []):
		if w is Dictionary and w.get("center") is Array and w.get("size") is Array:
			_water_root.add_child(Track.water_plane(float(w.get("level", 0.0)), Vector2(float(w.center[0]), float(w.center[1])),
				Vector2(float(w.size[0]), float(w.size[1]))))
	counts["water"] = int(counts.get("water", 0)) + 1


## The barrel drums the compile put first in data.props (3 per barrel cluster): static here.
func _barrels(d: Dictionary) -> Array:
	var out := []
	for p in d.get("props", []):
		if not (p is Dictionary) or str(p.get("model", "")) != LevelCompiler.BARREL_MODEL or not bool(p.get("physics", false)):
			break
		out.append(p)
	return out


## The lights the compile made for tunnels (first in data.lights, before the document's).
func _tunnel_lights(d: Dictionary) -> Array:
	var all: Array = d.get("lights", []) if d.get("lights") is Array else []
	var own := (doc.data.get("lights", []) as Array).size() if doc != null and doc.data.get("lights") is Array else 0
	return all.slice(0, maxi(all.size() - own, 0))


## The crowd members of a bake (data.crowds) as 0.5 x 1.8 m capsules: unshaded, no collision.
func _make_crowd(d: Dictionary) -> void:
	var list: Array = d.get("crowds", []) if d.get("crowds") is Array else []
	if crowd_mm == null or not is_instance_valid(crowd_mm):
		crowd_mm = MultiMeshInstance3D.new()
		crowd_mm.name = "CrowdStandIns"
		crowd_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var cm := CapsuleMesh.new()
		cm.radius = 0.25
		cm.height = 1.8
		cm.radial_segments = 8
		cm.rings = 2
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = CrowdsTool.GROUP_COLOR
		m.disable_fog = true
		cm.material = m
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = cm
		crowd_mm.multimesh = mm
		_items_root.get_parent().add_child(crowd_mm)
	var mm := crowd_mm.multimesh
	mm.instance_count = list.size()
	for i in list.size():
		var e = list[i]
		var p := _v3(e.get("pos") if e is Dictionary else null)
		var h := 0.6 if e is Dictionary and str(e.get("pose", "")) == "sit" else 0.9
		mm.set_instance_transform(i, Transform3D(Basis(), p + Vector3.UP * h))
	crowd_mm.visible = list.size() > 0
	counts["crowd"] = list.size()


func _queue_items(d: Dictionary) -> void:
	_queue(func() -> void:
		for c in _items_root.get_children():
			_items_root.remove_child(c)
			c.queue_free()
		counts["items"] = int(counts.get("items", 0)) + 1)
	var all := []
	for p in d.get("item_boxes", []):
		all.append(["box", p])
	for p in d.get("boost_pads", []):
		all.append(["pad", p])
	for p in _barrels(d):
		all.append(["drum", p])
	for p in _tunnel_lights(d):
		all.append(["light", p])
	var k := 0
	while k < all.size():
		var part := all.slice(k, k + ITEMS_PER_JOB)
		_queue(func() -> void:
			for e in part:
				_make_item(e[0], e[1]))
		k += ITEMS_PER_JOB


func _make_item(kind: String, p: Variant) -> void:
	match kind:
		"box":
			if not (p is Array) or (p as Array).size() < 3:
				return
			var b := ItemBox.new()
			b.index = _items_root.get_child_count()
			_items_root.add_child(b)
			var pos := Vector3(p[0], p[1], p[2])
			if p.size() >= 6:
				b.global_transform = Transform3D(Track.basis_up(Vector3(p[3], p[4], p[5]).normalized()), pos)
			else:
				b.global_position = pos
		"pad":
			if not (p is Dictionary):
				return
			var pad := BoostPad.new()
			pad.radius = float(p.get("r", 0.0))
			var pos := Vector3(p.pos[0], p.pos[1], p.pos[2])
			var f := Vector3(p.fwd[0], p.fwd[1], p.fwd[2])
			var u := Vector3(p.up[0], p.up[1], p.up[2])
			_items_root.add_child(pad)
			pad.global_transform = Transform3D(Basis(f.cross(u).normalized(), u, -f), pos)
		"light":
			var o := OmniLight3D.new()
			o.position = _v3(p.get("pos"))
			var c = p.get("color", [1.0, 0.9, 0.7])
			o.light_color = Color(float(c[0]), float(c[1]), float(c[2])) if c is Array and (c as Array).size() >= 3 else Color(1, 0.9, 0.7)
			o.omni_range = float(p.get("range", 16.0))
			o.light_energy = float(p.get("energy", 1.6))
			o.shadow_enabled = false
			o.distance_fade_enabled = true
			o.distance_fade_begin = 90.0
			o.distance_fade_length = 40.0
			_items_root.add_child(o)
		"drum":
			var e: Dictionary = (p as Dictionary).duplicate()
			e.erase("physics")
			var n := Track.prop_node(e, -1000.0, _shapes)
			if n != null:
				_items_root.add_child(n)


func _gantry_sig(d: Dictionary) -> int:
	var p = d.get("path")
	if not (p is Dictionary) or (p.get("center", []) as Array).is_empty():
		return 0
	return hash([p.center[0], p.fwd[0], p.width[0], str(d.get("gantry", "combine")), float(d.get("gantry_clear", 0.0))])


## The start arch, silent (no voice lines, no Breencast sound): scenery in the editor.
func _make_gantry(d: Dictionary) -> void:
	if gantry != null and is_instance_valid(gantry):
		gantry.get_parent().remove_child(gantry)
		gantry.queue_free()
	gantry = null
	counts["gantry"] = int(counts.get("gantry", 0)) + 1
	var p = d.get("path")
	if not (p is Dictionary) or (p.get("center", []) as Array).is_empty():
		return
	var c := Vector3(p.center[0][0], p.center[0][1], p.center[0][2])
	var f := Vector3(p.fwd[0][0], p.fwd[0][1], p.fwd[0][2])
	if f.length_squared() < 1e-6:
		return
	gantry = StartGantry.new()
	gantry.silent = true
	_gantry_root.add_child(gantry)
	gantry.setup(Transform3D(Basis.looking_at(f, Vector3.UP), c), float(p.width[0]), str(d.get("gantry", "combine")),
		float(d.get("gantry_clear", 0.0)))


# ---------------------------------------------------------------- document items

func _diff_nodes() -> void:
	if doc == null:
		return
	var want := {}
	for sec in NODE_SECTIONS:
		var list = doc.data.get(sec, [])
		if not (list is Array):
			continue
		for it in list:
			if not (it is Dictionary):
				continue
			var u := int(it.get("uid", 0))
			if u <= 0:
				continue
			want[u] = true
			if _sigs.get(u) == hash([sec, it]):
				continue
			_queue(_job_node.bind(u))
	for u in _sigs.keys():
		if not want.has(u):
			_queue(_job_node.bind(u))


func _job_node(u: int) -> void:
	if _sync_one(u):
		counts["props"] = int(counts.get("props", 0)) + 1


## Brings one uid's node in line with the document; true when something was made or removed.
func _sync_one(u: int) -> bool:
	var f: Dictionary = doc.find(u) if doc != null else {}
	var sec := str(f.get("section", ""))
	if not (sec in NODE_SECTIONS) or not (f.get("item") is Dictionary):
		if _sigs.has(u) or _nodes.has(u):
			_remove_node(u)
			return true
		return false
	var it: Dictionary = f.item
	var sig := hash([sec, it])
	if _sigs.get(u) == sig:
		return false
	_remove_node(u)
	_sigs[u] = sig
	var n := _make_node(sec, it)
	if n == null:
		return true
	n.set_meta("level_uid", u)
	n.set_meta("level_section", sec)
	(_props_root if sec == "props" else _fx_root).add_child(n)
	n.visible = not _hidden.has(u)
	_nodes[u] = n
	if sec == "props" and n.find_children("*", "CollisionShape3D", false, false).is_empty():
		_shapeless[u] = true
	return true


func _remove_node(u: int) -> void:
	var n: Node3D = _nodes.get(u)
	_nodes.erase(u)
	_sigs.erase(u)
	_shapeless.erase(u)
	if n != null and is_instance_valid(n):
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		n.queue_free()


func _make_node(sec: String, it: Dictionary) -> Node3D:
	var pos := _v3(it.get("pos"))
	match sec:
		"props":
			var key := str(it.get("model", ""))
			var e := {"model": key, "pos": [pos.x, pos.y, pos.z], "yaw": deg_to_rad(float(it.get("yaw", 0.0)))}
			var pitch := float(it.get("pitch", 0.0))
			var roll := float(it.get("roll", 0.0))
			if pitch != 0.0:
				e["pitch"] = deg_to_rad(pitch)
			if roll != 0.0:
				e["roll"] = deg_to_rad(roll)
			var sc := snappedf(float(it.get("scale", 1.0)), 0.05)
			if sc > 0.0 and sc != 1.0:
				e["scale"] = sc
			var tag := str(it.get("tag", ""))
			if tag != "":
				e["tag"] = tag
			# all static in the editor (physics props stay put until the race)
			var n := Track.prop_node(e, _sea_y(), _shapes)
			if n != null:
				n.set_meta("level_model", key)
				n.set_meta("level_scale", sc if sc > 0.0 else 1.0)
			return n
		"lights":
			var o := OmniLight3D.new()
			o.position = pos
			var c = it.get("color", [1.0, 0.85, 0.6])
			o.light_color = Color(float(c[0]), float(c[1]), float(c[2])) if c is Array and (c as Array).size() >= 3 else Color(1, 0.85, 0.6)
			o.omni_range = float(it.get("range", 16.0))
			o.light_energy = float(it.get("energy", 1.2))
			o.shadow_enabled = false
			o.distance_fade_enabled = true
			o.distance_fade_begin = 90.0
			o.distance_fade_length = 40.0
			return o
		"fires":
			var root := Node3D.new()
			root.position = pos
			var sz := clampf(float(it.get("size", 1.0)), 0.0, 3.0)
			var flame := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.3 + 0.5 * sz
			sm.height = sm.radius * 2.4
			flame.mesh = sm
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(1.0, 0.45, 0.1, 0.75) if sz > 0.0 else Color(0.3, 0.3, 0.3, 0.6)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			flame.material_override = m
			flame.position = Vector3(0, sm.radius, 0)
			flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(flame)
			if bool(it.get("light", true)) and sz > 0.0:
				var o := OmniLight3D.new()
				o.light_color = Color(1.0, 0.55, 0.2)
				o.omni_range = 6.0 + 4.0 * sz
				o.light_energy = 1.2
				o.position = Vector3(0, 1.0, 0)
				root.add_child(o)
			return root
		"screens":
			var root := Node3D.new()
			root.position = pos
			root.rotation.y = deg_to_rad(float(it.get("yaw", 0.0)))
			var w := float(it.get("w", 8.0))
			var h := float(it.get("h", 4.5))
			var frame := MeshInstance3D.new()
			var fb := BoxMesh.new()
			fb.size = Vector3(w + 0.6, h + 0.6, 0.5)
			frame.mesh = fb
			frame.material_override = SourceMaterials.world_material("metal/citadel_metalwall072a", Vector2(1, 1))
			frame.position = Vector3(0, 0, -0.3)
			root.add_child(frame)
			var scr := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(w, h)
			scr.mesh = q
			if gantry != null and is_instance_valid(gantry) and gantry.feed != null:
				scr.material_override = gantry.feed.screen_material()
			else:
				var sm := StandardMaterial3D.new()
				sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				sm.albedo_color = Color(0.1, 0.25, 0.35)
				scr.material_override = sm
			scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(scr)
			return root
	return null


func _sea_y() -> float:
	if doc == null:
		return -1000.0
	var w = doc.data.get("water", {})
	return float(w.get("level", 0.0)) if w is Dictionary and bool(w.get("sea", false)) else -1000.0


## A model's box in the prop body's frame (the model child is scaled by sc).
func _model_box(key: String, sc := 1.0) -> AABB:
	var box := Game.model_aabb(key)
	if box.size == Vector3.ZERO:
		box = AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	return AABB(box.position * sc, box.size * sc)


static func _v3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


func _ensure() -> void:
	if _geo != null:
		return
	_env_root = _holder("Env")
	_geo = _holder("Geometry")
	_terrain_root = _holder("Terrain")
	_chunks_root = Node3D.new()
	_chunks_root.name = "terrain_chunks"
	_terrain_root.add_child(_chunks_root)
	_tiles_root = Node3D.new()
	_tiles_root.name = "terrain_collision"
	_terrain_root.add_child(_tiles_root)
	_props_root = _holder("Props")
	_items_root = _holder("Items")
	_gantry_root = _holder("Gantry")
	_water_root = _holder("Water")
	_fx_root = _holder("Lights")


func _holder(nm: String) -> Node3D:
	var n := get_node_or_null(nm) as Node3D
	if n == null:
		n = Node3D.new()
		n.name = nm
		add_child(n)
	return n
