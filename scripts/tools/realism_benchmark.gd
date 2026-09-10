extends SceneTree

## GPU-only camera sweep, not a claim of visual approval or worst-case gameplay FPS.
## Reports actual wall frame intervals (including renderer synchronization), not estimates.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus":
		push_error("Benchmark requires a visible Forward+ renderer")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	print("BENCH_DEVICE ", RenderingServer.get_video_adapter_name(), " resolution=", root.size)
	for map_name: String in ["dev_test_grid", "pvp_linse", "parking_garage"]:
		var level := (load("res://scenes/levels/%s.tscn" % map_name) as PackedScene).instantiate()
		root.add_child(level)
		for frame: int in 90:
			await physics_frame
		var host := level.get_node("PhotorealEnvironment") as PhotorealEnvironment
		var player := level.get_node("Player") as PlayerController
		var start_yaw := player.rotation.y
		for weather: int in ([1] if host.standing_water >= 0.0 else [1, 2]):
			for quality: int in [1, 2, 3]:
				host.weather = weather as PhotorealEnvironment.Weather
				host.quality_preset = quality as PhotorealEnvironment.QualityPreset
				host.apply_preset()
				host.wetness_manager.advance(150.0)
				host.wetness_manager.publish()
				player.rotation.y = start_yaw
				for frame: int in 90:
					await process_frame
					await RenderingServer.frame_post_draw
				var intervals: Array[float] = []
				var draw_calls := 0.0
				var previous := Time.get_ticks_usec()
				for frame: int in 120:
					player.rotation.y = start_yaw + sin(float(frame) / 119.0 * TAU) * 0.35
					await process_frame
					await RenderingServer.frame_post_draw
					var now := Time.get_ticks_usec()
					intervals.append(float(now - previous) / 1000.0)
					previous = now
					draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
				intervals.sort()
				print("BENCH map=", map_name, " weather=", host.profile.label, " quality=", quality,
					" median_ms=", snappedf(intervals[60], 0.01), " p95_ms=", snappedf(intervals[114], 0.01),
					" avg_draws=", roundi(draw_calls / 120.0), " vram_mib=", roundi(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0))
		level.free()
		for frame: int in 12:
			await physics_frame
	print("BENCH_COMPLETE")
	quit()
