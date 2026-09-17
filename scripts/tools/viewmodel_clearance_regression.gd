extends SceneTree

var failures := 0
var samples := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("CLEARANCE_FAIL " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var capture := "--capture" in OS.get_cmdline_user_args()
	var level := (load("res://scenes/levels/dev_test_grid.tscn") as PackedScene).instantiate() as Node3D if capture else Node3D.new()
	root.add_child(level)
	current_scene = level
	var player := level.get_node_or_null("Player") as PlayerController
	if player == null:
		player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
		level.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.camera.set_process(false)
	var manager := player.weapon_manager
	manager.set_process(false)
	manager.set_physics_process(false)
	await process_frame
	await process_frame
	check(root.get_camera_3d() == player.camera, "world camera is active")
	var anim := player._body_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	(player._body_model.get_node("BodyAnimTree") as AnimationTree).active = false
	for clip: String in ["idle", "idle_crouching", "sprint_forward", "jump_up", "jump", "jump_down"]:
		anim.play(clip, 0.0)
		for frame: int in 20:
			anim.seek(anim.current_animation_length * frame / 20.0, true)
			player._update_bodycam(1.0 / 60.0)
			var chest := player._body_skeleton.global_transform * player._body_skeleton.get_bone_global_pose(player._chest_bone)
			# Compare in metres. Inverse imported rig scale magnifies float rounding
			# at non-origin map spawns by 55x; it is not physical mount separation.
			check(player.bodycam.global_position.distance_to(chest * player._chest_mount) < 0.00001, "mount remains attached: " + clip)
			check(player.to_local(player.camera.global_position).y < 1.5, "chest not head: " + clip)
	anim.play("idle", 0.0)
	anim.advance(0.0)
	player._update_bodycam(0.0)
	for index: int in manager.weapons.size():
		player.bodycam.rotation = Vector3.ZERO
		player.rotation = Vector3.ZERO
		(player.camera as BodycamPhysics).reset_recoil()
		manager._select(index)
		var weapon := manager.weapons[index]
		weapon.set_process(false)
		weapon._animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var camera := weapon.authored_camera
		check(weapon.get_viewport().get_camera_3d() == camera, "authored camera active")
		weapon._animation_player.play(weapon.idle_animation, 0.0)
		weapon._animation_player.advance(0.0)
		weapon.enforce_camera_clearance(1.0 / 60.0)
		print("IDLE_CLEARANCE ", weapon.weapon_name, " correction=", weapon.clearance_offset)
		print("IDLE_ACTUAL_NEAREST ", weapon.weapon_name, " ", _check_geometry(weapon, camera, weapon._clearance.nearest_z(camera)) + weapon.clearance_offset)
		if capture:
			await _capture("%d_idle" % index)
		var max_correction := 0.0
		for clip: String in [weapon.idle_animation, weapon.shot_animation, weapon.reload_animation]:
			weapon._animation_player.play(clip, 0.0)
			for frame: int in 25:
				weapon._animation_player.seek(weapon._animation_player.current_animation_length * frame / 25.0, true)
				for ads: bool in [false, true]:
					weapon.transform = weapon._ads_transform if ads else Transform3D.IDENTITY
					for stress: bool in [false, true]:
						manager.position = manager.base_position + (Vector3(0.03, 0.16, 0.62) if stress else Vector3.ZERO)
						manager.rotation = Vector3(-0.28, 0.12, -0.12) if stress else Vector3.ZERO
						player.weapon_aim_pivot.rotation = Vector3(0.12, -0.12, 0.02) if stress else Vector3.ZERO
						weapon.model_root.position = Vector3(0.02, 0, 0.13) if stress else Vector3.ZERO
						weapon.model_root.rotation = Vector3(0.27, 0, 0.12) if stress else Vector3.ZERO
						weapon.enforce_camera_clearance(1.0 / 60.0)
						if capture and clip == weapon.reload_animation and frame == 12 and not ads and not stress:
							await _capture("%d_reload" % index)
						max_correction = maxf(max_correction, weapon.clearance_offset)
						var conservative := weapon._clearance.nearest_z(camera)
						check(conservative <= -camera.near - WeaponBase.CAMERA_CLEARANCE + 0.00001, "final animated bounds " + weapon.weapon_name + " " + clip)
						# Independent CPU skinning of actual rendered vertices (not the guard's boxes).
						if frame % 6 == 0:
							_check_geometry(weapon, camera, conservative)
						samples += 1
		print("CLEARANCE_WEAPON ", weapon.weapon_name, " samples=", samples, " max_correction=", max_correction)
		manager.transform = Transform3D(Basis.IDENTITY, manager.base_position)
		player.weapon_aim_pivot.transform = Transform3D.IDENTITY
		weapon.reset_recoil()
		weapon._animation_player.play(weapon.idle_animation, 0.0)
		weapon._animation_player.advance(0.0)
		weapon.set_aiming(true)
		for frame: int in 120:
			weapon._process(1.0 / 60.0)
			weapon.enforce_camera_clearance(1.0 / 60.0)
		if index == 0:
			for name: String in ["RearSight", "FrontSight"]:
				var marker := weapon.model_root.find_child(name, true, false) as Marker3D
				var sight := camera.to_local(marker.global_position)
				check(Vector2(sight.x, sight.y).length() < 0.001, "ADS sight on camera axis: " + name + str(sight))
				check(sight.z < -0.5, "sights have eye relief")
			print("ADS_CLEARANCE ", weapon.clearance_offset)
			check(weapon.clearance_offset < 0.01, "authored ADS does not rely on large corrective displacement")
		var measure_start := Time.get_ticks_usec()
		for iteration: int in 500:
			weapon.enforce_camera_clearance(1.0 / 60.0)
		print("CLEARANCE_COST_US ", weapon.weapon_name, " ", float(Time.get_ticks_usec() - measure_start) / 500.0)
		if capture:
			await _capture("%d_ads" % index)
		# Actual frame-driven auto/semi recoil and authored animation, not only
		# synthetic extremes. Sample after the previous frame's final pose pass.
		weapon._animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		weapon.set_process(true)
		player.set_process(true)
		for frame: int in 90:
			if frame % 6 == 0:
				weapon._apply_recoil()
				weapon._play_shot_animation()
			manager.add_look_impulse(Vector2(25, -20))
			await process_frame
			check(weapon._clearance.nearest_z(camera) <= -camera.near - WeaponBase.CAMERA_CLEARANCE + 0.0001, "live final pose clearance")
		player.set_process(false)
		weapon.set_process(false)
		weapon.ammo = 1
		weapon.reload()
		weapon.set_aiming(true)
		check(not weapon.aiming, "reload leaves ADS")
		weapon.set_process(true)
		player.set_process(true)
		await weapon._reload_timer.timeout
		await process_frame
		await process_frame
		check(not weapon.reloading and weapon.ammo == weapon.magazine_size, "real reload timer completes after ADS")
		check(weapon.transform.is_equal_approx(Transform3D.IDENTITY), "reload/ADS exit restores the base transform")
		check(weapon._clearance.nearest_z(camera) <= -camera.near - WeaponBase.CAMERA_CLEARANCE + 0.0001, "clearance after live reload")
		weapon.set_process(false)
		player.set_process(false)
		weapon.reset_recoil()
	level.free()
	for frame: int in 12:
		await physics_frame
	print("CLEARANCE_RESULT failures=", failures, " samples=", samples)
	quit(1 if failures else 0)

func _check_geometry(weapon: WeaponBase, camera: Camera3D, conservative: float) -> float:
	var nearest := -INF
	for part: Dictionary in weapon._clearance._parts:
		var mesh := part.mesh as MeshInstance3D
		if not mesh.is_visible_in_tree() or part.skeleton == null:
			continue
		var skeleton := part.skeleton as Skeleton3D
		var view := camera.global_transform.affine_inverse() * mesh.global_transform
		for surface: int in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences: int = bones.size() / vertices.size()
			for index: int in vertices.size():
				var skinned := Vector3.ZERO
				for influence: int in influences:
					var slot := index * influences + influence
					if weights[slot] == 0.0:
						continue
					var bind := bones[slot]
					var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind))
					if bone < 0:
						bone = mesh.skin.get_bind_bone(bind)
					skinned += skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) * vertices[index] * weights[slot]
				nearest = maxf(nearest, (view * skinned).z)
				check((view * skinned).z <= conservative + 0.0001, "bone boxes bound CPU-skinned geometry: " + str(mesh.name))
	return nearest

func _capture(label: String) -> void:
	check(DisplayServer.get_name() != "headless", "captures require a real renderer")
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/verification")
	var image := root.get_texture().get_image()
	check(not image.is_empty() and image.save_png("res://build/verification/bodycam_%s.png" % label) == OK, "capture saved " + label)
	print("CLEARANCE_CAPTURE ", label, " size=", image.get_size())
