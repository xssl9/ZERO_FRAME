class_name SoldierRigModifier
extends SkeletonModifier3D

## Apply aim pitch after animation evaluation. First-person visibility uses a
## separate leg mesh; its skeleton is never collapsed or bent with camera pitch.

const PITCH_BONES: PackedStringArray = [
	"mixamorig_Spine",
	"mixamorig_Spine1",
	"mixamorig_Spine2",
]

const MAX_PITCH_DEGREES := 60.0

var hide_upper_body: bool = false
var aim_pitch: float = 0.0

var _pitch_indices: PackedInt32Array = []
var _resolved: bool = false

func _resolve(skeleton: Skeleton3D) -> void:
	if _resolved:
		return
	_resolved = true
	for bone_name: String in PITCH_BONES:
		var index := skeleton.find_bone(bone_name)
		if index >= 0:
			_pitch_indices.append(index)

func _apply(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	_resolve(skeleton)
	if hide_upper_body:
		# Local upper-body visibility is handled by a filtered mesh, never by
		# deforming the skeleton. Do not bend the legs/shadow through the camera.
		return
	if not _pitch_indices.is_empty():
		var clamped := clampf(aim_pitch, -MAX_PITCH_DEGREES, MAX_PITCH_DEGREES)
		var share := deg_to_rad(clamped) / float(_pitch_indices.size())
		for index: int in _pitch_indices:
			var pose := skeleton.get_bone_pose_rotation(index)
			# Mixamo joint axes are not the player's axes (the rig faces +Z).
			var model_right := Vector3.LEFT
			var axis := skeleton.get_bone_global_pose(index).basis.inverse() * model_right
			skeleton.set_bone_pose_rotation(index, pose * Quaternion(axis.normalized(), share))

func _process_modification() -> void:
	_apply(get_skeleton())

# Godot 4.5 renamed the virtual and passes a delta. Implementing both keeps the
# modifier working whichever one the running build dispatches.
func _process_modification_with_delta(_delta: float) -> void:
	_apply(get_skeleton())
