extends SceneTree

## Headless: actual imported mesh/placement integration. Forward+: paired captures
## and short A/B frame intervals at a fixed render resolution, not visual approval.
const DIRECTORY := "res://assets/environment/parking/fixture_details/"
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FIXTURE_FAIL " + message)

func vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

func bounds_of(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var box := mesh.global_transform * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func _run() -> void:
	var gpu := DisplayServer.get_name() != "headless"
	if gpu:
		check(RenderingServer.get_current_rendering_method() == "forward_plus", "requires Forward+ GPU")
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_size = Vector2i(1280, 720)
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + "manifest.json"))
	check(FileAccess.get_sha256("res://" + manifest.source) == manifest.source_sha256, "source glTF unchanged")
	check(FileAccess.get_sha256("res://" + manifest.source.replace(".gltf", ".bin")) == manifest.buffer_sha256, "source mesh buffer unchanged")
	ProjectSettings.set_setting("zero_frame/graphics_quality", 2)
	ProjectSettings.set_setting("zero_frame/weather", 0)
	var level := (load("res://scenes/levels/parking_garage.tscn") as PackedScene).instantiate()
	root.add_child(level)
	for frame: int in 90:
		await physics_frame
	var details := level.get_node("FixtureDetails") as Node3D
	var meshes := details.find_children("*", "MeshInstance3D", true, false)
	check(meshes.size() == 5, "five row meshes, not hundreds of separate draw instances")
	check(details.find_children("*", "Light3D", true, false).is_empty(), "no duplicate light emitters")
	check(details.find_children("*", "CollisionObject3D", true, false).is_empty(), "no new gameplay collision")
	var triangles := 0
	var surfaces := 0
	for node: Node in meshes:
		var mesh := node as MeshInstance3D
		check(mesh.scale.is_equal_approx(Vector3.ONE), "unit mesh scale")
		check(mesh.mesh.get_surface_count() == 2, "two material surfaces per row")
		for surface: int in mesh.mesh.get_surface_count():
			surfaces += 1
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			triangles += indices.size() / 3
			check(uv.size() == vertices.size() and normals.size() == vertices.size(), "UVs and normals survive glTF import")
			for normal: Vector3 in normals:
				check(normal.is_finite() and absf(normal.length() - 1.0) < 0.01, "finite unit normal")
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			check(material != null, "standard PBR after MaterialResponse binding")
			if material != null:
				check(not material.emission_enabled, "housing does not duplicate diffuser emission")
				check(material.roughness > 0.3 and material.roughness < 0.7, "plausible finish roughness")
				check(is_equal_approx(material.metallic, 0.0) or is_equal_approx(material.metallic, 1.0), "paint/metal separation")
	check(triangles == int(manifest.triangles), "triangle count matches Blender readback")
	var expected := AABB(vector(manifest.bounds_low), vector(manifest.bounds_high) - vector(manifest.bounds_low))
	var actual := bounds_of(details)
	check(actual.position.distance_to(expected.position) < 0.001 and actual.size.distance_to(expected.size) < 0.001, "Blender Z-up to Godot Y-up conversion")
	check(absf(actual.end.y - 3.1) < 0.001, "mounts meet ceiling, not floating")
	check(actual.position.y > 2.9, "detail remains above player clearance")
	var lights := level.get_node("Lights")
	check(lights.get_child_count() == 64, "existing light count preserved")
	for item: Dictionary in manifest.fixtures:
		var point := vector(item.centre)
		var matched := 0
		for child: Node in lights.get_children():
			var lamp := child as OmniLight3D
			if String(lamp.name).begins_with("Deck") and Vector2(lamp.position.x, lamp.position.z).distance_to(Vector2(point.x, point.z)) < 0.001:
				matched += 1
				check(absf(lamp.position.y - 2.87) < 0.001, "existing deck light not moved")
		check(matched == 1, "one housing per existing deck light")
	# Reuse as a child of a rotated/translated parent: no baked double axis conversion.
	var wrapper := Node3D.new()
	root.add_child(wrapper)
	wrapper.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(10, 3, -4))
	var reused := (load(DIRECTORY + "deck_fixture_housings.glb") as PackedScene).instantiate() as Node3D
	wrapper.add_child(reused)
	var moved := bounds_of(reused)
	var wanted := wrapper.transform * expected
	check(moved.position.distance_to(wanted.position) < 0.001 and moved.size.distance_to(wanted.size) < 0.001, "asset works under parent transforms")
	wrapper.free()
	var player := level.get_node("Player") as PlayerController
	check(player.is_on_floor() and player.weapon_manager.weapons.size() == 2, "surrounding gameplay initialized")
	if gpu:
		await _gpu_comparison(level, details)
	level.free()
	for frame: int in 12:
		await physics_frame
	print("FIXTURE_RESULT failures=", failures, " gpu=", gpu, " fixtures=", manifest.fixture_count, " triangles=", triangles, " surfaces=", surfaces)
	quit(1 if failures else 0)

func _gpu_comparison(level: Node3D, details: Node3D) -> void:
	var host := level.get_node("PhotorealEnvironment") as PhotorealEnvironment
	var player := level.get_node("Player") as PlayerController
	# Fixed close view of the first row. No player camera/weapon authoring is changed.
	player.set_physics_process(false)
	var camera := Camera3D.new()
	level.add_child(camera)
	camera.position = Vector3(-25.0, 1.65, -15.5)
	camera.look_at(Vector3(-26.0, 2.97, -18.0), Vector3.UP)
	camera.current = true
	for layer: Node in player.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	for quality: int in [2, 3]:
		host.quality_preset = quality as PhotorealEnvironment.QualityPreset
		host.apply_preset()
		for frame: int in 120:
			await process_frame
			await RenderingServer.frame_post_draw
		host.exposure_controller.enabled = false
		for enabled: bool in [false, true]:
			details.visible = enabled
			for frame: int in 60:
				await process_frame
				await RenderingServer.frame_post_draw
			var intervals: Array[float] = []
			var draws := 0.0
			var previous := Time.get_ticks_usec()
			for frame: int in 120:
				await process_frame
				await RenderingServer.frame_post_draw
				var now := Time.get_ticks_usec()
				intervals.append(float(now - previous) / 1000.0)
				previous = now
				draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			intervals.sort()
			var image := root.get_texture().get_image()
			check(image.get_size() == Vector2i(1280, 720), "actual GPU render target is 1280x720")
			var path := "/tmp/zero_frame_fixture_q%d_%s.png" % [quality, "after" if enabled else "before"]
			check(image.save_png(path) == OK, "GPU capture saved")
			print("FIXTURE_BENCH quality=", quality, " details=", enabled, " resolution=", image.get_size(),
				" median_ms=", snappedf(intervals[60], 0.01), " p95_ms=", snappedf(intervals[114], 0.01),
				" draws=", roundi(draws / 120.0), " capture=", path)
