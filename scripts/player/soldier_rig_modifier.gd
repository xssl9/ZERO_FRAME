class_name SoldierRigModifier
extends SkeletonModifier3D

## Runs after the AnimationTree has written the pose, which is the only place
## these two edits survive.
##
## 1. First-person culling. The player's own hands and rifle live in the isolated
##    weapon SubViewport; the body model exists purely so that looking down shows
##    legs and a torso. Collapsing the head and upper-arm bones to zero scale
##    takes every vertex weighted to them down to a point, so the duplicate head
##    and duplicate arms never appear in front of the camera. Hiding the mesh
##    outright would take the legs with it, and a per-vertex shader discard would
##    need a second material on a mesh shared with the remote view.
## 2. Aim pitch. The camera is deliberately not parented to the neck bone, so the
##    skeleton has no idea where the player is looking. Spreading the pitch over
##    three spine joints is what makes a remote soldier point the rifle where the
##    tracer actually goes.

const HIDDEN_BONES: PackedStringArray = [
	"mixamorig_Head",
	"mixamorig_LeftArm",
	"mixamorig_RightArm",
]

const PITCH_BONES: PackedStringArray = [
	"mixamorig_Spine",
	"mixamorig_Spine1",
	"mixamorig_Spine2",
]

const MAX_PITCH_DEGREES := 60.0

var hide_upper_body: bool = false
var aim_pitch: float = 0.0

var _hidden_indices: PackedInt32Array = []
var _pitch_indices: PackedInt32Array = []
var _resolved: bool = false

func _resolve(skeleton: Skeleton3D) -> void:
	if _resolved:
		return
	_resolved = true
	for bone_name: String in HIDDEN_BONES:
		var index := skeleton.find_bone(bone_name)
		if index >= 0:
			_hidden_indices.append(index)
	for bone_name: String in PITCH_BONES:
		var index := skeleton.find_bone(bone_name)
		if index >= 0:
			_pitch_indices.append(index)

func _apply(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	_resolve(skeleton)
	if hide_upper_body:
		for index: int in _hidden_indices:
			skeleton.set_bone_pose_scale(index, Vector3.ZERO)
	if not _pitch_indices.is_empty():
		var clamped := clampf(aim_pitch, -MAX_PITCH_DEGREES, MAX_PITCH_DEGREES)
		var share := deg_to_rad(clamped) / float(_pitch_indices.size())
		for index: int in _pitch_indices:
			var pose := skeleton.get_bone_pose_rotation(index)
			skeleton.set_bone_pose_rotation(index, pose * Quaternion(Vector3.RIGHT, share))

func _process_modification() -> void:
	_apply(get_skeleton())

# Godot 4.5 renamed the virtual and passes a delta. Implementing both keeps the
# modifier working whichever one the running build dispatches.
func _process_modification_with_delta(_delta: float) -> void:
	_apply(get_skeleton())
