class_name PropCatalog
extends RefCounted
## The object catalog (4.1): the category and facts of every model, computed once per content
## version into user://cache/prop_catalog.json, search, FAVOURITES / RECENT, and the LIGHTS & FX
## entries that are not models. The categories are a 1:1 port of the RULES of
## .handoff/scratch/editor/probes/model_catalog.py (first match wins). Main thread only (reads
## Game); tests swap in a fake catalog with `set_source`. P15.

const CACHE := "user://cache/prop_catalog.json"
const FORMAT := 1
## The model categories in tab order (the catalog drawer, 1.6 OBJECTS).
const CATEGORIES := ["BUILDINGS", "BRIDGES & BIG STRUCTURES", "ROCKS & CLIFFS", "TREES & PLANTS", "XEN FLORA",
	"STREET FURNITURE", "JUNK & CLUTTER", "VEHICLES", "TRAINS & RAIL", "COMBINE", "INDUSTRIAL", "DOCKS & COAST",
	"ROOFTOP", "LAB & BLACK MESA", "PRISON & INTERIORS", "FOREST & FARM"]
const ANIMATED := "ANIMATED"          # creatures and machines: hidden unless SHOW ANIMATED
const HAZARD_RIGS := "HAZARD RIGS"    # hidden: reached through their hazards
const OTHER := "OTHER"                # what no rule matches
## Never offered: gibs, drivers, crowd people (the CROWDS tool), items / weapons / projectiles.
const HIDDEN := ["GIBS", "DRIVERS", "CROWD PEOPLE", "ITEMS"]
const TAB_FAVOURITES := "FAVOURITES"
const TAB_RECENT := "RECENT"
const TAB_ALL := "ALL"
const TAB_FX := "LIGHTS & FX"
const RECENT_MAX := 16
const BIG := 30.0                     # metres: a "big" model (AABB max side)
const PHYS_MASS := 60.0               # physics_ok: kg at most ...
const PHYS_SIZE := 3.0                # ... and an AABB max side under this (1.6 PHYSICS)
## Track._knockable's fragments: props that break off when a kart hits them.
const KNOCK := ["lamppost", "signpole", "streetsign", "bench", "payphone", "trashcan", "trashbin", "traffic_light",
	"wood_fence", "barricade00", "utilitypole", "cardboard", "dumpster", "furniture", "floodlight"]
## The LIGHTS & FX entries (C2 S10): not models; each stamps an item of its section.
const FX := [
	{"id": "light", "name": "LIGHT", "section": "lights",
		"item": {"color": [1.0, 0.9, 0.75], "range": 16.0, "energy": 1.2}},
	{"id": "fire", "name": "FIRE", "section": "fires", "item": {"size": 1.0, "smoke": 1.0, "light": true}},
	{"id": "embers", "name": "EMBERS", "section": "fires", "item": {"size": 0.0, "smoke": 1.0, "light": false}},
	{"id": "screen", "name": "BREENCAST SCREEN", "section": "screens", "item": {"yaw": 0.0, "w": 8.0, "h": 4.5},
		"needs": "combine"},
]

# the probe's lists (model_catalog.py RULES)
const _ANIM_ROOTS := ["antlion", "antlion_grub", "antlion_guard", "antlion_worker", "combine_strider", "gunship",
	"combine_dropship", "combine_helicopter", "combine_scanner", "hunter", "headcrabclassic", "crow", "pigeon", "seagull",
	"dog", "combine_soldier_prisonguard", "combine_super_soldier", "vehicle", "buggy", "combine_apc"]
const _ANIM_KEYS := ["hl1/apache", "hl1/barnacle", "hl1/bullsquid", "hl1/controller", "hl1/floater", "hl1/garg",
	"hl1/hgrunt", "hl1/houndeye", "hl1/islave", "hl1/nihilanth", "hl1/osprey", "hl1/protozoa", "hl1/scientist",
	"hl1/sentry", "hl1/tentacle2", "hl1/turret", "hl1/miniturret", "hl1/p_tripmine", "combine_turrets/floor_turret",
	"grub_nugget_large", "grub_nugget_medium", "grub_nugget_small", "hl1/holo"]
const _ITEM_KEYS := ["manhack", "roller", "hl1/rpgrocket", "combine_helicopter/helicopter_bomb01"]
const _RIG_KEYS := ["props_wasteland/cranemagnet01a", "props_combine/combine_mine01", "props_combine/combinethumper002",
	"props_combine/combinethumper001a", "props_combine/headcrabcannister01a"]
const _BUILDING_KEYS := ["props_combine/combine_citadel001", "props_combine/prison01", "props_combine/prison01b",
	"props_combine/prison01c", "props_wasteland/depot", "props_combine/combinetower001", "props_combine/combine_bunker01",
	"props_combine/combinebuttress", "props_rooftop/parliament_dome_destroyed_exterior"]
const _BRIDGE_PREFIX := ["cliffs/bridge", "props_canal/canal_bridge", "props_wasteland/medbridge", "props_wasteland/bridge"]
const _BRIDGE_KEYS := ["props_combine/combine_bridge", "props_outland/bridge01", "props_c17/overpass_001a",
	"props_c17/overpass_001b", "map1_bridge/traincars", "props_canal/locks_large", "props_canal/canal_bridge_railing01"]
const _VEHICLE_KEYS := ["props_wasteland/tugtop001", "hl1/forklift", "hl1/loader", "hl1/dead_osprey"]
const _C17_NOT := ["props_c17/lockers001a", "props_c17/shelfunit01a"]
const _PRISON_KEYS := ["props_c17/lockers001a", "props_c17/shelfunit01a", "props_wasteland/cafeteria_bench001a",
	"props_wasteland/cafeteria_table001a", "props_wasteland/kitchen_counter001a", "props_wasteland/laundry_cart001",
	"props_wasteland/laundry_dryer001", "props_wasteland/shower_system001a", "props_wasteland/controlroom_desk001a",
	"props_wasteland/controlroom_filecabinet001a"]
const _DOCK_KEYS := ["props_wasteland/buoy01", "props_wasteland/dockplank01a", "props_wasteland/dockplank01b",
	"props_wasteland/lighthouse_fresnel_light_base"]

static var _facts := {}            # key -> facts (see `fact`)
static var _loaded := false
static var _fake := false          # set_source in use (no cache file)
static var _src_models := {}
static var _src_metas := {}


# ---------------------------------------------------------------- categories (model_catalog.py RULES)

## The category of a model by the first matching rule (HIDDEN ones included); `info` is its
## models.json entry (only `kind` is read).
static func category_of(key: String, info: Dictionary) -> String:
	var kind := str(info.get("kind", "props"))
	var root := key.get_slice("/", 0)
	var last := key.get_slice("/", key.get_slice_count("/") - 1)
	if kind == "gibs" or key.contains("_chunk") or key.contains("apc_destroyed_gib"):
		return "GIBS"
	if kind == "drivers":
		return "DRIVERS"
	if kind == "crowd":
		return "CROWD PEOPLE"
	if key.begins_with("items/") or key.begins_with("weapons/") or key in _ITEM_KEYS:
		return "ITEMS"
	if root in _ANIM_ROOTS or key in _ANIM_KEYS:
		return ANIMATED
	if key.begins_with("cranes/") or key.begins_with("seesawbridge/") or key in _RIG_KEYS:
		return HAZARD_RIGS
	if key.begins_with("props_buildings/") or key in _BUILDING_KEYS:
		return "BUILDINGS"
	if _starts(key, _BRIDGE_PREFIX) or key in _BRIDGE_KEYS:
		return "BRIDGES & BIG STRUCTURES"
	if key.begins_with("cliffs/") or last.contains("rock") or key.begins_with("props_mining/") or key == "hl1/big_rock":
		return "ROCKS & CLIFFS"
	if key.begins_with("props_foliage/") or key == "hl1/tree":
		return "TREES & PLANTS"
	if key.begins_with("props_hive/") or key.begins_with("hl1/uplant") or key.begins_with("hl1/fungus") \
			or key in ["hl1/hair", "hl1/crystal"]:
		return "XEN FLORA"
	if key.begins_with("props_trainstation/") or key.begins_with("props_combine/combine_train") \
			or key == "props_combine/combinetrain01a":
		return "TRAINS & RAIL"
	if key.begins_with("props_vehicles/") or key == "props_canal/boat001a" or key.contains("boat") or key in _VEHICLE_KEYS:
		return "VEHICLES"
	if key.begins_with("props_combine/"):
		return "COMBINE"
	if key.begins_with("props_c17/") and not key.contains("furniture") and not key in _C17_NOT:
		return "STREET FURNITURE"
	if key.begins_with("props_rooftop/"):
		return "ROOFTOP"
	if key.begins_with("props_lab/") or key in ["hl1/filecabinet", "hl1/light"]:
		return "LAB & BLACK MESA"
	if key.contains("prison") or key.begins_with("props_interiors/") or key.contains("furniture") or key in _PRISON_KEYS:
		return "PRISON & INTERIORS"
	if key.begins_with("props_docks/") or key in _DOCK_KEYS:
		return "DOCKS & COAST"
	if key.begins_with("props_wasteland/"):
		return "INDUSTRIAL"
	if key.begins_with("props_forest/") or key == "props_outland/haybale":
		return "FOREST & FARM"
	if key.begins_with("props_junk/") or key.begins_with("props_debris/") or key == "props_borealis/bluebarrel001":
		return "JUNK & CLUTTER"
	return OTHER


## Track._static_shape's rule by key: MESH (big irregular shapes), CYLINDER (trees, poles),
## NONE (grass, ferns, bushes), BOX (crystals, fungi), HULL (the rest).
static func collision_of(key: String) -> String:
	if key.begins_with("props_buildings/") or key.begins_with("props_trainstation/train") or key.contains("boxcar") \
			or key.contains("tanker") or key.contains("flatcar") or key.begins_with("props_combine/combine_bunker") \
			or key.contains("combinetower") or key.contains("buttress"):
		return "MESH"
	if key.begins_with("props_foliage/tree") or key.contains("lamppost") or key.contains("utilitypole") \
			or key.contains("powertower") or key.contains("signpole") or key.contains("traffic_light") \
			or key.begins_with("hl1/tree") or key.begins_with("hl1/light"):
		return "CYLINDER"
	if key.contains("grass") or key.contains("fern") or key.contains("shrub") or key.contains("bush") \
			or key.begins_with("hl1/hair") or key.begins_with("hl1/uplant") or key.begins_with("hl1/fungus_small"):
		return "NONE"
	if key.begins_with("hl1/crystal") or key.begins_with("hl1/fungus"):
		return "BOX"
	return "HULL"


static func knockable(key: String) -> bool:
	for k in KNOCK:
		if key.contains(k):
			return true
	return false


## The facts of one model from its models.json entry and (for `skinned`) its per-model meta.
static func make_facts(key: String, info: Dictionary, meta: Variant = null) -> Dictionary:
	var a := _v3(info.get("aabb_min"))
	var z := _v3(info.get("aabb_max"))
	var ext := (z - a).abs()
	var size := maxf(ext.x, maxf(ext.y, ext.z))
	var fx := maxf(absf(a.x), absf(z.x))
	var fz := maxf(absf(a.z), absf(z.z))
	var cat := category_of(key, info)
	var bones := 0
	if meta is Dictionary:
		var b = (meta as Dictionary).get("bones", [])
		if b is Array:
			bones = (b as Array).size()
		elif b is String and str(b).strip_edges() not in ["", "[]"]:
			bones = str(b).count(",") + 1
	var mass := float(info.get("mass", 1e9))
	return {
		"category": cat,
		"size": snappedf(size, 0.01),
		"foot": snappedf(sqrt(fx * fx + fz * fz), 0.01),
		"height": snappedf(ext.y, 0.01),
		"skinned": bones > 1,
		"physics_ok": str(info.get("kind", "props")) == "props" and mass <= PHYS_MASS and size < PHYS_SIZE,
		"knockable": knockable(key),
		"collision": collision_of(key),
		"big": size > BIG,
		"name": display_name(key),
	}


## "props_c17/bench01a" -> "BENCH01A"
static func display_name(key: String) -> String:
	return key.get_slice("/", key.get_slice_count("/") - 1).replace("_", " ").to_upper()


# ---------------------------------------------------------------- the catalog

## Tests: a fake catalog (models.json-shaped entries, metas {key: {bones}}); {} = Game's again.
static func set_source(models: Dictionary, metas := {}) -> void:
	_fake = not models.is_empty()
	_src_models = models
	_src_metas = metas
	_facts = {}
	_loaded = false


## Every model's facts {key: {category, size, foot, height, skinned, physics_ok, knockable,
## collision, big, name}}, read from the cache when it matches this content version, else
## computed (and the cache written).
static func facts() -> Dictionary:
	if _loaded:
		return _facts
	_loaded = true
	var models := _models()
	if models.is_empty():
		_facts = {}
		return _facts
	var version := _content_version()
	if not _fake:
		var cached := load_cache(CACHE, version, models.size())
		if not cached.is_empty():
			_facts = cached
			return _facts
	var out := {}
	var keys := models.keys()
	keys.sort()
	for k in keys:
		var info = models[k]
		if not (info is Dictionary):
			continue
		var meta = _src_metas.get(k) if _fake else _read_meta(str(k), info)
		out[str(k)] = make_facts(str(k), info, meta)
	_facts = out
	if not _fake:
		save_cache(CACHE, version, models.size(), out)
	return _facts


## Drops the facts in memory (the next call recomputes or reads the cache).
static func reset() -> void:
	_facts = {}
	_loaded = false


## One model's facts, {} for an unknown key.
static func fact(key: String) -> Dictionary:
	return facts().get(key, {})


static func has(key: String) -> bool:
	return facts().has(key)


static func size_of(key: String) -> float:
	return float(fact(key).get("size", 0.0))


static func physics_ok(key: String) -> bool:
	return bool(fact(key).get("physics_ok", false))


## Whether a category is offered in the drawer (ANIMATED only with SHOW ANIMATED).
static func visible(category: String, show_animated := false) -> bool:
	if category in HIDDEN or category == HAZARD_RIGS:
		return false
	return show_animated or category != ANIMATED


## The drawer's tabs: FAVOURITES, RECENT, ALL, LIGHTS & FX, the model categories, ANIMATED (with
## SHOW ANIMATED), OTHER (when anything falls there).
static func tabs(show_animated := false) -> PackedStringArray:
	var out := PackedStringArray([TAB_FAVOURITES, TAB_RECENT, TAB_ALL, TAB_FX])
	out.append_array(PackedStringArray(CATEGORIES))
	if show_animated:
		out.append(ANIMATED)
	if not keys(OTHER).is_empty():
		out.append(OTHER)
	return out


## The keys of a tab in key order (FAVOURITES and RECENT in their own order); LIGHTS & FX has no
## model keys (see `fx_entries`). HIDDEN models are never listed; ANIMATED and HAZARD RIGS only
## when asked for by name (ALL leaves them out unless SHOW ANIMATED, the rigs always).
static func keys(tab: String, show_animated := false) -> PackedStringArray:
	var out := PackedStringArray()
	if tab == TAB_FX:
		return out
	if tab == TAB_FAVOURITES or tab == TAB_RECENT:
		for k in (favourites() if tab == TAB_FAVOURITES else recent()):
			var f := fact(k)
			if not f.is_empty() and visible(str(f.category), show_animated):
				out.append(k)
		return out
	var all := facts()
	var ks := all.keys()
	ks.sort()
	for k in ks:
		var c := str(all[k].category)
		if tab == TAB_ALL:
			if visible(c, show_animated):
				out.append(str(k))
		elif tab == c and not c in HIDDEN:
			out.append(str(k))
	return out


## Case-insensitive substring search over the key's words and the category (every word of the
## query must match), within a tab (ALL by default).
static func search(text: String, tab := TAB_ALL, show_animated := false) -> PackedStringArray:
	var words := PackedStringArray()
	for w in text.to_lower().replace("/", " ").replace("_", " ").split(" ", false):
		words.append(w)
	var out := PackedStringArray()
	for k in keys(tab, show_animated):
		var hay := "%s %s %s" % [k.to_lower(), k.to_lower().replace("/", " ").replace("_", " "),
			str(fact(k).get("category", "")).to_lower()]
		var ok := true
		for w in words:
			if not hay.contains(w):
				ok = false
				break
		if ok:
			out.append(k)
	return out


## Models per category (hidden ones included).
static func counts() -> Dictionary:
	var out := {}
	var all := facts()
	for k in all:
		var c := str(all[k].category)
		out[c] = int(out.get(c, 0)) + 1
	return out


## How many models a fact holds (physics_ok, big, skinned, knockable...).
static func count_where(fact_key: String) -> int:
	var n := 0
	var all := facts()
	for k in all:
		if bool(all[k].get(fact_key, false)):
			n += 1
	return n


# ---------------------------------------------------------------- favourites and recent

static func favourites() -> PackedStringArray:
	return _setting_list("editor_fav_props")


static func is_favourite(key: String) -> bool:
	return key in favourites()


## Stars or unstars a model; returns whether it is a favourite now.
static func toggle_favourite(key: String) -> bool:
	var l := favourites()
	var on := not key in l
	if on:
		l.append(key)
	else:
		l.remove_at(l.find(key))
	_set_setting("editor_fav_props", l)
	return on


static func recent() -> PackedStringArray:
	return _setting_list("editor_recent_props")


## A model was placed: first in RECENT (the last 16).
static func note_placed(key: String) -> void:
	var l := recent()
	var at := l.find(key)
	if at >= 0:
		l.remove_at(at)
	l.insert(0, key)
	if l.size() > RECENT_MAX:
		l.resize(RECENT_MAX)
	_set_setting("editor_recent_props", l)


# ---------------------------------------------------------------- LIGHTS & FX

static func fx_entries() -> Array:
	return FX.duplicate(true)


static func fx_entry(id: String) -> Dictionary:
	for e in FX:
		if str(e.id) == id:
			return (e as Dictionary).duplicate(true)
	return {}


## Whether an entry can be stamped on this doc (the Breencast screen needs the COMBINE arch).
static func fx_enabled(id: String, doc: LevelDoc) -> bool:
	var e := fx_entry(id)
	if e.is_empty():
		return false
	if str(e.get("needs", "")) == "combine":
		var race = doc.data.get("race", {}) if doc != null else {}
		return not (race is Dictionary) or str(race.get("gantry", "combine")) == "combine"
	return true


## The doc item an entry stamps at `pos` (a uid from doc when given): [section, item], or [] for
## an unknown id.
static func fx_item(id: String, pos: Vector3, doc: LevelDoc = null) -> Array:
	var e := fx_entry(id)
	if e.is_empty():
		return []
	var item: Dictionary = e.item
	item["pos"] = [snappedf(pos.x, 0.001), snappedf(pos.y, 0.001), snappedf(pos.z, 0.001)]
	if doc != null:
		item["uid"] = doc.new_uid()
	return [str(e.section), item]


# ---------------------------------------------------------------- cache

## The cached facts when the file matches this content version and model count, else {}.
static func load_cache(path: String, version: int, count: int) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var v = JSON.parse_string(f.get_as_text())
	if not (v is Dictionary) or int(v.get("format", 0)) != FORMAT or int(v.get("content", -1)) != version \
			or int(v.get("count", -1)) != count or not (v.get("facts") is Dictionary):
		return {}
	var out := {}
	var fs: Dictionary = v.facts
	for k in fs:
		if fs[k] is Dictionary:
			var e: Dictionary = fs[k]
			for b in ["skinned", "physics_ok", "knockable", "big"]:
				e[b] = bool(e.get(b, false))
			out[str(k)] = e
	return out if out.size() == count else {}


static func save_cache(path: String, version: int, count: int, all: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"format": FORMAT, "content": version, "count": count, "facts": all}, "", true))
	f.close()
	return OK


# ---------------------------------------------------------------- helpers

static func _models() -> Dictionary:
	if _fake:
		return _src_models
	var g := _game()
	if g == null:
		return {}
	var m = g.get("models")
	return m if m is Dictionary else {}


static func _content_version() -> int:
	var g := _game()
	return int(g.get("content_version")) if g != null else 0


static func _read_meta(key: String, info: Dictionary) -> Variant:
	var p := str(info.get("meta", "res://assets/models/%s.json" % key))
	if not FileAccess.file_exists(p):
		return null
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


static func _setting_list(key: String) -> PackedStringArray:
	var g := _game()
	var out := PackedStringArray()
	if g == null:
		return out
	var s = g.get("settings")
	if s is Dictionary and (s as Dictionary).get(key) is Array:
		for k in s[key]:
			out.append(str(k))
	return out


static func _set_setting(key: String, l: PackedStringArray) -> void:
	var g := _game()
	if g == null:
		return
	var s = g.get("settings")
	if s is Dictionary:
		s[key] = Array(l)
		if g.has_method("save_settings"):
			g.call("save_settings")


static func _starts(key: String, prefixes: Array) -> bool:
	for p in prefixes:
		if key.begins_with(p):
			return true
	return false


static func _v3(v: Variant) -> Vector3:
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


static func _game() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Game")
	return null
