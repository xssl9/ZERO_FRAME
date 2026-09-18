shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

const int TOTAL_BLOOD_DROPS = 64;
const float BLOOD_ROUGHNESS = 0.05;
const float BLOOD_BLENDING = 0.12;

uniform sampler2D blood_texture : repeat_disable, filter_linear_mipmap;
uniform vec3 blood_color : source_color = vec3(0.04, 0.0, 0.0);
uniform float blood_merge_factor : hint_range(0.0, 1.0) = 0.25;

group_uniforms ExternallySetted;
uniform vec2 positions[TOTAL_BLOOD_DROPS];
uniform float scales[TOTAL_BLOOD_DROPS];
group_uniforms;

vec2 scale_from_center(vec2 uv, float s) {
	return ((uv - 0.5) * (1.0 / s)) + 0.5;
}

void fragment() {
	float blended = 1.0;
	for (int i = 0; i < TOTAL_BLOOD_DROPS; i++) {
		if (scales[i] <= 0.01) continue;
		vec2 uv_t = UV - positions[i] + 0.5;
		vec2 uv_s = scale_from_center(uv_t, scales[i]);
		blended *= texture(blood_texture, uv_s).r;
	}

	bool is_blood = false;
	for (int i = 0; i < TOTAL_BLOOD_DROPS; i++) {
		if (scales[i] <= 0.01) continue;
		if (blended < blood_merge_factor) {
			is_blood = true;
			break;
		}
	}

	if (is_blood) {
		ALBEDO = blood_color;
		ROUGHNESS = BLOOD_ROUGHNESS;
		ALPHA = 1.0;
	} else {
		ALPHA = 0.0;
	}
}
