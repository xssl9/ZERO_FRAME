extends SceneTree

## Finds a standing spot in an arbitrary level and renders an overview of it. Raycasts a
## grid of candidates, keeps the ones with floor under them, headroom above and clearance
## around, then prints the one nearest the map centre. Also drops an overview PNG so the
## layout can be judged before hand-placing a spawn.
##
## godot --script res://scripts/tools/find_spawn.gd -- --scene=res://scenes/levels/x.tscn

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene_path := "res://scenes/levels/pvp_linse.tscn"
	var output_path := "/tmp/zf_overview.png"
	var clearance := 1.1
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--scene="):
			scene_path = argument.trim_prefix("--scene=")
		elif argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--clearance="):
			clearance = argument.trim_prefix("--clearance=").to_float()
	var level := (load(scene_path) as PackedScene).instantiate()
	root.add_child(level)
	var player := get_first_node_in_group("player") as Node3D
	if player != null:
		player.queue_free()
	root.content_scale_size = Vector2i(1280, 720)
	for frame: int in 30:
		await physics_frame
	# The level lives in the root viewport's world; WorldEnvironment is not a Node3D, so
	# the space state has to come from the viewport rather than from the level's children.
	var space := root.world_3d.direct_space_state
	var bounds := AABB()
	for node: Node in level.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		var world := instance.global_transform * instance.mesh.get_aabb()
		bounds = world if bounds.size == Vector3.ZERO else bounds.merge(world)
	print("SPAWN_SCAN bounds pos=", bounds.position.snappedf(0.01), " size=", bounds.size.snappedf(0.01))
	var centre := bounds.get_center()
	var best := Vector3.INF
	var best_distance := INF
	var candidates := 0
	var step := 1.0
	var x := bounds.position.x + step
	while x < bounds.end.x:
		var z := bounds.position.z + step
		while z < bounds.end.z:
			var floor_point := _floor_at(space, Vector3(x, bounds.end.y + 1.0, z), bounds.position.y - 1.0)
			z += step
			if floor_point == Vector3.INF:
				continue
			if not _has_room(space, floor_point, clearance):
				continue
			candidates += 1
			var flat := Vector2(floor_point.x - centre.x, floor_point.z - centre.z).length()
			if flat < best_distance:
				best_distance = flat
				best = floor_point
		x += step
	print("SPAWN_SCAN candidates=", candidates, " best=", best.snappedf(0.01), " distance_to_centre=", snappedf(best_distance, 0.01))
	_place_overview_camera(level, bounds)
	for frame: int in 90:
		await process_frame
	var image := root.get_texture().get_image()
	print("SPAWN_SCAN overview=", output_path, " error=", error_string(image.save_png(output_path)))
	quit()

func _floor_at(space: PhysicsDirectSpaceState3D, from: Vector3, to_y: float) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(from, Vector3(from.x, to_y, from.z))
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	# Only floors, not walls or ceilings.
	if (hit["normal"] as Vector3).y < 0.7:
		return Vector3.INF
	return hit["position"] as Vector3

func _has_room(space: PhysicsDirectSpaceState3D, floor_point: Vector3, clearance: float) -> bool:
	var head := floor_point + Vector3.UP * 1.9
	var up_query := PhysicsRayQueryParameters3D.create(floor_point + Vector3.UP * 0.25, head)
	if not space.intersect_ray(up_query).is_empty():
		return false
	var chest := floor_point + Vector3.UP * 1.1
	for direction: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var side := PhysicsRayQueryParameters3D.create(chest, chest + direction * clearance)
		if not space.intersect_ray(side).is_empty():
			return false
	return true

func _place_overview_camera(level: Node, bounds: AABB) -> void:
	var camera := Camera3D.new()
	var centre := bounds.get_center()
	var radius := maxf(bounds.size.length() * 0.55, 6.0)
	camera.position = centre + Vector3(radius * 0.55, radius * 0.7, radius * 0.55)
	camera.look_at_from_position(camera.position, centre, Vector3.UP)
	camera.far = radius * 8.0
	camera.current = true
	level.add_child(camera)
