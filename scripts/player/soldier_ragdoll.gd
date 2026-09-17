class_name SoldierRagdoll
extends SkeletonModifier3D

## Metre-scale rigid bodies drive the imported, scaled skeleton after animation.
## Cosmetic on each peer: death/respawn remain host authoritative; bodies never
## become live hitboxes or obstruct players. No additional physics dependency.
var running := false
var bodies: Dictionary = {}
var _body_to_bone: Dictionary = {}
var _physics_root: Node3D
var _indices: Array[int] = []

func start(inherited_velocity: Vector3) -> void:
	if running:
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	running = true
	_physics_root = Node3D.new()
	_physics_root.name = "RagdollPhysics"
	add_child(_physics_root)
	_physics_root.top_level = true
	_physics_root.global_transform = Transform3D.IDENTITY
	for spec: Dictionary in SoldierHitboxes.SPEC:
		var index := skeleton.find_bone(spec.bone)
		var tip := skeleton.find_bone(spec.tip)
		if index < 0 or tip < 0:
			continue
		var bone_world := skeleton.global_transform * skeleton.get_bone_global_pose(index)
		var end := skeleton.global_transform * skeleton.get_bone_global_pose(tip).origin
		var offset := end - bone_world.origin
		var body := RigidBody3D.new()
		body.name = str(spec.bone)
		body.mass = 7.0 if spec.zone == "torso" else (4.5 if spec.zone == "head" else 3.0)
		# Layer 8 is cosmetic debris; world geometry is layer 1.
		body.collision_layer = 128
		body.collision_mask = 1
		body.linear_damp = 0.25
		body.angular_damp = 2.0
		body.continuous_cd = true
		body.freeze = true
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = float(spec.radius) * 0.85
		capsule.height = maxf(offset.length(), capsule.radius * 2.0)
		shape.shape = capsule
		body.add_child(shape)
		_physics_root.add_child(body)
		body.global_transform = Transform3D(SoldierHitboxes._align_to(offset).basis, bone_world.origin + offset * 0.5)
		bodies[index] = body
		_body_to_bone[index] = body.global_transform.affine_inverse() * bone_world
		_indices.append(index)
	_indices.sort()
	for index: int in _indices:
		var parent := skeleton.get_bone_parent(index)
		while parent >= 0 and not bodies.has(parent):
			parent = skeleton.get_bone_parent(parent)
		if parent < 0:
			continue
		var joint := ConeTwistJoint3D.new()
		joint.name = "Joint_" + str(index)
		_physics_root.add_child(joint)
		var bone_world := skeleton.global_transform * skeleton.get_bone_global_pose(index)
		joint.global_transform = bone_world.orthonormalized()
		joint.node_a = joint.get_path_to(bodies[parent])
		joint.node_b = joint.get_path_to(bodies[index])
		joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(25.0 if "Spine" in skeleton.get_bone_name(index) else 65.0))
		joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(20.0))
	for body: RigidBody3D in bodies.values():
		body.freeze = false
		body.linear_velocity = inherited_velocity.limit_length(10.0)
		# Break the unstable upright equilibrium without launching the corpse.
		body.angular_velocity = Vector3(0.45, 0.0, 0.2)

func stop() -> void:
	running = false
	if is_instance_valid(_physics_root):
		_physics_root.free()
	_physics_root = null
	bodies.clear()
	_body_to_bone.clear()
	_indices.clear()
	var skeleton := get_skeleton()
	if skeleton != null:
		skeleton.reset_bone_poses()

func bone_world_transform(bone_name: String) -> Transform3D:
	var index := get_skeleton().find_bone(bone_name)
	if bodies.has(index):
		return (bodies[index] as RigidBody3D).global_transform * (_body_to_bone[index] as Transform3D)
	return get_skeleton().global_transform * get_skeleton().get_bone_global_pose(index)

func _apply_pose() -> void:
	if not running:
		return
	var skeleton := get_skeleton()
	var inverse := skeleton.global_transform.affine_inverse()
	for index: int in _indices:
		var pose: Transform3D = inverse * (bodies[index] as RigidBody3D).global_transform * (_body_to_bone[index] as Transform3D)
		skeleton.set_bone_global_pose(index, pose)

func _process_modification() -> void:
	_apply_pose()

func _process_modification_with_delta(_delta: float) -> void:
	_apply_pose()
