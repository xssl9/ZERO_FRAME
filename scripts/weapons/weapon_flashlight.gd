class_name WeaponFlashlight
extends RefCounted

# A compact rail-mounted housing, shared by first/third person. The marker's
# -Z axis is the optical axis; the level light is mapped from this same marker.
static func build(parent: Node3D, mount_transform: Transform3D) -> Marker3D:
	var mount := Marker3D.new()
	mount.name = "FlashlightMount"
	parent.add_child(mount)
	mount.transform = mount_transform
	var housing := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.018
	cylinder.bottom_radius = 0.018
	cylinder.height = 0.085
	cylinder.radial_segments = 16
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.055, 0.06, 0.065)
	material.metallic = 0.8
	material.roughness = 0.32
	cylinder.material = material
	housing.mesh = cylinder
	housing.rotation.x = PI * 0.5
	housing.position.z = 0.0425
	mount.add_child(housing)
	var lens := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.015
	disc.bottom_radius = 0.015
	disc.height = 0.003
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.3, 0.4, 0.45)
	glass.metallic = 0.65
	glass.roughness = 0.12
	disc.material = glass
	lens.mesh = disc
	lens.rotation.x = PI * 0.5
	mount.add_child(lens)
	return mount
