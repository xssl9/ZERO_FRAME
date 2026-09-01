shader_type canvas_item;

// Wide bodycam optics inspired by the supplied gameplay reference. Distortion
// and edge softness are deliberate, but there is no hard circular crop.

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float alpha : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float lens_distortion : hint_range(0.0, 0.5, 0.005) = 0.07;
// Chromatic aberration grows toward the edges; tiny by default.
uniform float channel_offset : hint_range(0.0, 0.02, 0.0005) = 0.0008;
uniform float noise_strength : hint_range(0.0, 4.0, 0.05) = 0.08;
// Soft corner darkening (not a hard crop).
uniform float vignette_start : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform float vignette_end : hint_range(0.0, 1.4, 0.01) = 1.02;
uniform float vignette_darkness : hint_range(0.0, 1.0, 0.01) = 0.16;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv * 2.0 - 1.0;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	centered.x *= aspect;
	float radius_squared = dot(centered, centered);
	// Compress the outer image like a wide bodycam lens. Unlike an outward UV
	// warp this never pins samples to the screen border, so no smeared stripes.
	vec2 lens = centered / (1.0 + lens_distortion * radius_squared);
	lens.x /= aspect;
	uv = lens * 0.5 + 0.5;
	uv = clamp(uv, SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE);
	centered = SCREEN_UV - 0.5;
	float d = length(centered);
	vec2 dir = centered / max(d, 0.0001);

	// Radial chromatic aberration, zero at centre, small at edges.
	float ca = channel_offset * d;
	vec4 col;
	col.r = texture(SCREEN_TEXTURE, uv - dir * ca).r;
	col.g = texture(SCREEN_TEXTURE, uv).g;
	col.b = texture(SCREEN_TEXTURE, uv + dir * ca).b;
	col.a = 1.0;

	// Faint animated sensor grain.
	float x = (UV.x + 4.0) * (UV.y + 4.0) * (TIME * 10.0);
	col.rgb += (mod((mod(x, 13.0)) * (mod(x, 123.0)), 0.01) - 0.005) * noise_strength;

	// Soft vignette darkening toward the corners.
	float vig = smoothstep(vignette_start, vignette_end, d);
	col.rgb *= mix(1.0, 1.0 - vignette_darkness, vig);

	COLOR = vec4(col.rgb, alpha);
}
