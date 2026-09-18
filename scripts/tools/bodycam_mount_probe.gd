extends SceneTree

var failures := 0
var samples := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		if failures <= 12:
			push_error("MOUNT_FAIL " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	current_scene = level
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
	level.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.camera.set_process(false)
	player.camera.set_physics_process(false)
	player.weapon_manager.set_process(false)
	player.weapon_manager.set_physics_process(false)
	await process_frame
	await process_frame
	var skeleton := player._body_skeleton
	var mesh := player._body_model.find_child("FirstPersonLegs", true, false) as MeshInstance3D
	var anim := player._body_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	(player._body_model.get_node("BodyAnimTree") as AnimationTree).active = false
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim.play("idle", 0.0)
	anim.advance(0.0)
	var reference := ChestCameraMount.new()
	check(reference.configure(mesh, skeleton, player.to_global(Vector3(0.055, 1.30, -1.0)), -player.global_basis.z), "chest surface found")
	print("MOUNT_TRANSFORMS mesh=", mesh.transform, " skeleton=", skeleton.global_transform, " camera=", player.camera.global_transform)
	for clip: String in ["idle", "idle_aiming", "idle_crouching", "idle_crouching_aiming", "run_forward", "run_backward", "sprint_forward", "sprint_left", "walk_crouching_forward", "jump_up", "jump", "jump_down"]:
		anim.play(clip, 0.0)
		var nearest_front := INF
		var farthest_back := 0.0
		var missed_back := 0
		for frame: int in 12:
			player.position = Vector3(17, 2, -13) if frame % 2 else Vector3.ZERO
			player.rotation.y = frame * 0.5
			var pitch := deg_to_rad([-78.0, 0.0, 60.0][frame % 3])
			player.bodycam.rotation.x = pitch
			anim.seek(anim.current_animation_length * frame / 12.0, true)
			player._update_bodycam(0.0)
			check(root.get_camera_3d() == player.camera, "WorldCamera renders the world")
			var expected_forward := player.global_basis * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD
			check((-player.camera.global_basis.z).distance_to(expected_forward) < 0.0001, "attachment does not rotate player aim")
			var baked := SoldierModel.bake_mesh(mesh, skeleton)
			reference.sample()
			var origin := player.camera.global_position
			# Independent ray/triangle intersection against the entire baked torso,
			# not a comparison with the same attachment formula as production.
			var forward := reference.surface_normal
			var front_hit := INF
			var back_hit := INF
			for surface: int in baked.get_surface_count():
				var arrays := baked.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				for triangle: int in range(0, indices.size(), 3):
					var a := mesh.to_global(vertices[indices[triangle]])
					var b := mesh.to_global(vertices[indices[triangle + 1]])
					var c := mesh.to_global(vertices[indices[triangle + 2]])
					var hit: Variant = Geometry3D.ray_intersects_triangle(origin, forward, a, b, c)
					if hit != null:
						front_hit = minf(front_hit, origin.distance_to(hit))
					hit = Geometry3D.ray_intersects_triangle(origin, -forward, a, b, c)
					if hit != null:
						back_hit = minf(back_hit, origin.distance_to(hit))
			check(is_inf(front_hit), "lens faces out of the vest: " + clip)
			check(absf(back_hit - ChestCameraMount.LENS_STANDOFF) < 0.002, "lens stays on chest surface: " + clip + " distance=" + str(back_hit))
			samples += 1
			nearest_front = minf(nearest_front, front_hit)
			if is_inf(back_hit):
				missed_back += 1
			else:
				farthest_back = maxf(farthest_back, back_hit)
			if frame == 0:
				print("MOUNT_SAMPLE ", clip, " camera=", player.to_local(origin), " forward=", forward, " front_hit=", front_hit, " back_hit=", back_hit)
		print("MOUNT_CLIP ", clip, " nearest_front=", nearest_front, " farthest_back=", farthest_back, " missed_back=", missed_back)
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_mount(level, player, anim)
	level.free()
	for frame: int in 12:
		await physics_frame
	print("BODYCAM_MOUNT_RESULT failures=", failures, " samples=", samples)
	quit(1 if failures else 0)

func _capture_mount(level: Node3D, player: PlayerController, anim: AnimationPlayer) -> void:
	check(DisplayServer.get_name() != "headless", "mount captures require a real renderer")
	if DisplayServer.get_name() == "headless":
		return
	player.transform = Transform3D.IDENTITY
	player.bodycam.rotation = Vector3.ZERO
	player.camera.transform = Transform3D.IDENTITY
	player.get_node("WeaponLayer").hide()
	player.get_node("BodycamOverlay").hide()
	player.get_node("HUD").hide()
	var full := player._body_model.find_child("SoldierMesh", true, false) as MeshInstance3D
	full.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	player._body_model.find_child("FirstPersonLegs", true, false).hide()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.15, 0.18, 0.22)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	level.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -35, 0)
	level.add_child(sun)
	var lens := MeshInstance3D.new()
	var housing := BoxMesh.new()
	housing.size = Vector3(0.04, 0.035, 0.025)
	var green := StandardMaterial3D.new()
	green.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	green.albedo_color = Color.GREEN
	housing.material = green
	lens.mesh = housing
	level.add_child(lens)
	var axis := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.004
	cylinder.bottom_radius = 0.004
	cylinder.height = 0.3
	var yellow := green.duplicate() as StandardMaterial3D
	yellow.albedo_color = Color.YELLOW
	cylinder.material = yellow
	axis.mesh = cylinder
	level.add_child(axis)
	var observer := Camera3D.new()
	observer.fov = 60.0
	level.add_child(observer)
	observer.make_current()
	DirAccess.make_dir_recursive_absolute("res://build/verification")
	for clip: String in ["idle", "idle_crouching", "sprint_forward"]:
		anim.play(clip, 0.0)
		anim.advance(0.0)
		player._update_bodycam(0.0)
		lens.global_transform = player.camera.global_transform
		var forward := -player.camera.global_basis.z
		axis.global_position = lens.global_position + forward * 0.15
		axis.quaternion = Quaternion(Vector3.UP, forward)
		for side: String in ["side", "front"]:
			observer.position = player.bodycam.position + (Vector3(1.6, 0.2, 0) if side == "side" else Vector3(0.6, 0.2, -1.6))
			observer.look_at(player.bodycam.position + Vector3(0, -0.15, 0))
			await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			var path := "res://build/verification/chest_mount_%s_%s.png" % [clip, side]
			check(not image.is_empty() and image.save_png(path) == OK, "saved mount capture " + path)
			print("MOUNT_CAPTURE ", path, " size=", image.get_size())
