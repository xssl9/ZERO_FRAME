class_name WeaponMaterials
extends RefCounted

## Repair the FBX material bindings, not the mesh/rig. The supplied AK already has
## authored metal, roughness, AO, wear and polymer masks, but the importer dropped
## three of them. Do not invent part IDs from albedo brightness or metallize hands.
static func apply(model: Node) -> void:
	var copies: Dictionary = {}
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface: int in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			if not copies.has(source):
				var material := source.duplicate() as StandardMaterial3D
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				if source.resource_name == "ak74m":
					material.metallic = 1.0
					material.metallic_texture = load("res://assets/weapons/ak/textures/ak74m_Metallic.png")
					material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
					material.roughness = 1.0
					material.roughness_texture = load("res://assets/weapons/ak/textures/ak74m_Roughness.png")
					material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
					material.ao_enabled = true
					material.ao_texture = load("res://assets/weapons/ak/textures/ak74m_AO.png")
					material.ao_light_affect = 0.0
				elif source.resource_name == "arms":
					material.metallic = 0.0
					if source.roughness_texture == null:
						material.roughness_texture = load("res://assets/weapons/ak/textures/armRoughness.png")
						material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
				copies[source] = material
			mesh.set_surface_override_material(surface, copies[source])
