extends SceneTree

const SOURCE := "res://assets/weapons/pistol/scene.gltf"
const UNIFORM := "res://assets/weapons/pistol/pistol_uniform.gltf"
var failures := 0
var samples := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		if failures <= 20:
			push_error("PISTOL_UNIFORM_FAIL " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var before := (load(SOURCE) as PackedScene).instantiate() as Node3D
	var after := (load(UNIFORM) as PackedScene).instantiate() as Node3D
	root.add_child(before)
	root.add_child(after)
	var old_rig := before.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var new_rig := after.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	check(old_rig.get_bone_count() == new_rig.get_bone_count(), "bone count")
	for bone: int in old_rig.get_bone_count():
		check(old_rig.get_bone_name(bone) == new_rig.get_bone_name(bone), "bone names")
		check(old_rig.get_bone_parent(bone) == new_rig.get_bone_parent(bone), "bone hierarchy")
		check(old_rig.get_bone_rest(bone).is_equal_approx(new_rig.get_bone_rest(bone)), "rest transform")
	var old_anim := before.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var new_anim := after.find_child("AnimationPlayer", true, false) as AnimationPlayer
	old_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	new_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	check(old_anim.get_animation_list() == new_anim.get_animation_list(), "all five original clips retained")
	check(new_anim.get_animation_list().size() == 5, "expected five clips")
	var meshes := before.find_children("*", "MeshInstance3D", true, false)
	check(meshes.size() == after.find_children("*", "MeshInstance3D", true, false).size(), "mesh count")
	for old_mesh: MeshInstance3D in meshes:
		var new_mesh := after.get_node(before.get_path_to(old_mesh)) as MeshInstance3D
		check(old_mesh.transform.is_equal_approx(new_mesh.transform), "mesh transform: " + old_mesh.name)
		check(old_mesh.mesh.get_surface_count() == new_mesh.mesh.get_surface_count(), "surface count")
		for surface: int in old_mesh.mesh.get_surface_count():
			var a := old_mesh.mesh.surface_get_arrays(surface)
			var b := new_mesh.mesh.surface_get_arrays(surface)
			for channel: int in Mesh.ARRAY_MAX:
				check(a[channel] == b[channel], "unchanged vertex/index/UV/weight data: %s channel=%d" % [old_mesh.name, channel])
		check(old_mesh.skin.get_bind_count() == new_mesh.skin.get_bind_count(), "bind count")
		for bind: int in old_mesh.skin.get_bind_count():
			check(old_mesh.skin.get_bind_name(bind) == new_mesh.skin.get_bind_name(bind), "bind name")
			check(old_mesh.skin.get_bind_pose(bind).is_equal_approx(new_mesh.skin.get_bind_pose(bind)), "inverse bind pose")
	for clip: StringName in old_anim.get_animation_list():
		var old_clip := old_anim.get_animation(clip)
		var new_clip := new_anim.get_animation(clip)
		check(is_equal_approx(old_clip.length, new_clip.length), "clip length " + clip)
		check(old_clip.get_track_count() == new_clip.get_track_count(), "track count " + clip)
		for track: int in old_clip.get_track_count():
			check(old_clip.track_get_path(track) == new_clip.track_get_path(track), "track target")
			check(old_clip.track_get_key_count(track) == new_clip.track_get_key_count(track), "key count")
			for key: int in old_clip.track_get_key_count(track):
				check(old_clip.track_get_key_time(track, key) == new_clip.track_get_key_time(track, key), "key timing")
				check(old_clip.track_get_key_value(track, key) == new_clip.track_get_key_value(track, key), "key value")
		old_anim.play(clip, 0.0)
		new_anim.play(clip, 0.0)
		for frame: int in 13:
			var time := old_clip.length * frame / 12.0
			old_anim.seek(time, true)
			new_anim.seek(time, true)
			for bone: int in old_rig.get_bone_count():
				check(old_rig.get_bone_global_pose(bone).is_equal_approx(new_rig.get_bone_global_pose(bone)), "evaluated pose " + clip)
			samples += 1
		print("PISTOL_CLIP_VERIFIED ", clip, " length=", new_clip.length)
	var old_arms := before.find_child("Object_9", true, false) as MeshInstance3D
	var new_arms := after.find_child("Object_9", true, false) as MeshInstance3D
	var original_material := old_arms.get_active_material(0) as StandardMaterial3D
	var material := new_arms.get_active_material(0) as StandardMaterial3D
	check(material.resource_name == "SoldierUniformArms", "exported material selected")
	check(material.albedo_texture != null and material.albedo_texture != original_material.albedo_texture, "new albedo")
	check(is_zero_approx(material.metallic), "cloth is nonmetallic")
	check(material.roughness_texture != null, "authored roughness map")
	check(material.normal_enabled and material.normal_texture == original_material.normal_texture, "original normal detail retained")
	check(material.ao_enabled and material.ao_texture != null, "AO retained")
	WeaponMaterials.apply(after)
	material = new_arms.get_active_material(0) as StandardMaterial3D
	check(material.resource_name == "SoldierUniformArms" and material.roughness_texture != null, "runtime material pass preserves exported finish")
	check(not "ak/" in material.roughness_texture.resource_path, "no rifle-arm fallback on pistol")
	before.free()
	after.free()
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_gameplay()
	print("PISTOL_UNIFORM_RESULT failures=", failures, " pose_samples=", samples)
	quit(1 if failures else 0)

func _capture_gameplay() -> void:
	check(DisplayServer.get_name() != "headless", "GPU capture requires display")
	if DisplayServer.get_name() == "headless":
		return
	var level := (load("res://scenes/levels/dev_test_grid.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	var player := level.get_node("Player") as PlayerController
	for frame: int in 30:
		await physics_frame
	player.set_process(false)
	player.set_physics_process(false)
	player.camera.set_process(false)
	player.camera.set_physics_process(false)
	var manager := player.weapon_manager
	manager.set_process(false)
	manager.set_physics_process(false)
	manager._select(1)
	var weapon := manager.weapons[1]
	weapon.set_process(false)
	var animation := weapon._animation_player
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var runtime_arms := weapon.model_root.find_child("Object_9", true, false) as MeshInstance3D
	check(runtime_arms.get_active_material(0).resource_name == "SoldierUniformArms", "game uses uniform, not legacy scene")
	DirAccess.make_dir_recursive_absolute("res://build/verification")
	for clip: StringName in animation.get_animation_list():
		animation.play(clip, 0.0)
		animation.seek(animation.current_animation_length * 0.45, true)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var label := str(clip).get_slice("|", 1)
		check(not image.is_empty() and image.save_png("res://build/verification/uniform_%s.png" % label) == OK, "render/save " + label)
	animation.play(weapon.idle_animation, 0.0)
	animation.seek(0.0, true)
	weapon.set_aiming(true)
	for frame: int in 60:
		weapon._process(1.0 / 60.0)
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://build/verification/uniform_ads.png") == OK, "ADS capture")
	weapon.set_aiming(false)
	weapon.reset_recoil()
	player.bodycam.rotation_degrees.x = -65.0
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://build/verification/uniform_body.png") == OK, "body and sleeves capture")
	level.free()
	for frame: int in 12:
		await physics_frame
