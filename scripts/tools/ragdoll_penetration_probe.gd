extends SceneTree

## Focused probe for the two reported ragdoll bugs under Jolt:
##  A. spawn velocity is clamped (no launch when dying mid-air / at speed)
##  B. a body forced to intersect world geometry depenetrates instead of exploding
##  C. a corpse dropped from height lands intact instead of blowing apart
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("RAGDOLL_PEN_FAIL " + message)

func _stable(rag: SoldierRagdoll, hips_ref: Vector3, tag: String) -> void:
	for body: RigidBody3D in rag.bodies.values():
		check(body.global_position.is_finite(), tag + " finite position")
		check(body.linear_velocity.is_finite() and body.linear_velocity.length() < 15.0, tag + " not launched")
		check(body.global_position.distance_to(hips_ref) < 3.0, tag + " stays connected")

func _run() -> void:
	ProjectSettings.set_setting("zero_frame/graphics_quality", 1)
	var level := (load("res://scenes/levels/dev_test_grid.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for frame: int in 30:
		await physics_frame
	var panel := root.get_node("GlobalInput/DevPanel") as DevPanel
	panel._spawn_dummies(3)
	for frame: int in 30:
		await physics_frame
	var dummies := panel._dummy_container.get_children()

	# A. Velocity clamp: an extreme inherited velocity must be limited at spawn.
	var rag_a := (dummies[0] as Node3D).get_meta("ragdoll") as SoldierRagdoll
	rag_a.start(Vector3(100.0, -60.0, 40.0))
	check(rag_a._inherited_velocity.length() <= SoldierRagdoll.MAX_SPAWN_LINEAR_VELOCITY + 0.001,
		"inherited velocity clamped to MAX_SPAWN_LINEAR_VELOCITY: " + str(rag_a._inherited_velocity.length()))

	# B. Force a wall through a corpse's torso and confirm it depenetrates cleanly.
	var d_b := dummies[1] as Node3D
	d_b.global_position = Vector3(6, 0.05, 6)
	for frame: int in 5:
		await physics_frame
	var rag_b := d_b.get_meta("ragdoll") as SoldierRagdoll
	SoldierDummy.receive_hit(d_b, 100.0, rag_b.bone_world_transform("mixamorig_Spine2").origin,
		Vector3.FORWARD, "mixamorig_Spine2", "torso", 1.0)
	for frame: int in 5:
		await physics_frame
	var slab := StaticBody3D.new()
	slab.collision_layer = 1
	slab.collision_mask = 0
	var slab_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 3.0, 0.3)
	slab_shape.shape = box
	slab.add_child(slab_shape)
	level.add_child(slab)
	slab.global_position = rag_b.bone_world_transform("mixamorig_Hips").origin
	for frame: int in 180:
		await physics_frame
	_stable(rag_b, rag_b.bone_world_transform("mixamorig_Hips").origin, "wall-penetration")

	# C. Drop a corpse from height onto the floor; it must land, not shatter.
	var d_c := dummies[2] as Node3D
	d_c.global_position = Vector3(-6, 5.0, -6)
	for frame: int in 5:
		await physics_frame
	var rag_c := d_c.get_meta("ragdoll") as SoldierRagdoll
	SoldierDummy.receive_hit(d_c, 100.0, rag_c.bone_world_transform("mixamorig_Spine2").origin,
		Vector3.DOWN, "mixamorig_Spine2", "torso", 1.0)
	for frame: int in 240:
		await physics_frame
	var hips_c := rag_c.bone_world_transform("mixamorig_Hips").origin
	_stable(rag_c, hips_c, "high-drop")
	check(hips_c.y < 1.5 and hips_c.y > -1.0, "dropped corpse rests near the floor: " + str(hips_c.y))

	print("RAGDOLL_PEN_RESULT failures=", failures)
	quit(1 if failures else 0)
