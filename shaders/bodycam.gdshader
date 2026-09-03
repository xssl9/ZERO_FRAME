shader_type canvas_item;

// Bodycam lens and sensor. Everything here is what a cheap wide-angle body camera does to
// an image on its way to an h.264 file: barrel distortion, lateral colour, a soft vignette,
// CMOS grain that lives in the shadows, a slightly desaturated cool-shadow grade and an
// auto-exposure that never quite settles.
//
// The HUD is deliberately NOT under this pass: it sits on a CanvasLayer above, the way a
// real camera burns its stamp in after the optics.

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float alpha : hint_range(0.0, 1.0, 0.01) = 1.0;
// Action-cam barrel distortion. Two radial terms so the curvature is smooth rather than a
// pure parabola, normalised by its value at the top and bottom edge of the frame: those edges
// then map to themselves, the middle of the frame is very slightly wider than the render, and
// the corners fall outside it. That last part is deliberate - the lens port below is opaque out
// there anyway, and normalising on the corner instead is what used to magnify the centre by
// nearly two and blow the weapon up to fill the screen every time the strength was raised.
uniform float fisheye_strength : hint_range(0.0, 0.6, 0.005) = 0.10;
uniform float fisheye_falloff : hint_range(0.0, 1.0, 0.01) = 0.2;
// Lateral chromatic aberration, zero in the middle and growing towards the corners. Squared
// falloff: a cheap lens is clean across the middle and fringes hard only at the very edge.
uniform float channel_offset : hint_range(0.0, 0.02, 0.0005) = 0.0032;
// Veiling glare. A moulded plastic lens in front of a small sensor scatters bright light across
// the whole frame instead of resolving it, so anything hot bleeds a hazy halo and the highlights
// wash out. Taken from a mip of the screen, which is why the sampler asks for mipmaps. The
// threshold sits above the tonemapper's white point on purpose: a daylit sky lands just under 1.0
// after AgX, and anything lower than this turned an open courtyard into milk.
uniform float glare_strength : hint_range(0.0, 1.0, 0.01) = 0.10;
uniform float glare_threshold : hint_range(0.0, 2.0, 0.01) = 1.02;
uniform float grain_strength : hint_range(0.0, 2.0, 0.01) = 0.5;
// Sensor noise lives in the dark: bright pixels have plenty of photons, shadows do not.
uniform float grain_shadow_bias : hint_range(0.0, 4.0, 0.05) = 2.2;
uniform float vignette_start : hint_range(0.0, 1.0, 0.01) = 0.42;
uniform float vignette_end : hint_range(0.0, 1.4, 0.01) = 1.08;
uniform float vignette_darkness : hint_range(0.0, 1.0, 0.01) = 0.22;
// The lens port itself: the optic does not cover the sensor corners, so the image is a circle
// inscribed in the frame height and the corners are black. Measured in half-frame heights, so
// 1.0 is the top and bottom edge and a 16:9 corner sits at about 1.94.
uniform float lens_circle_start : hint_range(0.0, 2.0, 0.01) = 1.14;
uniform float lens_circle_end : hint_range(0.0, 2.0, 0.01) = 1.74;
uniform float lens_circle_darkness : hint_range(0.0, 1.0, 0.01) = 0.94;
uniform float saturation : hint_range(0.0, 2.0, 0.01) = 0.58;
uniform float black_lift : hint_range(0.0, 0.2, 0.001) = 0.032;
uniform float contrast : hint_range(0.5, 2.0, 0.01) = 1.02;
uniform vec3 shadow_tint : source_color = vec3(0.86, 0.92, 1.0);
uniform vec3 highlight_tint : source_color = vec3(1.0, 0.98, 0.94);
// Auto-exposure hunting: a real bodycam pumps a little as it re-meters the scene.
uniform float exposure_wobble : hint_range(0.0, 0.2, 0.001) = 0.018;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 19.19);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv * 2.0 - 1.0;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	centered.x *= aspect;
	float radius_squared = dot(centered, centered);
	// One, because `centered.y` is already normalised to the half-height.
	float edge_squared = 1.0;
	float distortion = 1.0 + fisheye_strength * radius_squared
		+ fisheye_strength * fisheye_falloff * radius_squared * radius_squared;
	float edge_distortion = 1.0 + fisheye_strength * edge_squared
		+ fisheye_strength * fisheye_falloff * edge_squared * edge_squared;
	vec2 lens = centered * (distortion / edge_distortion);
	lens.x /= aspect;
	uv = lens * 0.5 + 0.5;
	uv = clamp(uv, SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE);

	vec2 from_centre = SCREEN_UV - 0.5;
	float distance_to_centre = length(from_centre);
	vec2 direction = from_centre / max(distance_to_centre, 0.0001);

	// Radial chromatic aberration: the green channel stays put, red and blue split.
	float aberration = channel_offset * distance_to_centre * distance_to_centre * 2.8;
	vec3 color;
	color.r = texture(SCREEN_TEXTURE, uv - direction * aberration).r;
	color.g = texture(SCREEN_TEXTURE, uv).g;
	color.b = texture(SCREEN_TEXTURE, uv + direction * aberration).b;

	// Veiling glare before the grade, so the wash-out is part of the image the sensor sees
	// rather than something painted on top of a finished frame.
	vec3 scattered = textureLod(SCREEN_TEXTURE, uv, 4.0).rgb;
	color += max(scattered - glare_threshold, vec3(0.0)) * glare_strength;

	// Grade: lift the blacks, pull a little saturation out, cool the shadows and warm the
	// highlights. This is the cheap-sensor look, not a colour-managed camera.
	float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(vec3(luminance), color, saturation);
	color = mix(color * shadow_tint, color * highlight_tint, smoothstep(0.08, 0.7, luminance));
	color = (color - 0.5) * contrast + 0.5 + black_lift;
	color *= 1.0 + sin(TIME * 0.7) * sin(TIME * 2.3 + 1.7) * exposure_wobble;

	// Sensor grain, per pixel and per frame, weighted towards the shadows.
	float grain = hash12(SCREEN_UV * vec2(1920.0, 1080.0) + fract(TIME) * 371.0) - 0.5;
	float shadow_weight = pow(1.0 - clamp(luminance, 0.0, 1.0), grain_shadow_bias);
	color += grain * grain_strength * 0.09 * (0.25 + shadow_weight);

	// Soft vignette last, so the grade cannot brighten the corners back up, then the lens port
	// on top of it: that one is nearly opaque, because outside the optic there is no image.
	float vignette = smoothstep(vignette_start, vignette_end, distance_to_centre);
	color *= mix(1.0, 1.0 - vignette_darkness, vignette);
	float lens_radius = length(vec2(from_centre.x * aspect, from_centre.y)) * 2.0;
	float port = smoothstep(lens_circle_start, lens_circle_end, lens_radius);
	color *= mix(1.0, 1.0 - lens_circle_darkness, port);

	COLOR = vec4(max(color, vec3(0.0)), alpha);
}
