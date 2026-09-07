extends SceneTree

func _initialize() -> void:
	for type: String in ["GPUParticlesCollisionHeightField3D", "ParticleProcessMaterial", "Viewport", "RenderingServer"]:
		print("API ", type)
		for constant: String in ClassDB.class_get_integer_constant_list(type):
			if "COLLISION" in constant or "UPDATE_MODE" in constant or "DEBUG_DRAW" in constant:
				print(constant, "=", ClassDB.class_get_integer_constant(type, constant))
	quit()
