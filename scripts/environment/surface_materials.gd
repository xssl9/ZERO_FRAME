class_name SurfaceMaterials
extends Node3D

## Assigns one material per named mesh inside an imported level scene.
##
## The blockout comes out of Blender with flat placeholder materials grouped by function, and
## this is where those groups become the real thing: Poly Haven PBR through
## shaders/dev_grid.gdshader, which does world-space triplanar mapping, so a 60 m slab tiles
## correctly without anyone unwrapping UVs, and keeps the wetness and muzzle-flash terms.

@export var materials: Dictionary = {}

func _ready() -> void:
	# The meshes are siblings, not children: this node sits inside the imported scene next to
	# them, so the search starts at the parent. Searching from here found nothing at all, which
	# left the whole level on the flat placeholder materials from the blockout.
	var host := get_parent()
	if host == null:
		push_warning("SurfaceMaterials: no parent to search for meshes")
		return
	for mesh_name: String in materials:
		var material := materials[mesh_name] as Material
		if material == null:
			continue
		var instance := host.find_child(mesh_name, true, false) as MeshInstance3D
		if instance == null:
			push_warning("SurfaceMaterials: no mesh named '%s'" % mesh_name)
			continue
		instance.material_override = material
