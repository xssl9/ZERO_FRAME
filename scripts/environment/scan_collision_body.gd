class_name ScanCollisionBody
extends StaticBody3D

## Gives a photogrammetry scan collision. The mesh is a single 48k-triangle shell, so the
## shape is generated once at load from the child MeshInstance3D rather than authored: a
## ConcavePolygonShape3D that large is not something to hand-edit or store in the scene.
##
## Trimesh collision is one-sided and has no volume, which is exactly right for a scanned
## shell and is why the player must spawn above the floor rather than inside the mesh.

@export var mesh_child_name: String = "Mesh"
# The main-menu panorama shows this level with no player in it, so it turns the shape off:
# building a 48k-triangle trimesh for a background nobody can walk on is pure waste.
@export var build_collision: bool = true

func _ready() -> void:
	var instance := get_node_or_null(mesh_child_name) as MeshInstance3D
	if instance == null or instance.mesh == null:
		push_warning("ScanCollisionBody: no mesh at '%s'" % mesh_child_name)
		return
	# RealityCapture's diffuse-only MTL imports with metallic=1. Masonry is a
	# dielectric; preserve its UV/albedo and baked lighting, not this import default.
	for surface: int in instance.mesh.get_surface_count():
		var source := instance.get_active_material(surface) as StandardMaterial3D
		if source == null:
			continue
		var material := source.duplicate() as StandardMaterial3D
		material.metallic = 0.0
		material.roughness = 0.88
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		instance.set_surface_override_material(surface, material)
	if not build_collision:
		return
	var shape := CollisionShape3D.new()
	shape.name = "ScanShape"
	shape.shape = instance.mesh.create_trimesh_shape()
	add_child(shape)
