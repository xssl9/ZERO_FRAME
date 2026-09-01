class_name ImportedMapRuntime
extends Node3D

## Loads one downloaded architectural model as a playable static level.
## Rendering keeps the original meshes and generated LODs. Physics receives a
## compact mesh assembled from an appropriate LOD so multi-million triangle
## photogrammetry does not stall movement or cause physics tunnelling.

var source_path: String = ""
var collision_triangles: int = 0

func build(path: String, map_position: Vector3, map_rotation_degrees: Vector3, map_scale: Vector3, triangle_budget: int) -> bool:
	source_path = path
	position = map_position
	rotation_degrees = map_rotation_degrees
	scale = map_scale
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Downloaded map could not be loaded: %s" % path)
		return false
	var visual := packed.instantiate() as Node3D
	if visual == null:
		push_error("Downloaded map root is not Node3D: %s" % path)
		return false
	visual.name = "OriginalMapVisual"
	add_child(visual)
	var mesh_nodes: Array[MeshInstance3D] = []
	for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mesh_instance.visibility_range_end = 240.0
		mesh_instance.lod_bias = 0.72
		mesh_nodes.append(mesh_instance)
	_build_lod_collision(mesh_nodes, maxi(triangle_budget, 1000))
	return true

func _build_lod_collision(mesh_nodes: Array[MeshInstance3D], triangle_budget: int) -> void:
	var cache_path: String = source_path.get_basename() + "_collision.res"
	if ResourceLoader.exists(cache_path):
		var cached_mesh := load(cache_path) as ArrayMesh
		if cached_mesh != null:
			_attach_collision_mesh(cached_mesh)
			return
	var surface_count: int = 0
	for mesh_node: MeshInstance3D in mesh_nodes:
		surface_count += mesh_node.mesh.get_surface_count()
	var per_surface_budget: int = maxi(triangle_budget / maxi(surface_count, 1), 500)
	var combined_vertices: Array[Vector3] = []
	var combined_indices: Array[int] = []
	for mesh_node: MeshInstance3D in mesh_nodes:
		var local_transform: Transform3D = global_transform.affine_inverse() * mesh_node.global_transform
		for surface_index: int in mesh_node.mesh.get_surface_count():
			_append_collision_surface(mesh_node.mesh, surface_index, local_transform, per_surface_budget, combined_vertices, combined_indices)
	if combined_indices.is_empty():
		push_warning("No collision triangles generated for %s" % source_path)
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(combined_vertices)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(combined_indices)
	var collision_mesh := ArrayMesh.new()
	collision_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var save_error: Error = ResourceSaver.save(collision_mesh, cache_path)
	if save_error != OK:
		push_warning("Collision cache could not be saved: %s" % cache_path)
	_attach_collision_mesh(collision_mesh)

func _attach_collision_mesh(collision_mesh: ArrayMesh) -> void:
	var body := StaticBody3D.new()
	body.name = "SimplifiedMapCollision"
	add_child(body)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = collision_mesh.create_trimesh_shape()
	body.add_child(collision)
	var arrays: Array = collision_mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	collision_triangles = indices.size() / 3
	print("MAP_COLLISION source=", source_path, " triangles=", collision_triangles)

func _append_collision_surface(mesh: Mesh, surface_index: int, local_transform: Transform3D, triangle_budget: int, output_vertices: Array[Vector3], output_indices: Array[int]) -> void:
	if mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
		return
	var arrays: Array = mesh.surface_get_arrays(surface_index)
	var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if source_vertices.is_empty():
		return
	var original_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if original_indices.is_empty():
		original_indices.resize(source_vertices.size())
		for vertex_index: int in source_vertices.size():
			original_indices[vertex_index] = vertex_index
	var selected_indices: PackedInt32Array = _select_collision_indices(mesh, surface_index, original_indices, triangle_budget)
	var remap: Dictionary = {}
	for old_index: int in selected_indices:
		if old_index < 0 or old_index >= source_vertices.size():
			continue
		var new_index: int
		if remap.has(old_index):
			new_index = int(remap[old_index])
		else:
			new_index = output_vertices.size()
			remap[old_index] = new_index
			output_vertices.append(local_transform * source_vertices[old_index])
		output_indices.append(new_index)

func _select_collision_indices(mesh: Mesh, surface_index: int, original: PackedInt32Array, triangle_budget: int) -> PackedInt32Array:
	if original.size() / 3 <= triangle_budget:
		return original
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(surface_index))
	importer.generate_lods(60.0, 25.0, [])
	var best_under := PackedInt32Array()
	var smallest: PackedInt32Array = original
	for lod_index: int in importer.get_surface_lod_count(0):
		var candidate: PackedInt32Array = importer.get_surface_lod_indices(0, lod_index)
		if candidate.is_empty():
			continue
		if candidate.size() < smallest.size():
			smallest = candidate
		if candidate.size() / 3 <= triangle_budget and candidate.size() > best_under.size():
			best_under = candidate
	return smallest if best_under.is_empty() else best_under
