extends SceneTree

## Exercises the real menu entry, imported geometry and actual player physics.
var failures := 0
var player: PlayerController

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("PARKING_LIVE_FAIL " + message)

func _run() -> void:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/parking_rework/live_export.json"))
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await scene_changed
	var buttons := current_scene.find_children("*", "Button", true, false)
	var selected := false
	for button: Button in buttons:
		if button.text == "ПАРКИНГ":
			button.pressed.emit()
			selected = true
			break
	check(selected, "parking menu button found")
	if not selected:
		quit(1)
		return
	await scene_changed
	var level := current_scene
	check(level.scene_file_path == "res://scenes/levels/parking_garage_rework.tscn", "menu loads the new map")
	var garage := level.get_node("Garage")
	check(garage.get_meta("parking_export_sha256", "") == report["glb_sha256"], "import matches current export hash")
	for old: String in ["Cars", "Props", "Paint", "Garage/Surfaces", "FixtureDetails", "ArchitecturalRework"]:
		check(not level.has_node(old), "no stale layout " + old)
	var meshes: Dictionary = {}
	for mesh: MeshInstance3D in garage.find_children("*", "MeshInstance3D", true, false):
		var source := String(mesh.get_meta("parking_source_name", ""))
		check(not meshes.has(source), "one instance per Blender object " + source)
		meshes[source] = mesh
	check(meshes.size() == report["meshes"].size(), "visible geometry count matches Blender")
	var solids := 0
	var max_bounds_error := 0.0
	for record: Dictionary in report["meshes"]:
		var name: String = record["name"]
		check(meshes.has(name), "exported mesh present " + name)
		if not meshes.has(name):
			continue
		var mesh := meshes[name] as MeshInstance3D
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		var low: Array = record["bounds_min"]
		var high: Array = record["bounds_max"]
		var difference := maxf(box.position.distance_to(Vector3(low[0], low[1], low[2])), box.end.distance_to(Vector3(high[0], high[1], high[2])))
		max_bounds_error = maxf(max_bounds_error, difference)
		check(difference < 0.005, "Blender bounds " + name + " error=" + str(difference))
		check(mesh.material_override == null, "no old material substitution " + name)
		check(mesh.has_node("ParkingCollision") == bool(record["solid"]), "collision selection " + name)
		if record["solid"]:
			solids += 1
	for hidden: String in report["excluded"]:
		check(not meshes.has(hidden), "hidden authoring object excluded " + hidden)
	check(level.get_node("Lights").get_child_count() == report["lights"].size(), "both floors have authored light positions")
	player = level.get_node("Player") as PlayerController
	for frame: int in 90:
		await physics_frame
	check(player.is_on_floor(), "spawn grounded")
	# Ground-floor west entrance -> ramp -> upper-floor entrance, then descend.
	player.global_position = Vector3(-28, 0.15, 15)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	for frame: int in 40:
		await physics_frame
	for target: Vector3 in [Vector3(-33.5, 0, 15), Vector3(-33.5, 3.4, -15), Vector3(-28, 3.4, -15), Vector3(-33.5, 3.4, -15), Vector3(-33.5, 0, 15), Vector3(-28, 0, 15)]:
		await walk_to(target)
	player.flashlight.visible = true
	check(player.flashlight.visible, "flashlight remains available")
	player.flashlight.visible = false
	for index: int in 2:
		player.weapon_manager._select(index)
		await physics_frame
		var weapon := player.weapon_manager.weapons[index]
		var ammo := weapon.ammo
		weapon.fire_once()
		check(weapon.ammo == ammo - 1, "weapon fires " + str(index))
		check(weapon._world_flash_light != null, "weapon world flash")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("/tmp/parking_live_gameplay.png") == OK, "gameplay GPU capture")
	print("PARKING_LIVE_RESULT failures=", failures, " meshes=", meshes.size(), " solids=", solids, " max_bounds_error_m=", max_bounds_error)
	# Let audio/physics finish releasing the just-fired weapons before shutdown,
	# as in realism_regression.gd; don't conflate abrupt test exit with a map leak.
	current_scene = null
	level.free()
	for frame: int in 12:
		await physics_frame
	quit(0 if failures == 0 else 1)

func walk_to(target: Vector3) -> void:
	var reached := false
	for frame: int in 1000:
		var direction := Vector3(target.x - player.global_position.x, 0, target.z - player.global_position.z)
		if direction.length() < 0.25:
			reached = true
			break
		player.rotation.y = atan2(-direction.x, -direction.z)
		Input.action_press("move_forward")
		await physics_frame
	Input.action_release("move_forward")
	for frame: int in 20:
		await physics_frame
	check(reached, "walk reaches " + str(target) + " actual=" + str(player.global_position))
	check(absf(player.global_position.y - target.y) < 0.15 and player.is_on_floor(), "grounding at " + str(target))
	print("PARKING_ROUTE target=", target, " actual=", player.global_position, " reached=", reached)
