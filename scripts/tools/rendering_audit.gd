extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for path: String in ["res://scenes/levels/dev_test_grid.tscn", "res://scenes/levels/pvp_linse.tscn", "res://scenes/levels/parking_garage.tscn"]:
		var scene := (load(path) as PackedScene).instantiate()
		root.add_child(scene)
		await physics_frame
		await process_frame
		var meshes := scene.find_children("*", "MeshInstance3D", true, false)
		var materials: Dictionary = {}
		var triangles := 0
		for node: MeshInstance3D in meshes:
			if node.mesh == null:
				continue
			for surface: int in node.mesh.get_surface_count():
				var material := node.get_active_material(surface)
				if material != null:
					materials[material] = true
				var arrays := node.mesh.surface_get_arrays(surface)
				if not arrays.is_empty():
					var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
					triangles += indices.size() / 3 if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size() / 3
		print("AUDIT ", path, " meshes=", meshes.size(), " triangles=", triangles, " unique_materials=", materials.size(), " lights=", scene.find_children("*", "Light3D", true, false).size(), " probes=", scene.find_children("*", "ReflectionProbe", true, false).size())
		for material: Material in materials:
			if material is BaseMaterial3D:
				var m := material as BaseMaterial3D
				print("PBR ", m.resource_name, " rough=", m.roughness, " metal=", m.metallic, " albedo=", m.albedo_texture.resource_path if m.albedo_texture else "none", " normal=", m.normal_enabled, " rough_map=", m.roughness_texture != null, " ao=", m.ao_enabled)
		scene.free()
		for frame: int in 6:
			await process_frame
	quit()
