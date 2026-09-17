extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var steam_peer := SteamMultiplayerPeer.new()
	print("STEAM_RELAY_SUPPORTED ", steam_peer.is_server_relay_supported())
	var level := Node3D.new()
	root.add_child(level)
	current_scene = level
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
	level.add_child(player)
	player.set_physics_process(false)
	player.weapon_manager.set_process(false)
	player.camera.set_process(false)
	await process_frame
	await process_frame
	print("WORLD_CAMERA ", root.get_camera_3d().get_path(), " mount=", player.bodycam.transform, " camera=", player.camera.transform, " near=", player.camera.near)
	var body := player._body_skeleton
	var animation := player._body_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	print("BODY_ANIMATIONS ", animation.get_animation_list())
	(player._body_model.get_node("BodyAnimTree") as AnimationTree).active = false
	for clip: String in ["idle", "idle_crouching", "sprint_forward", "jump_up"]:
		animation.play(clip)
		animation.advance(0.1)
		for bone: String in ["mixamorig_Hips", "mixamorig_Spine1", "mixamorig_Spine2", "mixamorig_Head"]:
			print("BODY ", clip, " ", bone, " ", player.to_local(body.to_global(body.get_bone_global_pose(body.find_bone(bone)).origin)))
		var full := player._body_model.find_child("SoldierMesh", true, false) as MeshInstance3D
		var baked := SoldierModel.bake_mesh(full, body)
		var front := INF
		for surface: int in baked.get_surface_count():
			var raw := full.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			var influences: int = raw[Mesh.ARRAY_BONES].size() / vertices.size()
			for index: int in vertices.size():
				var torso := 0.0
				for influence: int in influences:
					var slot := index * influences + influence
					if "Spine2" in str(full.skin.get_bind_name(raw[Mesh.ARRAY_BONES][slot])):
						torso += raw[Mesh.ARRAY_WEIGHTS][slot]
				var point := player.to_local(body.to_global(vertices[index]))
				if torso > 0.8 and absf(point.x) < 0.15:
					front = minf(front, point.z)
		print("BODY_FRONT ", clip, " ", front)
	for index: int in player.weapon_manager.weapons.size():
		player.weapon_manager._select(index)
		var weapon := player.weapon_manager.weapons[index]
		weapon.set_process(false)
		print("WEAPON ", weapon.weapon_name, " camera=", weapon.authored_camera.global_transform, " manager=", player.weapon_manager.transform)
		var skeleton := weapon.model_root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		for clip: String in [weapon.idle_animation, weapon.shot_animation, weapon.reload_animation]:
			weapon._animation_player.play(clip, 0.0)
			weapon._animation_player.advance(0.0)
			for sample: int in 5:
				weapon._animation_player.seek(weapon._animation_player.current_animation_length * sample / 4.0, true)
				for mesh: MeshInstance3D in weapon.model_root.find_children("*", "MeshInstance3D", true, false):
					if mesh.skin == null or mesh.name == &"Object_9":
						continue
					var baked := SoldierModel.bake_mesh(mesh, skeleton)
					if mesh.name == &"Ak" and clip == weapon.idle_animation and sample == 0:
						var tops := {}
						for vertex: Vector3 in baked.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
							var point := weapon.authored_camera.to_local(mesh.to_global(vertex))
							var bin := floori(point.z * 40.0)
							if absf(point.x) < 0.012 and (not tops.has(bin) or point.y > tops[bin].y):
								tops[bin] = point
						print("AK_SIGHT_PROFILE ", tops)
					var bounds := weapon.authored_camera.global_transform.affine_inverse() * mesh.global_transform * baked.get_aabb()
					print("GEOMETRY ", weapon.weapon_name, " ", clip, " t=", sample, " ", mesh.name, " ", bounds)
	level.free()
	for frame: int in 12:
		await physics_frame
	quit()
