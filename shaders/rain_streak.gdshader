shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_disabled;

uniform vec4 tint : source_color = vec4(0.7, 0.76, 0.82, 0.3);
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
// Direction is expressed in this World3D; the viewmodel supplies camera-local gravity.
uniform vec3 fall_direction = vec3(0.13, -1.0, -0.065);

void vertex() {
	vec3 up = normalize(-fall_direction);
	vec3 toward_camera = normalize(INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz);
	vec3 right = cross(up, toward_camera);
	if (length(right) < 0.01) { right = INV_VIEW_MATRIX[0].xyz; }
	right = normalize(right);
	vec3 normal = normalize(cross(right, up));
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right * scale.x, 0), vec4(up * scale.y, 0), vec4(normal * scale.z, 0), MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float taper = sqrt(max(0.0, 1.0 - p.y * p.y));
	float width = abs(p.x) / max(taper, 0.001);
	float aa = max(fwidth(width), 0.08);
	float streak = (1.0 - smoothstep(0.15, 1.0 + aa, width)) * (1.0 - smoothstep(0.55, 1.0, abs(p.y)));
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 scene = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float contact = smoothstep(0.0, 0.12, -scene.z / scene.w + VERTEX.z);
	float distance_fade = smoothstep(0.12, 0.7, -VERTEX.z) * (1.0 - smoothstep(22.0, 48.0, -VERTEX.z));
	ALBEDO = tint.rgb;
	ROUGHNESS = 0.45;
	ALPHA = tint.a * COLOR.a * streak * contact * distance_fade;
}
