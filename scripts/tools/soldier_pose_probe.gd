extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for method: Dictionary in ClassDB.class_get_method_list("AnimationNodeBlendSpace2D"):
		if method.name == "add_blend_point":
			print("BLEND_API ", method)
	for path: String in [SoldierAvatar.MODEL_PATH, "res://scenes/weapons/ak_viewmodel.tscn", "res://scenes/weapons/pistol_viewmodel.tscn"]:
		var model := SoldierModel.instantiate() if path == SoldierAvatar.MODEL_PATH else (load(path) as PackedScene).instantiate()
		root.add_child(model)
		print("MODEL ", path)
		for node: Node in model.find_children("*", "Node3D", true, false):
			if node is Skeleton3D or node is MeshInstance3D or node.name == &"SoldierRig":
				print(node.name, " transform=", node.global_transform)
			if node is MeshInstance3D:
				print("MESH bounds=", node.get_aabb(), " skin=", node.skin != null)
				for s: int in node.mesh.get_surface_count():
					print(" surface ", s, " material=", node.mesh.surface_get_material(s).resource_name)
		var players := model.find_children("*", "AnimationPlayer", true, false)
		var skeletons := model.find_children("*", "Skeleton3D", true, false)
		if path != SoldierAvatar.MODEL_PATH:
			var skel := skeletons[0] as Skeleton3D
			for index: int in skel.get_bone_count():
				if "hand" in skel.get_bone_name(index).to_lower():
					print("WEAPON BONE ", skel.get_bone_name(index))
		if path == SoldierAvatar.MODEL_PATH:
			var skel := skeletons[0] as Skeleton3D
			var anim := players[0] as AnimationPlayer
			for clip: String in ["t_pose", "idle", "walk_forward", "idle_crouching"]:
				anim.play(clip)
				anim.seek(0.0, true)
				anim.advance(0.0)
				print("POSE ", clip)
				for bone: String in ["mixamorig_Hips", "mixamorig_Head", "mixamorig_LeftFoot", "mixamorig_RightFoot", "mixamorig_RightHand"]:
					print(bone, " local=", skel.get_bone_global_pose(skel.find_bone(bone)), " world=", skel.global_transform * skel.get_bone_global_pose(skel.find_bone(bone)).origin)
				var mesh := model.find_child("SoldierMesh", true, false) as MeshInstance3D
				var baked := SoldierModel.bake_mesh(mesh, skel)
				if baked != null:
					print("BAKED ", baked.get_aabb())
		model.free()
	quit()
