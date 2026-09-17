shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_disabled;

uniform vec4 tint : source_color = vec4(0.62, 0.64, 0.66, 0.22);
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform float softness = 0.18;
varying float age;
varying float seed;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1)), f.x), f.y);
}
float fbm(vec2 p) {
	return 0.57 * noise(p) + 0.28 * noise(p * 2.03 + 13.0) + 0.15 * noise(p * 4.09 + 37.0);
}
void vertex() {
	age = INSTANCE_CUSTOM.y;
	seed = INSTANCE_CUSTOM.x;
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	float c = cos(seed);
	float s = sin(seed);
	vec3 right = INV_VIEW_MATRIX[0].xyz * c + INV_VIEW_MATRIX[1].xyz * s;
	vec3 up = -INV_VIEW_MATRIX[0].xyz * s + INV_VIEW_MATRIX[1].xyz * c;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right * scale.x, 0), vec4(up * scale.y, 0), vec4(INV_VIEW_MATRIX[2].xyz * scale.z, 0), MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	vec2 flow = vec2(seed, -age * 0.9);
	float density = fbm(p * 2.8 + flow);
	float edge = 1.0 - smoothstep(0.28, 1.0, length(p) + (density - 0.5) * 0.23);
	float life = smoothstep(0.0, 0.07, age) * (1.0 - smoothstep(0.28, 1.0, age));
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 scene = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float separation = -scene.z / scene.w + VERTEX.z;
	float contact = smoothstep(0.0, softness, separation);
	float near_fade = smoothstep(0.06, 0.22, -VERTEX.z);
	ALBEDO = tint.rgb * COLOR.rgb * mix(0.8, 1.1, density);
	ROUGHNESS = 1.0;
	ALPHA = tint.a * COLOR.a * edge * mix(0.3, 1.0, density) * life * contact * near_fade;
}
