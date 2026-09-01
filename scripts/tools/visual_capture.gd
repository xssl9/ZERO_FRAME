extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var scene_path := "res://scenes/levels/test_range.tscn"
	var output_path := "/tmp/zero_frame_capture.png"
	var override_position := Vector3.INF
	var override_exposure := -1.0
	var override_sun := -1.0
	var disable_probes := false
	var original_materials := false
	var clean_world := false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--scene="):
			scene_path = argument.trim_prefix("--scene=")
		elif argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--position="):
			var parts := argument.trim_prefix("--position=").split(",")
			if parts.size() == 3:
				override_position = Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
		elif argument.begins_with("--exposure="):
			override_exposure = argument.trim_prefix("--exposure=").to_float()
		elif argument.begins_with("--sun="):
			override_sun = argument.trim_prefix("--sun=").to_float()
		elif argument == "--disable-probes":
			disable_probes = true
		elif argument == "--original-materials":
			original_materials = true
		elif argument == "--clean-world":
			clean_world = true
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("CAPTURE_LOAD_FAILED " + scene_path)
		quit(1)
		return
	root.content_scale_size = Vector2i(1280, 720)
	var level := packed.instantiate()
	root.add_child(level)
	await process_frame
	if override_exposure >= 0.0:
		var photo := level.find_child("PhysicalDayEnvironment", true, false)
		if photo != null:
			photo.set("exposure_multiplier", override_exposure)
			photo.call("apply_preset")
	if override_sun >= 0.0:
		var sun := level.find_child("PhysicalSun", true, false) as DirectionalLight3D
		if sun != null:
			sun.light_energy = override_sun
	if disable_probes:
		for node: Node in level.find_children("*", "ReflectionProbe", true, false):
			(node as ReflectionProbe).visible = false
	if original_materials:
		for mesh_name: String in ["Structures_8", "Structures_2"]:
			var mesh := level.find_child(mesh_name, true, false) as MeshInstance3D
			if mesh != null:
				mesh.material_override = null
	if clean_world:
		for layer: Node in level.find_children("*", "CanvasLayer", true, false):
			(layer as CanvasLayer).visible = false
	if override_position != Vector3.INF:
		var player := get_first_node_in_group("player") as PlayerController
		if player != null:
			player.global_position = override_position
			player.velocity = Vector3.ZERO
			player.reset_physics_interpolation()
	for frame: int in 60:
		await process_frame
	var image := root.get_texture().get_image()
	var error := image.save_png(output_path)
	print("VISUAL_CAPTURE path=", output_path, " size=", image.get_size(), " error=", error_string(error))
	level.free()
	for frame: int in 6:
		await process_frame
	quit(0 if error == OK else 1)
