class_name SoldierHitboxes
extends Node

## Builds the per-bone hit volumes for a soldier avatar.
##
## Each entry becomes a BoneAttachment3D carrying an Area3D with a capsule (or a
## sphere for the skull) fitted to that bone, so a shot at an outstretched arm
## registers on the arm and a shot past it misses. A single body-sized cylinder
## would make every near-miss a hit and would make the head untargetable.
##
## The rifle in the soldier's hands is deliberately not a hit volume - it is
## scenery, and bullets pass through it.
##
## The volumes sit on their own collision layer and are `Area3D`, so they are
## invisible to every existing query in the project: the weapon's wall-pushback
## ray sets `collide_with_areas = false`, the lean probe leaves it at its default
## false, and character movement only ever collides with bodies.

const HITBOX_LAYER := 3

## bone, the child bone that gives the bone its length, radius, zone.
## Zones select authoritative damage and cosmetic wound intensity.
## Each bone occurs exactly once: physics also uses these segment dimensions.
const SPEC: Array = [
	{"bone": "mixamorig_Head",         "tip": "mixamorig_HeadTop_End",   "radius": 0.105, "zone": "head",      "sphere": true},
	{"bone": "mixamorig_Neck",         "tip": "mixamorig_Head",          "radius": 0.072, "zone": "neck"},
	{"bone": "mixamorig_Spine2",       "tip": "mixamorig_Neck",          "radius": 0.165, "zone": "torso"},
	{"bone": "mixamorig_Spine",        "tip": "mixamorig_Spine1",        "radius": 0.155, "zone": "torso"},
	{"bone": "mixamorig_Spine1",       "tip": "mixamorig_Spine2",        "radius": 0.160, "zone": "torso"},
	{"bone": "mixamorig_Hips",         "tip": "mixamorig_Spine",         "radius": 0.165, "zone": "torso_low"},
	{"bone": "mixamorig_LeftArm",      "tip": "mixamorig_LeftForeArm",   "radius": 0.068, "zone": "arm_upper"},
	{"bone": "mixamorig_RightArm",     "tip": "mixamorig_RightForeArm",  "radius": 0.068, "zone": "arm_upper"},
	{"bone": "mixamorig_LeftForeArm",  "tip": "mixamorig_LeftHand",      "radius": 0.058, "zone": "arm_lower"},
	{"bone": "mixamorig_RightForeArm", "tip": "mixamorig_RightHand",     "radius": 0.058, "zone": "arm_lower"},
	{"bone": "mixamorig_LeftUpLeg",    "tip": "mixamorig_LeftLeg",       "radius": 0.098, "zone": "leg_upper"},
	{"bone": "mixamorig_RightUpLeg",   "tip": "mixamorig_RightLeg",      "radius": 0.098, "zone": "leg_upper"},
	{"bone": "mixamorig_LeftLeg",      "tip": "mixamorig_LeftFoot",      "radius": 0.078, "zone": "leg_lower"},
	{"bone": "mixamorig_RightLeg",     "tip": "mixamorig_RightFoot",     "radius": 0.078, "zone": "leg_lower"},
]

static func layer_mask() -> int:
	return 1 << (HITBOX_LAYER - 1)

## `owner_peer` is stamped onto every area so the hitscan can name a victim
## without walking back up the tree.
static func build(skeleton: Skeleton3D, owner_avatar: Node, owner_peer: int) -> Array[Area3D]:
	var built: Array[Area3D] = []
	if skeleton == null:
		return built
	for entry: Dictionary in SPEC:
		var bone_name := String(entry["bone"])
		var bone_index := skeleton.find_bone(bone_name)
		if bone_index < 0:
			push_warning("SOLDIER_HITBOXES: нет кости %s" % bone_name)
			continue

		# Stable zone/bone names for debugging; impacts use explicit metadata.
		var zone_name := String(entry["zone"])
		var attachment := BoneAttachment3D.new()
		attachment.name = "Attach_%s__%s" % [zone_name, bone_name]
		attachment.bone_name = bone_name
		attachment.bone_idx = bone_index
		skeleton.add_child(attachment)

		var area := Area3D.new()
		area.name = "Hit_%s__%s" % [zone_name, bone_name]
		# Raycasts read `collision_layer`; nothing needs these areas to detect
		# each other, so the monitoring half stays off.
		area.collision_layer = layer_mask()
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = true
		area.input_ray_pickable = false
		area.set_meta("hit_bone", bone_name)
		area.set_meta("hit_zone", String(entry["zone"]))
		area.set_meta("hit_peer", owner_peer)
		area.set_meta("hit_avatar", owner_avatar)
		attachment.add_child(area)

		var collision := CollisionShape3D.new()
		collision.name = "Shape"
		# Shapes inherit the armature scale; convert metre radii to bone units.
		var radius := float(entry["radius"]) / skeleton.global_basis.get_scale().abs().x
		var offset := _bone_offset(skeleton, String(entry["tip"]))
		var length := offset.length()

		if bool(entry.get("sphere", false)) or length < radius * 1.6:
			var sphere := SphereShape3D.new()
			sphere.radius = radius
			collision.shape = sphere
			collision.position = offset * 0.5
		else:
			var capsule := CapsuleShape3D.new()
			capsule.radius = radius
			# CapsuleShape3D.height spans the whole shape, hemispheres included.
			capsule.height = maxf(length, radius * 2.0 + 0.01)
			collision.shape = capsule
			collision.transform = _align_to(offset)
		area.add_child(collision)

		built.append(area)
	return built

## Vector from a bone to its child, in the bone's own space. The child's rest
## translation is exactly that, which keeps the fit correct whatever scale the
## GLB importer applied to the rig.
static func _bone_offset(skeleton: Skeleton3D, tip_name: String) -> Vector3:
	var tip_index := skeleton.find_bone(tip_name)
	if tip_index < 0:
		return Vector3(0.0, 0.2, 0.0)
	return skeleton.get_bone_rest(tip_index).origin

## Capsules are authored along +Y, so the shape is rotated to lie along the bone
## and shifted to sit halfway down it.
static func _align_to(offset: Vector3) -> Transform3D:
	var length := offset.length()
	if length <= 0.0001:
		return Transform3D.IDENTITY
	var up := offset / length
	var reference := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var right := reference.cross(up).normalized()
	var forward := right.cross(up).normalized()
	return Transform3D(Basis(right, up, forward), offset * 0.5)
