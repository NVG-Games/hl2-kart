class_name BreenFeed
extends SubViewport
## Live Breencast: Dr. Breen's head rendered off-screen for monitors (start
## arch, the Combine screens of HL2 maps), with his broadcasts on a speaker.

const SCREEN_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D feed : source_color, filter_linear;
uniform bool flip = true;
void fragment() {
	vec2 uv = vec2(flip ? 1.0 - UV.x : UV.x, UV.y);
	vec3 c = texture(feed, fract(uv)).rgb;
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(vec3(lum), c, 0.35) * vec3(0.75, 0.95, 1.15);
	float scan = 0.82 + 0.18 * sin(UV.y * 900.0 + TIME * 30.0);
	float vig = smoothstep(0.85, 0.3, length(fract(UV) - 0.5));
	ALBEDO = c * scan * (0.55 + 0.6 * vig) * 1.6 + vec3(0.02, 0.05, 0.08);
}
"""

static var _shader: Shader
var breen_skel: Skeleton3D
var head_bone := -1
var _t := 0.0


func _init() -> void:
	size = Vector2i(512, 288)
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _ready() -> void:
	var breen := Game.spawn_model("breen", "screen")
	add_child(breen)
	var sks := breen.find_children("*", "Skeleton3D", true, false)
	if sks.size() > 0:
		breen_skel = sks[0]
		BipedPose.standing(breen_skel)
		head_bone = BipedPose.bone(breen_skel, "ValveBiped.Bip01_Head1")
	var head := Vector3(0, 1.65, 0.05)
	if head_bone >= 0:
		head = breen_skel.get_bone_global_pose(head_bone).origin
	var cam := Camera3D.new()
	cam.fov = 26.0
	add_child(cam)
	cam.look_at_from_position(head + Vector3(0.08, 0.02, 0.85), head + Vector3(0, 0.04, 0), Vector3.UP)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-20, 25, 0)
	key.light_energy = 1.3
	add_child(key)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.09, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.5, 0.6)
	env.environment = e
	add_child(env)


## Material showing this feed (scanlines, Combine blue tint).
func screen_material(flip := true) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SCREEN_SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("feed", get_texture())
	m.set_shader_parameter("flip", flip)
	return m


func _process(delta: float) -> void:
	_t += delta
	if breen_skel and head_bone >= 0:
		# slow, deliberate head movement while he lectures
		var rest := breen_skel.get_bone_global_rest(head_bone)
		var r := Basis(Vector3.UP, sin(_t * 0.4) * 0.12) * Basis(Vector3.RIGHT, sin(_t * 0.27) * 0.05)
		breen_skel.set_bone_global_pose(head_bone, Transform3D(r * rest.basis, rest.origin))
