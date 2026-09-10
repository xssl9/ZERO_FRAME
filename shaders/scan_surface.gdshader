shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/rain_exposure.gdshaderinc"

// Diffuse-only scan: retain UVs and captured illumination. No invented metallic,
// height or tangent normal maps; reconstructing PBR needs de-lit source imagery.
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform float surface_roughness = 0.88;
uniform float wetness = 1.0;
uniform float roughness_variation = 0.08;
uniform int debug_view = 0;
uniform vec3 material_id : source_color = vec3(0.5);
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 n = normalize(world_normal);
	float wet = wetness * rain_exposure_at(world_position) * smoothstep(-0.3, 0.0, n.y);
	// Low-amplitude broad variation; no high-frequency procedural grain on the scan.
	float variation = sin(world_position.x * 1.7 + sin(world_position.z * 0.9)) * sin(world_position.y * 2.1 + world_position.z);
	ALBEDO = texture(albedo_texture, UV * uv_scale.xy + uv_offset.xy).rgb * albedo_tint.rgb * mix(1.0, 0.86, wet);
	ROUGHNESS = mix(clamp(surface_roughness + variation * roughness_variation * 0.25, 0.5, 0.98), 0.54, wet);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	if (debug_view > 0) {
		vec3 channel = vec3(ROUGHNESS);
		if (debug_view == 2) { channel = vec3(0.0); }
		if (debug_view == 3) { channel = n * 0.5 + 0.5; }
		if (debug_view == 4) { channel = vec3(1.0); }
		if (debug_view == 5) { channel = vec3(wet); }
		if (debug_view == 6) { channel = material_id; }
		ALBEDO = vec3(0.0);
		EMISSION = channel;
	}
}
