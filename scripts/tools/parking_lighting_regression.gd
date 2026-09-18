extends SceneTree

var failures := 0
func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("PARKING_LIGHT_FAIL " + message)

func _run() -> void:
	var level := (load("res://scenes/levels/parking_garage_rework.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for frame: int in 30:
		await physics_frame
	var player := level.get_node("Player") as PlayerController
	var space := player.get_world_3d().direct_space_state
	var blocked := 0
	var total := 0
	for light: Node3D in level.get_node("Lights").get_children():
		if not light is SpotLight3D or str(light.name).begins_with("GP_"):
			continue
		total += 1
		check((-light.global_basis.z).dot(Vector3.DOWN) > 0.99, "ceiling light points down: " + str(light.name))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(light.global_position, light.global_position - light.global_basis.z * 0.4, 1))
		if not hit.is_empty():
			blocked += 1
			print("PARKING_BLOCKED ", light.name, " at=", hit.position, " collider=", hit.collider.get_parent().name)
	check(total == 93 and blocked == 0, "all 93 ceiling lamps clear of their own ceilings")
	print("PARKING_LIGHT_AUDIT blocked=", blocked, "/", total)
	var host := level.get_node("PhotorealEnvironment") as PhotorealEnvironment
	print("PARKING_AMBIENT source=", host.environment.ambient_light_source, " energy=", host.environment.ambient_light_energy)
	if DisplayServer.get_name() != "headless":
		player.get_node("WeaponLayer").hide()
		var camera := Camera3D.new()
		level.add_child(camera)
		camera.make_current()
		for height: float in [1.6, 5.0]:
			camera.position = Vector3(-22, height, 0)
			camera.look_at(Vector3(12, height - 0.4, 0))
			for frame: int in 90:
				await physics_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			check(image.save_png("/tmp/parking_light_%s.png" % height) == OK, "capture")
			var lit := host.exposure_controller.measured_luminance
			var samples := host.exposure_controller.sample_count
			check(samples > 0 and lit > 0.003, "real HDR illumination on floor " + str(height))
			level.get_node("Lights").hide()
			for frame: int in 90:
				await physics_frame
			var unlit := host.exposure_controller.measured_luminance
			check(host.exposure_controller.sample_count > samples, "fresh GPU samples with lamps off")
			check(lit > unlit * 1.2, "lamps actually illuminate visible surfaces, not only their own ceilings")
			print("PARKING_GPU floor_height=", height, " lit=", lit, " unlit=", unlit, " samples=", host.exposure_controller.sample_count)
			level.get_node("Lights").show()
	current_scene = null
	level.free()
	for frame: int in 12:
		await physics_frame
	print("PARKING_LIGHT_RESULT failures=", failures)
	quit(1 if failures else 0)
