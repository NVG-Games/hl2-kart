class_name CrowdLook
extends SkeletonModifier3D
## Turns the head and upper spine about the skeleton's up axis toward `target`
## (and tilts the head toward it), after the AnimationPlayer has posed the bones.
## Rig-agnostic: works the same on ValveBiped, the vortigaunt rig and HL1 bipeds.

var head := -1
var spine := -1  # Spine4 / the vortigaunt's spine4: takes 30 % of the yaw
var target := Vector3.ZERO  # world point, set by the director (the group's focus)
var goal := 1.0  # weight the director wants; `weight` eases toward it
var weight := 0.0
var max_yaw := 1.2  # 70 degrees
var max_pitch := 0.35
var _yaw := 0.0
var _pitch := 0.0


func setup(sk: Skeleton3D) -> bool:
	head = BipedPose.limb(sk, "Head1")
	spine = BipedPose.limb(sk, "Spine4")
	return head >= 0


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or head < 0:
		return
	weight = move_toward(weight, goal, delta * 1.5)
	var hp := sk.get_bone_global_pose(head)
	var d := sk.global_transform.affine_inverse() * target - hp.origin
	var k := 1.0 - exp(-delta * 6.0)
	_yaw = lerp_angle(_yaw, clampf(atan2(d.x, d.z), -max_yaw, max_yaw) * weight, k)
	_pitch = lerpf(_pitch, clampf(atan2(d.y, Vector2(d.x, d.z).length()), -max_pitch, max_pitch) * weight, k)
	var head_yaw := _yaw
	if spine >= 0:
		var sp := sk.get_bone_global_pose(spine)
		sk.set_bone_global_pose(spine, Transform3D(Basis(Vector3.UP, _yaw * 0.3) * sp.basis, sp.origin))
		hp = sk.get_bone_global_pose(head)
		head_yaw = _yaw * 0.7
	# pitch about the sideways axis the head ends up with after the yaw
	var side := Basis(Vector3.UP, _yaw) * Vector3.RIGHT
	var r := Basis(side, -_pitch) * Basis(Vector3.UP, head_yaw)
	sk.set_bone_global_pose(head, Transform3D(r * hp.basis, hp.origin))
