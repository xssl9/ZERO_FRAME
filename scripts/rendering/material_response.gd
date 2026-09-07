class_name MaterialResponse
extends RefCounted

## Recover existing packed Poly Haven AO, never infer metal from diffuse brightness.
## One duplicate per unique material keeps batching and isolates menu/gameplay worlds.
static func apply(root: Node) -> void:
	var copies: Dictionary = {}
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or mesh.get_viewport() != root.get_viewport():
			continue
		for surface: int in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			if not copies.has(source):
				var material := source.duplicate() as StandardMaterial3D
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				var arm := source.roughness_texture
				if arm != null and "_arm_" in arm.resource_path and not source.ao_enabled:
					material.ao_enabled = true
					material.ao_texture = arm
					material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
					material.ao_light_affect = 0.0
				copies[source] = material
			if mesh.material_override != null:
				mesh.material_override = copies[source]
				break
			mesh.set_surface_override_material(surface, copies[source])
