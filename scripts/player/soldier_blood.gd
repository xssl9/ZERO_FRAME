class_name SoldierBlood
extends Node3D

## Shared by DEV dummies, local player and remote avatars. Host-confirmed wounds
## are cosmetic; a bounded level pool handles particles, surface marks and cleanup.
const MAX_WOUNDS := 6
const BLEED_SECONDS := 18.0
var skeleton: Skeleton3D
var ragdoll: SoldierRagdoll
var wounds: Array[Dictionary] = []
var stains: Array[Decal] = []
var effects: BloodEffects
var _sample_clock := 0.0

func configure(rig: Skeleton3D, physics: SoldierRagdoll) -> void:
	# Bone attachments move with the wounds when physics is transferred on respawn.
	for wound: Dictionary in wounds:
		var attachment := wound.get("attachment") as BoneAttachment3D
		if is_instance_valid(attachment) and attachment.get_parent() != rig:
			attachment.reparent(rig, false)
			attachment.bone_name = wound.bone
	skeleton = rig
	ragdoll = physics
	top_level = true
	global_transform = Transform3D.IDENTITY
	_prepare_effects.call_deferred()
	_sample_clock = float(get_instance_id() % 11) * 0.027
	set_physics_process(not wounds.is_empty())

func _prepare_effects() -> void:
	if not is_instance_valid(effects):
		effects = BloodEffects.for_node(self)

func add_wound(point: Vector3, direction: Vector3, bone: String, zone: String) -> void:
	if not is_instance_valid(skeleton) or skeleton.find_bone(bone) < 0 or not point.is_finite() or not direction.is_finite():
		return
	_prepare_effects()
	if wounds.size() >= MAX_WOUNDS:
		var old: Dictionary = wounds.pop_front()
		if is_instance_valid(old.get("attachment")):
			(old.attachment as Node).queue_free()
	var pose := ragdoll.bone_world_transform(bone)
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	# Resolve the initial transform before the next skeleton update.
	attachment.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone))
	var mark := effects.wound_mark(attachment, point, -direction if not direction.is_zero_approx() else Vector3.UP)
	if mark == null:
		attachment.queue_free()
	wounds.append({"bone": bone, "offset": pose.affine_inverse() * point, "zone": zone, "age": 0.0, "attachment": attachment if mark != null else null})
	set_physics_process(true)
	# Short back-spatter; no continuous fountain or per-particle collision/RPC.
	effects.splash(point, -direction, 1.2 if zone in ["head", "neck"] else 0.8)
	var hit := effects.trace(point, point + direction.normalized() * 1.8)
	_remember(effects.deposit(hit, 0.22 if zone in ["head", "neck"] else 0.14, false))

func _physics_process(delta: float) -> void:
	if not is_instance_valid(skeleton) or not is_instance_valid(effects):
		set_physics_process(false)
		return
	_sample_clock += delta
	var sample := _sample_clock >= 0.35
	if sample:
		_sample_clock = 0.0
	var bleeding := false
	for wound: Dictionary in wounds:
		wound.age += delta
		var pressure := maxf(0.0, 1.0 - float(wound.age) / BLEED_SECONDS)
		if ragdoll.running:
			pressure *= exp(-ragdoll.age / 2.5)
		if pressure < 0.035:
			continue
		bleeding = true
		if sample:
			var pose := ragdoll.bone_world_transform(wound.bone)
			var point := pose * (wound.offset as Vector3)
			var hit := effects.trace(point + Vector3.UP * 0.02, point + Vector3.DOWN * 2.5)
			_remember(effects.deposit(hit, 0.10 + pressure * 0.045))
	if not bleeding:
		set_physics_process(false)

func _remember(stain: Decal) -> void:
	if stain != null and not stains.has(stain):
		if stains.size() >= 8:
			stains.pop_front()
		stains.append(stain)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for wound: Dictionary in wounds:
			var attachment := wound.get("attachment") as BoneAttachment3D
			if is_instance_valid(attachment) and not attachment.is_queued_for_deletion():
				attachment.queue_free()
