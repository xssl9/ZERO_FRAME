class_name SoldierCorpse
extends Node3D

var ragdoll: SoldierRagdoll
var _skeleton: Skeleton3D

## Keep the simulated body when the owner respawns, without resetting its pose,
## duplicating physics or retaining the player/network controller.
static func preserve(source: SoldierRagdoll, blood: SoldierBlood) -> SoldierCorpse:
	if not source.running:
		return null
	var corpse := SoldierCorpse.new()
	corpse.name = "SoldierCorpse"
	var scene := source.get_tree().current_scene
	if scene == null:
		scene = source.get_tree().root
	scene.add_child(corpse)
	corpse.add_to_group("soldier_corpses")
	var model := SoldierModel.instantiate()
	corpse.add_child(model)
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var original := source.get_skeleton()
	skeleton.global_transform = original.global_transform
	# Respawn may already have teleported the live controller. Anchor culling
	# bounds near the actual corpse, not at the new spawn point.
	skeleton.global_position = source.bone_world_transform("mixamorig_Hips").origin - Vector3.UP
	corpse._skeleton = skeleton
	var weapon := original.get_node_or_null("WeaponAttach")
	if weapon != null:
		skeleton.add_child(weapon.duplicate(0))
	for index: int in original.get_bone_count():
		skeleton.set_bone_pose(index, original.get_bone_pose(index))
	corpse.ragdoll = SoldierRagdoll.new()
	skeleton.add_child(corpse.ragdoll)
	source.transfer_to(corpse.ragdoll)
	corpse.ragdoll._apply_pose()
	if blood != null:
		blood.reparent(corpse)
		blood.configure(skeleton, corpse.ragdoll)
	return corpse

func _physics_process(_delta: float) -> void:
	if ragdoll == null:
		return
	_skeleton.global_position = ragdoll.bone_world_transform("mixamorig_Hips").origin - Vector3.UP
	if ragdoll.age >= SoldierRagdoll.CORPSE_LIFETIME:
		queue_free()
