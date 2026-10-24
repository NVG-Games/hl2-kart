class_name BipedPose
## Procedural poses for HL2 / HL1 humanoid skeletons. Limb names are logical
## ("L_Thigh", "R_Forearm") and resolve to ValveBiped.Bip01_* or to the
## vortigaunt rig. Bones are aimed at directions in skeleton space:
## +Z forward, +Y up, +X left.

const F := Vector3(0, 0, 1)
const U := Vector3(0, 1, 0)
const L := Vector3(1, 0, 0)

## vortigaunt rig (digitigrade legs, own spine/arm names)
const VORT := {
	"Pelvis": "hips", "Spine": "spine1", "Spine1": "spine2", "Head1": "head",
	"L_Thigh": "leg_bone1_L", "L_Calf": "leg_bone2_L", "L_Ankle": "leg_bone3_L",
	"R_Thigh": "leg_bone1_R", "R_Calf": "leg_bone2_R", "R_Ankle": "leg_bone3_R",
	"L_Clavicle": "clavical_L", "L_UpperArm": "arm1_L", "L_Forearm": "arm2_L", "L_Hand": "hand1_L",
	"R_Clavicle": "clavical_R", "R_UpperArm": "arm1_R", "R_Forearm": "arm2_R", "R_Hand": "hand1_R",
}


static func bone(sk: Skeleton3D, bname: String) -> int:
	var i := sk.find_bone(bname)
	if i < 0:
		i = sk.find_bone(bname.replace(".", "_"))
	return i


## Logical limb name -> bone index on this skeleton (-1 if absent).
static func limb(sk: Skeleton3D, logical: String) -> int:
	var i := bone(sk, "ValveBiped.Bip01_" + logical)
	if i < 0 and VORT.has(logical):
		i = bone(sk, "ValveBiped." + VORT[logical])
	return i


static func is_vort(sk: Skeleton3D) -> bool:
	return bone(sk, "ValveBiped.leg_bone3_L") >= 0


static func aim(sk: Skeleton3D, b: String, child: String, dir: Vector3) -> void:
	var bi := limb(sk, b)
	var ci := limb(sk, child)
	if bi < 0 or ci < 0:
		return
	var g := sk.get_bone_global_pose(bi)
	var cg := sk.get_bone_global_pose(ci)
	var cur := (cg.origin - g.origin).normalized()
	if cur.length() < 0.5:
		return
	var q := Quaternion(cur, dir.normalized())
	sk.set_bone_global_pose(bi, Transform3D(Basis(q) * g.basis, g.origin))


static func _legs_seated(sk: Skeleton3D, s: String, sg: float) -> void:
	aim(sk, s + "_Thigh", s + "_Calf", F * 0.93 + U * 0.3 + L * sg * 0.16)
	if is_vort(sk):
		aim(sk, s + "_Calf", s + "_Ankle", F * 0.2 - U * 0.98)
		aim(sk, s + "_Ankle", s + "_Foot", F * 0.7 - U * 0.4)
	else:
		aim(sk, s + "_Calf", s + "_Foot", F * 0.35 - U * 0.94 + L * sg * 0.03)
		aim(sk, s + "_Foot", s + "_Toe0", F * 0.85 + U * 0.1)


static func seated(sk: Skeleton3D) -> void:
	aim(sk, "Spine", "Spine1", U * 0.96 - F * 0.22)
	for side in [["L", 1.0], ["R", -1.0]]:
		var s: String = side[0]
		var sg: float = side[1]
		_legs_seated(sk, s, sg)
		aim(sk, s + "_UpperArm", s + "_Forearm", F * 0.62 - U * 0.72 + L * sg * 0.22)
		aim(sk, s + "_Forearm", s + "_Hand", F * 0.92 + U * 0.28 - L * sg * 0.28)


## Riding on someone's shoulders (Dog): legs spread around the neck, hands forward.
static func straddle(sk: Skeleton3D) -> void:
	aim(sk, "Spine", "Spine1", U * 0.97 + F * 0.12)
	for side in [["L", 1.0], ["R", -1.0]]:
		var s: String = side[0]
		var sg: float = side[1]
		aim(sk, s + "_Thigh", s + "_Calf", F * 0.7 - U * 0.2 + L * sg * 0.62)
		if is_vort(sk):
			aim(sk, s + "_Calf", s + "_Ankle", -U * 0.95 + F * 0.2)
			aim(sk, s + "_Ankle", s + "_Foot", -U * 0.6 + F * 0.6)
		else:
			aim(sk, s + "_Calf", s + "_Foot", -U * 0.95 + F * 0.22 - L * sg * 0.15)
			aim(sk, s + "_Foot", s + "_Toe0", F * 0.9 - U * 0.2)
		aim(sk, s + "_UpperArm", s + "_Forearm", F * 0.7 - U * 0.45 + L * sg * 0.25)
		aim(sk, s + "_Forearm", s + "_Hand", F * 0.85 + U * 0.1 - L * sg * 0.3)


## Relaxed standing pose instead of the reference A/T-pose.
static func standing(sk: Skeleton3D) -> void:
	for side in [["L", 1.0], ["R", -1.0]]:
		var s: String = side[0]
		var sg: float = side[1]
		aim(sk, s + "_UpperArm", s + "_Forearm", -U * 0.96 + L * sg * 0.2 + F * 0.05)
		aim(sk, s + "_Forearm", s + "_Hand", -U * 0.9 + F * 0.3 + L * sg * 0.05)


## Arms raised in victory.
static func cheering(sk: Skeleton3D) -> void:
	for side in [["L", 1.0], ["R", -1.0]]:
		var s: String = side[0]
		var sg: float = side[1]
		aim(sk, s + "_UpperArm", s + "_Forearm", U * 0.85 + L * sg * 0.45)
		aim(sk, s + "_Forearm", s + "_Hand", U * 0.95 + L * sg * 0.1 + F * 0.15)
