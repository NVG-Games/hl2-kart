class_name LevelStyles
## Road styles (2.5): the built-in presets, the four barrier presets, the defaults of each kind,
## resolving a document's styles into full dicts against a material registry, and the width a
## style's side treatment takes beyond the road edge.

## Material used for a missing surface (and any other missing material slot).
const FALLBACK_MAT := "concrete/concretefloor037b"
const START_LINE_MAT := "concrete/concretefloor033y"
const KINDS := ["open", "street", "bridge", "tunnel"]

## Keys every style has, with their defaults.
const BASE := {"name": "", "kind": "open", "road": FALLBACK_MAT, "road_rep": 6.0, "road_u": "rep",
	"grip": "road", "bank": true, "lines": false, "lines_mat": START_LINE_MAT, "vmax": 40.0,
	"barrier_l": null, "barrier_r": null}

## Keys of each kind, with their defaults.
const KIND_KEYS := {
	"open": {"verge": "nature/grassfloor002a", "verge_w": 4.0, "verge_drop": 0.27},
	"street": {"curb": "concrete/concretewall064a", "curb_h": 0.16, "walk": 4.0,
		"walk_mat": "concrete/concretefloor011a"},
	"bridge": {"skirt": "concrete/concretewall066a", "skirt_h": 1.5, "pillar": "", "pillar_every": 30.0,
		"pillar_size": 2.4},
	"tunnel": {"wall": "concrete/concretewall059d", "ceil": "concrete/concreteceiling004a", "height": 7.5,
		"wall_gap": 0.6, "light": "", "light_every": 8.0, "light_color": [1.0, 0.9, 0.75],
		"light_energy": 1.6},
}

## Keys of a style that hold a material ("" = none for pillar and light).
const MAT_KEYS := ["road", "lines_mat", "verge", "curb", "walk_mat", "skirt", "pillar", "wall", "ceil", "light"]

## A barrier dict's keys and defaults.
const BARRIER_BASE := {"kind": "wall", "mat": "concrete/concretewall008a", "h": 1.0, "thick": 0.4,
	"off": 0.2, "col_h": 2.5, "rep": 3.0}
const BARRIER_KINDS := ["wall", "fence", "jersey", "rail"]

## The segment inspector's RAIL / FENCE / WALL / JERSEY.
const BARRIERS := {
	"rail": {"kind": "rail", "mat": "metal/metalrail013a", "h": 1.0, "thick": 0.05, "off": 0.2,
		"col_h": 2.5, "rep": 3.0},
	"fence": {"kind": "fence", "mat": "metal/metalfence001a", "h": 1.2, "thick": 0.05, "off": 0.2,
		"col_h": 2.5, "rep": 3.0},
	"wall": {"kind": "wall", "mat": "concrete/concretewall008a", "h": 1.2, "thick": 0.5, "off": 0.2,
		"col_h": 2.5, "rep": 3.0},
	"jersey": {"kind": "jersey", "mat": "concrete/concretewall064a", "h": 0.9, "thick": 0.6, "off": 0.3,
		"col_h": 2.5, "rep": 3.0},
}

## The built-in presets (2.5). Keys left out take BASE / KIND_KEYS defaults in resolve().
const PRESETS := {
	"asphalt": {"name": "ASPHALT", "kind": "open", "road": "concrete/concretefloor037b", "road_rep": 6.0,
		"verge": "nature/grassfloor002a", "verge_w": 4.0},
	"asphalt_rail": {"name": "ASPHALT, GUARD RAILS", "kind": "open", "road": "concrete/concretefloor037b",
		"road_rep": 6.0, "verge": "nature/grassfloor002a", "verge_w": 4.0,
		"barrier_l": {"kind": "fence", "mat": "metal/metalrail013a", "h": 1.0, "thick": 0.05, "off": 1.0,
			"col_h": 2.5, "rep": 3.0},
		"barrier_r": {"kind": "fence", "mat": "metal/metalrail013a", "h": 1.0, "thick": 0.05, "off": 1.0,
			"col_h": 2.5, "rep": 3.0}},
	"highway": {"name": "HIGHWAY", "kind": "open", "road": "concrete/concretefloor037b", "road_u": "full",
		"verge": "nature/blendsandsand008b", "verge_w": 4.0,
		"barrier_l": {"kind": "jersey", "mat": "concrete/concretewall064a", "h": 0.9, "thick": 0.6,
			"off": 0.3, "col_h": 2.5, "rep": 3.0},
		"barrier_r": {"kind": "jersey", "mat": "concrete/concretewall064a", "h": 0.9, "thick": 0.6,
			"off": 0.3, "col_h": 2.5, "rep": 3.0}},
	"dirt": {"name": "DIRT ROAD", "kind": "open", "road": "nature/dirtfloor003a", "road_rep": 5.0,
		"verge": "nature/grassfloor002a", "verge_w": 3.0, "verge_drop": 0.2},
	"sand": {"name": "SAND TRACK (off-road grip)", "kind": "open", "road": "nature/blendsandsand008a",
		"road_rep": 5.0, "grip": "offroad", "verge": "nature/blendsandsand008a", "verge_w": 2.0},
	"street": {"name": "CITY STREET", "kind": "street", "road": "concrete/concretefloor006a", "road_rep": 6.0,
		"curb": "concrete/concretewall064a", "walk_mat": "concrete/concretefloor011a", "walk": 4.0,
		"barrier_l": {"kind": "fence", "mat": "metal/metalfence001a", "h": 1.2, "thick": 0.05, "off": 0.2,
			"col_h": 2.5, "rep": 3.0},
		"barrier_r": {"kind": "fence", "mat": "metal/metalfence001a", "h": 1.2, "thick": 0.05, "off": 0.2,
			"col_h": 2.5, "rep": 3.0}},
	"plaza": {"name": "WALLED STREET", "kind": "street", "road": "concrete/concretefloor006a", "road_rep": 6.0,
		"curb": "concrete/concretewall064a", "walk_mat": "concrete/concretefloor011a", "walk": 4.0,
		"barrier_l": {"kind": "wall", "mat": "concrete/concretewall008a", "h": 2.5, "thick": 0.5, "off": 0.2,
			"col_h": 2.5, "rep": 3.0},
		"barrier_r": {"kind": "wall", "mat": "concrete/concretewall008a", "h": 2.5, "thick": 0.5, "off": 0.2,
			"col_h": 2.5, "rep": 3.0}},
	"bridge": {"name": "CONCRETE BRIDGE", "kind": "bridge", "road": "concrete/concretefloor037b", "road_rep": 6.0,
		"bank": false, "skirt": "concrete/concretewall066a", "skirt_h": 2.0, "pillar": "concrete/concretewall066a",
		"pillar_every": 30.0, "pillar_size": 2.4,
		"barrier_l": {"kind": "wall", "mat": "concrete/concretewall064a", "h": 1.0, "thick": 0.5, "off": 0.2,
			"col_h": 3.0, "rep": 3.0},
		"barrier_r": {"kind": "wall", "mat": "concrete/concretewall064a", "h": 1.0, "thick": 0.5, "off": 0.2,
			"col_h": 3.0, "rep": 3.0}},
	"wood_bridge": {"name": "WOODEN BRIDGE", "kind": "bridge", "road": "wood/woodfloor005a", "road_rep": 4.0,
		"bank": false, "skirt": "wood/woodbeam001a", "skirt_h": 1.0, "pillar": "wood/woodbeam001a",
		"pillar_every": 8.0, "pillar_size": 0.6,
		"barrier_l": {"kind": "fence", "mat": "wood/woodwall009a", "h": 0.9, "thick": 0.05, "off": 0.2,
			"col_h": 2.2, "rep": 3.0},
		"barrier_r": {"kind": "fence", "mat": "wood/woodwall009a", "h": 0.9, "thick": 0.05, "off": 0.2,
			"col_h": 2.2, "rep": 3.0}},
	"tunnel": {"name": "TUNNEL", "kind": "tunnel", "road": "concrete/concretefloor037b", "road_rep": 6.0,
		"bank": false, "wall": "concrete/concretewall059d", "ceil": "concrete/concreteceiling004a",
		"light": "lights/fluorescentcool001a", "light_every": 8.0},
}

const PRESET_IDS := ["asphalt", "asphalt_rail", "highway", "dirt", "sand", "street", "plaza", "bridge",
	"wood_bridge", "tunnel"]


## id -> full style dict for every preset and every own style of `doc` (the document's `data`).
## Each dict has every BASE and kind key, `id`, `own` (bool), full barrier dicts (or null) and
## `missing` (the material slots that were not in `materials` and now hold FALLBACK_MAT). An empty
## `materials` means no registry is known: keys are kept as they are.
static func resolve(doc: Dictionary, materials: Dictionary) -> Dictionary:
	var out := {}
	for id in PRESET_IDS:
		out[id] = _full(id, PRESETS[id], materials, false)
	var own = doc.get("styles", {})
	if own is Dictionary:
		for id in own:
			if own[id] is Dictionary:
				out[str(id)] = _full(str(id), own[id], materials, true)
	return out


## Metres a style's side treatment takes beyond the road edge on one side (side <= 0 left,
## side >= 1 right): open the verge (or the barrier's offset + thickness when wider), street the
## kerb + pavement + barrier, bridge the deck edge + barrier, tunnel the wall gap + 0.5.
static func treatment(st: Dictionary, side: int) -> float:
	var bar = st.get("barrier_r" if side >= 1 else "barrier_l")
	var thick := 0.0
	var off := 0.0
	if bar is Dictionary and str(bar.get("kind", "wall")) != "none":
		var k := str(bar.get("kind", "wall"))
		thick = 0.95 if k == "jersey" else float(bar.get("thick", 0.4 if k == "wall" else 0.05))
		off = float(bar.get("off", 0.2))
	match str(st.get("kind", "open")):
		"street":
			return 0.3 + float(st.get("walk", 4.0)) + thick
		"bridge":
			return 1.0 + thick
		"tunnel":
			return float(st.get("wall_gap", 0.6)) + 0.5
		_:
			return maxf(float(st.get("verge_w", 4.0)), off + thick if thick > 0.0 else 0.0)


## Every style id the document can use: the presets in order, then its own styles in doc order.
static func ids(doc: Dictionary) -> PackedStringArray:
	var out := PackedStringArray(PRESET_IDS)
	var own = doc.get("styles", {})
	if own is Dictionary:
		for id in own:
			if not str(id) in out:
				out.append(str(id))
	return out


# ---------------------------------------------------------------- additions (P0)

static func is_preset(id: String) -> bool:
	return PRESETS.has(id)


## A full barrier dict from a partial one (h replaced by `height` when > 0, col_h = max(2.5, h)
## as the segment inspector makes them); null for null; {kind: "none"} kept as is.
static func barrier(kind: String, height := 0.0) -> Variant:
	if kind == "" or kind == "style":
		return null
	if kind == "none":
		return {"kind": "none"}
	var b: Dictionary = (BARRIERS.get(kind, BARRIERS.wall) as Dictionary).duplicate(true)
	if height > 0.0:
		b.h = height
		b.col_h = maxf(2.5, height)
	return b


## The barrier on one side of a style (a full dict) or {} when it has none.
static func barrier_of(st: Dictionary, side: int) -> Dictionary:
	var bar = st.get("barrier_r" if side >= 1 else "barrier_l")
	if bar is Dictionary and str(bar.get("kind", "wall")) != "none":
		return bar
	return {}


static func _full(id: String, src: Dictionary, materials: Dictionary, own: bool) -> Dictionary:
	var kind := str(src.get("kind", "open"))
	if not kind in KINDS:
		kind = "open"
	var st: Dictionary = BASE.duplicate(true)
	st.bank = kind == "open" or kind == "street"
	for k in KIND_KEYS[kind]:
		st[k] = _copy(KIND_KEYS[kind][k])
	for k in src:
		st[k] = _copy(src[k])
	st.kind = kind
	st["id"] = id
	st["own"] = own
	if str(st.name) == "":
		st.name = id.to_upper()
	for side in ["barrier_l", "barrier_r"]:
		st[side] = _full_barrier(st.get(side))
	var missing := PackedStringArray()
	if not materials.is_empty():
		for k in MAT_KEYS:
			if not st.has(k):
				continue
			var m := str(st[k])
			if m == "" and (k == "pillar" or k == "light"):
				continue
			if not materials.has(m):
				st[k] = FALLBACK_MAT
				missing.append(k)
		for side in ["barrier_l", "barrier_r"]:
			var b = st[side]
			if b is Dictionary and b.has("mat") and not materials.has(str(b.mat)):
				b.mat = FALLBACK_MAT
				missing.append(side)
	st["missing"] = missing
	return st


static func _full_barrier(b: Variant) -> Variant:
	if not (b is Dictionary):
		return null
	if str(b.get("kind", "wall")) == "none":
		return {"kind": "none"}
	var out: Dictionary = BARRIER_BASE.duplicate(true)
	for k in b:
		out[k] = _copy(b[k])
	if not str(out.kind) in BARRIER_KINDS:
		out.kind = "wall"
	return out


static func _copy(v: Variant) -> Variant:
	if v is Dictionary or v is Array:
		return v.duplicate(true)
	return v
