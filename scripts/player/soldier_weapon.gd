class_name SoldierWeapon
extends RefCounted

const SCENES := ["res://scenes/weapons/ak_viewmodel.tscn", "res://scenes/weapons/pistol_viewmodel.tscn"]
const IDLES := ["Rig|AK_Idle", "Armature|FPS_Pistol_Idle"]
const HANDS := ["Hand_R", "Hand_R_038"]
static var _cache: Dictionary = {}
static var _mounts: Dictionary = {}

# Only baked weapon meshes survive. No first-person arms, cameras, scripts,
# lights or collision objects are copied into the opponent's hand.
static func build(index: int, parent: Node, soldier_hand: Transform3D) -> Node3D:
	if not _cache.has(index):
		var source := (load(SCENES[index]) as PackedScene).instantiate() as Node3D
		for camera: Node in source.find_children("*", "Camera3D", true, false):
			camera.free()
		parent.add_child(source)
		WeaponMaterials.apply(source)
		var animation := source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		animation.play(IDLES[index])
		animation.advance(0.0)
		var skeleton := source.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var source_space := source.global_transform.affine_inverse() * skeleton.global_transform
		var grip := source_space * skeleton.get_bone_global_pose(skeleton.find_bone(HANDS[index])).origin
		var parts: Array = []
		for node: Node in source.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh.name == &"arms" or mesh.name == &"Object_9" or mesh.name == &"Mag_2":
				continue
			var pose := source.global_transform.affine_inverse() * mesh.global_transform
			pose.origin -= grip
			# Use the same metre-scale assembly as first person; no second scale correction.
			parts.append({"mesh": SoldierModel.bake_mesh(mesh, skeleton), "pose": pose})
		_cache[index] = parts
		var muzzle := source.find_child("MuzzlePoint", true, false) as Marker3D
		var mount := (source.global_transform.affine_inverse() * muzzle.global_transform).orthonormalized()
		mount.origin -= grip
		mount.origin += Vector3(0.045, -0.025, 0.10) if index == 0 else Vector3(0.0, -0.035, 0.015)
		_mounts[index] = mount
		source.free()
	var weapon := Node3D.new()
	weapon.name = "AK74M" if index == 0 else "Pistol"
	# In the reference rifle pose the weapon points along the character's -Z.
	# Cancel the bind hand orientation once, then inherit its animated motion.
	weapon.basis = soldier_hand.basis.inverse()
	for part: Dictionary in _cache[index]:
		var mesh := MeshInstance3D.new()
		mesh.mesh = part.mesh
		mesh.transform = part.pose
		weapon.add_child(mesh)
	WeaponFlashlight.build(weapon, _mounts[index])
	return weapon
