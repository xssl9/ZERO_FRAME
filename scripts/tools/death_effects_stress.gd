extends SceneTree

var failures := 0
var rendered_samples := 0
func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("DEATH_EFFECTS_FAIL " + message)

func _run() -> void:
	ProjectSettings.set_setting("zero_frame/graphics_quality", 1)
	var level := (load("res://scenes/levels/dev_test_grid.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	var player := level.get_node("Player") as PlayerController
	player.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 18)))
	for frame: int in 60:
		await physics_frame
	var panel := root.get_node("GlobalInput/DevPanel") as DevPanel
	panel._spawn_dummies(10)
	check(panel._dummy_container.get_child_count() == 10, "ten DEV menu dummies")
	for frame: int in 30:
		await physics_frame
	var ragdolls: Array[SoldierRagdoll] = []
	for dummy: Node3D in panel._dummy_container.get_children():
		var rag := dummy.get_meta("ragdoll") as SoldierRagdoll
		ragdolls.append(rag)
		rag.modification_processed.connect(_check_rendered.bind(rag))
		for i: int in 5:
			var bone := "mixamorig_Neck" if i % 2 == 0 else "mixamorig_LeftArm"
			SoldierDummy.receive_hit(dummy, 1.0, rag.bone_world_transform(bone).origin, Vector3.FORWARD, bone, "neck", 1.0)
		var before := rag.bone_world_transform("mixamorig_Hips").origin
		SoldierDummy.receive_hit(dummy, 100.0, rag.bone_world_transform("mixamorig_Spine2").origin, Vector3.FORWARD, "mixamorig_Spine2", "torso", 1.0)
		var sk := rag.get_skeleton()
		var rendered := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_Hips"))
		check(rendered.origin.distance_to(before) < 0.002, "no one-frame collapse during mass death")
	panel.hit_feedback.on_hit({}, "torso", null)
	check(is_equal_approx(Engine.time_scale, 1.0), "hit never pauses simulation")
	var pool := level.get_node("BloodEffects") as BloodEffects
	check(pool != null, "shared level pool")
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame: int in 360:
		await physics_frame
		var now := Time.get_ticks_usec()
		if frame >= 60:
			samples.append(float(now - previous) / 1000.0)
		previous = now
		if frame % 30 == 0:
			for rag: SoldierRagdoll in ragdolls:
				var sk := rag.get_skeleton()
				var mesh := sk.get_node("SoldierMesh") as MeshInstance3D
				check(mesh.custom_aabb.has_point(mesh.to_local(rag.bone_world_transform("mixamorig_Hips").origin)), "corpse inside culling bounds")
		if DisplayServer.get_name() != "headless" and frame in [1, 30, 180]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/verification/death_stress_%03d.png" % frame)
	check(rendered_samples > 0, "ragdolls produce final render poses")
	check(pool.bursts.size() <= BloodEffects.MAX_BURSTS, "GPU particle budget")
	check(pool.stains.size() <= BloodEffects.MAX_STAINS, "world decal budget")
	check(get_nodes_in_group("blood_wound_marks").size() <= BloodEffects.MAX_WOUND_MARKS, "attached wound budget")
	# Saturation must recycle existing nodes instead of growing without limit.
	for i: int in 240:
		pool.splash(Vector3(0, 1, 18), Vector3.UP)
		pool.deposit({"position": Vector3(float(i) * 0.1, 0, 18), "normal": Vector3.UP}, 0.15, false)
	check(pool.bursts.size() == BloodEffects.MAX_BURSTS and pool.stains.size() == BloodEffects.MAX_STAINS, "pool remains capped after 240 impacts")
	for i: int in 24:
		pool.trace(Vector3.UP, Vector3.DOWN)
	check(pool._ray_count <= BloodEffects.MAX_RAYS_PER_FRAME, "global ray budget")
	samples.sort()
	print("DEATH_STRESS ten_corpses physics_interval_median_ms=", samples[samples.size() / 2], " physics_interval_p95_ms=", samples[int(samples.size() * 0.95)], " gpu=", DisplayServer.get_name() != "headless", " resolution=", root.size, " bursts=", pool.bursts.size(), " stains=", pool.stains.size())
	panel._on_clear_all()
	for frame: int in 3:
		await physics_frame
	check(get_nodes_in_group("blood_wound_marks").is_empty(), "clear dummies frees attached wounds")
	check(is_instance_valid(pool) and not pool.stains.is_empty(), "surface blood independent of corpse lifetime")
	current_scene = null
	level.free()
	for frame: int in 6:
		await physics_frame
	check(not is_instance_valid(pool), "level unload releases entire pool")
	print("DEATH_EFFECTS_RESULT failures=", failures)
	quit(1 if failures else 0)

func _check_rendered(rag: SoldierRagdoll) -> void:
	if not rag.running:
		return
	rendered_samples += 1
	var sk := rag.get_skeleton()
	# Modifiers are reverted after skinning. Sample at the actual final-pose signal.
	for spec: Dictionary in SoldierHitboxes.SPEC:
		var rendered := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(spec.bone))
		check(rendered.origin.distance_to(rag.bone_world_transform(spec.bone).origin) < 0.002, "rendered/physical agreement " + spec.bone)
