extends SceneTree

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--asset="):
			inspect_scene("CUSTOM", argument.trim_prefix("--asset="))
			quit()
			return
	inspect_scene("AK", "res://assets/weapons/ak/source/FpsAnims.fbx")
	inspect_scene("PISTOL", "res://assets/weapons/pistol/scene.gltf")
	inspect_scene("WAREHOUSE", "res://assets/environment/warehouse/source/Warehouse.fbx")
	quit()

func inspect_scene(label: String, path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		print(label, " LOAD FAILED")
		return
	var root := packed.instantiate()
	get_root().add_child(root)
	print("=== ", label, " ===")
	print("ROOT ", root.name, " XFORM=", (root as Node3D).transform if root is Node3D else Transform3D.IDENTITY)
	for spatial_node: Node in root.find_children("*", "Node3D", true, false):
		if spatial_node is not MeshInstance3D:
			print("NODE ", spatial_node.get_path(), " XFORM=", (spatial_node as Node3D).transform)
	var combined_aabb := AABB()
	var has_aabb := false
	var triangle_count: int = 0
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			var world_aabb: AABB = mesh_node.global_transform * mesh_node.mesh.get_aabb()
			combined_aabb = world_aabb if not has_aabb else combined_aabb.merge(world_aabb)
			has_aabb = true
			for surface_index: int in mesh_node.mesh.get_surface_count():
				var arrays: Array = mesh_node.mesh.surface_get_arrays(surface_index)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if not indices.is_empty():
					triangle_count += indices.size() / 3
			print("MESH ", mesh_node.name, " WORLD_AABB=", world_aabb)
	if has_aabb:
		print("COMBINED_AABB=", combined_aabb, " TRIANGLES=", triangle_count)
	for node: Node in root.find_children("*", "AnimationPlayer", true, false):
		var animation_player := node as AnimationPlayer
		print("ANIMATION PLAYER ", animation_player.get_path())
		for library_name: StringName in animation_player.get_animation_library_list():
			var library := animation_player.get_animation_library(library_name)
			for animation_name: StringName in library.get_animation_list():
				print("CLIP ", animation_name, " length=", library.get_animation(animation_name).length)
	for node: Node in root.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		print("SKELETON ", skeleton.name, " bones=", skeleton.get_bone_count())
		for bone_index: int in skeleton.get_bone_count():
			var bone_name := skeleton.get_bone_name(bone_index)
			if "cam" in String(bone_name).to_lower() or "root" in String(bone_name).to_lower():
				print("BONE ", bone_name, " rest=", skeleton.get_bone_global_rest(bone_index), " pose=", skeleton.get_bone_global_pose(bone_index))
	root.queue_free()
