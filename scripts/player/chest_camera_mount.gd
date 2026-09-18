class_name ChestCameraMount
extends RefCounted

# A surface attachment, not an arbitrary offset from the capsule or a single
# joint. Three cached skinned vertices follow exactly the same deformation as
# the vest; there is no per-frame mesh bake or physics collider for the body.
const LENS_STANDOFF := 0.06
var _mesh: MeshInstance3D
var _skeleton: Skeleton3D
var _vertices: Array[Array] = []
var _barycentric := Vector3.ZERO
var _normal_sign := 1.0
var surface_position := Vector3.ZERO
var surface_normal := Vector3.FORWARD

func configure(mesh: MeshInstance3D, skeleton: Skeleton3D, ray_origin: Vector3, forward: Vector3) -> bool:
	_mesh = mesh
	_skeleton = skeleton
	_vertices.clear()
	var baked := SoldierModel.bake_mesh(mesh, skeleton)
	var nearest := INF
	var selected_surface := -1
	var selected_indices := PackedInt32Array()
	for surface: int in baked.get_surface_count():
		var arrays := baked.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for triangle: int in range(0, indices.size(), 3):
			var a := mesh.to_global(points[indices[triangle]])
			var b := mesh.to_global(points[indices[triangle + 1]])
			var c := mesh.to_global(points[indices[triangle + 2]])
			var hit: Variant = Geometry3D.ray_intersects_triangle(ray_origin, -forward, a, b, c)
			if hit == null or ray_origin.distance_to(hit) >= nearest:
				continue
			nearest = ray_origin.distance_to(hit)
			selected_surface = surface
			selected_indices = indices.slice(triangle, triangle + 3)
			_barycentric = Geometry3D.get_triangle_barycentric_coords(hit, a, b, c)
			_normal_sign = 1.0 if (b - a).cross(c - a).dot(forward) >= 0.0 else -1.0
	if selected_surface < 0:
		return false
	var arrays := mesh.mesh.surface_get_arrays(selected_surface)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var influences: int = bones.size() / points.size()
	for index: int in selected_indices:
		var vertex: Array = []
		for influence: int in influences:
			var slot := index * influences + influence
			if weights[slot] <= 0.0:
				continue
			var bind := bones[slot]
			var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind))
			if bone < 0:
				bone = mesh.skin.get_bind_bone(bind)
			vertex.append({"bone": bone, "point": mesh.skin.get_bind_pose(bind) * points[index], "weight": weights[slot]})
		_vertices.append(vertex)
	return true

func sample() -> Vector3:
	var points := PackedVector3Array()
	for vertex: Array in _vertices:
		var point := Vector3.ZERO
		for influence: Dictionary in vertex:
			point += (_skeleton.get_bone_global_pose(influence.bone) * (influence.point as Vector3)) * float(influence.weight)
		points.append(_mesh.to_global(point))
	surface_position = points[0] * _barycentric.x + points[1] * _barycentric.y + points[2] * _barycentric.z
	surface_normal = (points[1] - points[0]).cross(points[2] - points[0]).normalized() * _normal_sign
	return surface_position + surface_normal * LENS_STANDOFF
