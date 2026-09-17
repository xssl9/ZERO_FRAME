class_name SoldierModel
extends RefCounted

const PATH := "res://IMPORTANT_MULTIPLAYER_ASSETS/soldier_rifle_locomotion.glb"
# The master rig is ~100 units tall. Its locomotion is Y-up / +Z forward,
# whereas the exported armature node still carries Blender's +90 degree X turn.
const UNIT_SCALE := 0.018

static func instantiate() -> Node3D:
	var model := (load(PATH) as PackedScene).instantiate() as Node3D
	var rig := model.get_node("SoldierRig") as Node3D
	rig.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * UNIT_SCALE), Vector3.ZERO)
	# The raw mesh is unit-sized but the inverse bind matrices expand it into
	# rig units. Its imported AABB therefore cannot bound the animated soldier.
	var mesh := rig.get_node("Skeleton3D/SoldierMesh") as MeshInstance3D
	mesh.custom_aabb = AABB(Vector3(-100, -20, -100), Vector3(200, 150, 200))
	return model

# CPU skinning also works with Godot's headless dummy renderer. Used to bake
# weapon-only meshes and to measure actual deformed geometry in regressions.
static func bake_mesh(instance: MeshInstance3D, skeleton: Skeleton3D) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface: int in instance.mesh.get_surface_count():
		var arrays := instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var count: int = bones.size() / vertices.size()
		for vertex: int in vertices.size():
			var point := Vector3.ZERO
			var normal := Vector3.ZERO
			for influence: int in count:
				var slot := vertex * count + influence
				if weights[slot] <= 0.0:
					continue
				var bind := bones[slot]
				var bone := skeleton.find_bone(instance.skin.get_bind_name(bind))
				if bone < 0:
					bone = instance.skin.get_bind_bone(bind)
				var pose := skeleton.get_bone_global_pose(bone) * instance.skin.get_bind_pose(bind)
				point += (pose * vertices[vertex]) * weights[slot]
				normal += (pose.basis.inverse().transposed() * normals[vertex]) * weights[slot]
			vertices[vertex] = point
			normals[vertex] = normal.normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_BONES] = null
		arrays[Mesh.ARRAY_WEIGHTS] = null
		arrays[Mesh.ARRAY_TANGENT] = null
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(surface, instance.get_active_material(surface))
	return result
