shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Full-geometry grass: every MultiMesh instance is two crossed 3D blades.
// Noise is sampled in world space so neighbouring patches share one wind field.
uniform sampler2D wind_noise : source_color, repeat_enable, filter_linear;
uniform sampler2D patch_noise : source_color, repeat_enable, filter_linear;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D arm_texture : filter_linear_mipmap_anisotropic;
uniform sampler2D alpha_texture : filter_linear_mipmap_anisotropic;
uniform vec2 wind_direction = vec2(0.86, 0.34);
uniform float wind_speed : hint_range(0.0, 2.0) = 0.22;
uniform float wind_strength : hint_range(0.0, 1.0) = 0.24;
uniform float patch_scale : hint_range(1.0, 50.0) = 14.0;
uniform float size_small : hint_range(0.1, 2.0) = 0.62;
uniform float size_large : hint_range(0.1, 2.0) = 1.08;

varying float blade_height;

void vertex() {
	// The selected Poly Haven tuft is authored at 8.1 cm tall.
	blade_height = clamp(VERTEX.y / 0.081, 0.0, 1.0);
	vec2 world_xz = NODE_POSITION_WORLD.xz;
	float patch = texture(patch_noise, fract(world_xz / patch_scale)).r;
	float blade_size = mix(size_small, size_large, smoothstep(0.20, 0.82, patch));
	VERTEX.xz *= blade_size;
	VERTEX.y *= blade_size;

	vec2 wind_uv = fract(world_xz / 10.0 - TIME * wind_direction * wind_speed);
	float gust = texture(wind_noise, wind_uv).r;
	// Ridged noise is centred around zero to produce calm periods between gusts.
	float gust_signed = gust * 2.0 - 1.0;
	float bend = gust_signed * wind_strength * pow(blade_height, 1.65);
	vec2 local_wind = (inverse(MODEL_MATRIX) * vec4(wind_direction.x, 0.0, wind_direction.y, 0.0)).xz;
	VERTEX.xz += local_wind * bend;

}

void fragment() {
	vec4 source = texture(albedo_texture, UV);
	float mask = texture(alpha_texture, UV).r;
	ALPHA = mask;
	ALPHA_SCISSOR_THRESHOLD = 0.34;
	ALBEDO = source.rgb;
	vec3 arm = texture(arm_texture, UV).rgb;
	AO = arm.r;
	ROUGHNESS = arm.g;
	METALLIC = 0.0;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	NORMAL_MAP_DEPTH = 0.72;
	SPECULAR = 0.16;
	BACKLIGHT = source.rgb * 0.16;
	AO_LIGHT_AFFECT = 1.0;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
