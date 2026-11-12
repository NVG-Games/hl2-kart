class_name HazardRig
## Procedural motion for hazard models (no animations are extracted): turn a bone
## about an axis through its rest origin in skeleton space (children follow), spin
## barrels and rotors, 2-bone IK for strider legs, a chain curl for the Xen tentacle,
## and model attachments (muzzles, the strider's cannon) at the current pose.

static var _attachments := {}


static func skeleton(root: Node) -> Skeleton3D:
	if root == null:
		return null
	var found := root.find_children("*", "Skeleton3D", true, false)
	return found[0] if not found.is_empty() else null


## Bone index by name; converted rigs may use "_" for "." and prefix the bones with the
## model's name ("Combine_Strider.Body_Bone"), so a bare "Body_Bone" also finds it.
static func bone(sk: Skeleton3D, bname: String) -> int:
	if sk == null or bname == "":
		return -1
	for n in [bname, bname.replace(".", "_")]:
		var i := sk.find_bone(n)
		if i >= 0:
			return i
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		if n.ends_with("." + bname) or n.ends_with("_" + bname):
			return i
	return -1


## Skeleton space <- model space (the model root's own frame), for a skeleton under it.
static func model_to_skeleton(model: Node3D, sk: Skeleton3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = sk
	while n != null and n != model:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf.affine_inverse()


## Turns bone bi (and everything under it) by `angle` about `axis` (skeleton space, at rest)
## through its rest origin, after the turn `parent` already given to the bones above it.
## Returns this bone's whole turn, to hand down to the next bone of the chain.
static func turn(sk: Skeleton3D, bi: int, axis: Vector3, angle: float, parent := Transform3D.IDENTITY) -> Transform3D:
	if bi < 0:
		return parent
	var rest := sk.get_bone_global_rest(bi)
	var o := parent * rest.origin
	var r := Basis((parent.basis * axis).normalized(), angle)
	var d := Transform3D(r, o - r * o) * parent
	sk.set_bone_global_pose(bi, d * rest)
	return d


## 2-bone IK in skeleton space: hip at `a`, upper length l1, lower length l2, foot target `t`,
## knee bending towards `pole`. Returns the knee position.
static func knee(a: Vector3, t: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
	var d := clampf(a.distance_to(t), 0.01, l1 + l2 - 0.001)
	var x := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - x * x, 0.0))
	var dir := (t - a).normalized()
	var side := (pole - a - dir * (pole - a).dot(dir)).normalized()
	return a + dir * x + side * h


## Points bone bi (rest direction `rest_dir`, skeleton space) along `dir`, keeping its origin
## where its parent put it. Used after knee() to lay a leg along the solved hip-knee-foot line.
static func point(sk: Skeleton3D, bi: int, rest_dir: Vector3, dir: Vector3) -> void:
	if bi < 0:
		return
	var g := sk.get_bone_global_pose(bi)
	var rest := sk.get_bone_global_rest(bi)
	var q := Quaternion(rest_dir.normalized(), dir.normalized())
	sk.set_bone_global_pose(bi, Transform3D(Basis(q) * rest.basis, g.origin))


## Curl a bone chain: bone i bends by angles[i] about `axis` (skeleton space) relative to its
## parent. It sets local pose rotations, so each bone carries the rest of the chain with it
## (exact for a planar curl: the axis does not change under rotations about itself).
static func curl(sk: Skeleton3D, chain: PackedInt32Array, axis: Vector3, angles: PackedFloat32Array) -> void:
	for i in chain.size():
		var bi := chain[i]
		if bi < 0:
			continue
		var parent := sk.get_bone_parent(bi)
		var pb := sk.get_bone_global_rest(parent).basis if parent >= 0 else Basis()
		var local_axis := (pb.inverse() * axis).normalized()
		var rest_q := sk.get_bone_rest(bi).basis.get_rotation_quaternion()
		sk.set_bone_pose_rotation(bi, Quaternion(local_axis, angles[i]) * rest_q)


## An attachment's position in model space at the rest pose (assets/models/<key>.json), and
## the bone it hangs on: [origin: Vector3, bone name: String], or [] when the model has none.
static func attachment(key: String, aname: String) -> Array:
	if not _attachments.has(key):
		var path := "res://assets/models/%s.json" % key
		var meta = Game.load_json(path) if FileAccess.file_exists(path) else {}
		_attachments[key] = meta.get("attachments", {}) if meta is Dictionary else {}
	var a: Dictionary = _attachments[key].get(aname, {})
	if a.is_empty():
		return []
	var o: Array = a["origin"]
	return [Vector3(o[0], o[1], o[2]), str(a.get("bone", ""))]


## World position of a point given in model space at rest that rides on bone bi, at the
## bone's current pose (an attachment, a muzzle).
static func follow(model: Node3D, sk: Skeleton3D, bi: int, rest_point: Vector3) -> Vector3:
	if sk == null or bi < 0:
		return model.global_transform * rest_point
	var m2s := model_to_skeleton(model, sk)
	var delta := sk.get_bone_global_pose(bi) * sk.get_bone_global_rest(bi).affine_inverse()
	return model.global_transform * (m2s.affine_inverse() * (delta * (m2s * rest_point)))
