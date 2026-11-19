class_name LevelBuild
extends RefCounted
## A compile's result: the runtime data dict, mesh buckets, terrain, roads, report, legal-spot
## flags, stats and the document revision it came from; instantiate() makes the nodes. P4.
##
## Everything but instantiate() is plain data, made on a worker thread and read-only after the
## compile. The digest (3.1) covers the gameplay keys only, so peers with different content agree.

## The parts of digest() in order: 8 hex of each part's sha256.
const PARTS := ["path", "branches", "grid", "item_boxes", "boost_pads", "hazards", "low_gravity", "kill_y", "offtrack"]
## Keys whose numbers are unit vectors (4 decimals in the digest); every other float gets 3.
const UNIT_KEYS := ["fwd", "right", "up", "dir", "axis"]
## The hazard entry keys the digest covers.
const HAZARD_KEYS := ["id", "type", "s", "span", "seed", "pos"]

var id := ""
var revision := -1              # the doc revision it was compiled from
var data := {}
var meta := {}                  # {id, name, short, desc, author, rescue, guid, length, branches, props, hazards, raceable, errors, warnings}
var meshes: LevelMeshSet
var terrain: LevelTerrain
var roads: Array[LevelRoad] = []
var report: LevelReport
var flags := {}                 # "branch_fork" / "branch_merge" / "hz_<type>" -> PackedByteArray per exported main sample
var stats := {}                 # compile_ms, samples, triangles, props, lights, people, heavy, crates, groups (preview)
var partial := false            # a preview build (roads + the changed groups only)

# ---------------------------------------------------------------- additions (P4)

## The terrain's render chunks made on the worker: [{name, cx, cz, lod, hash, arrays}] (LOD0 and
## LOD1 of every non-empty chunk); empty when the compile skipped them (opts.chunks false), then
## instantiate() makes them itself.
var chunks: Array = []
## The world edge skirt's arrays (made with the chunks), [] for none.
var skirt: Array = []
## The resolved styles of the compile (id -> full style dict).
var styles := {}

var _parts := {}


## Main thread: MeshInstance3D per bucket (+ meta level_road, level_group), terrain chunks (meta
## no_collision, no_shadow on LOD1) and "terrain_collision" tiles; groups limits to those road groups.
## collision false: no tiles and every bucket gets meta no_collision (Track.dress then makes no
## trimesh body for it). With groups only those groups' buckets are made (no terrain).
func instantiate(collision := true, groups := PackedStringArray()) -> Node3D:
	var root := Node3D.new()
	root.name = "Level"
	var want := {}
	for g in groups:
		want[g] = true
	var mats := {}
	if meshes != null:
		for e in meshes.meshes():
			if not want.is_empty() and not want.has(str(e.group)):
				continue
			root.add_child(mesh_node(e, collision, mats))
	if not want.is_empty() or terrain == null:
		return root
	var tn := Node3D.new()
	tn.name = "terrain_chunks"
	root.add_child(tn)
	if chunks.is_empty():
		var cc := terrain.chunk_count()
		for cz in cc:
			for cx in cc:
				for lod in 2:
					var mi := terrain.chunk_node(cx, cz, lod)
					if mi != null:
						tn.add_child(mi)
	else:
		for c in chunks:
			tn.add_child(chunk_node(c))
	var sk: MeshInstance3D = null
	if skirt.is_empty():
		sk = terrain.edge_skirt_node()
	else:
		sk = _skirt_node()
	if sk != null:
		root.add_child(sk)
	if collision:
		var col := Node3D.new()
		col.name = "terrain_collision"
		root.add_child(col)
		var tc := terrain.tile_count()
		for tz in tc:
			for tx in tc:
				var body := terrain.tile_body(tx, tz)
				if body != null:
					col.add_child(body)
	return root


## 72 hex: 8 per part (3.1).
func digest() -> String:
	var parts := digest_parts()
	var out := ""
	for k in PARTS:
		out += str(parts.get(k, "")).left(8)
	return out


## {part: sha256 hex} over the gameplay keys only, each serialised with sorted keys after rounding
## (3 decimals, 4 for unit vectors); hazards keep only id, type, s, span, seed, pos.
func digest_parts() -> Dictionary:
	if not _parts.is_empty():
		return _parts
	var out := {}
	for k in PARTS:
		var v = data.get(k)
		if k == "hazards":
			var hs := []
			for h in (v if v is Array else []):
				if not (h is Dictionary):
					continue
				var e := {}
				for hk in HAZARD_KEYS:
					if h.has(hk):
						e[hk] = h[hk]
				hs.append(e)
			v = hs
		out[k] = JSON.stringify(canon(v), "", true).sha256_text()
	_parts = out
	return out


## {raceable, errors, warnings, length, branches, props, hazards}: what the cache index stores.
func facts() -> Dictionary:
	var rep := report if report != null else LevelReport.new()
	var p = data.get("path")
	return {"raceable": rep.raceable() and p is Dictionary, "errors": rep.errors(), "warnings": rep.warnings(),
		"length": snappedf(float(p.get("length", 0.0)), 0.1) if p is Dictionary else 0.0,
		"branches": (data.get("branches", []) as Array).size(), "props": (data.get("props", []) as Array).size(),
		"hazards": (data.get("hazards", []) as Array).size()}


# ---------------------------------------------------------------- additions (P4)

## A value with every float rounded as exported: 3 decimals, 4 under a unit-vector key; ints and
## whole floats stay as they are, dictionaries keep their keys (JSON sorts them).
static func canon(v: Variant, key := "") -> Variant:
	if v is float:
		var q := 0.0001 if key in UNIT_KEYS else 0.001
		var r := snappedf(v, q)
		return 0.0 if r == 0.0 else r     # -0.0 and 0.0 serialise alike
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = canon(v[k], str(k))
		return d
	if v is Array:
		var a := []
		for x in v:
			a.append(canon(x, key))
		return a
	if v is Vector3:
		return canon([v.x, v.y, v.z], key)
	if v is Vector2:
		return canon([v.x, v.y], key)
	if v is PackedFloat32Array or v is PackedFloat64Array or v is PackedInt32Array or v is PackedByteArray:
		return canon(Array(v), key)
	return v


## One bucket of LevelMeshSet.meshes() as a MeshInstance3D: ArrayMesh with a placeholder material
## named after the material key (Track.dress swaps in the world material), meta level_road
## (-1 main, branch uid, -2 other), level_group, level_hash; meta no_collision when collision is off.
## mats shares one placeholder per material key.
static func mesh_node(e: Dictionary, collision := true, mats := {}) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, e.arrays)
	var key := str(e.material)
	var mat: StandardMaterial3D = mats.get(key)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.resource_name = key
		mats[key] = mat
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = str(e.name)
	mi.set_meta("level_road", LevelMeshSet.meta_road(int(e.road)))
	mi.set_meta("level_group", str(e.group))
	mi.set_meta("level_hash", int(e.hash))
	if not collision:
		mi.set_meta("no_collision", true)
	return mi


## A chunk of `chunks` as its MeshInstance3D (LevelTerrain.chunk_node's names, meta and
## visibility ranges), made from the worker's arrays.
func chunk_node(c: Dictionary) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, c.arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = str(c.name)
	mi.set_meta("no_collision", true)
	mi.set_meta("level_hash", int(c.get("hash", 0)))
	var chunk_m := LevelTerrain.CHUNK * terrain.cell
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if int(c.lod) >= 1:
		mi.set_meta("no_shadow", true)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_begin = 3.0 * chunk_m
		mi.visibility_range_begin_margin = LevelTerrain.LOD_MARGIN
	else:
		mi.visibility_range_end = 3.0 * chunk_m + LevelTerrain.LOD_MARGIN
		mi.visibility_range_end_margin = LevelTerrain.LOD_MARGIN
	return mi


func _skirt_node() -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, skirt)
	var m := StandardMaterial3D.new()
	m.resource_name = str(terrain.layers.get("base", "nature/grassfloor002a"))
	mesh.surface_set_material(0, m)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "deco_world_edge"
	mi.set_meta("no_collision", true)
	mi.set_meta("no_shadow", true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
