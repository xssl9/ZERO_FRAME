extends SceneTree

var failures := 0
var capture := false

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("GAMEPLAY_FAIL " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	if capture:
		check(DisplayServer.get_name() != "headless", "screenshots require a real renderer")
	ProjectSettings.set_setting("zero_frame/graphics_quality", 1)
	var level := (load("res://scenes/levels/dev_test_grid.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	var player := level.get_node("Player") as PlayerController
	for frame: int in 60:
		await physics_frame
	check(player.is_on_floor(), "player settles on map")
	var full := player._body_model.find_child("SoldierMesh", true, false) as MeshInstance3D
	var legs := player._body_model.find_child("FirstPersonLegs", true, false) as MeshInstance3D
	check(full.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "full body only casts shadows locally")
	check(legs != null and legs.mesh.get_surface_count() > 0, "skinned legs are retained")
	check(legs.skin == full.skin and legs.skeleton == full.skeleton, "legs use original skin and skeleton")
	var remote_model := SoldierModel.instantiate()
	root.add_child(remote_model)
	var remote_mesh := remote_model.find_child("SoldierMesh", true, false) as MeshInstance3D
	check(remote_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "remote body not hidden by local mesh filtering")
	check(remote_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() > legs.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size(), "full model retains discarded local triangles")
	remote_model.free()
	for pitch: float in [-78.0, -55.0, 0.0, 60.0]:
		player.bodycam.rotation_degrees.x = pitch
		for frame: int in 8:
			await physics_frame
		var scales: Array[Vector3] = []
		for bone: int in player._body_skeleton.get_bone_count():
			scales.append(player._body_skeleton.get_bone_pose_scale(bone))
		player._body_rig_modifier._apply(player._body_skeleton)
		for bone: int in player._body_skeleton.get_bone_count():
			check(player._body_skeleton.get_bone_pose_scale(bone) == scales[bone], "local visibility modifier preserves authored bone scale")
		for name: String in ["mixamorig_Head", "mixamorig_LeftArm", "mixamorig_RightArm"]:
			var bone := player._body_skeleton.find_bone(name)
			check(player._body_skeleton.get_bone_pose_scale(bone).is_equal_approx(Vector3.ONE), "head/arms never collapsed: " + name)
		# Check only indexed (rendered) vertices, not discarded upper-body vertices.
		var baked := SoldierModel.bake_mesh(legs, player._body_skeleton)
		var top := -INF
		var visible_waist := 0
		var waist_bounds := AABB()
		for surface: int in baked.get_surface_count():
			var arrays := baked.surface_get_arrays(surface)
			for index: int in arrays[Mesh.ARRAY_INDEX]:
				var point: Vector3 = player._body_skeleton.global_transform * arrays[Mesh.ARRAY_VERTEX][index]
				var height := point.y - player.global_position.y
				top = maxf(top, height)
				if height > 1.0 and height < 1.3:
					waist_bounds = waist_bounds.expand(player.to_local(point))
					if player.camera.is_position_in_frustum(point):
						visible_waist += 1
		if pitch <= -55.0:
			print("WAIST_GEOMETRY pitch=", pitch, " visible=", visible_waist, " bounds=", waist_bounds, " camera=", player.to_local(player.camera.global_position), " fov=", player.camera.fov)
			check(visible_waist > 30, "waist really lies inside downward camera frustum at " + str(pitch) + ": " + str(visible_waist))
		# Bodycam now intentionally includes the waist/lower vest. Keep an upper
		# bound to reject head/shoulder geometry, and require actual torso height.
		check(top > 1.1 and top < 1.45, "waist/lower vest retained without head/shoulders at pitch " + str(pitch) + " top=" + str(top))
	await _capture("look_down", player, -78.0)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for frame: int in 40:
		await physics_frame
	await _capture("running_legs", player, -65.0)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	Input.action_press("crouch")
	for frame: int in 20:
		await physics_frame
	await _capture("crouching_legs", player, -65.0)
	Input.action_release("crouch")
	player.weapon_manager._select(1)
	await _capture("pistol_look_down", player, -65.0)
	player.bodycam.rotation.x = 0
	await _check_pause(player)
	await _check_ballistics(player)
	level.free()
	for frame: int in 12:
		await physics_frame
	print("GAMEPLAY_REGRESSION failures=", failures, " capture=", capture)
	quit(1 if failures else 0)

func _esc() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	Input.parse_input_event(event)
	await process_frame

func _check_pause(player: PlayerController) -> void:
	var scene := current_scene
	await _esc()
	check(player.menu_open and paused and current_scene == scene, "Esc pauses offline, without exiting")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "menu releases mouse")
	player.pause_menu.set_fov(85)
	player.pause_menu.set_sensitivity(3.2)
	player.pause_menu.set_volume(40)
	player.pause_menu.set_graphics(1)
	check(player.camera.fov == 85 and is_equal_approx((player.camera as BodycamPhysics).mouse_sensitivity, 0.0032), "settings apply immediately")
	check(is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.4), "volume applies immediately")
	await _capture("pause_settings", player, 0)
	await _esc()
	check(not paused and not player.menu_open, "Esc resumes with focused menu button")
	var network := root.get_node("NetworkGame")
	# Real transport/second-peer coverage is in network_roundtrip.gd.
	network.active = true
	await _esc()
	check(player.menu_open and not paused and network.active, "online Esc does not pause or disconnect")
	var start := player.position
	var yaw := player.rotation.y
	var flashlight := player.flashlight.visible
	var weapon := player.weapon_manager.weapons[1]
	var ammo := weapon.ammo
	var index := player.weapon_manager.current_index
	for action: String in ["move_forward", "sprint", "aim", "fire", "reload", "weapon_1", "lean_left", "flashlight"]:
		Input.action_press(action)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(200, 80)
	player.camera._unhandled_input(motion)
	for frame: int in 40:
		await physics_frame
	check(Vector2(player.position.x - start.x, player.position.z - start.z).length() < 0.1, "menu blocks locomotion")
	check(is_equal_approx(player.rotation.y, yaw), "menu blocks looking")
	check(weapon.ammo == ammo and not weapon.reloading and player.weapon_manager.current_index == index, "menu blocks firing/reload/switch")
	check(not weapon.aiming and not player.sprinting and is_zero_approx((player.camera as BodycamPhysics).lean_amount()), "menu blocks ADS/sprint/lean")
	check(player.flashlight.visible == flashlight, "menu blocks flashlight")
	player._on_network_health(25)
	check(player.health == 25, "paused online player remains vulnerable")
	for action: String in ["move_forward", "sprint", "aim", "reload", "weapon_1", "lean_left", "flashlight"]:
		Input.action_release(action)
	await _esc()
	for frame: int in 15:
		await physics_frame
	check(weapon.ammo == ammo, "held menu click does not fire on resume")
	Input.action_release("fire")
	# process_frame is emitted before Node._process; allow a complete input poll.
	await process_frame
	await process_frame
	Input.action_press("fire")
	for frame: int in 12:
		await physics_frame
	Input.action_release("fire")
	check(weapon.ammo == ammo - 1, "fresh trigger works after resume: before=%s after=%s blocked=%s gate=%s released=%s" % [ammo, weapon.ammo, player.weapon_manager.wall_blocked, player.weapon_manager.require_trigger_release, weapon.trigger_released])
	network.active = false
	player.revive()

func _check_ballistics(player: PlayerController) -> void:
	var fixture := Node3D.new()
	current_scene.add_child(fixture)
	# Keep isolated from level walls while using the real physics World3D.
	fixture.position = Vector3(0, 20, 0)
	var target := Area3D.new()
	target.collision_layer = SoldierHitboxes.layer_mask()
	target.collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.12
	shape.shape = sphere
	target.add_child(shape)
	fixture.add_child(target)
	target.position = Vector3(0, 1.5, -5)
	var cover := StaticBody3D.new()
	var box := CollisionShape3D.new()
	var size := BoxShape3D.new()
	size.size = Vector3(2, 1.2, 0.2)
	box.shape = size
	cover.add_child(box)
	fixture.add_child(cover)
	cover.position = Vector3(0, 0.6, -1)
	for frame: int in 2:
		await physics_frame
	var impact_count := current_scene.get_child_count()
	player.weapon_manager.weapons[0]._spawn_impact(fixture.global_position, Vector3.ZERO)
	check(current_scene.get_child_count() == impact_count, "inside-cover hit does not create an invalid decal")
	var eye := fixture.global_position + Vector3(0, 1.5, 0)
	var muzzle := fixture.global_position + Vector3(0, 0.85, -0.5)
	var space := player.get_world_3d().direct_space_state
	var excluded: Array[RID] = [player.get_rid()]
	var sight := ShotBallistics.ray(space, eye, eye + Vector3.FORWARD * 10, excluded)
	check(sight.get("collider") == target, "camera sees target over low cover")
	var hit := ShotBallistics.trace(space, eye, Vector3.FORWARD, muzzle, excluded)
	check(hit.get("collider") == cover, "low cover blocks barrel even with clear camera")
	muzzle = fixture.global_position + Vector3(0, 0.85, -1.3)
	hit = ShotBallistics.trace(space, eye, Vector3.FORWARD, muzzle, excluded)
	check(hit.get("collider") == cover, "barrel through thin cover cannot shoot out the far side")
	cover.free()
	await physics_frame
	await physics_frame
	muzzle = eye + Vector3(0.15, -0.1, -0.5)
	hit = ShotBallistics.trace(space, eye, Vector3.FORWARD, muzzle, excluded)
	check(hit.get("collider") == target, "muzzle converges on unobstructed sight target")
	var miss := ShotBallistics.trace(space, eye, Vector3(0.1, 0, -1).normalized(), muzzle, excluded)
	check(miss.is_empty(), "near miss stays a miss")
	excluded.append(target.get_rid())
	check(ShotBallistics.trace(space, eye, Vector3.FORWARD, muzzle, excluded).is_empty(), "self hitbox exclusion")
	for weapon: int in 2:
		check(ShotBallistics.damage_at(weapon, "head", 5) > ShotBallistics.damage_at(weapon, "torso", 5), "head damage > torso")
		check(ShotBallistics.damage_at(weapon, "torso", 5) > ShotBallistics.damage_at(weapon, "limbs", 5), "torso damage > limbs")
		check(ShotBallistics.damage_at(weapon, "torso", 100) < ShotBallistics.damage_at(weapon, "torso", 5), "range loses damage")
		check(ShotBallistics.damage_at(weapon, "limbs", 120) > 0, "distant limbs still take damage")
	fixture.free()

func _capture(label: String, player: PlayerController, pitch: float) -> void:
	if not capture or DisplayServer.get_name() == "headless":
		return
	player.bodycam.rotation_degrees.x = pitch
	for frame: int in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/verification")
	var path := "res://build/verification/%s.png" % label
	var image := root.get_texture().get_image()
	check(not image.is_empty() and image.save_png(path) == OK, "capture saved: " + label)
	print("GAMEPLAY_CAPTURE ", path, " size=", image.get_size())
