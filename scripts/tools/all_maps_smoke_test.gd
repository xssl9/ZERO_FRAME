extends SceneTree

const MAPS: PackedStringArray = [
	"res://scenes/levels/dev_test_grid.tscn",
	"res://scenes/levels/pvp_linse.tscn",
	"res://scenes/levels/parking_garage.tscn",
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for path: String in MAPS:
		var packed := load(path) as PackedScene
		if packed == null:
			push_error("SMOKE_LOAD_FAILED " + path)
			continue
		var level := packed.instantiate()
		root.add_child(level)
		for frame: int in 90:
			await physics_frame
		var player := get_first_node_in_group("player") as PlayerController
		var on_floor := player != null and player.is_on_floor()
		var spawn_point := level.get_node_or_null("SpawnPoint3D") as Marker3D
		var spawn_xz_error := INF
		if player != null and spawn_point != null:
			spawn_xz_error = Vector2(player.global_position.x, player.global_position.z).distance_to(
				Vector2(spawn_point.global_position.x, spawn_point.global_position.z)
			)
		if spawn_xz_error > 0.05:
			push_error("SPAWN_POINT_MISMATCH %s error=%.3f" % [path, spawn_xz_error])
		var active_camera := "none"
		if player != null:
			var viewport := player.get_node("WeaponLayer/WeaponViewportContainer/WeaponViewport") as SubViewport
			var camera := viewport.get_camera_3d()
			if camera != null:
				active_camera = camera.name
		print("MAP_SMOKE path=", path, " player=", player != null, " on_floor=", on_floor,
			" spawn_xz_error=", snappedf(spawn_xz_error, 0.001), " weapon_camera=", active_camera)
		level.free()
		await process_frame
	quit()
