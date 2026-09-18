extends SceneTree

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("MOTION_FAIL " + message)

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
	var camera := player.camera as BodycamPhysics
	camera.set_process(false)
	camera.set_physics_process(false)
	var manager := player.weapon_manager
	manager.set_process(false)
	manager.set_physics_process(false)
	await process_frame
	await process_frame
	var limit := deg_to_rad(camera.pitch_limit_degrees)
	for start: float in [limit, limit - deg_to_rad(0.5), -limit, 0.0]:
		camera.reset_recoil()
		player.bodycam.rotation.x = start
		for shot: int in 5:
			camera.add_recoil(2.0, 0.0)
		for frame: int in 240:
			camera._recover_recoil(1.0 / 60.0)
		check(absf(player.bodycam.rotation.x - start) < 0.00001, "recovery returns only applied pitch at start=" + str(start))
	camera.reset_recoil()
	player.bodycam.rotation.x = limit - deg_to_rad(0.5)
	camera.add_recoil(2.0, 1.0)
	camera._apply_view_rotation(Vector2(deg_to_rad(1.0), -deg_to_rad(0.5)))
	var compensated := player.bodycam.rotation.x
	for frame: int in 240:
		camera._recover_recoil(1.0 / 60.0)
	check(absf(player.bodycam.rotation.x - compensated) < 0.00001, "manual compensation near pitch limit does not leave phantom debt")

	# Compare equal elapsed time after a mouse impulse: a slow frame must not
	# explode the manager's springs or run the recoil clock at a different speed.
	var manager_poses: Array[Vector4] = []
	for steps: int in [1, 30]:
		manager.sway = Vector2.ZERO
		manager.sway_velocity = Vector2.ZERO
		manager._drag = Vector2.ZERO
		manager._drag_velocity = Vector2.ZERO
		manager.add_look_impulse(Vector2(35, -24))
		for step: int in steps:
			manager._process(0.25 / steps)
		manager_poses.append(Vector4(manager.sway.x, manager.sway.y, manager._drag.x, manager._drag.y))
	check(manager_poses[0].distance_to(manager_poses[1]) < 0.001, "viewmodel sway/drag remains stable across a 250ms frame")
	for index: int in manager.weapons.size():
		manager._select(index)
		var weapon := manager.weapons[index]
		# Keep testing recoil combined with the opt-in clearance constraint;
		# default authored framing has its own regression.
		weapon.preserve_authored_framing = false
		weapon.set_process(false)
		var poses: Array[Transform3D] = []
		for steps: int in [1, 30]:
			weapon.reset_recoil()
			weapon._kick_velocity = 4.2
			weapon._kick_pitch_velocity = 6.0
			weapon._kick_roll_velocity = 2.0
			weapon._kick_side_velocity = 1.0
			weapon.set_aiming(true)
			for step: int in steps:
				weapon._process(0.25 / steps)
				weapon.enforce_camera_clearance(0.25 / steps)
			poses.append(weapon.model_root.transform)
			check(weapon._clearance.nearest_z(weapon.authored_camera) <= -weapon.authored_camera.near - WeaponBase.CAMERA_CLEARANCE + 0.0001, "ADS/recoil/hitch preserves camera clearance")
		check(poses[0].origin.distance_to(poses[1].origin) < 0.001 and poses[0].basis.get_rotation_quaternion().angle_to(poses[1].basis.get_rotation_quaternion()) < 0.001, "recoil clock matches elapsed time: " + weapon.weapon_name)
	level.free()
	for frame: int in 12:
		await physics_frame
	print("BODYCAM_MOTION_RESULT failures=", failures)
	quit(1 if failures else 0)
