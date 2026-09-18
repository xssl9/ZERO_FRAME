extends SceneTree

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var avatar := SoldierAvatar.new()
	root.add_child(avatar)
	avatar.configure(2, 0)
	avatar.is_local = false
	avatar._build()
	avatar.set_process(false)
	var skel := avatar._skeleton
	var mesh := avatar._model.find_child("SoldierMesh", true, false) as MeshInstance3D
	check(avatar._weapon_proxies.size() == 2, "both real weapons built")
	check(avatar._hitboxes.size() == 14, "all bone hitboxes built")
	check(avatar.get_node("Synchronizer").get_multiplayer_authority() == 1, "host distributes every avatar without client relay")
	avatar._animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for gait: String in ["walk", "run", "sprint", "walk_crouching"]:
		var speed := 1.9 if gait == "walk" else (7.0 if gait == "sprint" else (2.2 if gait == "walk_crouching" else 4.2))
		for direction: Vector2 in SoldierLocomotion.DIRECTIONS.values():
			for frame: int in 180:
				avatar._locomotion.update(Vector3(direction.x, 0, -direction.y) * speed, gait == "walk_crouching", false, gait == "sprint", false, false, 1.0 / 60.0)
				avatar._animation_tree.advance(1.0 / 60.0)
				var hips := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("mixamorig_Hips")).origin
				check(Vector2(hips.x, hips.z).length() < 0.35, "in-place hip position across loops/transitions: " + gait + str(direction) + " hips=" + str(hips))
			var head := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("mixamorig_Head")).origin
			check(head.y > 0.65 and head.y < 2.1, "upright head in " + gait + str(direction))
			var bounds := skel.global_transform * SoldierModel.bake_mesh(mesh, skel).get_aabb()
			check(bounds.size.y > 0.8 and bounds.size.y < 2.4, "human-sized skinned mesh in " + gait)
			check(bounds.position.y > -0.3 and bounds.position.y < 0.4, "feet near floor in " + gait)
		check(avatar._locomotion._playback.get_current_node() == ("crouch" if gait == "walk_crouching" else gait), "state machine actually travels to " + gait)
	for state: Array in [
		[Vector3.ZERO, false, true, false, false, "idle_aiming"],
		[Vector3.ZERO, true, true, false, false, "idle_crouching_aiming"],
		[Vector3(0, 3, 0), false, false, true, false, "jump_up"],
		[Vector3(0, -3, 0), false, false, true, false, "jump"],
		[Vector3.ZERO, false, false, false, true, "death"],
		[Vector3.ZERO, false, false, false, false, "idle"],
	]:
		for frame: int in 60:
			avatar._locomotion.update(state[0], state[1], state[2], false, state[3], state[4], 1.0 / 60.0)
			avatar._animation_tree.advance(1.0 / 60.0)
		check(avatar._locomotion._playback.get_current_node() == state[5], "state " + str(state[5]))
	for hitbox: Area3D in avatar._hitboxes:
		var shape := hitbox.get_child(0) as CollisionShape3D
		check(shape.basis.determinant() > 0.0, "right-handed hitbox basis")
		var radius: float = shape.shape.radius * skel.global_basis.get_scale().abs().x
		check(radius > 0.05 and radius < 0.18, "hitbox metre radius")
	if "--capture" in OS.get_cmdline_user_args():
		await _capture(avatar)
	avatar.free()
	await _check_player_integration()
	print("MULTIPLAYER_REGRESSION failures=", failures)
	quit(1 if failures else 0)

func _check_player_integration() -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
	root.add_child(player)
	player.set_physics_process(false)
	await process_frame
	var viewport := player.weapon_camera.get_viewport() as SubViewport
	check(viewport.own_world_3d and viewport.world_3d != player.get_world_3d(), "FPS weapons remain in isolated World3D")
	check(viewport.get_camera_3d() == player.weapon_manager.get_active_authored_camera(), "authored weapon camera retained")
	player.bodycam.rotation.x = 0.4
	player._update_body_awareness(1.0 / 60.0)
	check(is_equal_approx(player._body_rig_modifier.aim_pitch, rad_to_deg(0.4)), "body awareness reads the real pitch pivot")
	Input.action_press("crouch")
	player._update_stance()
	check(player.crouching, "crouch enters")
	var ceiling := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 0.2, 2)
	collision.shape = box
	ceiling.add_child(collision)
	root.add_child(ceiling)
	ceiling.position = player.position + Vector3(0, 1.45, 0)
	await physics_frame
	await physics_frame
	Input.action_release("crouch")
	player._update_stance()
	check(player.crouching, "cannot stand through a low ceiling")
	ceiling.free()
	await physics_frame
	await physics_frame
	player._update_stance()
	check(not player.crouching, "stands after clearance is restored")
	var weapon := player.weapon_manager.weapons[0]
	weapon.ammo = 1
	weapon.reload()
	check(weapon.reloading, "reload starts")
	var timer := weapon._reload_timer
	player.weapon_manager._select(1)
	check(not weapon.reloading and not timer.timeout.is_connected(weapon._finish_reload), "holstering cancels the old reload timer")
	player._on_network_health(0.0)
	var pistol := player.weapon_manager.weapons[1]
	var ammo := pistol.ammo
	Input.action_press("fire")
	player.weapon_manager._process(1.0)
	Input.action_release("fire")
	check(pistol.ammo == ammo, "dead player cannot fire via gameplay input")
	player.free()
	for frame: int in 12:
		await physics_frame

func _capture(avatar: SoldierAvatar) -> void:
	check(DisplayServer.get_name() != "headless", "capture needs a real renderer")
	if DisplayServer.get_name() == "headless":
		return
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.15, 0.18, 0.22)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.7
	root.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	light.light_energy = 2.0
	root.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	root.add_child(floor_mesh)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(2, 1.5, -3.5)
	camera.look_at(Vector3(0, 0.9, 0))
	camera.current = true
	for frame: int in 60:
		avatar._locomotion.update(Vector3.ZERO, false, false, false, false, false, 1.0 / 60.0)
		avatar._animation_tree.advance(1.0 / 60.0)
		await physics_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/verification")
	var path := "res://build/verification/soldier.png"
	check(root.get_texture().get_image().save_png(path) == OK, "GPU soldier capture saved")
	print("SOLDIER_CAPTURE ", path, " renderer=", RenderingServer.get_current_rendering_method())
	camera.free()
	floor_mesh.free()
	light.free()
	world.free()
