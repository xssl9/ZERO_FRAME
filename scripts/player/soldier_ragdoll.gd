class_name SoldierRagdoll
extends SkeletonModifier3D

## Metre-scale rigid bodies drive the imported, scaled skeleton after animation.
## Cosmetic on each peer: death/respawn remain host authoritative; bodies never
## become live hitboxes or obstruct players. Runs on the Jolt physics backend:
## rigid (linear-locked) Generic6DOF joints, anatomical angular limits and
## self-collision keep the corpse from turning to jelly or exploding on geometry.
const CORPSE_LIFETIME := 120.0

## Maximum speed any single body may inherit at spawn — prevents joint explosions
## when the player dies mid-air or after a high-speed impact.
const MAX_SPAWN_LINEAR_VELOCITY := 6.0
## Tiny random spin at spawn so a corpse never balances perfectly upright — without
## the old fixed kick that made every body visibly wobble.
const MAX_SPAWN_ANGULAR_VELOCITY := 0.5
## Linear damping: light. A falling body meets little air resistance; high values
## make the corpse float ("fall through honey"), so this stays small.
const LINEAR_DAMP := 0.3
## Angular damping: high enough to stop the "washing machine" spin that happens
## when constrained joints fight each other.
const ANGULAR_DAMP := 4.5
## Physics frames to keep bodies frozen after spawn. Gives Jolt a tick or two to
## resolve initial penetrations before any force or velocity is applied.
const UNFREEZE_DELAY_FRAMES := 2

## Ragdoll bodies live on their own collision layer (bit 8) and collide with the
## world (bit 1) and each other, so limbs cannot fold through the torso mesh.
const WORLD_LAYER := 1
const RAGDOLL_LAYER := 1 << 7

## Per-zone mass in kilograms. Neighbour ratios are kept below ~5:1 so the iterative
## solver stays stable (the old 1 kg neck between a 4.5 kg head and a 12 kg torso
## was a major instability source). Total ~80 kg.
const ZONE_MASS := {
	"head": 5.0, "neck": 2.0, "torso": 8.0, "torso_low": 12.0,
	"arm_upper": 2.8, "arm_lower": 1.6, "leg_upper": 10.0, "leg_lower": 4.5,
}

var age := 0.0
var running := false
var bodies: Dictionary = {}
var _body_to_bone: Dictionary = {}
var _physics_root: Node3D
var _indices: Array[int] = []
var _bounds_clock := 0.0
var _settled := false
var _original_bounds: Dictionary = {}
var _unfreeze_countdown := 0
var _inherited_velocity := Vector3.ZERO
var _anim_tree: AnimationTree = null

## Build the ragdoll: one linear-locked rigid body per hitbox zone, joined by
## anatomical Generic6DOF joints. Bodies spawn frozen; _physics_process releases
## them after UNFREEZE_DELAY_FRAMES with clamped inherited momentum.
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
	_inherited_velocity = inherited_velocity.limit_length(MAX_SPAWN_LINEAR_VELOCITY)
	_unfreeze_countdown = UNFREEZE_DELAY_FRAMES
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
		body.mass = float(ZONE_MASS.get(spec.zone, 3.0))
		body.physics_material_override = PhysicsMaterial.new()
		body.physics_material_override.friction = 0.8
		body.physics_material_override.bounce = 0.0
		body.collision_layer = RAGDOLL_LAYER
		body.collision_mask = WORLD_LAYER | RAGDOLL_LAYER
		body.linear_damp = LINEAR_DAMP
		body.angular_damp = ANGULAR_DAMP
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
		var bone_world_ortho := Transform3D(bone_world.basis.orthonormalized(), bone_world.origin)
		_body_to_bone[index] = body.global_transform.affine_inverse() * bone_world_ortho
		_indices.append(index)
	_indices.sort()
	_build_joints(skeleton)
	_add_self_collision_exceptions()
	_apply_pose()
	_update_bounds()

## Join every body to its nearest ancestor body with a Generic6DOF joint whose
## linear axes are all locked (rigid pivot — no separation, no skin stretch).
func _build_joints(skeleton: Skeleton3D) -> void:
	var skel_lateral := skeleton.global_transform.basis.x.normalized()
	for index: int in _indices:
		var parent := skeleton.get_bone_parent(index)
		while parent >= 0 and not bodies.has(parent):
			parent = skeleton.get_bone_parent(parent)
		if parent < 0:
			continue
		var joint := Generic6DOFJoint3D.new()
		joint.name = "Joint_" + str(index)
		_physics_root.add_child(joint)
		var bone_world := skeleton.global_transform * skeleton.get_bone_global_pose(index)
		_configure_joint(joint, skeleton.get_bone_name(index), bodies[index], bone_world.origin, skel_lateral)
		joint.node_a = joint.get_path_to(bodies[parent])
		joint.node_b = joint.get_path_to(bodies[index])

## One anatomical joint. All three linear axes are locked so the bodies stay pinned
## at the bone (rigid — this is the main cure for the "jelly" stretch). Angular
## limits then set how the joint may rotate: stiff spine/neck, wide shoulders/hips,
## and a sagittal-plane hinge (locked twist + splay) for elbows and knees.
func _configure_joint(joint: Generic6DOFJoint3D, bone_name: String, child: RigidBody3D, origin: Vector3, skel_lateral: Vector3) -> void:
	var is_hinge := ("ForeArm" in bone_name) or (("Leg" in bone_name) and not ("UpLeg" in bone_name))
	var basis := child.global_transform.basis.orthonormalized()
	if is_hinge:
		# Local Z = character lateral axis (the flexion axis), local Y = down the
		# bone. Bending then happens about Z in the sagittal plane only.
		var y_axis := basis.y
		var z_axis := skel_lateral - y_axis * skel_lateral.dot(y_axis)
		if z_axis.length() < 0.001:
			z_axis = basis.z
		z_axis = z_axis.normalized()
		var x_axis := y_axis.cross(z_axis).normalized()
		basis = Basis(x_axis, y_axis, z_axis)
	joint.global_transform = Transform3D(basis, origin)
	_lock_linear(joint)
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	if is_hinge:
		# Locked twist (Y) and splay (X); generous flexion in the sagittal plane (Z).
		_set_angular(joint, deg_to_rad(6.0), deg_to_rad(6.0), deg_to_rad(90.0))
		return
	var swing := deg_to_rad(65.0)
	var twist := deg_to_rad(30.0)
	if "Spine" in bone_name:
		swing = deg_to_rad(12.0)
		twist = deg_to_rad(10.0)
	elif "Neck" in bone_name:
		swing = deg_to_rad(30.0)
		twist = deg_to_rad(18.0)
	elif "Head" in bone_name:
		swing = deg_to_rad(25.0)
		twist = deg_to_rad(18.0)
	elif "Arm" in bone_name:
		swing = deg_to_rad(80.0)
		twist = deg_to_rad(40.0)
	elif "UpLeg" in bone_name:
		swing = deg_to_rad(55.0)
		twist = deg_to_rad(30.0)
	_set_angular(joint, swing, twist, swing)

## Lock all three linear axes at zero travel: the bodies cannot slide apart.
func _lock_linear(joint: Generic6DOFJoint3D) -> void:
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)

## Symmetric angular limits (radians) per axis: X, Z = swing, Y = twist.
func _set_angular(joint: Generic6DOFJoint3D, x: float, y: float, z: float) -> void:
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -x)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, x)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -y)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, y)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -z)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, z)

## Bodies that already overlap at spawn (adjacent segments, the two thighs, an arm
## resting on the torso) must not collide, or the solver would explode separating
## them on frame one. Bodies that are apart at spawn keep colliding, so a limb that
## later folds onto the torso is stopped instead of clipping through it.
func _add_self_collision_exceptions() -> void:
	for i: int in _indices.size():
		for j: int in range(i + 1, _indices.size()):
			var a := bodies[_indices[i]] as RigidBody3D
			var b := bodies[_indices[j]] as RigidBody3D
			if _bodies_overlap(a, b):
				a.add_collision_exception_with(b)

func _bodies_overlap(a: RigidBody3D, b: RigidBody3D) -> bool:
	var ca := _capsule_segment(a)
	var cb := _capsule_segment(b)
	var dist := _segment_distance(ca[0], ca[1], cb[0], cb[1])
	return dist < float(ca[2]) + float(cb[2]) + 0.01

func _capsule_segment(body: RigidBody3D) -> Array:
	var cap := (body.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
	var half := maxf(cap.height * 0.5 - cap.radius, 0.0)
	var axis := body.global_transform.basis.y.normalized()
	return [body.global_position - axis * half, body.global_position + axis * half, cap.radius]

## Shortest distance between two line segments (Ericson, Real-Time Collision
## Detection) — used to decide whether two capsule bodies overlap at spawn.
func _segment_distance(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 0.00001 and e <= 0.00001:
		return r.length()
	if a <= 0.00001:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 0.00001:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			if denom > 0.00001:
				s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	var c1 := p1 + d1 * s
	var c2 := p2 + d2 * t
	return (c1 - c2).length()

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
	target._unfreeze_countdown = 0
	target._inherited_velocity = Vector3.ZERO
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
func _physics_process(delta: float) -> void:
	if not running:
		return
	# Hold the bodies frozen for a couple of frames so Jolt can resolve any spawn
	# overlap gently before momentum is applied — then release with clamped speed.
	if _unfreeze_countdown > 0:
		_unfreeze_countdown -= 1
		if _unfreeze_countdown == 0:
			_release_bodies()
		_apply_pose()
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

## Unfreeze after the settle delay and hand the corpse its clamped inherited
## momentum plus a tiny random spin so it topples instead of balancing upright.
func _release_bodies() -> void:
	for body: RigidBody3D in bodies.values():
		body.freeze = false
		body.linear_velocity = _inherited_velocity
		body.angular_velocity = Vector3(
			randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)
		).limit_length(MAX_SPAWN_ANGULAR_VELOCITY)
		body.reset_physics_interpolation()

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





