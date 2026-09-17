class_name SoldierModel
extends RefCounted

const PATH := "res://IMPORTANT_MULTIPLAYER_ASSETS/soldier_rifle_locomotion.glb"
# The master rig is ~100 units tall. Its locomotion is Y-up / +Z forward,
# whereas the exported armature node still carries Blender's +90 degree X turn.
const UNIT_SCALE := 0.018
static var _libraries: Dictionary = {}
static var _legs_mesh: ArrayMesh

# Remove horizontal travel along the gait direction, retaining lateral sway, height and
# authored death motion. Cache private copies: never mutate imported resources.
static func prepare_animations(player: AnimationPlayer) -> void:
	for library_name: StringName in player.get_animation_library_list():
		if not _libraries.has(library_name):
			var library := player.get_animation_library(library_name).duplicate(true) as AnimationLibrary
			for clip: StringName in library.get_animation_list():
				var animation := library.get_animation(clip)
				var moving := str(clip).begins_with("walk") or str(clip).begins_with("run") or str(clip).begins_with("sprint")
				if moving:
					for track: int in animation.get_track_count():
						if animation.track_get_type(track) != Animation.TYPE_POSITION_3D or not str(animation.track_get_path(track)).ends_with(":mixamorig_Hips"):
							continue
						var last := animation.track_get_key_count(track) - 1
						if last < 1:
							continue
						var start: Vector3 = animation.track_get_key_value(track, 0)
						var travel: Vector3 = animation.track_get_key_value(track, last) - start
						travel.y = 0.0
						var forward := travel.normalized()
						for key: int in last + 1:
							var pose: Vector3 = animation.track_get_key_value(track, key)
							# Travel is not uniform in every clip. Remove the complete
							# longitudinal component, keeping lateral sway and height.
							pose -= forward * (pose - start).dot(forward)
							animation.track_set_key_value(track, key, pose)
				if moving or str(clip).begins_with("idle") or clip == &"jump_loop":
					animation.loop_mode = Animation.LOOP_LINEAR
			_libraries[library_name] = library
		player.remove_animation_library(library_name)
		player.add_animation_library(library_name, _libraries[library_name])

# Keep the waist, lower vest and legs, excluding head/arms and the upper chest
# around the lens. Filter by skin weights, never by collapsing skeleton bones.
# The untouched full mesh still casts body shadows.
static func first_person_legs(model: Node3D, skeleton: Skeleton3D) -> void:
	var full := model.find_child("SoldierMesh", true, false) as MeshInstance3D
	if _legs_mesh == null:
		_legs_mesh = ArrayMesh.new()
		for surface: int in full.mesh.get_surface_count():
			var arrays := full.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences: int = bones.size() / vertices.size()
			var keep: Array[bool] = []
			for vertex: int in vertices.size():
				var leg_weight := 0.0
				for influence: int in influences:
					var slot := vertex * influences + influence
					var name := str(full.skin.get_bind_name(bones[slot]))
					if name.is_empty():
						name = skeleton.get_bone_name(full.skin.get_bind_bone(bones[slot]))
					if "Leg" in name or "Foot" in name or "Toe" in name or name in ["mixamorig_Hips", "mixamorig_Spine", "mixamorig_Spine1"]:
						leg_weight += weights[slot]
				keep.append(leg_weight >= 0.5)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				for vertex: int in vertices.size():
					indices.append(vertex)
			var filtered := PackedInt32Array()
			for triangle: int in range(0, indices.size(), 3):
				if keep[indices[triangle]] and keep[indices[triangle + 1]] and keep[indices[triangle + 2]]:
					filtered.append_array(indices.slice(triangle, triangle + 3))
			if filtered.is_empty():
				continue
			arrays[Mesh.ARRAY_INDEX] = filtered
			_legs_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			_legs_mesh.surface_set_material(_legs_mesh.get_surface_count() - 1, full.get_active_material(surface))
	var legs := MeshInstance3D.new()
	legs.name = "FirstPersonLegs"
	legs.mesh = _legs_mesh
	legs.skin = full.skin
	legs.skeleton = full.skeleton
	legs.transform = full.transform
	legs.custom_aabb = full.custom_aabb
	legs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	full.get_parent().add_child(legs)
	full.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY

static func instantiate() -> Node3D:
	var model := (load(PATH) as PackedScene).instantiate() as Node3D
	var rig := model.get_node("SoldierRig") as Node3D
	rig.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * UNIT_SCALE), Vector3.ZERO)
	# The raw mesh is unit-sized but the inverse bind matrices expand it into
	# rig units. Its imported AABB therefore cannot bound the animated soldier.
	var mesh := rig.get_node("Skeleton3D/SoldierMesh") as MeshInstance3D
	mesh.custom_aabb = AABB(Vector3(-100, -20, -100), Vector3(200, 150, 200))
	prepare_animations(model.find_child("AnimationPlayer", true, false) as AnimationPlayer)
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
