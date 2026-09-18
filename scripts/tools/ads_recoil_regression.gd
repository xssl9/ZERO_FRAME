extends SceneTree

class PoseMonitor extends Node:
	var inspect: Callable

	func _process(_delta: float) -> void:
		inspect.call()

# Independent CPU skinning: detect actual triangles crossing the visible near
# plane, not stock/upper-arm vertices intentionally cropped outside the image.
var failures := 0
var failure_groups: Dictionary = {}
var samples := 0
var _surfaces: Array[Dictionary] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		var group := message.get_slice(" fps=", 0)
		failure_groups[group] = int(failure_groups.get(group, 0)) + 1
		if failures <= 12:
			push_error("ADS_RECOIL_FAIL " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	seed(714)
	var level := Node3D.new()
	root.add_child(level)
	current_scene = level
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
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
	manager._select(0)
	var weapon := manager.weapons[0]
	weapon.set_process(false)
	var animation := weapon._animation_player
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation.play(weapon.idle_animation, 0.0)
	animation.advance(0.0)
	_cache_geometry(weapon)
	_check_detector()
	_check_gameplay_recoil(player, weapon)
	for fps: int in [15, 60, 144]:
		for scenario: String in ["steady", "transition", "motion", "wall"]:
			_magazine(player, weapon, fps, scenario)
	await _live_magazine(player, weapon)
	Input.action_release("aim")
	Input.action_release("fire")
	level.free()
	for frame: int in 12:
		await physics_frame
	print("ADS_RECOIL_FAILURE_GROUPS ", failure_groups)
	print("ADS_RECOIL_RESULT failures=", failures, " samples=", samples)
	quit(1 if failures else 0)

func _magazine(player: PlayerController, weapon: WeaponBase, fps: int, scenario: String) -> void:
	seed(714)
	var manager := player.weapon_manager
	var bodycam := player.camera as BodycamPhysics
	var animation := weapon._animation_player
	weapon.reset_recoil()
	weapon.ammo = weapon.magazine_size
	bodycam.reset_recoil()
	player.bodycam.rotation = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	manager.transform = Transform3D(Basis.IDENTITY, manager.base_position)
	manager._free_aim = Vector2.ZERO
	manager.sway = Vector2.ZERO
	manager.sway_velocity = Vector2.ZERO
	manager._drag = Vector2.ZERO
	manager._drag_velocity = Vector2.ZERO
	manager._lean = 0.0
	manager.wall_pushback = 0.0
	manager._breath_time = 0.0
	manager._walk_phase = 0.0
	player.weapon_aim_pivot.transform = Transform3D.IDENTITY
	animation.play(weapon.idle_animation, 0.0)
	animation.advance(0.0)
	var view := weapon.authored_camera
	var rest_camera := view.global_transform
	var rest_fov := view.fov
	var dt := 1.0 / fps
	weapon.set_aiming(scenario != "transition")
	for frame: int in fps:
		weapon._process(dt)
	player._process(dt)
	check(_near_plane_intersections(view).is_empty(), "idle pose has no visible near-plane cut")
	check(weapon._clearance_pivot.transform.is_equal_approx(Transform3D.IDENTITY), "idle framing has no correction")
	var shots := 0
	var next_shot := 0.0
	var peak_kick := 0.0
	var clipped_frames := 0
	var clipped_without_spring := 0
	for frame: int in fps * 4:
		var time := frame * dt
		var ads := scenario != "transition" or (time > 0.15 and time < 1.0) or time > 1.3
		if ads:
			Input.action_press("aim")
		else:
			Input.action_release("aim")
		if scenario == "motion":
			player.velocity = Vector3(3.0, 0.0, -3.0)
			manager.set_lean(sin(time * 3.0))
			var motion := Vector2(cos(time * 4.0), sin(time * 3.0)) * 800.0 * dt
			manager.add_look_impulse(motion)
			var event := InputEventMouseMotion.new()
			event.relative = motion
			bodycam._unhandled_input(event)
		if scenario == "wall":
			# Compose the complete retraction range with a live recoil spring.
			manager.wall_pushback = (sin(time * 3.0) + 1.0) * 0.31
		manager._process(dt)
		bodycam._physics_process(dt)
		bodycam._process(dt)
		if shots < 30 and time >= next_shot:
			weapon.fire_once()
			shots += 1
			next_shot += 60.0 / weapon.rounds_per_minute
		weapon._process(dt)
		animation.advance(dt)
		player._process(dt)
		var cuts := _near_plane_intersections(view)
		if not cuts.is_empty():
			clipped_frames += 1
		# Diagnose independent movement/animation clipping without changing the
		# tested pose or relaxing the full-pose assertion below.
		if scenario == "motion" or scenario == "wall":
			if not _near_plane_intersections(view, weapon.model_root).is_empty():
				clipped_without_spring += 1
		check(cuts.is_empty(), "%s fps=%d frame=%d shot=%d kick=%.4f pitch=%.4f meshes=%s" % [scenario, fps, frame, shots, weapon.model_root.position.z, weapon.model_root.rotation.x, cuts])
		check(view.global_transform.is_equal_approx(rest_camera) and view.fov == rest_fov, "camera framing unchanged")
		peak_kick = maxf(peak_kick, weapon.model_root.position.z)
		var motion_scale := lerpf(1.0, weapon.ads_recoil_motion_scale, weapon._aim_weight)
		check(weapon.model_root.position.is_equal_approx(Vector3(weapon._kick_side * 0.12 * motion_scale, 0.0, weapon._kick_offset * motion_scale)), "only recoil moves the model; no arm lowering")
		check(weapon.model_root.rotation.is_equal_approx(Vector3(weapon._kick_pitch * motion_scale, 0.0, weapon._kick_roll * 0.7 * motion_scale)), "only scaled recoil rotates the model")
		check(weapon.transform.is_equal_approx(Transform3D.IDENTITY.interpolate_with(weapon._ads_transform, weapon._aim_weight)), "firing never resets the raised hands pose")
		check(weapon.model_root.get_parent() == weapon._clearance_pivot and weapon._clearance_pivot.transform.is_equal_approx(Transform3D.IDENTITY), "no extra arm correction pivot")
		check(weapon.model_root.global_basis.get_scale().is_equal_approx(Vector3.ONE), "weapon scale unchanged")
		check(is_zero_approx(weapon.clearance_offset), "whole-arm forward correction stays disabled")
		samples += 1
	check(shots == 30 and weapon.ammo == 0, "complete magazine fired")
	check(peak_kick > 0.005, "visual recoil remains visible")
	print("ADS_RECOIL_MAGAZINE scenario=", scenario, " fps=", fps, " shots=", shots, " clipped_frames=", clipped_frames, " clipped_without_spring=", clipped_without_spring, " peak_kick=", peak_kick)
	# Recovery must preserve ADS; holstering alone restores the base pose.
	manager.transform = Transform3D(Basis.IDENTITY, manager.base_position)
	player.weapon_aim_pivot.transform = Transform3D.IDENTITY
	animation.play(weapon.idle_animation, 0.0)
	animation.advance(0.0)
	weapon.set_aiming(true)
	for frame: int in fps * 2:
		weapon._process(dt)
		weapon.enforce_camera_clearance(dt)
	check(weapon.transform.is_equal_approx(weapon._ads_transform), "recovery retains the raised hands pose")
	check(weapon.model_root.position.length() < 0.0001, "recoil settles without a residual translation")
	weapon.reset_recoil()
	check(weapon.transform.is_equal_approx(Transform3D.IDENTITY) and weapon.model_root.transform.is_equal_approx(Transform3D.IDENTITY), "holster clears recoil and ADS")

func _check_detector() -> void:
	var rect := Rect2(-0.01, -0.01, 0.02, 0.02)
	check(_triangle_cuts_rect(Vector3(-0.1, 0, -0.1), Vector3(0.1, 0, -0.1), Vector3(0, 0, 0.1), -0.01, rect), "detect spanning triangle with all vertices outside lens")
	check(not _triangle_cuts_rect(Vector3(-0.1, -0.1, -0.1), Vector3(0.1, -0.1, -0.1), Vector3(0, -0.1, 0.1), -0.01, rect), "allow intentional cropping below the frame")

func _check_gameplay_recoil(player: PlayerController, weapon: WeaponBase) -> void:
	var manager := player.weapon_manager
	var profile := weapon.ads_recoil_motion_scale
	var reference: Array[Vector3] = []
	# Identical random series with the old/new visual profile must give exactly
	# the same real aim and free aim on every shot, not just similar averages.
	for pass_index: int in 2:
		seed(781)
		weapon.reset_recoil()
		weapon.ads_recoil_motion_scale = 1.0 if pass_index == 0 else profile
		(player.camera as BodycamPhysics).reset_recoil()
		player.bodycam.rotation = Vector3.ZERO
		player.rotation = Vector3.ZERO
		manager._free_aim = Vector2.ZERO
		weapon.set_aiming(true)
		for frame: int in 120:
			weapon._process(1.0 / 60.0)
		for shot: int in 30:
			weapon._apply_recoil()
			weapon._process(60.0 / weapon.rounds_per_minute)
			var aim := Vector3(player.bodycam.rotation.x, player.rotation.y, manager.free_aim().y)
			if pass_index == 0:
				reference.append(aim)
			else:
				check(aim.is_equal_approx(reference[shot]), "visual profile does not weaken gameplay recoil")
		check(player.bodycam.rotation.x > deg_to_rad(20.0), "uncompensated real aim still climbs")
	weapon.ads_recoil_motion_scale = profile
	weapon.reset_recoil()
	weapon._apply_recoil()
	weapon._process(1.0 / 60.0)
	check(is_equal_approx(weapon.model_root.position.z, weapon._kick_offset) and is_equal_approx(weapon.model_root.rotation.x, weapon._kick_pitch), "hip fire retains full visual recoil")
	weapon.reset_recoil()

func _live_magazine(player: PlayerController, weapon: WeaponBase) -> void:
	var manager := player.weapon_manager
	manager._select(0)
	weapon.ammo = weapon.magazine_size
	manager.wall_pushback = 0.0
	manager.wall_blocked = false
	manager._free_aim = Vector2.ZERO
	manager.sway = Vector2.ZERO
	manager.sway_velocity = Vector2.ZERO
	manager._drag = Vector2.ZERO
	manager._drag_velocity = Vector2.ZERO
	manager.set_lean(0.0)
	player.velocity = Vector3.ZERO
	player.weapon_aim_pivot.transform = Transform3D.IDENTITY
	weapon._animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	manager.set_process(true)
	weapon.set_process(true)
	player.set_process(true)
	player.camera.set_process(true)
	Input.action_press("aim")
	# Real engine processing order, input-driven automatic fire and the actual
	# AnimationPlayer. Sample after the player final-pose pass, before rendering.
	var monitor := PoseMonitor.new()
	monitor.process_priority = player.process_priority + 1
	monitor.inspect = func() -> void:
		check(_near_plane_intersections(weapon.authored_camera).is_empty(), "live final rendered pose has no near-plane cut")
		samples += 1
	player.get_parent().add_child(monitor)
	for frame: int in 30:
		await process_frame
	Input.action_press("fire")
	var deadline := Time.get_ticks_msec() + 8000
	while weapon.ammo > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	Input.action_release("fire")
	check(weapon.ammo == 0, "live automatic fire consumes a complete magazine")
	for frame: int in 30:
		await process_frame
	monitor.free()
	manager.set_process(false)
	weapon.set_process(false)
	player.set_process(false)
	player.camera.set_process(false)
	print("ADS_RECOIL_LIVE remaining_ammo=", weapon.ammo)

func _cache_geometry(weapon: WeaponBase) -> void:
	_surfaces.clear()
	for mesh: MeshInstance3D in weapon.model_root.find_children("*", "MeshInstance3D", true, false):
		if mesh.skin == null:
			continue
		var skeleton := mesh.get_node(mesh.skeleton) as Skeleton3D
		var bone_map := PackedInt32Array()
		for bind: int in mesh.skin.get_bind_count():
			var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind))
			bone_map.append(bone if bone >= 0 else mesh.skin.get_bind_bone(bind))
		for surface: int in mesh.mesh.get_surface_count():
			_surfaces.append({"mesh": mesh, "skeleton": skeleton, "map": bone_map, "arrays": mesh.mesh.surface_get_arrays(surface)})

func _near_plane_intersections(camera: Camera3D, without_recoil: Node3D = null) -> Array[String]:
	var cuts: Array[String] = []
	var size := camera.get_viewport().get_visible_rect().size
	var aspect := size.x / size.y
	var half := Vector2.ONE * camera.near * tan(deg_to_rad(camera.fov * 0.5))
	if camera.keep_aspect == Camera3D.KEEP_HEIGHT:
		half.x *= aspect
	else:
		half.y /= aspect
	var rect := Rect2(-half, half * 2.0)
	for surface: Dictionary in _surfaces:
		var mesh := surface.mesh as MeshInstance3D
		if not mesh.is_visible_in_tree():
			continue
		var skeleton := surface.skeleton as Skeleton3D
		var mesh_pose := mesh.global_transform
		if without_recoil != null:
			# Pure measurement: never rewrite the live node transform. Repeated
			# basis/Euler decomposition in a probe can introduce scale drift.
			mesh_pose = (without_recoil.get_parent() as Node3D).global_transform * without_recoil.global_transform.affine_inverse() * mesh_pose
		var view := camera.global_transform.affine_inverse() * mesh_pose
		var poses: Array[Transform3D] = []
		for bind: int in mesh.skin.get_bind_count():
			poses.append(view * skeleton.get_bone_global_pose(surface.map[bind]) * mesh.skin.get_bind_pose(bind))
		var arrays: Array = surface.arrays
		var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var influences := bones.size() / source.size()
		var vertices := PackedVector3Array()
		vertices.resize(source.size())
		for index: int in source.size():
			var point := Vector3.ZERO
			for influence: int in influences:
				var slot := index * influences + influence
				if weights[slot] > 0.0:
					point += (poses[bones[slot]] * source[index]) * weights[slot]
			vertices[index] = point
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for triangle: int in range(0, indices.size(), 3):
			if _triangle_cuts_rect(vertices[indices[triangle]], vertices[indices[triangle + 1]], vertices[indices[triangle + 2]], -camera.near, rect):
				cuts.append(str(mesh.name))
				break
	return cuts

func _triangle_cuts_rect(a: Vector3, b: Vector3, c: Vector3, z: float, rect: Rect2) -> bool:
	if minf(a.z, minf(b.z, c.z)) > z or maxf(a.z, maxf(b.z, c.z)) < z:
		return false
	var points := PackedVector2Array()
	var vertices := [a, b, c]
	for edge: int in 3:
		var start: Vector3 = vertices[edge]
		var end: Vector3 = vertices[(edge + 1) % 3]
		if (start.z <= z and end.z > z) or (end.z <= z and start.z > z):
			var hit := start.lerp(end, (z - start.z) / (end.z - start.z))
			points.append(Vector2(hit.x, hit.y))
	if points.size() != 2:
		return false
	if rect.has_point(points[0]) or rect.has_point(points[1]):
		return true
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for edge: int in 4:
		if Geometry2D.segment_intersects_segment(points[0], points[1], corners[edge], corners[(edge + 1) % 4]) != null:
			return true
	return false
