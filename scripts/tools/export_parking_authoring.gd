extends SceneTree

## Export the ACTUAL visible gameplay assembly, not the obsolete source .blend.
## Standard PBR transfers through glTF. Procedural paint is rasterized by the real
## GPU shader; world-triplanar material parameters are carried in a manifest for
## Blender reconstruction. Screen-space water/GI/postprocessing are not geometry.
const DESTINATION := "/home/tuxpc/game/ZERO_FRAME_backups/parking_full_rework_20260908/"
const GROUPS := ["Garage", "Cars", "Props", "Paint", "FixtureDetails"]
var paint_cache: Dictionary = {}
var painted := 0
var bake_view: SubViewport
var bake_rect: ColorRect

func _initialize() -> void:
	call_deferred("_run")

func fail(message: String) -> void:
	push_error("AUTHORING_EXPORT_FAIL " + message)
	quit(1)

func json_value(value: Variant) -> Variant:
	if value is Texture2D:
		return ProjectSettings.globalize_path(value.resource_path)
	if value is Color:
		return [value.r, value.g, value.b, value.a]
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Vector2:
		return [value.x, value.y]
	if value == null or value is float or value is int or value is bool or value is String:
		return value
	return null

func transform_values(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z,
		t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z,
		t.origin.x, t.origin.y, t.origin.z]

func _paint_material(source: ShaderMaterial) -> StandardMaterial3D:
	if paint_cache.has(source):
		return paint_cache[source]
	var code := source.shader.code.replace("shader_type spatial;", "shader_type canvas_item;")
	var expression := RegEx.new()
	expression.compile("render_mode[^;]+;")
	code = expression.sub(code, "render_mode unshaded;")
	code = code.replace("void fragment() {", "void fragment() {\nvec3 ALBEDO = vec3(1.0); float ALPHA = 1.0; float ROUGHNESS; float METALLIC; float SPECULAR;")
	var end := code.rfind("}")
	code = code.substr(0, end) + "COLOR = vec4(ALBEDO, ALPHA);\n" + code.substr(end)
	var shader := Shader.new()
	shader.code = code
	var material := ShaderMaterial.new()
	material.shader = shader
	for parameter: Dictionary in source.shader.get_shader_uniform_list():
		material.set_shader_parameter(parameter.name, source.get_shader_parameter(parameter.name))
	bake_rect.material = material
	bake_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	await process_frame
	await RenderingServer.frame_post_draw
	var image := bake_view.get_texture().get_image()
	assert(image != null and not image.is_empty(), "Paint GPU readback failed")
	var path := DESTINATION + "paint_%03d.png" % painted
	assert(image.save_png(path) == OK, "Paint image save failed")
	var pbr := StandardMaterial3D.new()
	pbr.resource_name = "AuthoredPaint_%03d" % painted
	image.generate_mipmaps()
	pbr.albedo_texture = ImageTexture.create_from_image(image)
	pbr.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pbr.cull_mode = BaseMaterial3D.CULL_DISABLED
	pbr.roughness = 0.82
	painted += 1
	paint_cache[source] = pbr
	return pbr

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		fail("Requires GPU to transfer procedural paint, not a material-less shell")
		return
	if FileAccess.file_exists(DESTINATION + "assembly.glb") or FileAccess.file_exists(DESTINATION + "manifest.json"):
		fail("Refusing to overwrite previous authoring export")
		return
	DirAccess.make_dir_recursive_absolute(DESTINATION)
	ProjectSettings.set_setting("zero_frame/graphics_quality", 2)
	ProjectSettings.set_setting("zero_frame/weather", 0)
	var level := (load("res://scenes/levels/parking_garage.tscn") as PackedScene).instantiate()
	root.add_child(level)
	for frame: int in 60:
		await physics_frame
	level.process_mode = Node.PROCESS_MODE_DISABLED
	bake_view = SubViewport.new()
	bake_view.size = Vector2i(512, 512)
	bake_view.transparent_bg = true
	bake_view.disable_3d = true
	bake_view.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(bake_view)
	bake_rect = ColorRect.new()
	bake_rect.size = Vector2(512, 512)
	bake_view.add_child(bake_rect)
	var assembly := Node3D.new()
	assembly.name = "ZERO_FRAME_CompleteParking"
	var records: Array = []
	var counts: Dictionary = {}
	var triangles := 0
	for node: Node in level.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var path := String(level.get_path_to(mesh))
		var group := path.get_slice("/", 0)
		if not group in GROUPS or not mesh.is_visible_in_tree() or mesh.mesh == null:
			continue
		var copy := MeshInstance3D.new()
		copy.name = "ZF_%04d" % records.size()
		copy.mesh = mesh.mesh
		copy.transform = mesh.global_transform
		copy.cast_shadow = mesh.cast_shadow
		assembly.add_child(copy)
		copy.owner = assembly
		var shaders: Array = []
		for index: int in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(index)
			var material: Material = source
			var attributes := mesh.mesh.surface_get_arrays(index)
			var indices: PackedInt32Array = attributes[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = attributes[Mesh.ARRAY_VERTEX]
			triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
			if source is ShaderMaterial:
				var sm := source as ShaderMaterial
				var info: Dictionary = {"surface": index, "shader": sm.shader.resource_path, "parameters": {}}
				for parameter: Dictionary in sm.shader.get_shader_uniform_list():
					info.parameters[parameter.name] = json_value(sm.get_shader_parameter(parameter.name))
				shaders.append(info)
				if sm.shader.resource_path.ends_with("dev_grid.gdshader"):
					var pbr := StandardMaterial3D.new()
					pbr.resource_name = "Triplanar_" + String(copy.name)
					pbr.albedo_texture = sm.get_shader_parameter("albedo_texture")
					pbr.roughness_texture = sm.get_shader_parameter("arm_texture")
					pbr.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
					pbr.roughness = 1.0
					material = pbr
				elif sm.shader.resource_path.ends_with("bay_paint.gdshader") or sm.shader.resource_path.ends_with("graffiti.gdshader"):
					material = await _paint_material(sm)
				else:
					fail("Unmapped shader: " + sm.shader.resource_path)
					assembly.free()
					level.free()
					return
			copy.set_surface_override_material(index, material)
		var bounds := mesh.global_transform * mesh.get_aabb()
		records.append({"name": String(copy.name), "path": path, "group": group,
			"transform": transform_values(copy.transform), "shaders": shaders,
			"bounds_low": json_value(bounds.position), "bounds_high": json_value(bounds.end)})
		counts[group] = int(counts.get(group, 0)) + 1
	var lamps: Array = []
	for node: Node in level.get_node("Lights").get_children():
		var light := node as OmniLight3D
		lamps.append({"name": String(light.name), "transform": transform_values(light.global_transform),
			"color": json_value(light.light_color), "energy": light.light_energy,
			"range": light.omni_range, "shadow": light.shadow_enabled, "visible": light.visible})
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var appended := document.append_from_scene(assembly, state)
	if appended != OK:
		fail("GLTF append: " + error_string(appended))
		return
	var written := document.write_to_filesystem(state, DESTINATION + "assembly.glb")
	if written != OK:
		fail("GLTF write: " + error_string(written))
		return
	var manifest := {"source_scene": "res://scenes/levels/parking_garage.tscn",
		"scene_sha256": FileAccess.get_sha256("res://scenes/levels/parking_garage.tscn"),
		"meshes": records, "counts": counts, "triangles": triangles, "lights": lamps,
		"paint_images": painted, "spawn": transform_values(level.get_node("SpawnPoint3D").global_transform),
		"excluded_non_geometry": ["Player and viewmodel", "screen-space WetGround pass", "runtime collision helpers", "reflection/GI/postprocess state"]}
	var file := FileAccess.open(DESTINATION + "manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	file.close()
	print("AUTHORING_EXPORT_RESULT PASS meshes=", records.size(), " counts=", counts,
		" triangles=", triangles, " lights=", lamps.size(), " paint_images=", painted)
	assembly.free()
	level.free()
	bake_view.queue_free()
	paint_cache.clear()
	for frame: int in 12:
		await physics_frame
	quit()
