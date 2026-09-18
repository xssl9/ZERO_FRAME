extends SceneTree

class LifetimeProbe extends Node:
	var corpse: SoldierCorpse
	var last_alive_age := 0.0
	func _physics_process(_delta: float) -> void:
		if is_instance_valid(corpse):
			last_alive_age = corpse.ragdoll.age

var failures := 0
func _process(_delta: float) -> bool:
	var player := get_first_node_in_group("player") as PlayerController
	if player != null and player.camera != null and not player.camera.global_transform.is_finite():
		push_error("RAGDOLL_BLOOD_FAIL nonfinite camera health=%s ragdoll=%s camera_rest=%s death_offset=%s" % [player.health, player._ragdoll.running, player._camera_rest, player._death_camera_offset])
		quit(1)
	return false

func _initialize() -> void:
	root.close_requested.connect(func() -> void: print("RAGDOLL_BLOOD_ABORTED window closed before completion"))
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("RAGDOLL_BLOOD_FAIL " + message)

func _run() -> void:
	ProjectSettings.set_setting("zero_frame/graphics_quality", 1)
	var level := (load("res://scenes/levels/dev_test_grid.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	var player := level.get_node("Player") as PlayerController
	for frame: int in 30:
		await physics_frame
	var panel := root.get_node("GlobalInput/DevPanel") as DevPanel
	panel._spawn_dummies(1)
	var dummy := panel._dummy_container.get_child(0) as Node3D
	var ragdoll := dummy.get_meta("ragdoll") as SoldierRagdoll
	var blood := dummy.get_meta("blood") as SoldierBlood
	var neck: Area3D
	var bones: Dictionary = {}
	for spec: Dictionary in SoldierHitboxes.SPEC:
		check(not bones.has(spec.bone), "unique physical segment " + spec.bone)
		bones[spec.bone] = true
	for area: Area3D in dummy.find_children("*", "Area3D", true, false):
		if area.get_meta("hit_zone") == "neck":
			neck = area
	check(neck != null and neck.get_meta("hit_bone") == "mixamorig_Neck", "neck targets its own bone")
	var point := ragdoll.bone_world_transform("mixamorig_Neck").origin
	check(not SoldierDummy.receive_hit(dummy, 20, point, Vector3.FORWARD, "mixamorig_Neck", "neck", 1), "nonlethal wound does not incapacitate")
	check(not ragdoll.running and blood.wounds.size() == 1, "no active-balance or scripted stumble")
	var arm_point := ragdoll.bone_world_transform("mixamorig_LeftArm").origin
	SoldierDummy.receive_hit(dummy, 20, arm_point, Vector3.RIGHT, "mixamorig_LeftArm", "arm_upper", 1)
	check(blood.wounds.size() == 2, "independent neck/arm wounds")
	for frame: int in 90:
		await physics_frame
	check(not blood.stains.is_empty(), "bleeding deposits on real floor")
	check(SoldierDummy.receive_hit(dummy, 100, point, Vector3.FORWARD, "mixamorig_Neck", "neck", 1), "health death starts physics")
	check(ragdoll.bodies.size() == 14 and ragdoll._physics_root.get_child_count() == 27, "exactly 14 bodies and 13 joints")
	for frame: int in 180:
		await physics_frame
	for wound: Dictionary in blood.wounds:
		var expected := ragdoll.bone_world_transform(wound.bone) * (wound.offset as Vector3)
		check((wound.emitter as Node3D).global_position.distance_to(expected) < 0.05, "wound follows falling bone")
	var hips := ragdoll.bone_world_transform("mixamorig_Hips").origin
	check(hips.y < dummy.global_position.y + 0.6, "lethal neck impulse settles instead of launching body")
	for body: RigidBody3D in ragdoll.bodies.values():
		check(body.global_position.is_finite() and body.global_position.distance_to(hips) < 2.0, "shot ragdoll stays connected")
	if DisplayServer.get_name() != "headless":
		var camera := Camera3D.new()
		level.add_child(camera)
		camera.global_position = hips + Vector3(1.6, 1.5, 1.6)
		camera.look_at(hips)
		camera.make_current()
		player.get_node("WeaponLayer").hide()
		for frame: int in 10:
			await physics_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("/tmp/ragdoll_blood.png") == OK, "blood/ragdoll Forward+ capture")
		camera.free()
		player.camera.make_current()
		player.get_node("WeaponLayer").show()
	# Keep the real bodies on revive, not a second simulated copy.
	player._on_network_health(0)
	player.apply_physical_hit(player._ragdoll.bone_world_transform("mixamorig_Neck").origin, Vector3.FORWARD, "mixamorig_Neck", "neck")
	for frame: int in 60:
		await physics_frame
	var original_body := player._ragdoll.bodies.values()[0] as RigidBody3D
	var original_blood := player._blood
	var respawn := player.spawn_transform
	respawn.origin += Vector3(10, 0, 0)
	player.teleport_to(respawn)
	player.revive()
	var corpses := get_nodes_in_group("soldier_corpses")
	check(corpses.size() == 1, "one visible corpse per local death")
	var corpse := corpses[0] as SoldierCorpse
	check(corpse.ragdoll.bodies.values().has(original_body), "respawn transfers existing physics")
	check(corpse._skeleton.global_position.distance_to(original_body.global_position) < 3.0, "corpse culling bounds stay at death location after distant respawn")
	check(original_blood.get_parent() == corpse and player._blood != original_blood, "wounds remain with corpse, respawn clean")
	check(not player._ragdoll.running and player.health == 100, "live controller restored")
	# Actual physics clock, including the five-second respawn interval. Use
	# --fixed-fps 60 to run these 120 simulation seconds without wall-clock waits.
	var probe := LifetimeProbe.new()
	probe.corpse = corpse
	probe.process_physics_priority = -1
	level.add_child(probe)
	while is_instance_valid(corpse) and corpse.ragdoll.age < 30.0:
		await physics_frame
	check(is_instance_valid(original_blood) and not (original_blood.wounds[0].emitter as CPUParticles3D).emitting, "postmortem bleeding subsides")
	while is_instance_valid(corpse) and corpse.ragdoll.age < 121.0:
		await physics_frame
	check(not is_instance_valid(corpse), "corpse node is removed, not merely hidden")
	check(probe.last_alive_age >= 119.8 and probe.last_alive_age <= 120.05, "corpse survives until exactly 120 seconds from death: " + str(probe.last_alive_age))
	check(not is_instance_valid(original_body), "corpse and physics freed after 120 seconds")
	check(not is_instance_valid(dummy), "dummy corpse also expires after 120 seconds")
	panel._on_clear_all()
	current_scene = null
	level.free()
	for frame: int in 12:
		await physics_frame
	print("RAGDOLL_BLOOD_RESULT failures=", failures)
	quit(1 if failures else 0)
