@tool
class_name SurfaceDecal
extends Decal

## Authored native projection, not a transparent quad floating above the surface.
## Small deterministic textures are generated only on ready/rebuild, never per frame.
## ORM changes roughness without adding metal to dirt, rust or rubber deposits.
enum Kind { WATER_STAIN, RUST_RUNOFF, TIRE_SCUFF }
@export var kind: Kind = Kind.WATER_STAIN
@export var variation_seed: int = 17
@export_range(0.0, 1.0) var strength: float = 0.22
@export_range(32, 512, 32) var texture_size: int = 128

func _ready() -> void:
	rebuild()

func rebuild() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = variation_seed
	noise.frequency = 0.06
	noise.fractal_octaves = 3
	var albedo := Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
	var orm := Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
	var tint := Color(0.25, 0.24, 0.21)
	var rough := 0.76
	if kind == Kind.RUST_RUNOFF:
		tint = Color(0.28, 0.15, 0.07)
		rough = 0.88
	elif kind == Kind.TIRE_SCUFF:
		tint = Color(0.12, 0.12, 0.11)
		rough = 0.82
	for y: int in texture_size:
		for x: int in texture_size:
			var uv := Vector2(float(x) + 0.5, float(y) + 0.5) / texture_size
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var edge := smoothstep(0.0, 0.12, minf(minf(uv.x, 1.0 - uv.x), minf(uv.y, 1.0 - uv.y)))
			var mask := smoothstep(0.35, 0.65, n) * edge
			if kind == Kind.RUST_RUNOFF:
				var streak := noise.get_noise_2d(x * 2.0, y * 0.12) * 0.5 + 0.5
				mask = smoothstep(0.42, 0.68, streak) * edge * (1.0 - uv.y) * (0.5 + n * 0.5)
			elif kind == Kind.TIRE_SCUFF:
				var tread := 0.65 + 0.35 * sin((uv.y * 13.0 + uv.x * 2.0) * TAU)
				mask *= tread * (1.0 - smoothstep(0.18, 0.43, absf(uv.x - 0.5)))
			albedo.set_pixel(x, y, Color(tint.r, tint.g, tint.b, mask * strength))
			orm.set_pixel(x, y, Color(1.0, rough, 0.0, 1.0))
	albedo.generate_mipmaps()
	orm.generate_mipmaps()
	texture_albedo = ImageTexture.create_from_image(albedo)
	texture_orm = ImageTexture.create_from_image(orm)
	albedo_mix = 1.0
	normal_fade = 0.65
	upper_fade = 0.2
	lower_fade = 0.2
	distance_fade_enabled = true
	distance_fade_begin = 22.0
	distance_fade_length = 8.0
