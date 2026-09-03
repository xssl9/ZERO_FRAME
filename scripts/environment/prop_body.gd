class_name PropBody
extends StaticBody3D

## Turns any imported prop into cover you can hide behind.
##
## The collider is measured from the meshes underneath rather than typed in by hand: a
## downloaded prop has whatever dimensions it has, and a wrong box is either a phantom wall or
## a crate you walk through. One box per prop is deliberate - a rack of shelves does not need
## its every strut in the physics world.

@export var height_scale: float = 1.0
@export var inset: float = 0.02

func _ready() -> void:
	var bounds := AABB()
	var found := false
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		# A hidden mesh is not something anyone can walk into. Some downloaded props ship two
		# variants in one file and only one of them is shown, and measuring both would put a
		# collider across three metres of empty floor.
		if not instance.is_visible_in_tree():
			continue
		# Local to this body, so the shape follows however the prop was placed inside it.
		var local := global_transform.affine_inverse() * instance.global_transform
		var mesh_bounds := local * instance.mesh.get_aabb()
		bounds = mesh_bounds if not found else bounds.merge(mesh_bounds)
		found = true
	if not found:
		push_warning("PropBody %s has no mesh to measure" % name)
		return
	var shape := BoxShape3D.new()
	var size := bounds.size
	shape.size = Vector3(
		maxf(size.x - inset, 0.05),
		maxf(size.y * height_scale - inset, 0.05),
		maxf(size.z - inset, 0.05))
	var collider := CollisionShape3D.new()
	collider.name = "PropShape"
	collider.shape = shape
	collider.position = bounds.get_center() - Vector3(0.0, size.y * (1.0 - height_scale) * 0.5, 0.0)
	add_child(collider)
