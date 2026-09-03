shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley;

// Spray-paint tag, drawn rather than photographed. A photo of real graffiti is somebody's
// artwork under somebody's licence, and one image repeated on twenty pillars reads as wallpaper;
// this builds a different tag per instance from a seed, so no two pillars carry the same mark.
//
// Meant for a quad laid flat on a wall with a centimetre of standoff. Not a Decal node: those
// take textures, and the whole point here is that there is no texture.

uniform float mark_seed : hint_range(0.0, 64.0, 0.01) = 0.0;
uniform vec3 primary_color : source_color = vec3(0.86, 0.13, 0.42);
uniform vec3 secondary_color : source_color = vec3(0.16, 0.72, 0.92);
uniform vec3 outline_color : source_color = vec3(0.04, 0.04, 0.05);
// How many strokes the tag is made of. Three or four reads as a word, one reads as a smear.
uniform float stroke_count : hint_range(1.0, 6.0, 1.0) = 4.0;
uniform float stroke_thickness : hint_range(0.01, 0.3, 0.005) = 0.075;
uniform float outline_width : hint_range(0.0, 0.1, 0.002) = 0.026;
// Overspray: the halo of dry mist around every line a rattle can leaves on a wall.
uniform float overspray : hint_range(0.0, 0.4, 0.01) = 0.13;
uniform float drip_amount : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float wear : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 0.92;

float hash11(float value) {
	return fract(sin(value * 127.1 + mark_seed * 13.7) * 43758.5453);
}

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
	for (int octave = 0; octave < 4; octave++) {
		sum += value_noise(point) * amplitude;
		point *= 2.03;
		amplitude *= 0.5;
	}
	return sum;
}

// Distance to a line segment, which is what a stroke of a tag actually is.
float segment_distance(vec2 point, vec2 from, vec2 to) {
	vec2 offset = point - from;
	vec2 span = to - from;
	float along = clamp(dot(offset, span) / max(dot(span, span), 0.0001), 0.0, 1.0);
	return length(offset - span * along);
}

// A tag is one continuous line that doubles back on itself, not a row of separate marks, so the
// strokes are a chain: each one starts where the last ended and turns by a seeded amount. Sine
// curves in parallel lanes, which is the obvious thing to write, come out as isolated lens
// shapes and read as stickers.
float tag_distance(vec2 uv) {
	float strokes = stroke_count;
	vec2 cursor = vec2(0.1, 0.5 + (hash11(1.7) - 0.5) * 0.4);
	float nearest = 1000.0;
	for (int index = 0; index < 6; index++) {
		if (float(index) >= strokes) {
			break;
		}
		float step_x = 0.8 / strokes;
		// Alternating vertical direction is what makes it zig-zag like handwriting rather
		// than drift in one direction.
		float direction = mod(float(index), 2.0) < 0.5 ? 1.0 : -1.0;
		vec2 next = cursor + vec2(
			step_x * (0.65 + hash11(float(index) * 3.1) * 0.7),
			direction * (0.2 + hash11(float(index) * 5.9) * 0.42));
		next.y = clamp(next.y, 0.12, 0.88);
		nearest = min(nearest, segment_distance(uv, cursor, next));
		// Every other stroke gets a short spur, the way a tag has crossbars and tails.
		if (hash11(float(index) * 11.3) > 0.45) {
			vec2 spur = next + vec2(
				(hash11(float(index) * 2.9) - 0.5) * 0.28,
				(hash11(float(index) * 8.1) - 0.5) * 0.5);
			spur.y = clamp(spur.y, 0.1, 0.9);
			nearest = min(nearest, segment_distance(uv, next, spur));
		}
		cursor = next;
	}
	return nearest;
}

void fragment() {
	vec2 uv = UV;
	// Warp the whole tag: a hand holding a can does not draw a clean parametric curve.
	uv += (vec2(fbm(uv * 3.7), fbm(uv * 3.7 + 19.0)) - 0.5) * 0.06;

	float distance_to_ink = tag_distance(uv);
	// The line itself, the darker outline sprayed under it, and the dry mist around both.
	float ink = 1.0 - smoothstep(stroke_thickness, stroke_thickness + 0.014, distance_to_ink);
	float edge = 1.0 - smoothstep(stroke_thickness + outline_width,
		stroke_thickness + outline_width + overspray, distance_to_ink);
	// Second colour follows the height of the stroke, the way a fill fades into a highlight.
	float which = smoothstep(0.35, 0.7, uv.y + (fbm(uv * 5.0) - 0.5) * 0.4);

	// Paint running down from the wet edge of a line, thinning as it goes.
	float drip_column = floor(uv.x * 26.0);
	float drip_seed = hash11(drip_column * 1.7);
	float drip_length = 0.06 + drip_seed * 0.32;
	// Only where there is ink above to run out of.
	float source = 1.0 - smoothstep(stroke_thickness, stroke_thickness + 0.05,
		tag_distance(vec2(uv.x, uv.y - drip_length * 0.35)));
	float in_drip = step(0.68, drip_seed) * drip_amount * source
		* (1.0 - smoothstep(0.0, drip_length, uv.y - 0.5))
		* (1.0 - smoothstep(0.2, 0.5, abs(fract(uv.x * 26.0) - 0.5)));
	ink = max(ink, in_drip * 0.9);

	// Dry wall, worn paint and a rectangular quad that must not show its own edges.
	float grain = fbm(uv * 26.0);
	float chipped = 1.0 - wear * smoothstep(0.42, 0.72, grain);
	float speckle = smoothstep(0.35, 0.75, grain);
	float border = smoothstep(0.0, 0.06, uv.x) * smoothstep(0.0, 0.06, 1.0 - uv.x)
		* smoothstep(0.0, 0.06, uv.y) * smoothstep(0.0, 0.06, 1.0 - uv.y);

	float coverage = clamp(ink * chipped + edge * speckle * 0.45, 0.0, 1.0) * border;
	if (coverage < 0.01) {
		discard;
	}
	vec3 paint = mix(primary_color, secondary_color, which);
	// The dark halo where the outline was sprayed over first.
	float outline_mix = clamp((edge - ink) * 1.6, 0.0, 1.0);
	ALBEDO = mix(paint, outline_color, outline_mix * 0.7);
	ALPHA = coverage * opacity;
	// Fresh aerosol on porous concrete is flat, and a mirror-smooth tag looks like a sticker.
	ROUGHNESS = mix(0.72, 0.92, wear);
	METALLIC = 0.0;
	SPECULAR = 0.35;
}
