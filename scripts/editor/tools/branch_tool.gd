class_name BranchTool
extends EditorTool
## 1.6 BRANCH: forks and shortcuts the bots use, in three steps. While the tool is active the main
## road shows the legal-spot tint (build.flags branch_fork / branch_merge, 3.6 #14): green where a
## fork (step 1) or a merge (step 2) may sit, red elsewhere. Step 1: a click on the main road puts
## the FORK on the nearest green exported sample (a click on red is refused with the reason); step
## 2: clicks on the ground add the branch's points, a click on the main road ahead the MERGE; step 3:
## Enter or a double click finishes (one undo step), Esc cancels. Fork / merge markers slide along
## the main road (snapping to green), the branch's points edit like the road's (RoadTool's point
## methods), Delete on a branch marker deletes the branch. P13.

const KINDS := ["branch", "branch_point"]
## A branch end marker's sub (EditorHit.sub): 3 the fork, 4 the merge; a point's "+" dot is 5.
const SUB_FORK := 3
const SUB_MERGE := 4
const SUB_MID := 5
const MAX_BRANCHES := 8
const MAX_POINTS := 100
const NAME_LEN := 24
const KIND_IDS := ["alt", "jump", "ledge", "high", "trail"]
const KIND_NAMES := ["ALT ROUTE", "SHORTCUT JUMP", "LEDGE", "HIGH ROAD", "TRAIL"]
const RESPAWN_IDS := ["before", "after", "main"]
const RESPAWN_NAMES := ["BACK BEFORE IT", "AFTER IT", "ON THE MAIN ROAD"]
const SIDES := ["AUTO", "LEFT", "RIGHT"]
const DEFAULT_WIDTH := 10.0
const REFUSE := "Forks need a straight, unbanked open road, street or bridge"

const OK_TINT := Color(0.3, 0.9, 0.35, 0.35)
const BAD_TINT := Color(0.95, 0.25, 0.2, 0.3)
const FORK_COLOR := Color(0.35, 1.0, 0.45)
const MERGE_COLOR := Color(1.0, 0.45, 0.35)
const POINT_COLOR := Color(0.75, 1.0, 0.75)
const DRAFT_COLOR := Color(1.0, 0.61, 0.0)
const NOSE_COLOR := Color(1.0, 0.55, 0.0)
const MID_COLOR := Color(0.75, 1.0, 0.85)
## Why no branch can start yet while the main road is not a closed loop.
const TEXT_OPEN := "Close the loop first ({ed_close_loop}): branches fork off a closed lap."

## The branch being made: {fork: anchor, fork_pos, points: [dict], merge: anchor | null,
## merge_pos} ({} when none); its step is step().
var draft := {}
## The last refusal (the status line shows it).
var refusal := ""

var _drag := {}          # a fork / merge marker slide: {uid, end}


func _init(ed: TrackEditor) -> void:
	super(ed)
	id = "branch"
	title = "BRANCH"
	purpose = "Forks and shortcuts that leave the road and rejoin it; the bots take them"


func kinds() -> PackedStringArray:
	return PackedStringArray(KINDS)


func deactivate() -> void:
	cancel()
	var rt := road_tool()
	if rt != null:
		rt._cancel_drag(false)


func options(box: VBoxContainer) -> void:
	var n := (editor.doc.data.get("branches", []) as Array).size() if editor != null and editor.doc != null else 0
	box.add_child(EditorKit.row("BRANCHES", UiKit.label("%d of %d" % [n, MAX_BRANCHES], EditorKit.FONT_SMALL, UiKit.TEXT)))
	box.add_child(EditorKit.button("CANCEL THIS BRANCH", cancel, "{ed_cancel}"))
	box.add_child(EditorKit.hint("1 CLICK THE ROAD WHERE IT LEAVES (GREEN) · 2 CLICK THE GROUND TO LAY IT OUT, THEN THE ROAD WHERE IT REJOINS · 3 {ed_finish} FINISH"))


func road_tool() -> RoadTool:
	return editor.tools.get("road") as RoadTool


## 1 = waiting for the fork, 2 = laying out (merge not yet), 3 = merge placed (Enter finishes).
func step() -> int:
	if draft.is_empty():
		return 1
	return 3 if draft.get("merge") is Dictionary else 2


func status_step() -> String:
	if refusal != "":
		return refusal
	match step():
		1:
			if main_open():
				return TEXT_OPEN
			return "Click the road where the branch leaves"
		2:
			return "Click the ground to lay it out, then the road where it rejoins"
		_:
			return "{ed_finish} to finish, {ed_cancel} to cancel"


func hints(hit: EditorHit) -> Array:
	if hit == null:
		return []
	if hit.what == "marker":
		match hit.kind:
			"branch":
				return [["DRAG SLIDE ALONG THE ROAD"], ["CLICK SELECT THE BRANCH"], ["{ed_delete} DELETE THE BRANCH"]]
			"branch_point":
				if hit.sub == SUB_MID:
					return [["DRAG ADD A POINT HERE"]]
				if hit.sub == 1 or hit.sub == 2:
					return [["DRAG TURN THE CURVE"], ["DOUBLE CLICK AUTO"]]
				return [["CLICK SELECT"], ["DRAG MOVE"], ["{ed_mod_shift} DRAG HEIGHT"], ["{ed_mod_ctrl} WHEEL WIDTH"], ["{ed_delete} DELETE"]]
			"issue":
				return [["CLICK SHOW THE PROBLEM"]]
	var on_main := hit.what == "road" and hit.road == -1
	match step():
		1:
			if main_open():
				return [["{ed_close_loop} CLOSE THE LOOP FIRST"]]
			if on_main:
				return [["CLICK FORK HERE"] if legal_at("fork", hit.s) else ["NO FORK HERE"]]
			return [["CLICK THE ROAD: WHERE THE BRANCH LEAVES"]]
		2:
			if on_main:
				return [["CLICK MERGE HERE"] if legal_at("merge", hit.s) else ["NO MERGE HERE"], ["{ed_cancel} CANCEL"]]
			return [["CLICK ADD A POINT"], ["{ed_cancel} CANCEL"]]
	return [["{ed_finish} FINISH"], ["DOUBLE CLICK FINISH"], ["{ed_cancel} CANCEL"]]


# ---------------------------------------------------------------- legal spots

## The flags of an end ("fork" / "merge"); `buid` > 0: that kept branch's own (its stretches free).
func flags_for(end: String, buid := 0) -> PackedByteArray:
	return LevelFixes.legal_flags(editor.build, end, buid)


func main_road() -> LevelRoad:
	return LevelFixes.road_of(editor.build, -1)


## True while the main road is open (or has under 3 points): no fork flags exist until it closes.
func main_open() -> bool:
	var road = editor.doc.data.get("road") if editor != null and editor.doc != null else null
	return not (road is Dictionary and bool(road.get("closed", false)) and (road.get("points", []) as Array).size() >= 3)


## The exported sample of a spot s metres along the main road.
func sample_of(s_m: float) -> int:
	var m := main_road()
	var f := flags_for("fork")
	if m == null or f.is_empty():
		return -1
	return posmod(roundi(s_m / (3.0 * m.step)), f.size())


func legal_at(end: String, s_m: float, buid := 0) -> bool:
	var f := flags_for(end, buid)
	var e := sample_of(s_m)
	return e >= 0 and e < f.size() and f[e] == 1


## Snaps a spot to the nearest green sample (when the clicked one is green itself or next to it):
## {anchor, pos, e} or {} (refused: `refusal` says why).
func snap(end: String, s_m: float, buid := 0) -> Dictionary:
	refusal = ""
	if main_open():
		refusal = TEXT_OPEN
		return {}
	var m := main_road()
	var f := flags_for(end, buid)
	if m == null or f.is_empty():
		refusal = "Wait for the bake to finish, then click again."
		return {}
	var e := sample_of(s_m)
	if f[e] != 1:
		refusal = refusal_reason(end, e)
		return {}
	var at := LevelFixes.nearest_legal(m, f, s_m)
	if at < 0:
		refusal = refusal_reason(end, e)
		return {}
	var i := mini(at * 3, m.n - 1)
	var a := m.s_to_anchor(m.s[i])
	if a.is_empty():
		return {}
	a.t = snappedf(float(a.t), LevelFixes.T_STEP)
	return {"anchor": a, "pos": m.pos[i], "e": at}


## Why a fork / merge cannot sit at exported sample e (the status line's words).
func refusal_reason(end: String, e: int) -> String:
	var m := main_road()
	if m == null:
		return REFUSE
	var i := mini(e * 3, m.n - 1)
	var lap := m.s[i] / maxf(m.length, 1.0)
	var word := "Forks" if end == "fork" else "Merges"
	if lap < 0.04 or lap > 0.96:
		return "%s keep away from the start line: between 4 %% and 96 %% of the lap." % word
	var k := m.kind(i)
	if not k in ["open", "street", "bridge"] or (m.seesaw.size() == m.n and m.seesaw[i] == 1):
		return "%s need an open road, a street or a bridge (not a tunnel or a see-saw)." % word
	if m.gap[i] == 1 or (m.lift.size() == m.n and m.lift[i] > 0.0):
		return "%s cannot share a jump." % word
	if m.radius_at(i) < 120.0:
		return "%s need a straight: this bend is tighter than 120 m." % word
	if m.bank_set.size() == m.n and m.bank_set[i] == 1:
		return "%s need an unbanked road: set that bank to AUTO." % word
	if end == "fork":
		return REFUSE
	return "Merges need a straight, unbanked open road, street or bridge, clear of other branches"


# ---------------------------------------------------------------- the three steps

func click(hit: EditorHit, mods: int) -> bool:
	if editor == null or editor.doc == null:
		return false
	if hit.what == "marker" and hit.kind in KINDS:
		if hit.kind == "branch":
			editor.select(PackedInt32Array([hit.uid]))
			return true
		return false
	var on_main := hit.what == "road" and hit.road == -1
	if step() == 1:
		if on_main:
			return place_fork(hit.s)
		return false
	# steps 2 and 3: the main road takes the merge, the ground another point (not once the merge
	# is down: a double click there finishes)
	if on_main:
		return place_merge(hit.s)
	if step() == 2:
		add_point(hit)
	return true


func double_click(hit: EditorHit, mods: int) -> bool:
	if step() == 3:
		finish()
		return true
	if hit.what == "marker" and hit.kind == "branch_point":
		road_tool().set_auto_handle(road_tool().road_of_point(hit.uid), hit.uid)
		return true
	return false


func place_fork(s_m: float) -> bool:
	if (editor.doc.data.get("branches", []) as Array).size() >= MAX_BRANCHES:
		refusal = "A track has at most %d branches." % MAX_BRANCHES
		editor.status(refusal)
		return true
	var sn := snap("fork", s_m)
	if sn.is_empty():
		editor.status(refusal)
		return true
	draft = {"fork": sn.anchor, "fork_pos": sn.pos, "fork_e": sn.e, "points": [], "merge": null}
	editor.status("")
	editor.redraw()
	return true


func place_merge(s_m: float) -> bool:
	if (draft.points as Array).is_empty():
		refusal = "Lay the branch out first: click the ground beside the road."
		editor.status(refusal)
		return true
	var sn := snap("merge", s_m)
	if sn.is_empty():
		editor.status(refusal)
		return true
	draft["merge"] = sn.anchor
	draft["merge_pos"] = sn.pos
	editor.status("")
	editor.redraw()
	return true


## Step 2: a branch point at the ground spot (FOLLOW GROUND on terrain).
func add_point(hit: EditorHit) -> void:
	var pts: Array = draft.points
	if pts.size() >= MAX_POINTS:
		return
	var rt := road_tool()
	var p := rt._ground_pos(hit)
	pts.append({"uid": 0, "pos": RoadTool._arr(p), "width": DEFAULT_WIDTH, "style": "asphalt", "follow": rt._on_terrain(hit)})
	editor.redraw()


## Step 3: the branch goes into the document (one undo step "ADD BRANCH").
func finish() -> int:
	if step() != 3:
		return 0
	var doc := editor.doc
	var buid := doc.new_uid()
	var pts := []
	for p in draft.points:
		var q: Dictionary = (p as Dictionary).duplicate(true)
		q.uid = doc.new_uid()
		pts.append(q)
	var n := (doc.data.get("branches", []) as Array).size() + 1
	var b := {"uid": buid, "name": "BRANCH %d" % n, "kind": "alt", "fork": draft.fork, "merge": draft.merge,
		"side": 0, "merge_side": 0, "points": pts, "ai": {"take": 0.5, "min_skill": 0.0, "commit": 40.0},
		"risk": 0.0, "respawn": "before", "retry_back": 45.0, "offtrack": -1.0}
	editor.commit("ADD BRANCH", [LevelDoc.op_insert(["branches"], -1, b)])
	draft = {}
	refusal = ""
	editor.select(PackedInt32Array([buid]))
	succeeded()
	return buid


func cancel() -> void:
	draft = {}
	refusal = ""
	if not _drag.is_empty() and editor != null and editor.history != null:
		editor.history.end_gesture()
	_drag = {}
	if editor != null:
		editor.redraw()


## Esc while the button holds a drag: a branch end's move taken back (its points: ROAD's rule).
func cancel_drag() -> void:
	if not _drag.is_empty():
		_drag = {}
		if editor != null and editor.history != null:
			editor.history.cancel_gesture()
		editor.redraw()
		return
	var rt := road_tool()
	if rt != null:
		rt._cancel_drag(true)


func key(ev: InputEvent) -> bool:
	if _act(ev, "ed_finish"):
		if step() == 3:
			finish()
			return true
		return false
	if _act(ev, "ed_cancel"):
		if not draft.is_empty() or not _drag.is_empty():
			cancel()
			return true
		return false
	return false


func _act(ev: InputEvent, action: String) -> bool:
	return InputMap.has_action(action) and ev.is_action_pressed(action, false, true)


# ---------------------------------------------------------------- drags

func drag_begin(hit: EditorHit, mods: int) -> bool:
	if hit.what != "marker":
		return false
	var rt := road_tool()
	if hit.kind == "branch" and (hit.sub == SUB_FORK or hit.sub == SUB_MERGE):
		_drag = {"uid": hit.uid, "end": "fork" if hit.sub == SUB_FORK else "merge"}
		editor.history.begin_gesture("MOVE BRANCH END")
		return true
	if hit.kind == "branch_point":
		var key := rt.road_of_point(hit.uid)
		if key == -2:
			return false
		if hit.sub == 1 or hit.sub == 2:
			return rt.begin_handle_drag(key, hit.uid, hit.sub, hit)
		if hit.sub == SUB_MID:
			return rt.begin_insert_drag(key, hit.uid, hit, mods)
		return rt.begin_point_drag(key, hit.uid, hit, mods)
	return false


func drag_move(hit: EditorHit, mods: int) -> void:
	if not _drag.is_empty():
		var ops := end_ops(int(_drag.uid), str(_drag.end), hit)
		if not ops.is_empty():
			editor.commit("MOVE BRANCH END", ops, "branch_end")
		return
	road_tool().drag_move(hit, mods)


func drag_end(hit: EditorHit, mods: int) -> void:
	if not _drag.is_empty():
		var ops := end_ops(int(_drag.uid), str(_drag.end), hit)
		if not ops.is_empty():
			editor.commit("MOVE BRANCH END", ops, "branch_end")
		editor.history.end_gesture()
		_drag = {}
		succeeded()
		return
	road_tool().drag_end(hit, mods)


## The fork / merge of a branch slid to the green sample nearest the cursor's road spot.
func end_ops(buid: int, end: String, hit: EditorHit) -> Array:
	var m := main_road()
	if m == null or m.n <= 0:
		return []
	var p := hit.pos if hit.hit else SelectTool._plane_point(hit, m.pos[0].y, m.pos[0])
	var s_m := m.s[m.closest(p)]
	if hit.what == "road" and hit.road == -1:
		s_m = hit.s
	var f := flags_for(end, buid)
	if f.is_empty():
		return []
	var e := LevelFixes.nearest_legal(m, f, s_m)
	if e < 0:
		return []
	var a := m.s_to_anchor(m.s[mini(e * 3, m.n - 1)])
	if a.is_empty():
		return []
	a.t = snappedf(float(a.t), LevelFixes.T_STEP)
	var br := branch(buid)
	if br.is_empty() or br.get(end) == a:
		return []
	return [LevelDoc.op_set(["branches", "#%d" % buid, end], a)]


func slide(uid: int, hit: EditorHit, phase: int) -> Array:
	if phase == 0:
		if hit.kind == "branch" and (hit.sub == SUB_FORK or hit.sub == SUB_MERGE):
			_drag = {"uid": uid, "end": "fork" if hit.sub == SUB_FORK else "merge"}
		return []
	if _drag.is_empty():
		return []
	var ops := end_ops(int(_drag.uid), str(_drag.end), hit)
	if phase == 2:
		_drag = {}
	return ops


func wheel(hit: EditorHit, mods: int, notches: int) -> bool:
	return road_tool().wheel(hit, mods, notches)


# ---------------------------------------------------------------- document

func branch(buid: int) -> Dictionary:
	for b in editor.doc.data.get("branches", []):
		if b is Dictionary and int(b.get("uid", 0)) == buid:
			return b
	return {}


## Delete: a branch with what is anchored on it; branch points one after the other.
func delete_ops(uids: PackedInt32Array) -> Array:
	var doc := editor.doc
	var out := []
	var points := PackedInt32Array()
	var gone := {}
	for u in uids:
		if editor.kind_of(u) == "branch":
			gone[u] = true
			out.append_array(doc._drop_road_ops(u))
	for u in uids:
		if editor.kind_of(u) == "branch_point" and not gone.has(road_tool().road_of_point(u)):
			points.append(u)
	if not points.is_empty():
		out.append_array(RoadTool.point_delete_ops(doc, points))
	return out


func item_aabb(uid: int) -> AABB:
	var k := editor.kind_of(uid)
	if k == "branch_point":
		return road_tool().item_aabb(uid)
	if k != "branch":
		return AABB()
	var br := branch(uid)
	var box := AABB()
	var first := true
	for p in br.get("points", []):
		var v := RoadTool._v3(p.get("pos"))
		if first:
			box = AABB(v, Vector3.ZERO)
			first = false
		else:
			box = box.expand(v)
	return box.grow(10.0) if not first else AABB()


# ---------------------------------------------------------------- markers, tint, overlay

func markers(m: EditorMarkers) -> void:
	if editor == null or editor.doc == null:
		return
	var main := main_road()
	var rt := road_tool()
	for b in editor.doc.data.get("branches", []):
		if not (b is Dictionary):
			continue
		var buid := int(b.get("uid", 0))
		if main != null and main.n > 0 and not main.partial:
			for end in ["fork", "merge"]:
				if b.get(end) is Dictionary:
					var i := main.idx(main.anchor_s(b[end]))
					m.add("branch", buid, main.pos[i] + main.up[i] * 0.4, EditorMarkers.Shape.BAR,
						FORK_COLOR if end == "fork" else MERGE_COLOR, 3.0, SUB_FORK if end == "fork" else SUB_MERGE)
		var pts: Array = b.get("points", [])
		for p in pts:
			if p is Dictionary:
				m.add("branch_point", int(p.get("uid", 0)), RoadTool._v3(p.get("pos")), EditorMarkers.Shape.DOT, POINT_COLOR, 2.0)
		if rt != null:
			rt.add_handles(m, buid, "branch_point")
			for k in pts.size() - 1:
				m.add("branch_point", int(pts[k].get("uid", 0)), rt.curve_at(buid, k, 0.5), EditorMarkers.Shape.PLUS, MID_COLOR, 1.6, SUB_MID)


func overlay(d: EditorDraw) -> void:
	if editor == null or editor.doc == null:
		return
	var m := main_road()
	if m != null and editor.tool == self:
		var end := "merge" if step() >= 2 else "fork"
		var buid := 0
		if not _drag.is_empty():
			end = str(_drag.end)
			buid = int(_drag.uid)
		var f := flags_for(end, buid)
		if not f.is_empty():
			d.flags_on_road(m, f, OK_TINT, BAD_TINT)
	var rt := road_tool()
	for b in editor.doc.data.get("branches", []):
		if b is Dictionary and rt != null:
			rt.draw_handle_lines(d, int(b.get("uid", 0)))
	# the noses (where the roads part) as orange ticks
	if m != null and editor.build != null:
		for e in editor.build.data.get("branches", []):
			if not (e is Dictionary):
				continue
			for k in ["fork_nose_i", "merge_nose_i"]:
				var i := int(e.get(k, -1)) * 3
				if i >= 0 and i < m.n:
					var w := m.width[i] * 0.5 + 2.0
					d.line(m.surface(i, -w, 0.5), m.surface(i, w, 0.5), NOSE_COLOR)
	if draft.is_empty():
		return
	var line := PackedVector3Array([draft.fork_pos])
	for p in draft.points:
		line.append(RoadTool._v3(p.pos))
	if draft.get("merge") is Dictionary:
		line.append(draft.merge_pos)
	elif editor.hover != null and editor.hover.hit:
		line.append(editor.hover.pos)
	d.polyline(line, DRAFT_COLOR, false, true)
	d.circle(draft.fork_pos, Vector3.UP, 3.0, FORK_COLOR)
	if draft.get("merge") is Dictionary:
		d.circle(draft.merge_pos, Vector3.UP, 3.0, MERGE_COLOR)


# ---------------------------------------------------------------- inspector

func inspect(uids: PackedInt32Array, box: VBoxContainer) -> bool:
	if uids.is_empty():
		return false
	var k := editor.kind_of(uids[0])
	if k == "branch_point":
		var rt := road_tool()
		rt.point_inspector(rt.road_of_point(uids[0]), uids, box)
		return true
	if k != "branch":
		return false
	var buid := uids[0]
	var b := branch(buid)
	if b.is_empty():
		return false
	var path := ["branches", "#%d" % buid]
	box.add_child(EditorKit.section("BRANCH"))
	var rename := func(t: String) -> void:
		var nm := t.strip_edges().to_upper().left(NAME_LEN)
		if nm != "" and nm != str(branch(buid).get("name", "")):
			editor.commit("RENAME BRANCH", [LevelDoc.op_set(path + ["name"], nm)])
	box.add_child(EditorKit.row("NAME", EditorKit.text(str(b.get("name", "")), rename, NAME_LEN)))
	box.add_child(EditorKit.row("KIND", EditorKit.choice(KIND_NAMES, maxi(KIND_IDS.find(str(b.get("kind", "alt"))), 0),
		func(i: int) -> void: editor.commit("BRANCH KIND", [LevelDoc.op_set(path + ["kind"], KIND_IDS[i])]))))
	var side := int(b.get("side", 0))
	box.add_child(EditorKit.row("SIDE", EditorKit.choice(SIDES, 0 if side == 0 else (1 if side < 0 else 2),
		func(i: int) -> void: editor.commit("BRANCH SIDE", [LevelDoc.op_set(path + ["side"], [0, -1, 1][i])]))))
	var ai: Dictionary = b.get("ai", {}) if b.get("ai") is Dictionary else {}
	box.add_child(EditorKit.row("BOTS TAKE IT", EditorKit.slider(0.0, 100.0, 1.0, float(ai.get("take", 0.5)) * 100.0,
		func(v: float) -> void: editor.commit("BOTS TAKE IT", [LevelDoc.op_set(path + ["ai", "take"], snappedf(v / 100.0, 0.01))], "br_take_%d" % buid),
		"%d %%")))
	box.add_child(EditorKit.row("ONLY BOTS WITH SKILL >=", EditorKit.number(float(ai.get("min_skill", 0.0)), 0.0, 1.0, 0.05,
		func(v: float) -> void: editor.commit("BOT SKILL", [LevelDoc.op_set(path + ["ai", "min_skill"], v)], "br_skill_%d" % buid), "%.2f")))
	box.add_child(EditorKit.row("RISK", EditorKit.number(float(b.get("risk", 0.0)), 0.0, 1.0, 0.05,
		func(v: float) -> void: editor.commit("RISK", [LevelDoc.op_set(path + ["risk"], v)], "br_risk_%d" % buid), "%.2f")))
	box.add_child(EditorKit.row("IF YOU FALL", EditorKit.choice(RESPAWN_NAMES, maxi(RESPAWN_IDS.find(str(b.get("respawn", "before"))), 0),
		func(i: int) -> void: editor.commit("IF YOU FALL", [LevelDoc.op_set(path + ["respawn"], RESPAWN_IDS[i])]))))
	var e := entry(buid)
	if not e.is_empty():
		var parts := PackedStringArray()
		parts.append("SAVES %d m" % roundi(float(e.get("saves", 0.0))))
		parts.append("NEEDS %d m/s" % roundi(float(e.get("need_speed", 0.0))))
		if bool(e.get("need_boost", false)):
			parts.append("BOOST ONLY")
		box.add_child(UiKit.label(" · ".join(parts), EditorKit.FONT_SMALL, UiKit.TEXT))
	elif editor.build != null:
		box.add_child(UiKit.label("Left out of the race: see its problems (F3).", EditorKit.FONT_SMALL, EditorKit.WARN_COLOR))
	box.add_child(EditorKit.hint("DRAG ITS ENDS ALONG THE ROAD · {ed_delete} DELETE THE BRANCH"))
	return true


## The bake's data.branches entry of a kept branch ({} when it was left out).
func entry(buid: int) -> Dictionary:
	if editor.build == null:
		return {}
	for e in editor.build.data.get("branches", []):
		if e is Dictionary and str(e.get("id", "")) == "b%d" % buid:
			return e
	return {}
