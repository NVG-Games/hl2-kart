class_name TrackBranch
extends TrackPath
## A branch of the main loop (shortcut, jump, high road): an open path that leaves the lap at
## a fork and rejoins it at a merge (data["branches"], see tools/track_gen.py), plus how its
## metres count on the lap (s_main) and what drivers, the AI and the scanner need to know.
## A cave (kind "cave") has no fork: its road begins at a dead end under the lap, and a kart gets
## onto it only by falling through one of its drops (Kart._track_route); out at its merge it earns
## the cave's bonus (Kart.cave_bonus).

## metres over which a kart's lap metres hand over from the main road's to s_main at a nose
const BLEND := 10.0

var id := ""
var title := ""
var index := 0
## jump | ledge | high | tube | alt | trail | cave
var kind := "alt"
## lap metres of the fork / merge and their exported main sample indices (the indices here
## and of the noses are filled in by TrackPath.add_branches when the data leaves them out)
var fork_s := 0.0
var merge_s := 0.0
var fork_i := 0
var merge_i := 0
## branch metres of the two noses (where the roads part for good) and their main indices
var fork_nose_u := 0.0
var merge_nose_u := 0.0
var fork_nose_i := 0
var merge_nose_i := 0
var side := 1
var merge_side := 1
var saves := 0.0
## 0 safe .. 1 brutal (AI)
var risk := 0.0
## launch speed its jumps need (m/s, 0 for none) and whether only a boost reaches it
var need_speed := 0.0
var need_boost := false
var ai_take := 0.5
var ai_min_skill := 0.0
## metres before this branch's jump gap from which a computer driver goes flat out at it and fires
## a boost it held for it (data "ai" "commit"; shorter where a bend comes close to the kicker)
var ai_commit := 40.0
## where a kart that falls off is put back: before | after | main
var respawn := "before"
var retry_back := 45.0
## lateral off-track limit on this branch (-1: the circuit's)
var offtrack := -1.0
var merge_type := "gore"
var in_hall := false
## lap metres per sample (monotone, fork_s .. merge_s)
var s_main := PackedFloat32Array()
## a cave's openings beside the main road (data "drops", tools/branches.py), each {s0, s1: lap
## metres; side: +1 right of the main road; lat0, lat1: metres out from its centre on that side
## (its edge, the cave's far wall); top: the edge's height; floor: the cave road's under it; u0, u1:
## cave metres}; none on any other branch
var drops: Array[Dictionary] = []
## what driving a cave out earns (data "bonus"): a boost of that many seconds at that power, and an
## item from the crates' pool for a kart holding none
var bonus_boost := 0.0
var bonus_power := 1.0
var bonus_item := false
## ... drawn from the pool the last kart draws from (the strongest items), whatever its place
var bonus_best := false
## cave metres up to which a kart that got onto a cave fell into it (past the end of its last drop
## by 10 m); one that got on further on came down its way out backwards
var fell_in_u := -1.0


func _init(d: Dictionary, k: int) -> void:
	super(d["path"], true)
	index = k
	id = str(d.get("id", "branch%d" % k))
	title = str(d.get("name", id))
	kind = str(d.get("kind", "alt"))
	fork_s = float(d["fork_s"])
	merge_s = float(d["merge_s"])
	fork_i = int(d.get("fork_i", -1))
	merge_i = int(d.get("merge_i", -1))
	fork_nose_u = float(d.get("fork_nose_u", 0.0))
	merge_nose_u = float(d.get("merge_nose_u", length))
	fork_nose_i = int(d.get("fork_nose_i", -1))
	merge_nose_i = int(d.get("merge_nose_i", -1))
	side = int(d.get("side", 1))
	merge_side = int(d.get("merge_side", side))
	saves = float(d.get("saves", 0.0))
	risk = float(d.get("risk", 0.0))
	need_speed = float(d.get("need_speed", 0.0))
	need_boost = bool(d.get("need_boost", false))
	var ai: Dictionary = d.get("ai", {})
	ai_take = float(ai.get("take", 0.5))
	ai_min_skill = float(ai.get("min_skill", 0.0))
	ai_commit = float(ai.get("commit", 40.0))
	respawn = str(d.get("respawn", "before"))
	retry_back = float(d.get("retry_back", 45.0))
	offtrack = float(d.get("offtrack", -1.0))
	merge_type = str(d.get("merge_type", "gore"))
	in_hall = bool(d.get("in_hall", false))
	if kind == "cave":
		for e: Dictionary in d.get("drops", []):
			var dd := {}
			for key in ["s0", "s1", "lat0", "lat1", "top", "floor", "u0", "u1"]:
				dd[key] = float(e.get(key, 0.0))
			dd["side"] = 1.0 if float(e.get("side", 1)) > 0.0 else -1.0
			drops.append(dd)
			fell_in_u = maxf(fell_in_u, dd["u1"] + 10.0)
		var bn: Dictionary = d.get("bonus", {})
		bonus_boost = float(bn.get("boost", 2.0))
		bonus_power = float(bn.get("power", 1.15))
		bonus_item = bool(bn.get("item", true))
		bonus_best = bool(bn.get("best_item", false))
	for v in d["path"].get("s_main", []):
		s_main.append(v)
	if s_main.size() != n:
		# no mapping exported: spread the lap stretch evenly over the branch
		s_main.resize(n)
		for i in n:
			s_main[i] = lerpf(fork_s, merge_s, u_of(i) / maxf(length, 0.001))


## The drop of this cave whose opening holds `p`, at lap metres `s` on the main loop `main`: its
## index, -1 for none (or on any other branch). The box reaches a metre past either end of the
## opening, half a metre in over the main road's edge, a metre past the far wall, 3 m over the edge
## and down to a metre under the cave's floor.
func drop_at(p: Vector3, s: float, main: TrackPath) -> int:
	for k in drops.size():
		var d := drops[k]
		if s < d["s0"] - 1.0 or s > d["s1"] + 1.0 or p.y > d["top"] + 3.0 or p.y < d["floor"] - 1.0:
			continue
		var lat: float = main.lateral(p, main.index_at(s)) * d["side"]
		if lat >= d["lat0"] - 0.5 and lat <= d["lat1"] + 1.0:
			return k
	return -1


## How far the road at u is still the main road's (1 from the fork to BLEND metres before
## its nose and from BLEND metres past the merge nose on, 0 in between): there a kart counts
## the main road's own lap metres, so leaving or rejoining it never moves its race position.
func shared(u: float) -> float:
	return maxf(smoothstep(fork_nose_u, fork_nose_u - BLEND, u), smoothstep(merge_nose_u, merge_nose_u + BLEND, u))


## Lap metres for branch metres u.
func main_s(u: float) -> float:
	var f := _frac(u)
	var i := mini(int(f), n - 2)
	return lerpf(s_main[i], s_main[i + 1], f - i)


## Branch metres for lap metres s (fork_s..merge_s): where main_s first reaches s.
func u_at_main(s: float) -> float:
	if s <= s_main[0]:
		return 0.0
	if s >= s_main[n - 1]:
		return length
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if s_main[mid] < s:
			lo = mid
		else:
			hi = mid
	var t := (s - s_main[lo]) / maxf(s_main[hi] - s_main[lo], 0.0001)
	return lerpf(u_of(lo), u_of(hi), t)


## Metres from u to the start of the next jump gap on the branch (0 inside one, INF if none).
func gap_ahead(u: float) -> float:
	for i in range(index_at(u), n):
		if gap[i] == 1:
			return maxf(u_of(i) - u, 0.0)
	return INF


## Start (branch metres) of the gap u is in, or of the first one starting within `within`
## metres ahead of u; INF if neither (the "before" respawn retries from in front of it).
func gap_start_at_or_ahead(u: float, within: float) -> float:
	var i := index_at(u)
	if gap[i] == 1:
		while i > 0 and gap[i - 1] == 1:
			i -= 1
		return u_of(i)
	var d := gap_ahead(u)
	return u + d if d <= within else INF
