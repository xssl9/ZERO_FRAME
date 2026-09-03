shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley;

// Worn line paint for parking bays. A bay marking is a 10 cm stripe of thermoplastic that cars
// have driven over for fifteen years, so what matters is not the line but how much of it is
// missing: the wear mask is what stops it reading as a decal someone pasted on the floor.
//
// Drawn on a thin quad lying on the floor with a centimetre of standoff.

uniform float mark_seed : hint_range(0.0, 64.0, 0.01) = 0.0;
uniform vec3 paint_color : source_color = vec3(0.82, 0.81, 0.76);
// Fraction of the quad's width the stripe fills. The quad is authored the width of the stripe
// plus its feather, so this stays near one.
uniform float line_width : hint_range(0.05, 1.0, 0.01) = 0.62;
uniform float wear : hint_range(0.0, 1.0, 0.01) = 0.55;
// Whole sections scrubbed away by tyres, as opposed to the fine pitting of `wear`.
uniform float patchiness : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float dirt : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 0.95;

float hash21(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7)) + mark_seed) * 43758.5453);
}

float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 offset = fract(point);
	offset = offset * offset * (3.0 - 2.0 * offset);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), offset.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0, 1.0)), offset.x), offset.y);
}

float fbm(vec2 point) {
	float sum = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < 3; octave++) {
		sum += value_noise(point) * amplitude;
		point *= 2.11;
		amplitude *= 0.5;
	}
	return sum;
}

void fragment() {
	// Across the stripe, zero in the middle. The quad's U axis runs across the line.
	float across = abs(UV.x - 0.5) * 2.0;
	float stripe = 1.0 - smoothstep(line_width, line_width + 0.18, across);

	// Along the line: long scrubbed sections, then fine pitting on what is left.
	float along = UV.y;
	float scrubbed = 1.0 - patchiness * smoothstep(0.4, 0.68, fbm(vec2(along * 5.0, 0.5)));
	float pitting = 1.0 - wear * smoothstep(0.38, 0.74, fbm(vec2(along * 60.0, across * 8.0)));
	// The edge of old line paint is chipped, never straight.
	float chipped_edge = 1.0 - smoothstep(line_width - 0.1, line_width + 0.1,
		across + (fbm(vec2(along * 40.0, 3.0)) - 0.5) * 0.22);

	float coverage = stripe * scrubbed * pitting * max(chipped_edge, 0.35);
	if (coverage < 0.02) {
		discard;
	}
	ALBEDO = paint_color * mix(1.0, 0.55, dirt * fbm(vec2(along * 12.0, across * 4.0)));
	ALPHA = coverage * opacity;
	ROUGHNESS = 0.78;
	METALLIC = 0.0;
	SPECULAR = 0.4;
}
