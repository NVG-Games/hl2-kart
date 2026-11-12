class_name CrowdPoses
## Spectator poses and clips. A pose aims limbs at directions in skeleton space
## (BipedPose: +Z forward, +Y up, +X the model's left); a clip strings poses into
## keys. Each model key's clips are baked once into an AnimationLibrary that all of
## its spectators' AnimationPlayers share, so playing them costs no script per frame.

const F := Vector3(0, 0, 1)
const U := Vector3(0, 1, 0)
const L := Vector3(1, 0, 0)

## Limb directions are Vector3(forward, up, side) with side toward the arm's own
## side: (0.05, -0.96, 0.2) on the right arm points 0.2 to the model's right.
## "arms": [upper arm, forearm] for both; "R" / "L": one arm (the other idles);
## "spine": where Spine -> Neck1 points; "spine_turn" / "head": [axis, radians] on
## top of the pose (axis "F", "U" or "L"); "legs": [thigh, calf]; "leg_L" / "leg_R":
## one thigh; "seated": the seated legs; "lift": metres the body leaves the floor.
const ARMS_IDLE := [Vector3(0.05, -0.96, 0.2), Vector3(0.3, -0.9, 0.05)]
const ARMS_CLAP_OPEN := [Vector3(0.5, -0.78, 0.36), Vector3(0.62, 0.5, -0.32)]
const ARMS_CLAP_SHUT := [Vector3(0.5, -0.78, 0.36), Vector3(0.62, 0.5, -0.62)]
const ARMS_CHEER_LOW := [Vector3(0.2, 0.35, 0.75), Vector3(0.2, 0.9, 0.0)]
const ARMS_CHEER_HIGH := [Vector3(0.0, 0.85, 0.45), Vector3(0.15, 0.95, 0.1)]
const ARMS_CROSSED := [Vector3(0.38, -0.82, 0.32), Vector3(0.3, 0.22, -0.92)]
const ARMS_HIPS := [Vector3(-0.2, -0.62, 0.62), Vector3(0.45, -0.45, -0.62)]
const ARMS_BOO := [Vector3(0.45, -0.72, 0.52), Vector3(0.32, 0.8, -0.5)]
const ARMS_SIT := [Vector3(0.45, -0.88, 0.18), Vector3(0.9, -0.3, -0.12)]
const ARMS_CHANT := [Vector3(0.25, -0.9, 0.3), Vector3(0.55, -0.35, 0.2)]
const BATON_L := [Vector3(0.55, -0.78, 0.2), Vector3(0.85, 0.25, -0.45)]
const LEGS_CROUCH := [Vector3(0.62, -0.75, 0.18), Vector3(-0.55, -0.82, 0.0)]

const POSES := {
	"idle_a": {},
	"idle_b": {"arms": [Vector3(0.08, -0.95, 0.24), Vector3(0.34, -0.88, 0.08)], "spine_turn": ["F", 0.06]},
	"clap_open": {"arms": ARMS_CLAP_OPEN},
	"clap_closed": {"arms": ARMS_CLAP_SHUT},
	"cheer_low": {"arms": ARMS_CHEER_LOW},
	"cheer_high": {"arms": ARMS_CHEER_HIGH},
	"fist_low": {"R": [Vector3(0.35, -0.3, 0.35), Vector3(0.3, 0.95, 0.05)]},
	"fist_high": {"R": [Vector3(0.25, 0.75, 0.35), Vector3(0.12, 0.95, 0.0)]},
	"wave_a": {"R": [Vector3(0.2, 0.4, 0.85), Vector3(0.15, 0.9, 0.4)]},
	"wave_b": {"R": [Vector3(0.2, 0.4, 0.85), Vector3(0.15, 0.9, -0.25)]},
	"point_a": {"R": [Vector3(0.95, 0.12, 0.12), Vector3(0.97, 0.1, 0.08)]},
	"point_b": {"R": [Vector3(0.92, 0.3, 0.12), Vector3(0.94, 0.28, 0.06)]},
	"crossed_a": {"arms": ARMS_CROSSED},
	"crossed_b": {"arms": ARMS_CROSSED, "head": ["U", 0.1]},
	"hips_a": {"arms": ARMS_HIPS},
	"hips_b": {"arms": ARMS_HIPS, "head": ["U", -0.1]},
	"boo_a": {"arms": ARMS_BOO, "head": ["L", -0.25]},
	"boo_b": {"arms": ARMS_BOO, "head": ["L", -0.25], "spine_turn": ["L", 0.1]},
	"baton_up": {"L": BATON_L, "R": [Vector3(0.45, -0.6, 0.3), Vector3(0.5, 0.75, -0.42)]},
	"baton_tap": {"L": BATON_L, "R": [Vector3(0.45, -0.6, 0.3), Vector3(0.8, 0.1, -0.5)]},
	"salute": {"R": [Vector3(0.45, 0.3, 0.75), Vector3(0.2, 0.75, -0.55)]},
	"bow": {"spine": Vector3(0.8, 0.6, 0.0), "arms": [Vector3(0.4, -0.9, 0.1), Vector3(0.65, -0.7, -0.2)]},
	"flinch": {"arms": [Vector3(0.6, 0.2, 0.45), Vector3(0.15, 0.6, -0.75)], "spine_turn": ["L", -0.15],
		"head": ["L", 0.2]},
	"shrug": {"arms": [Vector3(0.2, -0.85, 0.45), Vector3(0.7, 0.3, 0.6)], "head": ["F", 0.12]},
	"cower_a": {"spine": Vector3(0.5, 0.85, 0.0), "legs": LEGS_CROUCH,
		"arms": [Vector3(0.65, 0.55, 0.45), Vector3(0.2, 0.42, -0.82)]},
	"cower_b": {"spine": Vector3(0.53, 0.83, 0.03), "legs": LEGS_CROUCH,
		"arms": [Vector3(0.65, 0.57, 0.43), Vector3(0.2, 0.44, -0.8)]},
	"zombie_l": {"spine": Vector3(0.42, 0.88, 0.0), "arms": [Vector3(0.9, 0.08, 0.25), Vector3(0.95, 0.12, 0.05)],
		"leg_L": Vector3(0.3, -0.95, 0.0)},
	"zombie_r": {"spine": Vector3(0.42, 0.88, 0.0), "arms": [Vector3(0.9, 0.08, 0.25), Vector3(0.95, 0.12, 0.05)],
		"leg_R": Vector3(0.3, -0.95, 0.0)},
	"jump_crouch": {"spine": Vector3(0.3, 0.95, 0.0), "legs": [Vector3(0.62, -0.75, 0.12), Vector3(-0.55, -0.82, 0.0)],
		"arms": ARMS_CHEER_LOW},
	"jump_air": {"legs": [Vector3(0.4, -0.9, 0.0), Vector3(-0.42, -0.9, 0.0)], "arms": ARMS_CHEER_HIGH, "lift": 0.3},
	"jump_land": {"arms": ARMS_CHEER_HIGH},
	"sit_a": {"seated": true, "arms": ARMS_SIT},
	"sit_b": {"seated": true, "arms": ARMS_SIT, "head": ["U", 0.12]},
	"sit_clap_open": {"seated": true, "arms": ARMS_CLAP_OPEN},
	"sit_clap_closed": {"seated": true, "arms": ARMS_CLAP_SHUT},
	"sit_cheer_low": {"seated": true, "arms": ARMS_CHEER_LOW},
	"sit_cheer_high": {"seated": true, "arms": ARMS_CHEER_HIGH},
	"tie_a": {"R": [Vector3(0.55, -0.75, 0.2), Vector3(0.3, 0.85, -0.35)]},
	"tie_b": {"R": [Vector3(0.55, -0.73, 0.2), Vector3(0.32, 0.86, -0.38)], "head": ["U", 0.06]},
	"sway_l": {"arms": ARMS_CHANT, "spine_turn": ["F", 0.1]},
	"sway_r": {"arms": ARMS_CHANT, "spine_turn": ["F", -0.1]},
}

enum Loop { NONE, LINEAR, PING }

## clip: keys [[pose, seconds], ...], length, loop, seconds a one-shot holds before idling again
const CLIPS := {
	"idle": [[["idle_a", 0.0], ["idle_b", 1.8]], 1.8, Loop.PING, 0.0],
	"clap": [[["clap_open", 0.0], ["clap_closed", 0.16]], 0.16, Loop.PING, 0.0],
	"cheer": [[["cheer_low", 0.0], ["cheer_high", 0.35]], 0.35, Loop.PING, 0.0],
	"jump": [[["jump_crouch", 0.0], ["jump_air", 0.2], ["jump_land", 0.4], ["jump_crouch", 0.55]], 0.7, Loop.LINEAR, 0.0],
	"fist": [[["fist_low", 0.0], ["fist_high", 0.25]], 0.25, Loop.PING, 0.0],
	"wave": [[["wave_a", 0.0], ["wave_b", 0.3]], 0.3, Loop.PING, 0.0],
	"point": [[["point_a", 0.0], ["point_b", 0.6]], 0.6, Loop.PING, 0.0],
	"crossed": [[["crossed_a", 0.0], ["crossed_b", 1.5]], 1.5, Loop.PING, 0.0],
	"hips": [[["hips_a", 0.0], ["hips_b", 1.5]], 1.5, Loop.PING, 0.0],
	"boo": [[["boo_a", 0.0], ["boo_b", 0.45]], 0.45, Loop.PING, 0.0],
	"condemn": [[["baton_up", 0.0], ["baton_tap", 0.18], ["baton_up", 0.5]], 0.5, Loop.LINEAR, 0.0],
	"salute": [[["idle_a", 0.0], ["salute", 0.35]], 0.35, Loop.NONE, 1.6],
	"bow": [[["idle_a", 0.0], ["bow", 0.6]], 0.6, Loop.NONE, 1.4],
	"flinch": [[["idle_a", 0.0], ["flinch", 0.12]], 0.12, Loop.NONE, 0.7],
	"shrug": [[["idle_a", 0.0], ["shrug", 0.3]], 0.3, Loop.NONE, 0.9],
	"cower": [[["cower_a", 0.0], ["cower_b", 0.15]], 0.15, Loop.PING, 0.0],
	"shamble": [[["zombie_l", 0.0], ["zombie_r", 0.7]], 0.7, Loop.PING, 0.0],
	"sit_idle": [[["sit_a", 0.0], ["sit_b", 1.9]], 1.9, Loop.PING, 0.0],
	"sit_clap": [[["sit_clap_open", 0.0], ["sit_clap_closed", 0.17]], 0.17, Loop.PING, 0.0],
	"sit_cheer": [[["sit_cheer_low", 0.0], ["sit_cheer_high", 0.35]], 0.35, Loop.PING, 0.0],
	"tie": [[["tie_a", 0.0], ["tie_b", 1.2]], 1.2, Loop.PING, 0.0],
	"sway": [[["sway_l", 0.0], ["sway_r", 1.1]], 1.1, Loop.PING, 0.0],
}

## one-armed clips also baked mirrored ("<clip>_m"), for the left-handed
const MIRRORED := ["fist", "wave", "point", "salute"]
## a rig whose rest back leans further than this from upright (HL1's alien slaves stoop 60
## degrees, hands down to the floor) stands up to UPRIGHT in every pose without a "spine"
const HUNCH_COS := 0.77
const UPRIGHT := Vector3(0.3, 0.95, 0.0)
## what a seated spectator plays instead
const SEATED := {"idle": "sit_idle", "clap": "sit_clap", "cheer": "sit_cheer", "jump": "sit_cheer", "fist": "sit_cheer",
	"wave": "sit_cheer"}

static var _libs := {}


## Apply pose `name` to the skeleton (from its rest pose); returns how far the body
## must rise (or sink, negative) to keep its feet on the floor, or on the seat.
static func apply(sk: Skeleton3D, name: String, mirror := false) -> float:
	sk.reset_bone_poses()
	var p: Dictionary = POSES[name]
	var flip := -1.0 if mirror else 1.0
	# the HL1 HD scientist hangs his thighs off Spine: bend from Spine1 there
	var thigh := BipedPose.limb(sk, "L_Thigh")
	var waist := "Spine1" if thigh >= 0 and sk.get_bone_parent(thigh) == BipedPose.limb(sk, "Spine") else "Spine"
	var back: Vector3 = p["spine"] if p.has("spine") else (UPRIGHT if _hunched(sk, waist) else Vector3.ZERO)
	if back != Vector3.ZERO:
		BipedPose.aim_chain(sk, waist, "Neck1", F * back.x + U * back.y + L * back.z * flip)
	if p.has("spine_turn"):
		_turn(sk, waist, p["spine_turn"], flip)
	if p.has("head"):
		_turn(sk, "Head1", p["head"], flip)
	var both: Array = p.get("arms", ARMS_IDLE)
	var right: Array = p.get("L" if mirror else "R", both if not (p.has("L") or p.has("R")) else ARMS_IDLE)
	var left: Array = p.get("R" if mirror else "L", both if not (p.has("L") or p.has("R")) else ARMS_IDLE)
	_arm(sk, "L", 1.0, left)
	_arm(sk, "R", -1.0, right)
	if p.get("seated", false):
		BipedPose.seated_legs(sk)
		var pel := BipedPose.limb(sk, "Pelvis")
		return 0.12 - (sk.get_bone_global_rest(pel).origin.y if pel >= 0 else 0.95)
	for side in [["L", 1.0], ["R", -1.0]]:
		var s: String = side[0]
		var sg: float = side[1]
		var key := "leg_" + (s if not mirror else ("R" if s == "L" else "L"))
		if p.has("legs"):
			var legs: Array = p["legs"]
			BipedPose.aim(sk, s + "_Thigh", s + "_Calf", _dir(legs[0], sg))
			BipedPose.aim(sk, s + "_Calf", s + "_Foot", _dir(legs[1], sg))
		elif p.has(key):
			BipedPose.aim(sk, s + "_Thigh", s + "_Calf", _dir(p[key], sg))
	return BipedPose.foot_offset(sk) + float(p.get("lift", 0.0))


static func _dir(c: Vector3, sg: float) -> Vector3:
	return F * c.x + U * c.y + L * c.z * sg


## The back from `waist` to the neck (the head on rigs without one) leans more than HUNCH_COS
## allows in the pose the skeleton has now (its rest pose in apply()).
static func _hunched(sk: Skeleton3D, waist: String) -> bool:
	var w := BipedPose.limb(sk, waist)
	var n := BipedPose.limb(sk, "Neck1")
	if n < 0:
		n = BipedPose.limb(sk, "Head1")
	if w < 0 or n < 0:
		return false
	var d := sk.get_bone_global_pose(n).origin - sk.get_bone_global_pose(w).origin
	return d.length() > 0.01 and d.normalized().dot(U) < HUNCH_COS


static func _arm(sk: Skeleton3D, s: String, sg: float, a: Array) -> void:
	BipedPose.aim(sk, s + "_UpperArm", s + "_Forearm", _dir(a[0], sg), true)
	BipedPose.aim(sk, s + "_Forearm", s + "_Hand", _dir(a[1], sg), true)


## Turn a bone about a skeleton axis on top of its current pose (mirrored: the other way
## for sideways and yaw turns).
static func _turn(sk: Skeleton3D, b: String, spec: Array, flip: float) -> void:
	var bi := BipedPose.limb(sk, b)
	if bi < 0:
		return
	var axis: Vector3 = {"F": F, "U": U, "L": L}[spec[0]]
	var angle: float = spec[1] * (1.0 if spec[0] == "L" else flip)
	var g := sk.get_bone_global_pose(bi)
	sk.set_bone_global_pose(bi, Transform3D(Basis(axis, angle) * g.basis, g.origin))


## Every clip (and the mirrored ones) for the model `key`, baked on its skeleton `sk`
## (under `root`, the node its AnimationPlayers animate from) the first time it is asked for.
static func library(key: String, sk: Skeleton3D, root: Node) -> AnimationLibrary:
	if _libs.has(key):
		return _libs[key]
	var skel_path := String(root.get_path_to(sk))
	var rest := []
	for b in sk.get_bone_count():
		rest.append(sk.get_bone_rest(b).basis.get_rotation_quaternion())
	# every pose a clip uses, plus the mirrored ones: rotations of all bones and the lift
	var baked := {}
	var moved := {}
	for clip in CLIPS:
		for mirror in ([false, true] if clip in MIRRORED else [false]):
			for k in CLIPS[clip][0]:
				var pk := "%s|%s" % [k[0], mirror]
				if baked.has(pk):
					continue
				var lift := apply(sk, k[0], mirror)
				var rots := []
				for b in sk.get_bone_count():
					var q := sk.get_bone_pose_rotation(b)
					rots.append(q)
					if not q.is_equal_approx(rest[b]):
						moved[b] = true
				baked[pk] = [rots, lift]
	sk.reset_bone_poses()
	var roots := sk.get_parentless_bones()
	var root_bone := roots[0] if roots.size() > 0 else -1
	var lib := AnimationLibrary.new()
	for clip in CLIPS:
		for mirror in ([false, true] if clip in MIRRORED else [false]):
			var c: Array = CLIPS[clip]
			var a := Animation.new()
			a.length = c[1]
			a.loop_mode = [Animation.LOOP_NONE, Animation.LOOP_LINEAR, Animation.LOOP_PINGPONG][c[2]]
			for b in moved:
				var t := a.add_track(Animation.TYPE_ROTATION_3D)
				a.track_set_path(t, NodePath("%s:%s" % [skel_path, sk.get_bone_name(b)]))
				for k in c[0]:
					a.rotation_track_insert_key(t, k[1], baked["%s|%s" % [k[0], mirror]][0][b])
			if root_bone >= 0:
				var o := sk.get_bone_rest(root_bone).origin
				var t := a.add_track(Animation.TYPE_POSITION_3D)
				a.track_set_path(t, NodePath("%s:%s" % [skel_path, sk.get_bone_name(root_bone)]))
				for k in c[0]:
					a.position_track_insert_key(t, k[1], o + Vector3(0, baked["%s|%s" % [k[0], mirror]][1], 0))
			lib.add_animation(clip + ("_m" if mirror else ""), a)
	_libs[key] = lib
	return lib


## Length and hold of a clip (one-shots hold their last pose this long, then idle).
static func clip_length(clip: StringName) -> float:
	var c: Array = CLIPS.get(String(clip).trim_suffix("_m"), CLIPS["idle"])
	return c[1]


static func clip_hold(clip: StringName) -> float:
	var c: Array = CLIPS.get(String(clip).trim_suffix("_m"), CLIPS["idle"])
	return c[3] if c[2] == Loop.NONE else 0.0
