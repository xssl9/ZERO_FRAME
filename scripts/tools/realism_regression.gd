extends SceneTree

## Run headless for state/gameplay, then WITHOUT --headless for real Forward+ shaders,
## HDR readback and motion captures. Never equate headless success with visual approval.
var failures: int = 0
var gpu: bool = false

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("REALISM_FAIL " + message)

func _run() -> void:
	gpu = DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "forward_plus"
	var wet := WetnessManager.new()
	wet.wetness = 0.0
	wet.target_wetness = 1.0
	wet.advance(22.5)
	check(is_equal_approx(wet.wetness, 0.5), "soak at 45 seconds")
	wet.advance(-10.0)
	check(is_equal_approx(wet.wetness, 0.5), "negative dt cannot reverse wetness")
	wet.target_wetness = 0.0
	wet.advance(30.0)
	check(is_equal_approx(wet.wetness, 0.3), "dry at 150 seconds")
	wet.free()
	for map_name: String in ["dev_test_grid", "pvp_linse", "parking_garage"]:
		ProjectSettings.set_setting("zero_frame/graphics_quality", 2)
		ProjectSettings.set_setting("zero_frame/weather", 0)
		var level := (load("res://scenes/levels/%s.tscn" % map_name) as PackedScene).instantiate()
		root.add_child(level)
		for frame: int in 90:
			await physics_frame
		var host := level.get_node("PhotorealEnvironment") as PhotorealEnvironment
		var player := level.get_node("Player") as PlayerController
		check(player.is_on_floor(), map_name + " player grounded")
		check(player.weapon_manager.weapons.size() == 2, "weapon inventory intact")
		check(host.wetness_manager != null, "wetness manager bound")
		var meter := host.exposure_controller
		check(meter != null, "exposure controller bound")
		if gpu:
			check(meter.sample_count > 0, map_name + " real GPU HDR samples")
			check(is_finite(meter.measured_luminance) and meter.measured_luminance > 0.0, "finite HDR luminance")
		for weather: int in [1, 2, 3, 0]:
			if host.standing_water < 0.0:
				host.weather = weather + 1 as PhotorealEnvironment.Weather
			host.apply_preset()
			for frame: int in 12:
				await physics_frame
			if host.standing_water < 0.0:
				check(host.profile.label == WeatherVisualProfile.defaults(weather).label, "weather ID compatibility")
				var rain := level.find_child("Rain", true, false) as RainSystem
				check(rain != null, map_name + " rain exists")
				if rain != null:
					check(is_equal_approx(rain.intensity, host.profile.rain_intensity), "rain tracks profile")
			check(is_equal_approx(host.environment.tonemap_exposure, player.weapon_environment.environment.tonemap_exposure), "world/viewmodel share exposure")
			check(host.environment != player.weapon_environment.environment, "isolated environments")
			if gpu:
				await RenderingServer.frame_post_draw
				var path := "/tmp/zero_frame_%s_weather%d.png" % [map_name, weather]
				check(root.get_texture().get_image().save_png(path) == OK, "capture " + path)
		for quality: int in [1, 3, 2]:
			host.quality_preset = quality as PhotorealEnvironment.QualityPreset
			host.apply_preset()
			await process_frame
			if gpu:
				check(host.resolved_quality == quality, "preset selection")
				check(root.use_taa == (quality >= 2), "world temporal AA")
				check(not player.weapon_camera.get_viewport().use_taa, "weapon MSAA, not TAA")
		var before := player.global_position
		Input.action_press("move_forward")
		Input.action_press("sprint")
		for frame: int in 24:
			await physics_frame
		Input.action_release("sprint")
		Input.action_press("crouch")
		for frame: int in 16:
			await physics_frame
		Input.action_release("crouch")
		Input.action_release("move_forward")
		check(player.global_position.distance_to(before) > 0.1, "movement remains live")
		for index: int in 2:
			player.weapon_manager._select(index)
			var weapon := player.weapon_manager.weapons[index]
			var ammo := weapon.ammo
			await physics_frame
			weapon.fire_once()
			check(weapon.ammo == ammo - 1, "firing consumes one round")
			check(weapon._world_flash_light != null and weapon._world_flash_light.light_energy > 0.0, "world flash light")
			for frame: int in 8:
				await physics_frame
			check(player.weapon_camera.get_viewport().get_camera_3d() == weapon.authored_camera, "authored weapon camera retained")
		print("REALISM_MAP ", map_name, " gpu=", gpu, " luminance=", meter.measured_luminance, " samples=", meter.sample_count, " exposure=", meter.current_exposure,
			" draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " vram=", Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
		level.free()
		for frame: int in 8:
			await process_frame
	print("REALISM_RESULT failures=", failures, " gpu=", gpu)
	quit(1 if failures > 0 else 0)
