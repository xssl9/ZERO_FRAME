class_name SoldierBlood
extends Node3D

## Cosmetic wounds only. Never changes health or starts a death on a client.
## Bone-local wounds follow animation and physics; droplets stay in world space.
const MAX_WOUNDS := 12
const MAX_STAINS := 32
const BLEED_SECONDS := 24.0
const STAIN_SHADER := preload("res://shaders/blood_stain.gdshader")
var skeleton: Skeleton3D
var ragdoll: SoldierRagdoll
var wounds: Array[Dictionary] = []
var stains: Array[MeshInstance3D] = []
var _sample_clock := 0.0

func configure(rig: Skeleton3D, physics: SoldierRagdoll) -> void:
	skeleton = rig
	ragdoll = physics
	# Do not inherit the imported skeleton's centimetre scale.
	top_level = true
	global_transform = Transform3D.IDENTITY

func add_wound(point: Vector3, direction: Vector3, bone: String, zone: String) -> void:
	if skeleton == null or skeleton.find_bone(bone) < 0 or not point.is_finite() or not direction.is_finite():
		return
	if wounds.size() >= MAX_WOUNDS:
		var oldest: Dictionary = wounds.pop_front()
		(oldest.emitter as CPUParticles3D).queue_free()
	var pose := ragdoll.bone_world_transform(bone)
	var emitter := CPUParticles3D.new()
	emitter.name = "Wound_" + zone
	emitter.amount = 60 if zone == "neck" else 30
	emitter.lifetime = 0.55
	emitter.local_coords = false
	emitter.direction = -direction.normalized()
	emitter.spread = 18.0 if zone == "neck" else 28.0
	emitter.gravity = Vector3(0, -12.0, 0)
	emitter.initial_velocity_min = 1.2 if zone == "neck" else 0.5
	emitter.initial_velocity_max = 3.5 if zone == "neck" else 1.8
	# Tiny flat quads — look like droplets, not balls
	emitter.scale_amount_min = 0.3
	emitter.scale_amount_max = 0.9
	emitter.scale_amount_curve = null
	# Flatten along velocity so they streak
	emitter.anim_speed_min = 0.0
	emitter.anim_speed_max = 0.0
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.004, 0.008)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.08, 0.001, 0.002)
	material.roughness = 0.15
	material.metallic = 0.0
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	emitter.mesh = mesh
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(emitter)
	emitter.global_position = point
	wounds.append({"bone": bone, "offset": pose.affine_inverse() * point,
		"direction": pose.basis.inverse() * -direction.normalized(), "zone": zone,
		"age": 0.0, "emitter": emitter})

func _physics_process(delta: float) -> void:
	if not is_instance_valid(skeleton):
		return
	_sample_clock += delta
	var sample := _sample_clock >= 0.3
	if sample:
		_sample_clock = 0.0
	for wound: Dictionary in wounds:
		wound.age += delta
		var emitter := wound.emitter as CPUParticles3D
		var pose := ragdoll.bone_world_transform(wound.bone)
		emitter.global_position = pose * (wound.offset as Vector3)
		emitter.direction = (pose.basis * (wound.direction as Vector3)).normalized()
		var pressure := maxf(0.0, 1.0 - float(wound.age) / BLEED_SECONDS)
		# No perpetual arterial pump after death: pressure rapidly subsides.
		if ragdoll.running:
			pressure *= exp(-ragdoll.age / 5.0)
		emitter.emitting = pressure > 0.025
		emitter.initial_velocity_min = 0.08 + pressure * 0.5
		emitter.initial_velocity_max = 0.15 + pressure * (2.25 if wound.zone == "neck" else 1.05)
		if sample and emitter.emitting:
			_deposit(emitter.global_position, pressure)

func _deposit(point: Vector3, pressure: float) -> void:
	# Only real nearby world surfaces receive blood; never floating floor quads.
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.03, point + Vector3.DOWN * 2.5, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var position: Vector3 = hit.position
	for stain: MeshInstance3D in stains:
		if stain.global_position.distance_to(position) < 0.24:
			var size := minf(stain.scale.x + 0.012 * pressure, 0.7)
			stain.scale = Vector3.ONE * size
			return
	if stains.size() >= MAX_STAINS:
		return
	var stain := MeshInstance3D.new()
	stain.name = "BloodStain"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	stain.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = STAIN_SHADER
	material.set_shader_parameter("seed", float(stains.size()) * 7.13)
	stain.material_override = material
	stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stain)
	stain.global_position = position + (hit.normal as Vector3) * 0.006
	stain.quaternion = Quaternion(Vector3.UP, hit.normal)
	stain.scale = Vector3.ONE * 0.13
	stains.append(stain)
