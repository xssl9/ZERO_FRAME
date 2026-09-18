shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform float seed = 0.0;
// Very dark dried-blood: near-black core, deep maroon at edges
const vec3 BLOOD_CORE  = vec3(0.010, 0.000, 0.001);
const vec3 BLOOD_EDGE  = vec3(0.042, 0.001, 0.002);
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float angle = atan(p.y, p.x);
	float edge = 0.78 + 0.08 * sin(angle * 7.0 + seed) + 0.05 * sin(angle * 13.0 - seed);
	float r = length(p);
	if (r > edge) { discard; }
	// Darker at the centre (pooled, dried), slightly less dark at the rim
	vec3 base = mix(BLOOD_CORE, BLOOD_EDGE, smoothstep(0.0, edge, r));
	// Subtle density variation: fake micro-relief so the pool isn't flat
	float density = 0.85 + 0.15 * (sin(angle * 5.0 + seed * 1.7) * 0.5 + 0.5);
	ALBEDO = base * density;
	ROUGHNESS = 0.18;   // wet/glossy
	SPECULAR = 0.55;
}
