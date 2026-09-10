extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("SURFACE_FAIL " + message)

func _box(parent: Node3D, size: Vector3, position: Vector3) -> MeshInstance3D:
	var body := StaticBody3D.new()
	parent.add_child(body)
	body.position = position
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return mesh

func _run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var floor := _box(level, Vector3(12.0, 0.4, 8.0), Vector3(0.0, -0.2, 0.0))
	_box(level, Vector3(4.0, 0.2, 4.0), Vector3(-3.0, 3.0, 0.0))
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/dev_grid.gdshader")
	material.set_shader_parameter("wetness", 1.0)
	floor.material_override = material
	# Two surfaces with one override must still create only one material copy.
	var multi := ArrayMesh.new()
	var source := BoxMesh.new()
	multi.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.get_mesh_arrays())
	multi.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.get_mesh_arrays())
	var test_mesh := MeshInstance3D.new()
	test_mesh.mesh = multi
	test_mesh.material_override = material
	level.add_child(test_mesh)
	var wet := WetnessManager.new()
	level.add_child(wet)
	wet.configure(level, 1.0)
	check(wet.materials.size() == 1, "shared override is duplicated once")
	check(floor.material_override != material, "authored resource is isolated")
	var roof := RainExposureMask.new()
	roof.resolution = 32
	roof.rays_per_frame = 256
	level.add_child(roof)
	roof.configure(level, wet.materials)
	for frame: int in 12:
		await physics_frame
	check(roof.ready_mask, "roof build completes")
	if roof.ready_mask:
		for point: Vector3 in [Vector3(-3.0, 0.0, 0.0), Vector3(3.0, 0.0, 0.0)]:
			var uv := Vector2((point.x - roof.bounds.position.x) / roof.bounds.size.x, (point.z - roof.bounds.position.z) / roof.bounds.size.z)
			var height := roof._image.get_pixel(int(uv.x * roof.resolution), int(uv.y * roof.resolution)).r
			check(is_equal_approx(height, 3.1 if point.x < 0.0 else 0.0), "raycast distinguishes covered and exposed ground")
	for kind: int in SurfaceDecal.Kind.size():
		var decal := SurfaceDecal.new()
		decal.kind = kind as SurfaceDecal.Kind
		decal.texture_size = 32
		level.add_child(decal)
		check(decal.texture_albedo != null and decal.texture_orm != null, "native decal textures generated")
		check(decal.texture_albedo.get_image().has_mipmaps(), "decal mipmaps")
		check(is_zero_approx(decal.texture_orm.get_image().get_pixel(16, 16).b), "deposits remain dielectric")
	level.free()
	await process_frame
	print("SURFACE_RESULT failures=", failures)
	quit(1 if failures else 0)
