extends SceneTree

class DeathCameraMonitor extends Node:
	var player: PlayerController
	var samples := 0
	var maximum_error := 0.0

	func _process(_delta: float) -> void:
		var expected := player._ragdoll.bone_world_transform("mixamorig_Spine2").orthonormalized() * player._death_camera_offset
		maximum_error = maxf(maximum_error, player.camera.global_position.distance_to(expected.origin))
		samples += 1

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("BODY_WEAPON_FAIL " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	ProjectSettings.set_setting("zero_frame/graphics_quality", 1)
	var level := (load("res://scenes/levels/dev_test_grid.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	var player := level.get_node("Player") as PlayerController
	for frame: int in 40:
		await physics_frame
	var manager := player.weapon_manager
	for index: int in 2:
		manager._select(index)
		await process_frame
		await process_frame
		var weapon := manager.weapons[index]
		check(weapon.flashlight_mount != null, "weapon has physical flashlight mount")
		player.flashlight.visible = true
		for pitch: float in [-65, 0, 45]:
			player.bodycam.rotation_degrees.x = pitch
			manager.rotation.y = 0.08
			weapon.model_root.rotation.x = 0.1
			player._update_weapon_flashlight()
			var expected := weapon.world_marker_transform(player.camera, weapon.flashlight_mount)
			check(player.flashlight.global_transform.is_equal_approx(expected), "flashlight follows weapon at pitch/recoil " + str(pitch))
			# Camera placement is authored per weapon: the AK rail can legitimately
			# be closer than 25 cm. Verify the exact nonzero mount offset instead of
			# forcing camera framing to satisfy an arbitrary distance threshold.
			var rail_offset := weapon.authored_camera.to_local(weapon.flashlight_mount.global_position)
			var light_offset := player.camera.to_local(player.flashlight.global_position)
			check(not rail_offset.is_zero_approx() and light_offset.distance_to(rail_offset) < 0.00001, "flashlight keeps the authored rail offset, not the camera origin")
		player.bodycam.rotation = Vector3.ZERO
		# Authored reload moves the receiver independently of the procedural root.
		var mount_parent := weapon.flashlight_mount.get_parent() as BoneAttachment3D
		check(mount_parent != null and weapon.muzzle.get_parent() == mount_parent, "light and barrel share the animated receiver")
		var mount_local := weapon.flashlight_mount.transform
		weapon._animation_player.play(weapon.reload_animation, 0.0)
		weapon._animation_player.advance(0.45)
		await process_frame
		await process_frame
		player._update_weapon_flashlight()
		check(weapon.flashlight_mount.transform.is_equal_approx(mount_local), "reload retains rail attachment")
		check(player.flashlight.global_transform.is_equal_approx(weapon.world_marker_transform(player.camera, weapon.flashlight_mount)), "beam follows authored reload")
		var min_pitch := INF
		var max_pitch := -INF
		var min_yaw := INF
		var max_yaw := -INF
		for shot: int in 24:
			weapon.reset_recoil()
			manager._free_aim = Vector2.ZERO
			(player.camera as BodycamPhysics).reset_recoil()
			player.bodycam.rotation.x = 0.0
			player.rotation.y = 0.0
			weapon.aiming = shot % 2 == 0
			weapon._apply_recoil()
			var pitch := rad_to_deg(player.bodycam.rotation.x)
			var yaw := rad_to_deg(player.rotation.y)
			check(pitch > (0.55 if index == 0 else 1.0), "first round reaches real aim, including ADS")
			min_pitch = minf(min_pitch, pitch)
			max_pitch = maxf(max_pitch, pitch)
			min_yaw = minf(min_yaw, yaw)
			max_yaw = maxf(max_yaw, yaw)
		check(max_pitch - min_pitch > 0.3 and max_yaw - min_yaw > 0.5, "non-repeating vertical/lateral recoil")
		# Manual compensation must still cancel recovery, not cause a reverse kick.
		var camera := player.camera as BodycamPhysics
		camera._apply_view_rotation(Vector2(-player.rotation.y, -player.bodycam.rotation.x))
		camera._recover_recoil(1.0)
		camera._recover_recoil(1.0)
		check(absf(player.bodycam.rotation.x) < 0.0001, "manual recoil compensation remains stable")
		weapon.reset_recoil()
		weapon.fire_once()
		var first := weapon._smoke_pool[0]
		var emitted_at := first.global_transform
		check(first.get_world_3d() == player.get_world_3d(), "smoke belongs to world")
		check(first.lifetime == WeaponBase.MUZZLE_SMOKE_LIFETIME, "smoke outlives shot")
		check(first.draw_pass_1.material is ShaderMaterial, "smoke uses soft noise/depth shader")
		check(WeaponBase.MUZZLE_SMOKE_POOL_SIZE * WeaponBase.MUZZLE_SMOKE_INTERVAL > first.lifetime, "no live-puff pool reuse")
		if "--capture" in OS.get_cmdline_user_args():
			for frame: int in 10:
				await physics_frame
			await _capture("muzzle_smoke_%d" % index)
		player.rotate_y(0.5)
		for frame: int in 25:
			await physics_frame
		check(first.global_transform.is_equal_approx(emitted_at), "turning never drags old smoke")
		check(weapon._smoke_index >= 2, "residual muzzle gas after trigger release")
	player.bodycam.rotation.x = 0
	player.flashlight.visible = false
	if "--capture" in OS.get_cmdline_user_args():
		var weather := level.get_node("PhotorealEnvironment") as PhotorealEnvironment
		weather.weather = PhotorealEnvironment.Weather.RAIN
		weather.apply_preset()
		for frame: int in 70:
			await physics_frame
		await _capture("rain_streaks")
		manager.weapons[0]._spawn_impact(player.camera.global_position - player.camera.global_basis.z * 2.0, player.camera.global_basis.z)
		for frame: int in 12:
			await physics_frame
		await _capture("impact_dust")
	await _ragdoll_checks(level, player)
	level.free()
	for frame: int in 12:
		await physics_frame
	print("BODY_WEAPON_RESULT failures=", failures, " renderer=", RenderingServer.get_current_rendering_method(), " display=", DisplayServer.get_name())
	quit(1 if failures else 0)

func _ragdoll_checks(level: Node, player: PlayerController) -> void:
	# Isolated real collision floor, away from map cover. Test a sloping surface too.
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12, 0.4, 12)
	shape.shape = box
	floor_body.add_child(shape)
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = box.size
	floor_mesh.mesh = floor_box
	floor_body.add_child(floor_mesh)
	level.add_child(floor_body)
	floor_body.position = Vector3(0, 20, 0)
	floor_body.rotation.z = 0.08
	var avatar := SoldierAvatar.new()
	level.add_child(avatar)
	avatar.configure(2, 0)
	avatar.is_local = false
	avatar._build()
	avatar.sync_position = Vector3(0, 20.3, 0)
	for frame: int in 12:
		await physics_frame
	avatar.sync_velocity = Vector3(0.4, 0, 0.3)
	avatar.set_dead(true)
	var ragdoll := avatar._ragdoll
	# Godot restores pre-modifier poses after skinning. Read the final pose at
	# modification_processed, not later from the animation's restored skeleton.
	var rendered_poses: Dictionary = {}
	ragdoll.modification_processed.connect(func() -> void:
		for index: int in ragdoll.bodies:
			rendered_poses[index] = avatar._skeleton.global_transform * avatar._skeleton.get_bone_global_pose(index))
	check(ragdoll.running and ragdoll.bodies.size() == 14, "14 dynamic body segments on death")
	check(not avatar._animation_tree.active and not avatar._rig_modifier.active, "animation/aim no longer fight physics")
	var anchors: Array[Dictionary] = []
	for child: Node in ragdoll._physics_root.get_children():
		if child is ConeTwistJoint3D:
			var joint := child as ConeTwistJoint3D
			var a := joint.get_node(joint.node_a) as RigidBody3D
			var b := joint.get_node(joint.node_b) as RigidBody3D
			anchors.append({"a": a, "b": b, "local_a": a.to_local(joint.global_position), "local_b": b.to_local(joint.global_position)})
	check(anchors.size() == 13, "all segments connected by constrained joints")
	var initial := ragdoll.bone_world_transform("mixamorig_Hips").origin
	avatar.set_dead(true)
	check(ragdoll.bodies.size() == 14, "repeated death notification is idempotent")
	for frame: int in 210:
		await physics_frame
	var settled := ragdoll.bone_world_transform("mixamorig_Hips").origin
	check(settled.y < initial.y - 0.25, "corpse actually falls under gravity")
	check(settled.y > 19.5, "corpse collides with sloping floor")
	for area: Area3D in avatar._hitboxes:
		check(area.collision_layer == 0, "dead body is not a live hitbox")
	for index: int in ragdoll.bodies:
		var body := ragdoll.bodies[index] as RigidBody3D
		check(body.global_position.is_finite() and body.global_position.distance_to(settled) < 2.0, "joints keep corpse connected")
		check(body.global_basis.get_scale().is_equal_approx(Vector3.ONE), "physics uses metres, not imported rig scale")
		check(rendered_poses.has(index), "ragdoll modifier actually evaluated")
		var rendered: Transform3D = rendered_poses.get(index, Transform3D.IDENTITY)
		check(rendered.origin.distance_to(ragdoll.bone_world_transform(avatar._skeleton.get_bone_name(index)).origin) < 0.08, "skinned bone follows rigid body")
	for anchor: Dictionary in anchors:
		check((anchor.a as Node3D).to_global(anchor.local_a).distance_to((anchor.b as Node3D).to_global(anchor.local_b)) < 0.12, "joint anchors stay together on impact")
	if "--capture" in OS.get_cmdline_user_args():
		var camera := Camera3D.new()
		level.add_child(camera)
		camera.position = Vector3(2, 22, 3)
		camera.look_at(settled)
		camera.current = true
		player.get_node("WeaponLayer").hide()
		await _capture("ragdoll_slope")
		camera.free()
		player.camera.current = true
		player.get_node("WeaponLayer").show()
	avatar.set_dead(false)
	check(not ragdoll.running and ragdoll.bodies.is_empty() and avatar._animation_tree.active, "respawn releases physics and restores animation")
	avatar.free()
	# Local camera follows chest physics, then returns to a live bodycam on respawn.
	player.teleport_to(Transform3D(Basis.IDENTITY, Vector3(3, 20.4, 0)))
	player._on_network_health(0)
	check(player._ragdoll.running and not player.get_node("WeaponLayer").visible, "local death hides isolated arms/weapon")
	# Several physics ticks can occur before one render frame at low FPS. The
	# camera deliberately updates in _process: sample after it, not mid-physics.
	var monitor := DeathCameraMonitor.new()
	monitor.player = player
	monitor.process_priority = player.process_priority + 1
	level.add_child(monitor)
	for frame: int in 60:
		await physics_frame
	check(monitor.samples > 0 and monitor.maximum_error < 0.001, "death camera follows chest on every rendered frame: error=" + str(monitor.maximum_error))
	monitor.free()
	player.revive()
	await physics_frame
	await physics_frame
	check(not player._ragdoll.running and player.camera.is_processing() and not player.get_node("CollisionShape3D").disabled, "local respawn restores camera/capsule")
	floor_body.free()
	player.teleport_to(player.spawn_transform)
	player.apply_damage(100.0)
	check(player.health == 0.0 and player._ragdoll.running, "offline lethal damage starts ragdoll, not immediate teleport")
	for frame: int in 320:
		await physics_frame
	check(player.health == 100.0 and not player._ragdoll.running, "offline five-second timer really respawns")
	check(Vector2(player.global_position.x - player.spawn_position.x, player.global_position.z - player.spawn_position.z).length() < 0.1, "offline respawn returns to spawn")

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "capture requires a GPU run")
		return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/verification")
	var image := root.get_texture().get_image()
	check(not image.is_empty() and image.save_png("res://build/verification/%s.png" % label) == OK, "capture " + label)
	print("BODY_WEAPON_CAPTURE ", label, " size=", image.get_size())
