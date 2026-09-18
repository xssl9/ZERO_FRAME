extends SceneTree

var failures := 0
var samples := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		if failures <= 12:
			push_error("FRAMING_FAIL " + message)

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
	player.set_process(false)
	player.set_physics_process(false)
	player.camera.set_process(false)
	player.camera.set_physics_process(false)
	var manager := player.weapon_manager
	manager.set_process(false)
	manager.set_physics_process(false)
	await process_frame
	await process_frame
	for index: int in manager.weapons.size():
		manager._select(index)
		manager.transform = Transform3D(Basis.IDENTITY, manager.base_position)
		player.weapon_aim_pivot.transform = Transform3D.IDENTITY
		var weapon := manager.weapons[index]
		weapon.set_process(false)
		weapon._animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		# Load an independent authored scene. Do not compare against a runtime
		# rest transform that could already include the unwanted correction.
		var source := (load(weapon.model_path) as PackedScene).instantiate() as Node3D
		var source_camera := source.get_node("WeaponTuningCamera") as Camera3D
		source_camera.current = false
		source.visible = false
		level.add_child(source)
		var source_anim := source.find_child("AnimationPlayer", true, false) as AnimationPlayer
		source_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var runtime_source := weapon.model_root.get_child(0) as Node3D
		var view := weapon.authored_camera
		check(view == weapon.get_viewport().get_camera_3d(), "active camera comes from the weapon scene")
		for clip: String in [weapon.idle_animation, weapon.shot_animation, weapon.reload_animation]:
			weapon._animation_player.play(clip, 0.0)
			source_anim.play(clip, 0.0)
			for frame: int in 12:
				var time := weapon._animation_player.current_animation_length * frame / 12.0
				weapon._animation_player.seek(time, true)
				source_anim.seek(time, true)
				# The real player's final-pose pass must not move the assembly just
				# to bring deliberately cropped arm/stock vertices into the frame.
				player.camera.fov = 75.0 if frame % 2 else 110.0
				player._process(1.0 / 60.0)
				check(view.fov == source_camera.fov and view.keep_aspect == source_camera.keep_aspect and view.near == source_camera.near and view.far == source_camera.far, "authored projection survives world FOV changes")
				var authored := source_camera.global_transform.affine_inverse() * source.global_transform
				var actual := view.global_transform.affine_inverse() * runtime_source.global_transform
				check(actual.is_equal_approx(authored), "camera-to-model transform matches saved scene: " + weapon.weapon_name + " " + clip)
				check(is_zero_approx(weapon.clearance_offset) and weapon._clearance_pivot.transform.is_equal_approx(Transform3D.IDENTITY), "no forced whole-arm displacement")
				for mesh: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
					var runtime_mesh := runtime_source.get_node(source.get_path_to(mesh)) as MeshInstance3D
					var expected_mesh := source_camera.global_transform.affine_inverse() * mesh.global_transform
					var actual_mesh := view.global_transform.affine_inverse() * runtime_mesh.global_transform
					check(actual_mesh.is_equal_approx(expected_mesh), "mesh framing retained: " + str(mesh.name))
				samples += 1
		print("AUTHORED_FRAMING ", weapon.weapon_name, " correction=", weapon.clearance_offset, " fov=", view.fov)
		weapon.reset_recoil()
		weapon._animation_player.play(weapon.idle_animation, 0.0)
		weapon._animation_player.advance(0.0)
		player._process(1.0 / 60.0)
		if capture:
			player.camera.fov = 96.0
			await process_frame
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://build/verification")
			var image := root.get_texture().get_image()
			check(not image.is_empty() and image.save_png("res://build/verification/authored_viewmodel_%d.png" % index) == OK, "saved authored-framing capture")
		# Procedural motion remains, but it must not move the camera or add an
		# independent whole-assembly correction during ADS/recoil/wall retraction.
		var camera_rest := view.transform
		weapon.set_aiming(true)
		weapon._apply_recoil()
		manager.position += Vector3(0.03, 0.16, 0.62)
		manager.rotation = Vector3(-0.28, 0.12, -0.12)
		for frame: int in 60:
			weapon._process(1.0 / 60.0)
			player._process(1.0 / 60.0)
			check(view.transform.is_equal_approx(camera_rest), "ADS/recoil do not rewrite the authored camera")
			check(is_zero_approx(weapon.clearance_offset), "motion does not re-enable whole-arm displacement")
		# Returning from the optional constraint must not retain its old offset.
		weapon.reset_recoil()
		manager.transform = Transform3D(Basis.IDENTITY, manager.base_position)
		weapon._animation_player.play(weapon.idle_animation, 0.0)
		weapon._animation_player.advance(0.0)
		weapon.preserve_authored_framing = false
		player._process(1.0 / 60.0)
		check(weapon.clearance_offset > 0.0, "optional constraint can still be enabled explicitly")
		weapon.preserve_authored_framing = true
		player._process(1.0 / 60.0)
		check(is_zero_approx(weapon.clearance_offset) and weapon._clearance_pivot.transform.is_equal_approx(Transform3D.IDENTITY), "authored mode removes stale correction immediately")
		source.free()
		weapon.reset_recoil()
	level.free()
	for frame: int in 12:
		await physics_frame
	print("AUTHORED_VIEWMODEL_RESULT failures=", failures, " samples=", samples)
	quit(1 if failures else 0)
