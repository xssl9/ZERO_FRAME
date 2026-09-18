extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
	level.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.camera.set_process(false)
	player.weapon_manager.set_process(false)
	player.weapon_manager.set_physics_process(false)
	await process_frame
	await process_frame
	for index: int in 2:
		player.weapon_manager._select(index)
		var weapon := player.weapon_manager.weapons[index]
		weapon.set_process(false)
		weapon._animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		weapon._animation_player.play(weapon.idle_animation, 0.0)
		weapon._animation_player.advance(0.0)
		var skeleton := weapon.model_root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		print("SIGHT_WEAPON ", weapon.weapon_name)
		for bone: int in skeleton.get_bone_count():
			var name := skeleton.get_bone_name(bone)
			if name.begins_with("P"):
				print("SIGHT_BONE ", name, " pose=", skeleton.get_bone_global_pose(bone))
		for mesh: MeshInstance3D in weapon.model_root.find_children("*", "MeshInstance3D", true, false):
			if mesh.skin == null or mesh.name == &"arms" or mesh.name == &"Object_9":
				continue
			var baked := SoldierModel.bake_mesh(mesh, skeleton)
			var bounds := AABB()
			var tops := {}
			var dump: Array = []
			var source := weapon.model_root.find_child("SourceRig_SKINNED_DO_NOT_ROTATE_SKELETON", true, false) as Node3D
			for surface: int in baked.get_surface_count():
				var vertices: PackedVector3Array = baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for vertex: Vector3 in vertices:
					var point := weapon.model_root.to_local(mesh.to_global(vertex))
					var source_point := source.to_local(mesh.to_global(vertex))
					dump.append({"point": [point.x, point.y, point.z], "source": [source_point.x, source_point.y, source_point.z]})
					bounds = bounds.expand(point)
					var bin := floori(point.z * 200.0)
					if not tops.has(bin) or point.y > tops[bin].y:
						tops[bin] = point
			if "--dump" in OS.get_cmdline_user_args():
				DirAccess.make_dir_recursive_absolute("res://build/verification")
				var file := FileAccess.open("res://build/verification/sight_%s_%s.json" % [index, mesh.name], FileAccess.WRITE)
				file.store_string(JSON.stringify(dump))
			print("SIGHT_MESH ", mesh.name, " bounds=", bounds)
			var bins := tops.keys()
			bins.sort()
			for bin: int in bins:
				print("SIGHT_TOP ", mesh.name, " ", bin, " ", tops[bin])
	level.free()
	for frame: int in 12:
		await physics_frame
	quit()
