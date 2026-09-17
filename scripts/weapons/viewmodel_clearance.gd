class_name ViewmodelClearance
extends RefCounted

# Conservative animated bounds without CPU-skinning thousands of vertices each
# frame. Each positive skin influence contributes to a bind-space box. A skinned
# vertex is a convex combination of those transformed boxes, hence lies inside
# their union's enclosing AABB, including between animation keys/blends.
var _parts: Array[Dictionary] = []

func configure(root: Node3D) -> void:
	_parts.clear()
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		var boxes: Dictionary = {}
		if mesh.skin != null and skeleton != null:
			for surface: int in mesh.mesh.get_surface_count():
				var arrays := mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var influences: int = bones.size() / vertices.size()
				for vertex: int in vertices.size():
					for influence: int in influences:
						var slot := vertex * influences + influence
						if weights[slot] <= 0.0:
							continue
						var bind := bones[slot]
						var point := mesh.skin.get_bind_pose(bind) * vertices[vertex]
						boxes[bind] = (boxes[bind] as AABB).expand(point) if boxes.has(bind) else AABB(point, Vector3.ZERO)
			var entries: Array[Dictionary] = []
			for bind: int in boxes:
				var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind))
				if bone < 0:
					bone = mesh.skin.get_bind_bone(bind)
				entries.append({"bone": bone, "bounds": boxes[bind]})
			_parts.append({"mesh": mesh, "skeleton": skeleton, "entries": entries})
		else:
			_parts.append({"mesh": mesh, "skeleton": null, "bounds": mesh.mesh.get_aabb()})

func nearest_z(camera: Camera3D) -> float:
	var nearest := -INF
	var view := camera.global_transform.affine_inverse()
	for part: Dictionary in _parts:
		var mesh := part.mesh as MeshInstance3D
		if not mesh.is_visible_in_tree():
			continue
		var local_view := view * mesh.global_transform
		var skeleton := part.skeleton as Skeleton3D
		if skeleton == null:
			nearest = maxf(nearest, (local_view * (part.bounds as AABB)).end.z)
		else:
			for entry: Dictionary in part.entries:
				var bounds: AABB = local_view * skeleton.get_bone_global_pose(entry.bone) * (entry.bounds as AABB)
				nearest = maxf(nearest, bounds.end.z)
	return nearest
