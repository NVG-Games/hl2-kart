class_name LevelCrowds
## Spectators and extras (4.3): the doc's crowd groups and easter eggs compiled into the runtime
## data CrowdDirector / CrowdEggs / CrowdBirds read unchanged (`crowd_groups`, `crowds`,
## `crowd_eggs`). Ports of tools/crowds.py: the palette per role, the member line with seeded
## jitter and the crowd_fail rules (roads, pits, water, slope, props, reserved corridors, spacing,
## decks over the feet). Members that break a rule are left out and counted in one `crowd`
## warning (filed by `lint`); so is a hologram whose road has no jump. Pure data, no Game access:
## it runs on the compile's worker. P15.

const ROLES := ["citizen", "refugee", "rebel", "metrocop", "combine", "scientist", "guard", "vort", "islave", "hecu", "zombie", "cameo"]
const MOODS := ["fan", "polite", "excited", "loyal", "military", "chant", "scared"]
const EGGS := ["gman", "birds", "gnome", "zombies", "holo", "lamarr", "nihilanth"]

## tools/crowds.py CROWD_PALETTE: deterministic picks per role; keys this install lacks are left
## out, then CrowdRules.FALLBACK stands in.
const PALETTE := {
	"citizen": ["humans/group01/male_01", "humans/group01/male_02", "humans/group01/male_03", "humans/group01/male_04",
		"humans/group01/male_05", "humans/group01/male_06", "humans/group01/male_07", "humans/group01/male_08",
		"humans/group01/male_09", "humans/group01/female_01", "humans/group01/female_02", "humans/group01/female_03",
		"humans/group01/female_04", "humans/group01/female_06", "humans/group01/female_07"],
	"refugee": ["humans/group02/male_01", "humans/group02/male_03", "humans/group02/male_05", "humans/group02/male_07",
		"humans/group02/male_09", "humans/group02/female_02", "humans/group02/female_04", "humans/group02/female_06"],
	"rebel": ["humans/group03/male_01", "humans/group03/male_02", "humans/group03/male_04", "humans/group03/male_06",
		"humans/group03/male_08", "humans/group03/female_01", "humans/group03/female_03", "humans/group03/female_07"],
	"metrocop": ["police"], "combine": ["combine_soldier"],
	"scientist": ["hl1/sci_glasses", "hl1/sci_einstein", "hl1/sci_luther", "hl1/sci_slick"],
	"guard": ["hl1/guard"], "vort": ["vortigaunt"], "islave": ["hl1/islave_hd"],
	"hecu": ["hl1/marine_mask", "hl1/marine_cmdr", "hl1/marine_shot"], "zombie": ["zombie/classic"],
	"cameo": ["kleiner"],
}
## lod 0 stays on FEW (45 %), 1 on FULL (25 % more), 2 only with FULL and HIGH graphics
const LOD_CYCLE := [0, 1, 2, 0, 0, 2, 1, 0, 2, 0, 1, 0, 2, 0, 1, 2, 0, 1, 0, 2]
const SPACING := 0.85         # metres between two people standing
const SPACING_SIT := 0.75     # ... seated
const ROW_GAP := 0.9          # metres between rows
const JITTER := 0.2           # the most a spot moves along or across (kept within the spacing)
const ROAD_GAP := 0.5         # plan metres past a road's edge nobody stands closer than
const ROAD_DY := 8.0          # a road this far over or under a spot is not "its" road
const PIT_REACH := 6.0        # metres past the edge of a road over a drop nobody stands
const SLOPE_MAX := 0.45
const PROP_MARGIN := 0.45
const BODY := Vector2(0.15, 1.9)   # metres over the feet nothing built may cross
const DODGE_PAST := 5.0       # metres past an open road's verge where people hop out of a kart's way
const EGG_BODY := 1.2         # nobody stands this close to an egg (the hologram, the gnome...)
const BED_MIN := 12           # members a group needs for a murmur bed
const MAX_PEOPLE := 600       # the hard cap of built members (2.10)
const HUMAN_BEDS := ["citizen", "refugee", "rebel", "scientist", "guard", "hecu"]
const ALIEN_BEDS := ["vort", "islave"]
## Why a member was left out, as the `crowd` warning words it.
const WHY := {"road": "on a road", "pit": "over a drop", "ground": "with no ground under them",
	"water": "in water", "slope": "on a steep slope", "prop": "inside an object", "hazard": "in a hazard's way",
	"close": "too close together", "under": "under a road", "egg": "in an extra's spot",
	"model": "with no model for their role", "branch": "beside a branch that is left out",
	"end": "past the end of their road",
	"limit": "past the limit of %d" % MAX_PEOPLE}
const CELL := 16.0            # the road-sample hash (metres)
const REACH := 32.0           # plan metres around a spot whose road samples are looked at


## data.crowd_groups, data.crowds, data.crowd_eggs from doc.crowds / doc.eggs (compile step 12).
static func compile(ctx: LevelContext) -> void:
	var p := _Place.new(ctx)
	ctx.data["crowd_eggs"] = p.eggs()
	var groups := []
	var people := []
	var gi := 0
	for g in ctx.doc.data.get("crowds", []):
		if not (g is Dictionary):
			continue
		var e := p.group(g, gi, people)
		if not e.is_empty():
			groups.append(e)
			gi += 1
	ctx.data["crowd_groups"] = groups
	ctx.data["crowds"] = people
	ctx.set_meta("crowd_issues", p.issues(people.size()))


## The `crowd` warnings of the last compile: members left out (with the commonest reasons) and
## eggs dropped.
static func lint(ctx: LevelContext) -> void:
	if not ctx.has_meta("crowd_issues"):
		return
	for it in ctx.get_meta("crowd_issues"):
		LevelValidate.issue(ctx.report, "crowd", it[0], it[1])


## The palette of a role as this install has it: CROWD_PALETTE's keys it has, else
## CrowdRules.FALLBACK's, else (an empty registry = nothing known) the palette as it is.
static func palette(role: String, models: Dictionary) -> PackedStringArray:
	var pal := PackedStringArray(PALETTE.get(role, []))
	if models.is_empty():
		return pal
	var out := PackedStringArray()
	for k in pal:
		if models.has(k):
			out.append(k)
	if out.is_empty():
		for k in CrowdRules.FALLBACK.get(role, []):
			if models.has(k):
				out.append(k)
	return out


## Why a spot breaks the rules ("" if it does not); on_ground: the feet are on the terrain (the
## slope counts), else on a pavement, verge or deck. Exposed for the CROWDS tool's hover.
static func spot_fail(ctx: LevelContext, q: Vector3, on_ground := true, seated := false) -> String:
	var p := _Place.new(ctx)
	return p.fail(q, on_ground, seated, true)


# ---------------------------------------------------------------- placement

class _Place:
	var ctx: LevelContext
	var models := {}
	var grid := {}           # Vector2i -> Array of (road index << 20 | sample)
	var members := {}        # Vector2i (1 m) -> Array of [Vector3, seated]
	var props := {}          # Vector2i -> Array of prop boxes [pos, yaw, scale, amin, amax]
	var bodies := PackedVector3Array()   # egg points nobody stands on
	var left := {}           # why -> count
	var left_by := {}        # group uid -> count
	var where_of := {}       # group uid -> {uid, road, s, pos}
	var wanted := 0
	var egg_issues := []
	var sea := -1000.0
	var waters := []

	func _init(c: LevelContext) -> void:
		ctx = c
		var m = ctx.registries.get("models", {})
		models = m if m is Dictionary else {}
		sea = float(ctx.data.get("sea_level", -1000.0))
		var w = ctx.data.get("waters", [])
		waters = w if w is Array else []
		for ri in ctx.roads.size():
			var r: LevelRoad = ctx.roads[ri]
			if r == null:
				continue
			for i in r.n:
				var k := _cell(r.pos[i])
				if not grid.has(k):
					grid[k] = []
				(grid[k] as Array).append((ri << 20) | i)
		for e in ctx.props:
			_add_prop(e)

	# ------------------------------------------------------------ eggs

	func eggs() -> Array:
		var out := []
		for e in ctx.doc.data.get("eggs", []):
			if not (e is Dictionary):
				continue
			var kind := str(e.get("kind", ""))
			if not kind in LevelCrowds.EGGS:
				continue
			var ent := _egg(e, kind)
			if ent.is_empty():
				continue
			out.append(ent)
			for k in ["pos", "center"]:
				if ent.get(k) is Array and kind in ["gman", "holo", "gnome", "zombies", "lamarr"]:
					bodies.append(_v3(ent[k]))
			for q in ent.get("path", []):
				bodies.append(_v3(q))
		return out

	func _egg(e: Dictionary, kind: String) -> Dictionary:
		var pos := _v3(e.get("pos"))
		var yaw := snappedf(deg_to_rad(float(e.get("yaw", 0.0))), 0.001)
		var near := _nearest_road(pos)
		var r: LevelRoad = near[0]
		var i: int = near[1]
		var out := {"kind": kind}
		match kind:
			"gman":
				var s := r.s[i] if r != null else 0.0
				out["pos"] = _r3(pos)
				out["yaw"] = yaw
				out["s"] = snappedf(s, 0.1)
				out["model"] = "gman_high"
				out["window"] = [snappedf(s - 40.0, 0.1), snappedf(s + 40.0, 0.1)]
				out["chance"] = snappedf(clampf(float(e.get("chance", 0.5)), 0.0, 1.0), 0.001)
				_route(out, r)
			"holo":
				var gap := _gap_near(r, pos)
				if gap.is_empty():
					egg_issues.append([{"left": 1, "count": 1, "why": "the hologram needs a jump on its road"},
						{"uid": int(e.get("uid", 0)), "road": r.key if r != null else -1, "pos": pos}])
					return {}
				out["pos"] = _r3(pos)
				out["yaw"] = yaw
				out["gap"] = gap
				_route(out, r)
			"lamarr", "zombies":
				var path := []
				for q in e.get("path", []):
					path.append(_r3(_v3(q)))
				if path.size() < 2:
					egg_issues.append([{"left": 1, "count": 1, "why": "%s needs a path of two points or more" % (
						"Lamarr" if kind == "lamarr" else "the zombies")}, {"uid": int(e.get("uid", 0)), "pos": pos}])
					return {}
				out["path"] = path
				if kind == "zombies":
					out["count"] = clampi(int(e.get("count", 3)), 1, 40)
					out["model"] = "zombie/classic"
			"birds":
				out["species"] = str(e.get("species", "pigeon"))
				out["center"] = _r3(pos)
				out["radius"] = snappedf(clampf(float(e.get("radius", 6.0)), 4.0, 60.0), 0.01)
				out["count"] = clampi(int(e.get("count", 8)), 1, 40)
			"gnome":
				out["pos"] = _r3(pos)
				out["yaw"] = yaw
			"nihilanth":
				out["pos"] = _r3(pos)
		return out

	## [road, sample] nearest to p in plan over every kept road ([null, 0] without roads).
	func _nearest_road(p: Vector3) -> Array:
		var best: LevelRoad = null
		var bi := 0
		var bd := INF
		for r in ctx.roads:
			if r == null or r.n == 0:
				continue
			for i in r.n:
				var d := Vector2(r.pos[i].x - p.x, r.pos[i].z - p.z).length_squared()
				if d < bd:
					bd = d
					best = r
					bi = i
		return [best, bi]

	## The road metres [s0, s1] of the jump gap of r nearest to p, [] when r has none.
	func _gap_near(r: LevelRoad, p: Vector3) -> Array:
		if r == null:
			return []
		var best := []
		var bd := INF
		for g in r.gaps:
			var a := r.wrap(g.x)
			var b := r.wrap(g.y - 1)
			var mid := r.wrap(g.x + (g.y - g.x) / 2)
			var d := Vector2(r.pos[mid].x - p.x, r.pos[mid].z - p.z).length_squared()
			if d < bd:
				bd = d
				var s0 := r.s[a]
				var s1 := s0 + (g.y - 1 - g.x) * r.step if r.uniform else r.s[b]
				best = [snappedf(s0, 0.1), snappedf(s1, 0.1)]
		return best

	func _route(out: Dictionary, r: LevelRoad) -> void:
		if r != null and r.key != -1:
			out["route"] = "b%d" % r.key

	# ------------------------------------------------------------ groups

	## One group's entry (its members appended to people), {} when nobody joined.
	func group(g: Dictionary, gi: int, people: Array) -> Dictionary:
		var uid := int(g.get("uid", 0))
		var length := clampf(float(g.get("length", 20.0)), 6.0, 120.0)
		var rows := clampi(int(g.get("rows", 2)), 1, 4)
		var density := clampf(float(g.get("density", 1.0)), 0.5, 2.0)
		var setback := clampf(float(g.get("setback", 2.5)), 0.5, 20.0)
		var sit := clampf(float(g.get("sit", 0.0)), 0.0, 1.0)
		var role := str(g.get("role", "citizen"))
		if not role in LevelCrowds.ROLES:
			role = "citizen"
		var mood := str(g.get("mood", "fan"))
		if not mood in LevelCrowds.MOODS:
			mood = "fan"
		var side := -1 if int(g.get("side", 1)) < 0 else 1
		var step := maxf(SPACING, 1.0 / density)
		var per_row := int(floor(length / step)) + 1
		var r := ctx.road(int(g.get("road", -1)))
		var at = g.get("at", {})
		if r == null or r.n < 2 or not (at is Dictionary):
			_drop("branch", uid, per_row * rows, true)
			return {}
		var s := r.anchor_s(at)
		var rng := ctx.rng(uid)
		var pal := LevelCrowds.palette(role, models)
		where_of[uid] = {"uid": uid, "road": r.key, "s": s, "pos": r.pos[r.idx(s)]}
		var mine := []
		for row in rows:
			var line := _side_line(r, s, length * 0.5 + 6.0, side, setback + ROW_GAP * row)
			if line.is_empty():
				_drop("ground", uid, per_row, true)
				continue
			# odd rows sit between the people in front (a stand's stagger)
			var u0 := -length * 0.5 + (step * 0.5 if row % 2 == 1 else 0.0)
			var k := 0
			while true:
				var u := u0 + k * step
				if u > length * 0.5 + 1e-4:
					break
				k += 1
				wanted += 1
				var seated := rng.randf() < sit
				# the jitter never brings two of the group closer than SPACING
				var ja := minf(JITTER, maxf(0.0, (step - SPACING) * 0.5))
				var jl := JITTER if rows == 1 else minf(JITTER, maxf(0.0, (ROW_GAP - SPACING) * 0.5))
				var du := rng.randf_range(-ja, ja)
				var dl := rng.randf_range(-jl, jl)
				var pick := rng.randi()
				var yaw_n := clampf(rng.randfn(0.0, 0.18), -0.4, 0.4)
				var seed_n := rng.randi() & 0x3fffffff
				if pal.is_empty():
					_drop("model", uid)
					continue
				if people.size() >= MAX_PEOPLE:
					_drop("limit", uid)
					continue
				var spot := _at(line, u + du, dl)
				if spot.is_empty():
					_drop("end", uid)
					continue
				var q: Vector3 = spot[0]
				var why := fail(q, bool(spot[1]), seated, false)
				if why != "":
					_drop(why, uid)
					continue
				var c: Vector3 = spot[2]
				var d := Vector3(c.x - q.x, 0.0, c.z - q.z)
				var yaw := atan2(d.x, d.z) + yaw_n
				var i := r.idx(s + u)
				var m := {"pos": _r3(q), "yaw": snappedf(yaw, 0.001), "model": pal[pick % pal.size()], "role": role,
					"mood": mood, "pose": "sit" if seated else "stand", "group": gi, "seed": seed_n,
					"lod": LevelCrowds.LOD_CYCLE[people.size() % 20], "dodge": _dodge(r, i, setback + ROW_GAP * row)}
				if not bool(spot[1]):
					m["on"] = "geom"
				people.append(m)
				mine.append(q)
				_take(q, seated)
		if mine.is_empty():
			return {}
		var center := Vector3.ZERO
		for q in mine:
			center += q
		center /= float(mine.size())
		var rad := 0.0
		for q in mine:
			rad = maxf(rad, Vector2(q.x - center.x, q.z - center.z).length())
		var bed := ""
		if mine.size() >= BED_MIN:
			bed = "human" if role in HUMAN_BEDS else ("alien" if role in ALIEN_BEDS else "")
		var tags := []
		for t in g.get("tags", []):
			if str(t) in ["start", "jump"] and not str(t) in tags:
				tags.append(str(t))
		var e := {"id": gi, "s": snappedf(s, 0.1), "side": side, "kind": "line", "role": role,
			"watch": [snappedf(s - length * 0.5 - 10.0, 0.1), snappedf(s + length * 0.5 + 10.0, 0.1)],
			"center": _r3(center), "radius": snappedf(rad + 1.0, 0.01), "bed": bed, "tags": tags}
		if r.key != -1:
			e["route"] = "b%d" % r.key
		return e

	## A row's side line from s - half to s + half: [[spot, on_ground, road centre, arc]] per
	## sample, arc 0 abreast of s.
	func _side_line(r: LevelRoad, s: float, half: float, side: int, setback: float) -> Array:
		# the side line of a bend's outside is longer than the centre's: half again as much
		var n := int(ceil((half * 1.5 + 6.0) / maxf(r.step, 0.1)))
		var out := []
		var i0 := r.idx(s)
		var arc := 0.0
		var prev := Vector3.ZERO
		var zero_at := 0
		for k in range(-n, n + 1):
			var j := i0 + k
			if not r.closed and (j < 0 or j >= r.n):
				continue
			j = r.wrap(j)
			var q := ctx.side_point(r, j, side, setback)
			var g := ctx.ground(q.x, q.z)
			var on_ground := not is_nan(g) and absf(g - q.y) < 1e-3
			if not out.is_empty():
				arc += Vector2(q.x - prev.x, q.z - prev.z).length()
			if k == 0:
				zero_at = out.size()
			out.append([q, on_ground, r.pos[j], arc, j])
			prev = q
		if out.is_empty():
			return []
		var a0: float = out[zero_at][3]
		for e in out:
			e[3] = float(e[3]) - a0
		return out

	## [spot, on_ground, road centre] at arc u along a side line, moved dl across (outwards); []
	## past the line's ends (an open road's end).
	func _at(line: Array, u: float, dl: float) -> Array:
		if line.size() < 2 or u < float(line[0][3]) or u > float(line[-1][3]):
			return []
		var k := 0
		while k < line.size() - 2 and float(line[k + 1][3]) < u:
			k += 1
		var a: Array = line[k]
		var b: Array = line[mini(k + 1, line.size() - 1)]
		var span := float(b[3]) - float(a[3])
		var t := 0.0 if span < 1e-6 else clampf((u - float(a[3])) / span, 0.0, 1.0)
		var q: Vector3 = (a[0] as Vector3).lerp(b[0], t)
		var c: Vector3 = (a[2] as Vector3).lerp(b[2], t)
		var out_dir := Vector3(q.x - c.x, 0.0, q.z - c.z)
		if out_dir.length_squared() > 1e-9 and dl != 0.0:
			q += out_dir.normalized() * dl
		var on_ground := bool(a[1]) and bool(b[1])
		if on_ground:
			q.y = ctx.ground(q.x, q.z)
		return [q, on_ground, c]

	func _dodge(r: LevelRoad, i: int, setback: float) -> bool:
		if r.kind(i) != "open":
			return false
		return setback <= float(r.style_at(i).get("verge_w", 4.0)) + DODGE_PAST

	# ------------------------------------------------------------ the rules (crowd_fail)

	## Why q breaks the rules, "" when it does not (spacing only with `alone` false).
	func fail(q: Vector3, on_ground: bool, seated: bool, alone: bool) -> String:
		if is_nan(q.y):
			return "ground"
		var why := _roads(q)
		if why != "":
			return why
		for pt in ctx.pits:
			if pt is Dictionary and pt.get("center") is Vector2:
				if Vector2(q.x, q.z).distance_to(pt.center) <= float(pt.get("radius", 0.0)):
					return "pit"
		if q.y < sea + 0.1:
			return "water"
		for w in waters:
			if not (w is Dictionary):
				continue
			var c = w.get("center", [0, 0])
			var sz = w.get("size", [0, 0])
			if absf(q.x - float(c[0])) <= float(sz[0]) * 0.5 and absf(q.z - float(c[1])) <= float(sz[1]) * 0.5 \
					and q.y < float(w.get("level", 0.0)) + 0.1:
				return "water"
		if on_ground and _slope(q) > SLOPE_MAX:
			return "slope"
		if _in_prop(q):
			return "prop"
		if _reserved(q):
			return "hazard"
		for b in bodies:
			if Vector2(b.x - q.x, b.z - q.z).length() < EGG_BODY and absf(b.y - q.y) < 2.0:
				return "egg"
		if not alone and _taken(q, SPACING_SIT if seated else SPACING):
			return "close"
		return ""

	## The road rules: on a road surface, over a drop beside one, under a deck.
	func _roads(q: Vector3) -> String:
		var c0 := _cell(q)
		var reach := int(ceil(REACH / CELL))
		var best := {}       # road index -> [gap, sample]
		var under := false
		for dx in range(-reach, reach + 1):
			for dz in range(-reach, reach + 1):
				var k := Vector2i(c0.x + dx, c0.y + dz)
				if not grid.has(k):
					continue
				for code in grid[k]:
					var ri: int = code >> 20
					var i: int = code & 0xfffff
					var r: LevelRoad = ctx.roads[ri]
					var d := Vector3(q.x - r.pos[i].x, 0.0, q.z - r.pos[i].z)
					var fw := Vector3(r.fwd[i].x, 0.0, r.fwd[i].z)
					if fw.length_squared() > 1e-9:
						fw = fw.normalized()
					var along := d.dot(fw)
					var lat := d.dot(r.flat_right[i])
					var hw := r.width[i] * 0.5
					var gap := absf(lat) - hw if absf(along) <= r.step * 0.6 else d.length() - hw
					if absf(q.y - r.pos[i].y) <= ROAD_DY and (not best.has(ri) or gap < float(best[ri][0])):
						best[ri] = [gap, i]
					if absf(along) > r.step * 0.6 or r.gap[i] == 1 or r.skip[i] == 1:
						continue
					var kind := r.kind(i)
					var deck := hw + (r.treatment(i, 1 if lat >= 0.0 else -1) if kind == "bridge" else 0.0)
					if absf(lat) > deck:
						continue
					var surf := r.pos[i].y + r.right[i].y * clampf(lat, -hw, hw)
					var above := surf - q.y
					var thick := float(r.style_at(i).get("skirt_h", 1.5)) if kind == "bridge" else 0.5
					if above > BODY.x and above - thick < BODY.y:
						under = true
		for ri in best:
			var gap: float = best[ri][0]
			var i: int = best[ri][1]
			var r: LevelRoad = ctx.roads[ri]
			if gap < ROAD_GAP:
				return "road"
			if r.pit[i] == 1 and gap < PIT_REACH and q.y < r.pos[i].y + 0.5:
				return "pit"
		return "under" if under else ""

	func _slope(q: Vector3) -> float:
		var gx0 := ctx.ground(q.x - 0.5, q.z)
		var gx1 := ctx.ground(q.x + 0.5, q.z)
		var gz0 := ctx.ground(q.x, q.z - 0.5)
		var gz1 := ctx.ground(q.x, q.z + 0.5)
		if is_nan(gx0) or is_nan(gx1) or is_nan(gz0) or is_nan(gz1):
			return 0.0
		return Vector2(gx1 - gx0, gz1 - gz0).length()

	func _add_prop(e: Variant) -> void:
		if not (e is Dictionary):
			return
		var info = models.get(str(e.get("model", "")))
		if not (info is Dictionary) or not (info.get("aabb_min") is Array) or not (info.get("aabb_max") is Array):
			return
		var p := _v3(e.get("pos"))
		var sc := float(e.get("scale", 1.0))
		var a := _v3(info.aabb_min) * sc
		var z := _v3(info.aabb_max) * sc
		var box := [p, float(e.get("yaw", 0.0)), a, z]
		var rad := sqrt(maxf(a.x * a.x, z.x * z.x) + maxf(a.z * a.z, z.z * z.z)) + PROP_MARGIN
		var c0 := _cell(p - Vector3(rad, 0, rad))
		var c1 := _cell(p + Vector3(rad, 0, rad))
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				var k := Vector2i(cx, cz)
				if not props.has(k):
					props[k] = []
				(props[k] as Array).append(box)

	func _in_prop(q: Vector3) -> bool:
		for box in props.get(_cell(q), []):
			var p: Vector3 = box[0]
			var a: Vector3 = box[2]
			var z: Vector3 = box[3]
			if q.y < p.y + a.y - 2.0 or q.y > p.y + z.y:
				continue
			var l := (q - p).rotated(Vector3.UP, -float(box[1]))
			if l.x >= a.x - PROP_MARGIN and l.x <= z.x + PROP_MARGIN and l.z >= a.z - PROP_MARGIN and l.z <= z.z + PROP_MARGIN:
				return true
		return false

	func _reserved(q: Vector3) -> bool:
		var p2 := Vector2(q.x, q.z)
		for res in ctx.reserved:
			if not (res is Array) or (res as Array).size() < 2 or not (res[0] is PackedVector3Array):
				continue
			var line: PackedVector3Array = res[0]
			var rr := float(res[1])
			for j in line.size():
				var a := Vector2(line[j].x, line[j].z)
				var b := a if j == line.size() - 1 else Vector2(line[j + 1].x, line[j + 1].z)
				var ab := b - a
				var t := 0.0 if ab.length_squared() < 1e-9 else clampf((p2 - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
				if (a + ab * t).distance_to(p2) <= rr:
					return true
		return false

	func _taken(q: Vector3, r: float) -> bool:
		var c := Vector2i(floori(q.x), floori(q.z))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for m in members.get(Vector2i(c.x + dx, c.y + dz), []):
					var p: Vector3 = m
					if absf(p.y - q.y) < 1.5 and Vector2(p.x - q.x, p.z - q.z).length() < r - 1e-3:
						return true
		return false

	func _take(q: Vector3, _seated: bool) -> void:
		var c := Vector2i(floori(q.x), floori(q.z))
		if not members.has(c):
			members[c] = []
		(members[c] as Array).append(q)

	func _drop(why: String, uid: int, n := 1, bulk := false) -> void:
		if bulk:
			wanted += n
		left[why] = int(left.get(why, 0)) + n
		left_by[uid] = int(left_by.get(uid, 0)) + n

	## [[args, where]] of the `crowd` warnings: the members left out (where = the group that lost
	## most), then each dropped egg.
	func issues(built: int) -> Array:
		var out := []
		var n := 0
		for k in left:
			n += int(left[k])
		if n > 0:
			var why := left.keys()
			why.sort_custom(func(a, b): return int(left[a]) > int(left[b]) or (int(left[a]) == int(left[b]) and str(a) < str(b)))
			var words := PackedStringArray()
			for k in why.slice(0, 3):
				words.append("%d %s" % [int(left[k]), str(WHY.get(k, k))])
			var worst := -1
			var most := 0
			for u in left_by:
				if int(left_by[u]) > most:
					most = int(left_by[u])
					worst = int(u)
			var where: Dictionary = where_of.get(worst, {"uid": worst}).duplicate()
			out.append([{"left": n, "count": maxi(wanted, built + n), "why": ", ".join(words)}, where])
		out.append_array(egg_issues)
		return out

	static func _cell(p: Vector3) -> Vector2i:
		return Vector2i(floori(p.x / CELL), floori(p.z / CELL))

	static func _v3(v: Variant) -> Vector3:
		if v is Vector3:
			return v
		if v is Array and (v as Array).size() >= 3:
			return Vector3(float(v[0]), float(v[1]), float(v[2]))
		return Vector3.ZERO

	static func _r3(v: Vector3) -> Array:
		return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]
