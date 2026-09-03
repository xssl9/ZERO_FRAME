class_name LevelMeshCollision
extends Node3D

## Gives an imported level mesh trimesh collision without hand-authoring a shape.
##
## Put this on the node that owns the imported scene and name the meshes that are supposed to
## be solid. Everything else - pipes, light fixtures, signs - stays collision-free, which is
## both cheaper and what you want: nobody should bump into a fluorescent tube.
##
## The default is the parking blockout's own mesh names rather than a placeholder, because the
## Godot editor drops this property when it re-saves a generated scene, and a level whose floor
## quietly stops existing is a worse failure than one that builds a shape nobody asked for.

@export var solid_mesh_names: PackedStringArray = [
	"Floor_Parking", "Floor_Annex", "Walls_Concrete", "Walls_Plaster", "Ceiling", "Entrance_Shutter"
]
@export var build_collision: bool = true

func _ready() -> void:
	if not build_collision:
		return
	for mesh_name: String in solid_mesh_names:
		var instance := find_child(mesh_name, true, false) as MeshInstance3D
		if instance == null or instance.mesh == null:
			push_warning("LevelMeshCollision: no mesh named '%s'" % mesh_name)
			continue
		var body := StaticBody3D.new()
		body.name = "%sBody" % mesh_name
		var shape := CollisionShape3D.new()
		shape.shape = instance.mesh.create_trimesh_shape()
		body.add_child(shape)
		# Parented to the mesh so the body inherits whatever transform the import gave it.
		instance.add_child(body)
