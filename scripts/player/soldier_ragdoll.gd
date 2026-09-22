class_name SoldierRagdoll
extends SkeletonModifier3D

## Metre-scale rigid bodies drive the imported, scaled skeleton after animation.
## Cosmetic on each peer: death/respawn remain host authoritative; bodies never
## become live hitboxes or obstruct players. No additional physics dependency.
const CORPSE_LIFETIME := 120.0

var age := 0.0
var running := false
var bodies: Dictionary = {}
var _body_to_bone: Dictionary = {}
var _physics_root: Node3D
var _indices: Array[int] = []
var _bounds_clock := 0.0
var _settled := false
var _original_bounds: Dictionary = {}

func start(inherited_velocity: Vector3) -> void:
	if running:
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for mesh: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		if mesh.skin != null:
			_original_bounds[mesh] = mesh.custom_aabb
	running = true
	age = 0.0
	_settled = false
	_physics_root = Node3D.new()
	_physics_root.name = "RagdollPhysics"
	add_child(_physics_root)
	_physics_root.top_level = true
	_physics_root.global_transform = Transform3D.IDENTITY
	for spec: Dictionary in SoldierHitboxes.SPEC:
		var index := skeleton.find_bone(spec.bone)
		var tip := skeleton.find_bone(spec.tip)
		if index < 0 or tip < 0 or bodies.has(index):
			continue
		var bone_world := skeleton.global_transform * skeleton.get_bone_global_pose(index)
		var end := skeleton.global_transform * skeleton.get_bone_global_pose(tip).origin
		var offset := end - bone_world.origin
		var body := RigidBody3D.new()
		body.name = str(spec.bone)
		body.mass = float({"head": 4.5, "neck": 1.0, "torso": 9.0, "torso_low": 12.0,
			"arm_upper": 2.5, "arm_lower": 1.5, "leg_upper": 8.0, "leg_lower": 4.0}.get(spec.zone, 3.0))
		body.physics_material_override = PhysicsMaterial.new()
		body.physics_material_override.friction = 0.7
		body.physics_material_override.bounce = 0.0
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
		# Strip skeleton scale from bone_world so _body_to_bone is scale-free.
		var bone_world_ortho := Transform3D(bone_world.basis.orthonormalized(), bone_world.origin)
		_body_to_bone[index] = body.global_transform.affine_inverse() * bone_world_ortho
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
		body.reset_physics_interpolation()
	_apply_pose()
	_update_bounds()

func stop() -> void:
	_restore_bounds()
	running = false
	_settled = false
	if is_instance_valid(_physics_root):
		_physics_root.free()
	_physics_root = null
	bodies.clear()
	_body_to_bone.clear()
	_indices.clear()
	var skeleton := get_skeleton()
	if skeleton != null:
		skeleton.reset_bone_poses()

## Deliver a physics impulse to the ragdoll body that owns `bone_name`.
## `world_pos`  — world-space point of application (for torque calculation).
## `impulse`    — world-space linear impulse (N·s).
## Safe to call while the ragdoll is running; silently ignored otherwise.
func apply_impulse(bone_name: String, world_pos: Vector3, impulse: Vector3) -> void:
	if not running:
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var bone_index := skeleton.find_bone(bone_name)
	# Walk up the hierarchy until we find a body that owns this bone.
	while bone_index >= 0 and not bodies.has(bone_index):
		bone_index = skeleton.get_bone_parent(bone_index)
	if bone_index < 0:
		return
	var body := bodies[bone_index] as RigidBody3D
	if not world_pos.is_finite() or not impulse.is_finite():
		return
	# Godot expects a world-oriented offset, not a body-local point.
	var offset := (world_pos - body.global_position).limit_length(0.08)
	# A light neck/forearm must not receive the same velocity change as a torso.
	# Limit the point impulse as well as its lever arm to avoid joint explosions.
	body.apply_impulse(impulse.limit_length(minf(8.0, body.mass * 0.6)), offset)

func bone_world_transform(bone_name: String) -> Transform3D:
	var skeleton := get_skeleton()
	var index := skeleton.find_bone(bone_name)
	if index < 0:
		return skeleton.global_transform.orthonormalized()
	if bodies.has(index):
		return (bodies[index] as RigidBody3D).global_transform * (_body_to_bone[index] as Transform3D)
	# Wound offsets use metres before AND after the animation/physics transition.
	return (skeleton.global_transform * skeleton.get_bone_global_pose(index)).orthonormalized()

## Transfer the actual bodies/joints, retaining pose and momentum across respawn.
## The corpse starts its own lifetime counter from zero so it lives the full
## CORPSE_LIFETIME regardless of how long the source ragdoll was already running.
func transfer_to(target: SoldierRagdoll) -> void:
	_restore_bounds()
	target._settled = _settled
	target.running = running
	target.age = 0.0          # corpse gets its own fresh lifetime
	target.bodies = bodies
	target._body_to_bone = _body_to_bone
	target._indices = _indices
	target._physics_root = _physics_root
	_physics_root.reparent(target)
	# Null out source references before stop() so stop() cannot free the
	# physics root that now belongs to the target.
	_physics_root = null
	bodies = {}
	_body_to_bone = {}
	_indices = []
	# Reset source skeleton to T-pose; does not touch the target.
	running = false
	var skeleton := get_skeleton()
	if skeleton != null:
		skeleton.reset_bone_poses()

func _apply_pose() -> void:
	if not running:
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var skel_world := skeleton.global_transform
	var position_inverse := skel_world.affine_inverse()
	var rotation_inverse := skel_world.basis.orthonormalized().inverse()
	for index: int in _indices:
		var body_world: Transform3D = (bodies[index] as RigidBody3D).global_transform
		var bone_world_ortho: Transform3D = body_world * (_body_to_bone[index] as Transform3D)
		# Positions must return to imported rig units, rotations must remain unit scale.
		var local := Transform3D(rotation_inverse * bone_world_ortho.basis, position_inverse * bone_world_ortho.origin)
		skeleton.set_bone_global_pose(index, local)

## Called by SkeletonModifier3D when AnimationTree is active.
func _process_modification() -> void:
	_apply_pose()

func _process_modification_with_delta(_delta: float) -> void:
	_apply_pose()

## Fallback: drive bones directly when AnimationTree is inactive (death state).
## SkeletonModifier3D._process_modification is only dispatched while the skeleton
## is being ticked by an active AnimationTree/AnimationPlayer. After stop(true)
## the skeleton goes silent and modifiers are never called, so we push poses
## ourselves every physics frame instead.
var _anim_tree: AnimationTree = null

func _physics_process(delta: float) -> void:
	if not running:
		return
	age += delta
	_bounds_clock -= delta
	if _bounds_clock <= 0.0:
		_bounds_clock = 0.2
		_update_bounds()
	# Sleeping bodies keep their final pose; retain lifetime cleanup but stop solving.
	if not _settled and age > 4.0:
		var quiet := true
		for body: RigidBody3D in bodies.values():
			quiet = quiet and body.linear_velocity.length_squared() < 0.01 and body.angular_velocity.length_squared() < 0.04
		if quiet:
			_settled = true
			for body: RigidBody3D in bodies.values():
				body.freeze = true
	# If AnimationTree is active it will tick the skeleton and trigger
	# _process_modification automatically. Only drive bones manually when it is off.
	if _anim_tree != null and _anim_tree.active:
		return
	_apply_pose()

func _update_bounds() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or bodies.is_empty():
		return
	# Bounds follow physics even when the living model's origin remains at spawn.
	for mesh: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		if mesh.skin == null:
			continue
		var inverse := mesh.global_transform.affine_inverse()
		var bounds := AABB(inverse * (bodies.values()[0] as RigidBody3D).global_position, Vector3.ZERO)
		for body: RigidBody3D in bodies.values():
			bounds = bounds.expand(inverse * body.global_position)
		mesh.custom_aabb = bounds.grow(0.45 / maxf(mesh.global_basis.get_scale().x, 0.001))

func _restore_bounds() -> void:
	for mesh: MeshInstance3D in _original_bounds:
		if is_instance_valid(mesh):
			mesh.custom_aabb = _original_bounds[mesh]
	_original_bounds.clear()
