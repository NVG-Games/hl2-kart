class_name CrowdActor
extends Node3D
## One spectator: its model, skeleton and an AnimationPlayer on the baked crowd
## clips, a look-at modifier while it is near the camera, the clip the director
## queued for it (the passing wave) and the hop out of a kart's way.

var model: Node3D
var skel: Skeleton3D
var player: AnimationPlayer
var look: CrowdLook
var key := ""
var role := &"citizen"
var mood := &"fan"
var rng_seed := 0
var base_yaw := 0.0
var home := Vector3.ZERO
var dodge := false
var seated := false
var lap_s := 0.0  # metres along its group's road where it stands (wave timing)
var clip := &"idle"
var _queued := &""
var _queued_at := 0.0
var _toward: Variant = null  # where to turn when the queued clip starts
var _idle_at := 0.0  # a one-shot (salute, bow) goes back to idle then
var _dodge_until := 0.0
var _speed := 1.0


static func now() -> float:
	return Time.get_ticks_msec() * 0.001


## Place the spectator described by the track data entry `m` with the model `model_key`;
## its meshes fade out at `vis_end` metres.
func setup(m: Dictionary, model_key: String, vis_end: float) -> void:
	key = model_key
	role = StringName(str(m.get("role", "citizen")))
	mood = StringName(str(m.get("mood", "fan")))
	rng_seed = int(m.get("seed", 0))
	dodge = bool(m.get("dodge", false))
	seated = str(m.get("pose", "stand")) == "sit"
	var p: Array = m["pos"]
	position = Vector3(p[0], p[1], p[2])
	home = position
	base_yaw = float(m.get("yaw", 0.0))
	rotation.y = base_yaw
	model = Game.spawn_model(key)
	add_child(model)
	set_range(vis_end)
	var sks := model.find_children("*", "Skeleton3D", true, false)
	skel = sks[0] if sks.size() > 0 else null
	if role == &"metrocop" and skel and Game.models.has("weapons/w_stunbaton"):
		_baton()


## No shadows, no GI (skinned spectators must not count as static), a fade at `vis_end`,
## and room for raised arms outside the rest-pose bounds.
func set_range(vis_end: float) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var g := mi as GeometryInstance3D
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		g.visibility_range_end = vis_end
		g.visibility_range_end_margin = 10.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		g.extra_cull_margin = 0.6


## The clips of this model (shared by everyone wearing it): starts idling at a seeded
## phase and speed, then freezes until the director wakes it up. `manual`: the director
## advances it and its look-at (a few times a second, CrowdDirector.HOT_HZ), not the scene tree.
func animate(lib: AnimationLibrary, manual := true) -> void:
	if skel == null:
		return
	player = AnimationPlayer.new()
	if manual:
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		skel.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	model.add_child(player)
	player.root_node = NodePath("..")
	player.add_animation_library("", lib)
	_speed = 0.85 + float(rng_seed % 36) / 100.0
	player.speed_scale = _speed
	play(&"idle", 0.0)
	player.seek(fposmod(float(rng_seed % 1000) * 0.0137, CrowdPoses.clip_length(&"idle") * 2.0), true)
	player.active = false


func play(clip_name: StringName, blend := 0.25) -> void:
	clip = clip_name
	if player == null:
		return
	var c := String(clip_name)
	if seated:
		c = CrowdPoses.SEATED.get(c, "sit_idle")
	if c in CrowdPoses.MIRRORED and rng_seed % 10 < 3:
		c += "_m"
	if not player.has_animation(c):
		return
	player.play(c, blend)
	var hold := CrowdPoses.clip_hold(StringName(c))
	_idle_at = now() + CrowdPoses.clip_length(StringName(c)) / _speed + hold if hold > 0.0 else 0.0


## Start `clip_name` at time `at` (the director's wave runs along a stand this way), turned
## toward the point `toward` if one is given.
func queue(clip_name: StringName, at: float, toward: Variant = null) -> void:
	if now() < _dodge_until:
		return
	_queued = clip_name
	_queued_at = at
	_toward = toward


func pending() -> bool:
	return _queued != &"" or _idle_at > 0.0


## Called by the director for actors that are near enough to animate.
func update(t: float) -> void:
	if _queued != &"" and t >= _queued_at:
		var q := _queued
		_queued = &""
		play(q)
		if _toward is Vector3:
			face(_toward)
		elif q == &"idle":
			face_home()
	elif _idle_at > 0.0 and t >= _idle_at:
		_idle_at = 0.0
		play(&"shamble" if role == &"zombie" else &"idle")
		face_home()


func set_active(on: bool) -> void:
	if player and player.active != on:
		player.active = on


## Stand stock still (the G-Man went by) or carry on.
func hold(on: bool) -> void:
	if player:
		player.speed_scale = 0.0 if on else _speed


## Turn the body toward `p` (at most 60 degrees off the way it was placed).
func face(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() < 0.5:
		return
	_turn_to(base_yaw + clampf(angle_difference(base_yaw, atan2(d.x, d.z)), -1.05, 1.05))


func face_home() -> void:
	_turn_to(base_yaw)


func _turn_to(yaw: float) -> void:
	var d := angle_difference(rotation.y, yaw)
	if absf(d) < 0.05:
		return
	create_tween().tween_property(self, "rotation:y", rotation.y + d, 0.35)


## A kart is coming straight at this pavement spectator: hop aside, cower, walk back.
func dodge_from(kart_pos: Vector3, kart_vel: Vector3) -> bool:
	var t := now()
	var flat := Vector3(kart_vel.x, 0.0, kart_vel.z)
	if t < _dodge_until or flat.length() < 2.0:
		return false
	var side := flat.normalized().cross(Vector3.UP)
	var dir := side if (global_position - kart_pos).dot(side) >= 0.0 else -side
	_dodge_until = t + 3.6
	_queued = &""
	play(&"cower", 0.1)
	var tw := create_tween()
	tw.tween_property(self, "position", home + dir * (1.2 + float(rng_seed % 9) * 0.1), 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.0)
	tw.tween_callback(play.bind(&"idle", 0.4))
	tw.tween_property(self, "position", home, 1.2)
	return true


## Hidden while the camera is inside it (pavement spectators by the road).
func hide_near_camera(cam_pos: Vector3) -> void:
	visible = (global_position + Vector3.UP).distance_to(cam_pos) > 1.2


## Metrocop: the stun baton in the right hand. The weapon model is made for bonemerge,
## so it sits at the inverse of its own hand bone.
func _baton() -> void:
	var hand := BipedPose.limb(skel, "R_Hand")
	if hand < 0:
		return
	var at := BoneAttachment3D.new()
	at.bone_name = skel.get_bone_name(hand)
	skel.add_child(at)
	var baton := Game.spawn_model("weapons/w_stunbaton")
	at.add_child(baton)
	var wsks := baton.find_children("*", "Skeleton3D", true, false)
	if wsks.is_empty():
		return
	var wsk: Skeleton3D = wsks[0]
	var wh := BipedPose.limb(wsk, "R_Hand")
	if wh >= 0:
		baton.transform = (baton.global_transform.affine_inverse() * wsk.global_transform * wsk.get_bone_global_rest(wh)) \
			.affine_inverse()
	for mi in baton.find_children("*", "MeshInstance3D", true, false):
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
