shader_type spatial;
// Premultiplied alpha instead of plain additive blending: the viewmodel is drawn in a
// SubViewport with transparent_bg, and an additive pass leaves the framebuffer alpha at
// zero, so the flash would be invisible everywhere it did not overlap the gun itself.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// 0.0 is the instant the round leaves the barrel, 1.0 is a dead flash.
uniform float progress : hint_range(0.0, 1.0) = 1.0;
// Rotates and reshuffles the whole pattern so consecutive rounds never draw the same flame.
uniform float seed = 0.0;
uniform float brightness : hint_range(0.0, 200.0) = 26.0;
// How many tongues of burning powder the ragged edge breaks into.
uniform float tongue_count : hint_range(1.0, 24.0) = 9.0;
uniform float turbulence : hint_range(0.0, 4.0) = 1.0;
// 0.0 = ragged star of flame tongues, 1.0 = round ball of glowing gas. The petals use
// 0.0 and the muzzle core/outer glow use 1.0, all from this one shader.
uniform float soft_ball : hint_range(0.0, 1.0) = 0.0;
// Powder flame is a blackbody gradient, not one orange: white-hot gas at the muzzle,
// yellow in the body, deep red where it cools at the tips.
uniform vec3 core_color : source_color = vec3(1.0, 0.99, 0.94);
uniform vec3 mid_color : source_color = vec3(1.0, 0.72, 0.28);
uniform vec3 edge_color : source_color = vec3(0.94, 0.24, 0.03);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 w = f * f * (3.0 - 2.0 * f);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

// Three octaves is enough: the flash is on screen for two frames at 60 FPS, so finer
// detail costs fill rate nobody can see.
float fbm(vec2 p) {
	float sum = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
		sum += value_noise(p) * amplitude;
		p *= 2.03;
		amplitude *= 0.5;
	}
	return sum;
}

void vertex() {
	// Burning gas is already at full width the instant it clears the muzzle, so the quad
	// only puffs outwards slightly while it dies instead of growing from nothing.
	VERTEX.xy *= 0.88 + 0.30 * progress;
}

void fragment() {
	vec2 offset = UV * 2.0 - 1.0;
	float radius = length(offset);
	vec2 direction = offset / max(radius, 0.0001);

	// The tongue pattern is sampled on a circle, so it is seamless across the +/-PI wrap
	// instead of showing a visible split like an angle-based sine would.
	float ragged = fbm(direction * tongue_count + vec2(seed, seed * 0.71));
	float reach = mix(mix(0.40, 1.0, ragged), 0.88, soft_ball);
	// Interior erosion breaks the flame into separate tongues instead of one flat blob.
	float erosion = mix(0.52 + 0.48 * fbm(offset * (1.0 + 2.8 * turbulence) + seed * 1.37), 1.0, soft_ball);
	float body = 1.0 - smoothstep(reach * 0.22, reach, radius);
	float shape = clamp(body * erosion, 0.0, 1.0);
	// A hot ball of gas sits right at the muzzle whatever the tongues are doing.
	float core = exp(-radius * radius * mix(5.5, 3.0, soft_ball));

	float heat = clamp(shape * 0.75 + core, 0.0, 1.0);
	// Real flashes are gone within one or two frames: full brightness immediately, then
	// a fast non-linear decay rather than a fade.
	float life = pow(1.0 - progress, 1.7);
	float intensity = (shape * 0.8 + core * 1.35) * life;

	vec3 color = mix(edge_color, mid_color, smoothstep(0.05, 0.55, heat));
	color = mix(color, core_color, smoothstep(0.55, 0.96, heat));

	// Premultiplied: ALBEDO already carries the coverage, so it is not multiplied by
	// ALPHA again downstream. ALPHA only exists so the flash composites over the world.
	ALBEDO = color * intensity * brightness;
	ALPHA = clamp(intensity * 1.6, 0.0, 1.0);
}
