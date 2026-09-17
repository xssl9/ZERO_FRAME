extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for index: int in 2:
		var source := (load(SoldierWeapon.SCENES[index]) as PackedScene).instantiate() as Node3D
		root.add_child(source)
		var animation := source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		animation.play(SoldierWeapon.IDLES[index])
		animation.advance(0.0)
		var skeleton := source.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		if "--bones" in OS.get_cmdline_user_args():
			for bone: int in skeleton.get_bone_count():
				print("WEAPON_BONE ", index, " ", bone, " ", skeleton.get_bone_name(bone))
		var bounds := AABB()
		var first := true
		for node: Node in source.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh.name in [&"arms", &"Object_9", &"Mag_2"]:
				continue
			var box := mesh.global_transform * SoldierModel.bake_mesh(mesh, skeleton).get_aabb()
			print("WEAPON_PART ", index, " ", mesh.name, " ", box)
			bounds = box if first else bounds.merge(box)
			first = false
		print("WEAPON_BOUNDS ", index, " ", bounds)
		var valid_length := bounds.size.z > 0.92 and bounds.size.z < 0.96 if index == 0 else bounds.size.z > 0.20 and bounds.size.z < 0.24
		var muzzle := source.find_child("MuzzlePoint", true, false) as Marker3D
		var muzzle_at_tip := absf(muzzle.global_position.z - bounds.position.z) < 0.02
		# Third person must use the same actual weapon dimensions, not a second
		# guessed scale. Build and measure its baked meshes with a unit hand pose.
		var proxy := SoldierWeapon.build(index, root, Transform3D.IDENTITY)
		root.add_child(proxy)
		var proxy_bounds := AABB()
		var first_proxy := true
		for node: Node in proxy.get_children():
			if node is MeshInstance3D:
				var mesh := node as MeshInstance3D
				var box := mesh.transform * mesh.mesh.get_aabb()
				proxy_bounds = box if first_proxy else proxy_bounds.merge(box)
				first_proxy = false
		var same_scale := proxy_bounds.size.is_equal_approx(bounds.size)
		proxy.free()
		source.free()
		if not valid_length or not muzzle_at_tip or not same_scale:
			push_error("WEAPON_GEOMETRY_FAIL length=%s muzzle=%s shared_scale=%s" % [valid_length, muzzle_at_tip, same_scale])
			quit(1)
			return
	print("WEAPON_GEOMETRY_RESULT failures=0")
	quit()
