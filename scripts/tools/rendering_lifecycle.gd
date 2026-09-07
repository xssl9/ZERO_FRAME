extends SceneTree

## Isolate render-resource teardown independently of gameplay/quality switching.
## --no-meter and --no-rain isolate optional systems; --cycles=3 tests repeated loads.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var cycles := 1
	var map_name := "dev_test_grid"
	for arg: String in args:
		if arg.begins_with("--cycles="):
			cycles = maxi(1, arg.trim_prefix("--cycles=").to_int())
		if arg.begins_with("--map="):
			map_name = arg.trim_prefix("--map=")
	for cycle: int in cycles:
		var level := (load("res://scenes/levels/%s.tscn" % map_name) as PackedScene).instantiate()
		var host := level.get_node("PhotorealEnvironment") as PhotorealEnvironment
		host.enable_auto_exposure = "--no-meter" not in args
		host.quality_preset = PhotorealEnvironment.QualityPreset.HIGH
		if "--no-rain" in args:
			var rain := level.get_node_or_null("Rain")
			if rain != null:
				rain.free()
		root.add_child(level)
		for frame: int in 90:
			await process_frame
		if "--switch-weather" in args:
			for weather: int in [2, 3, 4, 1]:
				host.weather = weather as PhotorealEnvironment.Weather
				host.apply_preset()
				for frame: int in 20:
					await process_frame
		if "--switch-quality" in args:
			for quality: int in [1, 3, 2]:
				host.quality_preset = quality as PhotorealEnvironment.QualityPreset
				host.apply_preset()
				for frame: int in 20:
					await process_frame
		print("LIFECYCLE loaded=", cycle, " meter=", host.enable_auto_exposure)
		level.free()
		for frame: int in 30:
			await process_frame
	print("LIFECYCLE complete cycles=", cycles)
	quit()
