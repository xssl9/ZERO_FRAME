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
	for map_name: String in ["dev_test_grid", "pvp_linse", "parking_garage", "parking_garage_rework"]:
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
		if host.standing_water < 0.0:
			var roof := host.get_node("RainExposureMask") as RainExposureMask
			check(roof.ready_mask and roof.texture != null, "static roof mask completed")
			for material: ShaderMaterial in host.wetness_manager.materials:
				check(material.get_shader_parameter("rain_roof_ready") == true, "roof mask bound to weather materials")
		if map_name == "pvp_linse":
			check(level.get_node("Scan/ScanShape").transform.is_equal_approx(level.get_node("Scan/Mesh").transform), "scan collider uses rendered axis correction")
			check(not host.wetness_manager.materials.is_empty(), "scan participates in sheltered wetness")
		var meter := host.exposure_controller
		check(meter != null, "exposure controller bound")
		if gpu:
			check(meter.sample_count > 0, map_name + " real GPU HDR samples before synthetic tests")
		_check_tuning(host, player)
		_check_exposure(host)
		for debug_mode: int in RenderingDebug.Mode.size():
			host.rendering_debug.set_mode(debug_mode as RenderingDebug.Mode)
			await process_frame
			if gpu:
				await RenderingServer.frame_post_draw
			check(host.rendering_debug.mode == debug_mode, "debug mode selected")
		host.rendering_debug.set_mode(RenderingDebug.Mode.OFF)
		check(meter.enabled, "debug restores adaptation")
		await process_frame
		if gpu:
			check(meter.sample_count > 0, map_name + " real GPU HDR samples")
			check(is_finite(meter.measured_luminance) and meter.measured_luminance > 0.0, "finite HDR luminance")
		for weather: int in [1, 2, 3, 0]:
			if host.standing_water < 0.0:
				host.weather = weather + 1 as PhotorealEnvironment.Weather
			host.apply_preset()
			# Advance the simulation clock to the settled surface state for the capture;
			# actual soak/dry rates are checked independently above (no instant runtime wetting).
			host.wetness_manager.advance(150.0)
			host.wetness_manager.publish()
			for frame: int in 24:
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
			check(weapon._smoke_pool.size() == 4, "bounded four-puff pool")
			var first_puff := weapon._smoke_pool[0]
			check(first_puff.get_world_3d() == player.get_world_3d(), "smoke receives real world lighting")
			var puff_transform := first_puff.global_transform
			for frame: int in 15:
				await physics_frame
			weapon.fire_once()
			check(weapon._smoke_index == 2, "burst uses a different emitter, not restart of previous puff")
			check(first_puff.global_transform.is_equal_approx(puff_transform), "previous smoke remains world anchored")
			for frame: int in 8:
				await physics_frame
			check(player.weapon_camera.get_viewport().get_camera_3d() == weapon.authored_camera, "authored weapon camera retained")
		print("REALISM_MAP ", map_name, " gpu=", gpu, " luminance=", meter.measured_luminance, " samples=", meter.sample_count, " exposure=", meter.current_exposure,
			" draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " vram=", Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
		level.free()
		# Rendering can run uncapped; eight idle frames may take <1 ms. Allow real
		# mixer/physics time for asynchronous audio playback release before shutdown.
		for frame: int in 12:
			await physics_frame
	print("REALISM_RESULT failures=", failures, " gpu=", gpu)
	quit(1 if failures > 0 else 0)

func _check_tuning(host: PhotorealEnvironment, player: PlayerController) -> void:
	var tuning := host.get_node_or_null("RealismManager") as RealismManager
	check(tuning != null, "central tuning is instantiated")
	if tuning == null:
		return
	check(tuning._bodycam_material != null, "central tuning binds the existing lens")
	tuning.wetness_override = 0.42
	tuning.dust_amount = 0.08
	tuning.stain_amount = 0.12
	tuning.atmosphere_density_scale = 0.5
	host.apply_preset()
	check(is_equal_approx(host.wetness_manager.target_wetness, 0.42), "override survives preset changes")
	check(is_equal_approx(host.environment.volumetric_fog_density, host.atmosphere_density_in_effect() * 0.5), "fog scaling preserves map baseline")
	for material: ShaderMaterial in host.wetness_manager.materials:
		if material.shader.resource_path.ends_with("dev_grid.gdshader"):
			check(is_equal_approx(material.get_shader_parameter("dust_amount"), 0.08), "dust reaches bound materials")
			check(is_equal_approx(material.get_shader_parameter("stain_amount"), 0.12), "stains reach bound materials")
	tuning.wetness_override = -1.0
	var natural := host.standing_water if host.standing_water >= 0.0 else host.profile.wetness
	check(is_equal_approx(host.wetness_manager.target_wetness, natural), "clearing override restores weather target")
	tuning.dust_amount = 0.0
	tuning.stain_amount = 0.0
	tuning.atmosphere_density_scale = 1.0
	var lighting := player.get_node("WeaponLighting") as WeaponLighting
	lighting._process(0.0)
	check(is_equal_approx(player.weapon_environment.environment.ambient_light_energy, host.environment.ambient_light_energy), "no weapon-only ambient boost")
	check(is_equal_approx(player.weapon_environment.environment.glow_intensity, host.environment.glow_intensity), "same bloom response in both worlds")

func _check_exposure(host: PhotorealEnvironment) -> void:
	var ec := host.exposure_controller
	var saved := ec.current_exposure
	var samples := ec.sample_count
	var luminance := ec.measured_luminance
	ec.current_exposure = 1.0
	ec._on_luminance(100.0)
	ec._process(0.1)
	check(is_equal_approx(ec.current_exposure, pow(2.0, -0.12)), "bright exterior reduces exposure at 1.2 stops/s")
	ec.current_exposure = 1.0
	ec._on_luminance(0.001)
	ec._process(0.1)
	check(is_equal_approx(ec.current_exposure, pow(2.0, 0.06)), "dark interior increases exposure at 0.6 stops/s")
	var before := ec.current_exposure
	ec._process(-1.0)
	check(is_equal_approx(ec.current_exposure, before), "negative dt cannot reverse exposure")
	ec._on_luminance(NAN)
	check(is_equal_approx(ec.measured_luminance, 0.001), "NaN meter sample rejected")
	ec.current_exposure = saved
	host.environment.tonemap_exposure = saved
	ec._on_luminance(luminance)
	ec.sample_count = samples
