class_name GrassField
extends MultiMeshInstance3D

## Batched Poly Haven grass. A low-cost tuft from grass_medium_01 is instanced
## thousands of times while one shared material handles wind and interaction.

const GRASS_SCENE := "res://assets/polyhaven/models/grass_medium_01/grass_medium_01_1k.gltf"
const GRASS_TUFT_NAME := "grass_medium_01_tiny_c_LOD0"
const GRASS_ALBEDO := "res://assets/polyhaven/models/grass_medium_01/textures/grass_medium_01_diff_1k.jpg"
const GRASS_NORMAL := "res://assets/polyhaven/models/grass_medium_01/textures/grass_medium_01_nor_gl_1k.jpg"
const GRASS_ARM := "res://assets/polyhaven/models/grass_medium_01/textures/grass_medium_01_arm_1k.jpg"
const GRASS_ALPHA := "res://assets/polyhaven/models/grass_medium_01/textures/grass_medium_01_alpha_1k.png"

var _grass_material: ShaderMaterial

func configure(_target: Node3D, patch_size: Vector2, count: int, seed_value: int) -> void:
	var shader := load("res://shaders/grass_wind.gdshader") as Shader
	_grass_material = ShaderMaterial.new()
	_grass_material.shader = shader
	_grass_material.set_shader_parameter("wind_direction", Vector2(0.86, 0.34))
	_grass_material.set_shader_parameter("wind_speed", 0.22)
	_grass_material.set_shader_parameter("wind_strength", 0.24)
	_grass_material.set_shader_parameter("size_small", 5.6)
	_grass_material.set_shader_parameter("size_large", 7.8)
	_grass_material.set_shader_parameter("albedo_texture", load(GRASS_ALBEDO))
	_grass_material.set_shader_parameter("normal_texture", load(GRASS_NORMAL))
	_grass_material.set_shader_parameter("arm_texture", load(GRASS_ARM))
	_grass_material.set_shader_parameter("alpha_texture", load(GRASS_ALPHA))
	var wind_noise := FastNoiseLite.new()
	wind_noise.seed = seed_value
	wind_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wind_noise.frequency = 0.42
	wind_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	wind_noise.fractal_octaves = 4
	var noise_texture := NoiseTexture2D.new()
	noise_texture.noise = wind_noise
	noise_texture.width = 128
	noise_texture.height = 128
	noise_texture.seamless = true
	noise_texture.seamless_blend_skirt = 0.22
	_grass_material.set_shader_parameter("wind_noise", noise_texture)
	_grass_material.set_shader_parameter("patch_noise", noise_texture)
	material_override = _grass_material

	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = false
	batch.mesh = _load_polyhaven_tuft()
	if batch.mesh == null:
		push_error("GrassField: Poly Haven tuft '%s' is missing" % GRASS_TUFT_NAME)
		return
	batch.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for index: int in count:
		var x := rng.randf_range(-patch_size.x * 0.5, patch_size.x * 0.5)
		var z := rng.randf_range(-patch_size.y * 0.5, patch_size.y * 0.5)
		var yaw := rng.randf_range(-PI, PI)
		var scale := rng.randf_range(0.78, 1.18)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale))
		batch.set_instance_transform(index, Transform3D(basis, Vector3(x, 0.0, z)))
	multimesh = batch
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Alpha-tested vegetation is fill-rate heavy. Fifty-five metres keeps the
	# playable courtyard dense without rendering thousands of tiny distant tufts.
	visibility_range_end = 55.0
	visibility_range_end_margin = 9.0
	visibility_range_begin = 0.0
	visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	# Keep the whole patch in the culling volume even when its base mesh is tiny.
	custom_aabb = AABB(Vector3(-patch_size.x * 0.5, -0.1, -patch_size.y * 0.5), Vector3(patch_size.x, 1.2, patch_size.y))

func _load_polyhaven_tuft() -> Mesh:
	var packed := load(GRASS_SCENE) as PackedScene
	if packed == null:
		return null
	var model := packed.instantiate()
	var tuft := model.find_child(GRASS_TUFT_NAME, true, false) as MeshInstance3D
	var result: Mesh = tuft.mesh if tuft != null else null
	model.free()
	return result
