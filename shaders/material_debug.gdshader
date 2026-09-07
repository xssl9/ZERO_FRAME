shader_type spatial;
render_mode unshaded, fog_disabled;

uniform int mode = 1;
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform sampler2D roughness_map : hint_default_white;
uniform sampler2D metallic_map : hint_default_white;
uniform sampler2D ao_map : hint_default_white;
uniform sampler2D normal_map : hint_normal;
uniform bool has_normal = false;
uniform float normal_strength = 1.0;
uniform vec4 roughness_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec4 metallic_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec4 ao_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform vec3 material_id = vec3(0.5);

void fragment() {
	vec2 uv = UV * uv_scale.xy + uv_offset.xy;
	vec3 result = vec3(roughness * dot(texture(roughness_map, uv), roughness_channel));
	if (mode == 2) { result = vec3(metallic * dot(texture(metallic_map, uv), metallic_channel)); }
	if (mode == 3) {
		vec3 n = NORMAL;
		if (has_normal) {
			vec3 map = texture(normal_map, uv).rgb * 2.0 - 1.0;
			map.xy *= normal_strength;
			n = normalize(TANGENT * map.x + BINORMAL * map.y + NORMAL * map.z);
		}
		result = normalize(INV_VIEW_MATRIX * vec4(n, 0.0)).xyz * 0.5 + 0.5;
	}
	if (mode == 4) { result = vec3(dot(texture(ao_map, uv), ao_channel)); }
	// Standard materials without a weather binding are explicitly dry, not guessed.
	if (mode == 5) { result = vec3(0.0); }
	if (mode == 6) { result = material_id; }
	ALBEDO = result;
}
