@tool
class_name WetnessManager
extends Node

## Per-level state, not a global shader uniform: menu and gameplay have isolated worlds.
## Authored wetness remains surface capacity; shaders retain a dry baseline at zero.
@export_range(0.0, 1.0) var wetness: float = 0.0
@export_range(0.0, 1.0) var target_wetness: float = 0.0
@export var soak_seconds: float = 45.0
@export var dry_seconds: float = 150.0
@export_range(0.0, 1.0) var roughness_variation: float = 0.08
var rain_intensity: float = 0.0
var puddle_amount: float = 0.0
var materials: Array[ShaderMaterial] = []
var _capacity: Dictionary = {}
var _water: MeshInstance3D
var _timer: float = 0.0

func configure(root: Node, initial: float) -> void:
	wetness = clampf(initial, 0.0, 1.0)
	target_wetness = wetness
	materials.clear()
	_capacity.clear()
	# Duplicate once per unique resource; preserve intentional sharing within this level.
	var copies: Dictionary = {}
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.get_viewport() != root.get_viewport() or mesh.mesh == null:
			continue
		for surface: int in mesh.mesh.get_surface_count():
			var original := mesh.get_active_material(surface) as ShaderMaterial
			if original == null or original.shader == null:
				continue
			var path := original.shader.resource_path
			if path not in ["res://shaders/dev_grid.gdshader", "res://shaders/rain_puddles.gdshader", "res://shaders/scan_surface.gdshader"]:
				continue
			if not copies.has(original):
				copies[original] = original.duplicate()
				var copy := copies[original] as ShaderMaterial
				materials.append(copy)
				if not path.ends_with("rain_puddles.gdshader"):
					var authored: Variant = original.get_shader_parameter("wetness")
					_capacity[copy] = float(authored) if authored != null else 0.0
			if mesh.material_override != null:
				mesh.material_override = copies[original]
				break # One override covers all surfaces; do not duplicate its copy again.
			else:
				mesh.set_surface_override_material(surface, copies[original])
	_water = root.find_child("WetGround", true, false) as MeshInstance3D
	publish()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	advance(delta)
	_timer += delta
	if _timer >= 0.1:
		_timer = 0.0
		publish()

func advance(delta: float) -> void:
	var seconds := soak_seconds if target_wetness > wetness else dry_seconds
	wetness = move_toward(wetness, clampf(target_wetness, 0.0, 1.0), maxf(delta, 0.0) / maxf(seconds, 0.01))
	puddle_amount = smoothstep(0.35, 1.0, wetness)

func publish() -> void:
	puddle_amount = smoothstep(0.35, 1.0, wetness)
	for material: ShaderMaterial in materials:
		if _capacity.has(material):
			material.set_shader_parameter("wetness", float(_capacity[material]) * wetness)
			material.set_shader_parameter("roughness_variation", roughness_variation)
		else:
			material.set_shader_parameter("puddle_amount", puddle_amount)
			material.set_shader_parameter("rain_intensity", rain_intensity)
	if _water != null:
		_water.visible = puddle_amount > 0.001
