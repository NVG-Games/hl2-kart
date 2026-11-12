class_name TrackBranch
extends TrackPath
## A branch of the main loop (shortcut, jump, high road): an open path that leaves the lap at
## a fork and rejoins it at a merge (data["branches"], see tools/track_gen.py), plus how its
## metres count on the lap (s_main) and what drivers, the AI and the scanner need to know.

## metres over which a kart's lap metres hand over from the main road's to s_main at a nose
const BLEND := 10.0

var id := ""
var title := ""
var index := 0
## jump | ledge | high | tube | alt | trail
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
	for v in d["path"].get("s_main", []):
		s_main.append(v)
	if s_main.size() != n:
		# no mapping exported: spread the lap stretch evenly over the branch
		s_main.resize(n)
		for i in n:
			s_main[i] = lerpf(fork_s, merge_s, u_of(i) / maxf(length, 0.001))


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
