class_name Showroom
extends SubViewportContainer
## Live 3D preview of a racer standing next to their chosen (tinted) vehicle.

var vp: SubViewport
var stage: Node3D
var turntable: Node3D
var cam: Camera3D
var _t := 0.0


func _init(px: Vector2i) -> void:
	stretch = true
	custom_minimum_size = Vector2(px)
	vp = SubViewport.new()
	vp.size = px
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	stage = Node3D.new()
	vp.add_child(stage)
	cam = Camera3D.new()
	cam.position = Vector3(0.3, 1.75, 8.0)
	cam.rotation_degrees = Vector3(-6, 0, 0)
	cam.fov = 33.0
	stage.add_child(cam)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.5
	key.shadow_enabled = true
	stage.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-2.5, 3.0, -2.5)
	rim.light_color = Color(1.0, 0.8, 0.45)
	rim.light_energy = 2.5
	rim.omni_range = 9.0
	stage.add_child(rim)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.52, 0.58)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	stage.add_child(env)
	var floor_mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 4.6
	disc.bottom_radius = 4.6
	disc.height = 0.1
	floor_mi.mesh = disc
	floor_mi.position = Vector3(0, -0.05, 0)
	floor_mi.material_override = SourceMaterials.world_material("concrete/concretefloor028c", Vector2(3, 3))
	stage.add_child(floor_mi)
	turntable = Node3D.new()
	stage.add_child(turntable)


func show_character(c: Dictionary, index: int, vehicle_id := "buggy") -> void:
	for n in turntable.get_children():
		n.queue_free()
	var who := Game.spawn_model(c["model"], "showroom")
	who.rotation.y = 0.3
	who.position = Vector3(-1.6, 0, 1.7)
	turntable.add_child(who)
	var sks := who.find_children("*", "Skeleton3D", true, false)
	if sks.size() > 0:
		BipedPose.standing(sks[0])
	var k := Kart.new()
	k.char_data = c
	k.character_id = c["id"]
	k.racer_index = 90 + index
	k.spec = VehicleSpec.get_spec(vehicle_id)
	k.wheels = k.spec.wheels
	# pull the camera back for the APCs so the whole hull stays in frame
	var ref := VehicleSpec.get_spec("buggy")
	var f := maxf(1.0, maxf(k.spec.length / ref.length, k.spec.height / ref.height))
	cam.position = Vector3(0.3, 1.75 + (f - 1.0) * 1.6, 8.0 * f)
	var kv := KartVisual.new()
	kv.position = Vector3(1.4 + (f - 1.0) * 1.5, 0, -1.0 - (f - 1.0) * 2.0)
	kv.rotation.y = -2.25
	turntable.add_child(kv)
	kv.setup(k)
	kv.driver.visible = false
	kv.set_process(false)
	# the Kart only feeds data to the visual here; it never enters the tree
	kv.tree_exiting.connect(func():
		if is_instance_valid(k):
			k.free())


func _process(delta: float) -> void:
	_t += delta
	turntable.rotation.y = sin(_t * 0.35) * 0.3
