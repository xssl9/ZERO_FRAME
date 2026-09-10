class_name RainExposureMask
extends Node

## Once-per-level STATIC collision height map; no per-frame CPU texture readback.
## Multi-storey floors below the top receiver remain sheltered. Thin render-only
## overhangs need collision proxies; moving roofs require an explicit rebuild.
@export_range(16, 256, 16) var resolution: int = 96
@export_range(32, 1024, 32) var rays_per_frame: int = 256
var ready_mask: bool = false
var bounds: AABB
var texture: ImageTexture
var _image: Image
var _cursor: int = 0
var _root: Node3D
var _materials: Array[ShaderMaterial] = []
var _exclude: Array[RID] = []

func configure(level: Node3D, materials: Array[ShaderMaterial]) -> void:
	_root = level
	_materials = materials
	var found := false
	for node: Node in level.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or mesh.get_viewport() != level.get_viewport() or mesh.name == "WetGround":
			continue
		var box := mesh.global_transform * mesh.get_aabb()
		bounds = bounds.merge(box) if found else box
		found = true
	if not found:
		set_physics_process(false)
		return
	bounds = bounds.grow(0.5)
	for node: Node in level.find_children("*", "CharacterBody3D", true, false):
		_exclude.append((node as CharacterBody3D).get_rid())
	_image = Image.create(resolution, resolution, false, Image.FORMAT_RF)
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("rain_roof_enabled", true)
		material.set_shader_parameter("rain_roof_ready", false)
		material.set_shader_parameter("rain_roof_bounds", Vector4(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z))

func _physics_process(_delta: float) -> void:
	if _root == null or _image == null or ready_mask:
		return
	var space := _root.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.exclude = _exclude
	# Backfaces also occlude rainfall: scans may have inconsistent winding.
	query.hit_back_faces = true
	var end := mini(_cursor + rays_per_frame, resolution * resolution)
	while _cursor < end:
		var x := _cursor % resolution
		var y := _cursor / resolution
		var px := bounds.position.x + (float(x) + 0.5) / resolution * bounds.size.x
		var pz := bounds.position.z + (float(y) + 0.5) / resolution * bounds.size.z
		query.from = Vector3(px, bounds.end.y + 1.0, pz)
		query.to = Vector3(px, bounds.position.y - 1.0, pz)
		var hit := space.intersect_ray(query)
		var height: float = hit.position.y if not hit.is_empty() else bounds.position.y - 1.0
		_image.set_pixel(x, y, Color(height, 0.0, 0.0))
		_cursor += 1
	if _cursor == resolution * resolution:
		texture = ImageTexture.create_from_image(_image)
		for material: ShaderMaterial in _materials:
			material.set_shader_parameter("rain_roof_height", texture)
			material.set_shader_parameter("rain_roof_ready", true)
		ready_mask = true
		set_physics_process(false)
