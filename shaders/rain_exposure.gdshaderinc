// Static top-down collision coverage. Separate per-level resources keep menu worlds isolated.
// This is roof occlusion, not a drainage/porosity simulation. Resolution is authored in metres.
uniform sampler2D rain_roof_height : filter_nearest, repeat_disable;
uniform vec4 rain_roof_bounds = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool rain_roof_enabled = false;
uniform bool rain_roof_ready = false;

float rain_exposure_at(vec3 position_world) {
	if (!rain_roof_enabled) { return 1.0; }
	if (!rain_roof_ready) { return 0.0; }
	vec2 uv = (position_world.xz - rain_roof_bounds.xy) / max(rain_roof_bounds.zw, vec2(0.001));
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) { return 0.0; }
	float roof = texture(rain_roof_height, uv).r;
	return smoothstep(roof - 0.16, roof - 0.04, position_world.y);
}
