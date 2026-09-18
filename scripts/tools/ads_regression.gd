extends SceneTree

var failures := 0
var samples := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		if failures <= 20:
			push_error("ADS_FAIL " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var level := (load("res://scenes/levels/dev_test_grid.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	var player := level.get_node("Player") as PlayerController
	for frame: int in 40:
		await physics_frame
	player.set_process(false)
	player.set_physics_process(false)
	player.camera.set_process(false)
	player.camera.set_physics_process(false)
	var body_tree := player._body_model.get_node("BodyAnimTree") as AnimationTree
	body_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var manager := player.weapon_manager
	manager.set_process(false)
	manager.set_physics_process(false)
	# ADS must not select a different local chest animation and move the lens.
	for crouched: bool in [false, true]:
		player.crouching = crouched
		Input.action_press("aim")
		player._update_body_awareness(1.0 / 60.0)
		check(player._body_locomotion._state == ("idle_crouching" if crouched else "idle"), "local ADS retains the chest locomotion pose")
		Input.action_release("aim")
	player.crouching = false
	for index: int in manager.weapons.size():
		manager._select(index)
		manager.transform = Transform3D(Basis.IDENTITY, manager.base_position)
		player.weapon_aim_pivot.transform = Transform3D.IDENTITY
		var weapon := manager.weapons[index]
		weapon.set_process(false)
		weapon._animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		weapon._animation_player.play(weapon.idle_animation, 0.0)
		weapon._animation_player.seek(0.0, true)
		# BoneAttachment3D consumes the evaluated skeleton on the next frame.
		await process_frame
		await process_frame
		player._update_bodycam(0.0)
		var view := weapon.authored_camera
		var rear := weapon.model_root.find_child("RearSight", true, false) as Marker3D
		var front := weapon.model_root.find_child("FrontSight", true, false) as Marker3D
		check(rear != null and front != null, weapon.weapon_name + " has authored iron sights")
		if rear == null or front == null:
			continue
		var rest_camera := view.global_transform
		var rest_world := player.camera.global_transform
		var fov := view.fov
		var world_fov := player.camera.fov
		var rest_rear := view.to_local(rear.global_position)
		var rest_front := view.to_local(front.global_position)
		var sight_length := rear.global_position.distance_to(front.global_position)
		_check_sight_geometry(weapon, rear, front)
		if "--capture" in OS.get_cmdline_user_args():
			await _capture("ads_hip_%d" % index)
		for fps: int in [15, 60, 144]:
			weapon.reset_recoil()
			weapon.set_aiming(true)
			for frame: int in fps:
				weapon._process(1.0 / fps)
				player._process(1.0 / fps)
				check(view.global_transform.is_equal_approx(rest_camera) and player.camera.global_transform.is_equal_approx(rest_world), "ADS leaves both camera transforms unchanged")
				check(view.fov == fov and player.camera.fov == world_fov, "ADS never zooms either camera")
				samples += 1
			var aimed_rear := view.to_local(rear.global_position)
			var aimed_front := view.to_local(front.global_position)
			check(Vector2(aimed_rear.x, aimed_rear.y).length() < 0.0001 and Vector2(aimed_front.x, aimed_front.y).length() < 0.0001, "both sights align with fixed optical axis: " + str(aimed_rear) + " / " + str(aimed_front))
			check(aimed_rear.y > rest_rear.y + 0.01 and aimed_front.y > rest_front.y + 0.01, "hands/weapon rise to the camera")
			check(absf(aimed_rear.z - rest_rear.z) < 0.0001, "raising retains authored rear-sight depth instead of pushing gun away")
			check(absf(sight_length - rear.global_position.distance_to(front.global_position)) < 0.00001, "ADS never scales the weapon")
			check(aimed_front.z < aimed_rear.z and aimed_rear.z < -view.near, "sights ordered in front of the lens")
			check(is_zero_approx(weapon.clearance_offset), "default ADS does not push cropped arms/stock into view")
			weapon.set_aiming(false)
			for frame: int in fps:
				weapon._process(1.0 / fps)
			check(weapon.transform.is_equal_approx(Transform3D.IDENTITY), "release restores authored hip pose without drift")
		weapon.set_aiming(true)
		weapon._process(1.0)
		_check_sight_visibility(weapon, front)
		if "--capture" in OS.get_cmdline_user_args():
			await _capture("ads_%d" % index)
		# These layers must still move the gun rather than being cancelled by ADS.
		var aimed := front.global_position
		manager.position += Vector3(0, 0.1, 0.3)
		weapon._kick_velocity = 2.0
		weapon._process(1.0 / 60.0)
		check(front.global_position.distance_to(aimed) > 0.2, "wall retraction and recoil remain layered over ADS")
		check(view.global_transform.is_equal_approx(rest_camera), "motion does not move weapon camera")
		weapon.ammo = 1
		weapon.reload()
		weapon.set_aiming(true)
		check(not weapon.aiming, "reload rejects ADS")
		for frame: int in 60:
			weapon._process(1.0 / 60.0)
		check(weapon.transform.is_equal_approx(Transform3D.IDENTITY), "reload lowers weapon out of ADS")
		weapon.reset_recoil()
		check(not weapon.aiming and is_zero_approx(weapon._aim_weight), "holster clears ADS")
		manager.transform = Transform3D(Basis.IDENTITY, manager.base_position)
		print("ADS_WEAPON ", weapon.weapon_name, " rest_rear=", rest_rear, " rest_front=", rest_front)
	# Raising during sprint deceleration must immediately leave the lowered pose,
	# even while actual speed is still above the old 5 m/s sprint threshold.
	Input.action_press("sprint")
	Input.action_press("aim")
	player.velocity = Vector3(0, 0, -7)
	manager._sprint_blend = 1.0
	manager._process(0.1)
	check(manager.weapons[manager.current_index].aiming and manager._sprint_blend < 1.0, "ADS releases sprint lowering before velocity has settled")
	Input.action_release("aim")
	Input.action_release("sprint")
	level.free()
	for frame: int in 12:
		await physics_frame
	print("ADS_RESULT failures=", failures, " samples=", samples)
	quit(1 if failures else 0)

func _check_sight_geometry(weapon: WeaponBase, rear: Marker3D, front: Marker3D) -> void:
	# Independent CPU-skinned mesh, not simply two self-consistent markers.
	var skeleton := weapon.model_root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var mesh := weapon.model_root.find_child("Ak" if weapon.weapon_name == "AK-74M" else "Object_93", true, false) as MeshInstance3D
	var baked := SoldierModel.bake_mesh(mesh, skeleton)
	for marker: Marker3D in [rear, front]:
		var nearest := INF
		for surface: int in baked.get_surface_count():
			for vertex: Vector3 in baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				nearest = minf(nearest, marker.global_position.distance_to(mesh.to_global(vertex)))
		# Rear is empty notch space between the ears; front is the post tip.
		check(nearest < (0.003 if marker == rear else 0.0015), "sight marker belongs to actual skinned iron sight: " + str(marker.name) + " distance=" + str(nearest))

func _check_sight_visibility(weapon: WeaponBase, front: Marker3D) -> void:
	# Looking just over the post tip must not intersect the receiver, rear-sight
	# ears or hands. Marker alignment alone cannot prove a usable sight picture.
	var camera := weapon.authored_camera
	var end := front.global_position + camera.global_basis.y * 0.0005
	var nearest := INF
	var blocker := ""
	var skeleton := weapon.model_root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for mesh: MeshInstance3D in weapon.model_root.find_children("*", "MeshInstance3D", true, false):
		if mesh.skin == null:
			continue
		var start := mesh.to_local(camera.global_position)
		var finish := mesh.to_local(end)
		for surface: int in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			# Skin positions directly: rebuilding an ArrayMesh also requires the
			# pistol arms' custom-channel format flags, irrelevant to this ray test.
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences: int = bones.size() / vertices.size()
			for index: int in vertices.size():
				var skinned := Vector3.ZERO
				for influence: int in influences:
					var slot := index * influences + influence
					if weights[slot] <= 0.0:
						continue
					var bind := bones[slot]
					var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind))
					if bone < 0:
						bone = mesh.skin.get_bind_bone(bind)
					skinned += skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) * vertices[index] * weights[slot]
				vertices[index] = skinned
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for triangle: int in range(0, indices.size(), 3):
				var hit: Variant = Geometry3D.segment_intersects_triangle(start, finish, vertices[indices[triangle]], vertices[indices[triangle + 1]], vertices[indices[triangle + 2]])
				if hit != null:
					var distance := camera.global_position.distance_to(mesh.to_global(hit))
					if distance < nearest:
						nearest = distance
						blocker = str(mesh.name)
	check(nearest >= camera.global_position.distance_to(end) - 0.003, "clear view over the front post: " + blocker + " hit_distance=" + str(nearest))

func _capture(label: String) -> void:
	check(DisplayServer.get_name() != "headless", "capture needs a real renderer")
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/verification")
	var image := root.get_texture().get_image()
	check(not image.is_empty() and image.save_png("res://build/verification/%s.png" % label) == OK, "saved " + label)
