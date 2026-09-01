shader_type spatial;
// Premultiplied alpha instead of plain additive blending: the viewmodel is drawn in a
// SubViewport with transparent_bg, and an additive pass leaves the framebuffer alpha at
// zero, so the flash would be invisible everywhere it did not overlap the gun itself.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// 0.0 is the instant the round leaves the barrel, 1.0 is a dead flash.
uniform float progress : hint_range(0.0, 1.0) = 1.0;
// Rotates the spike pattern so consecutive rounds never draw the same flame.
uniform float seed = 0.0;
uniform float brightness : hint_range(0.0, 60.0) = 16.0;
uniform float spike_count : hint_range(1.0, 16.0) = 7.0;
uniform vec3 core_color : source_color = vec3(1.0, 0.97, 0.86);
uniform vec3 edge_color : source_color = vec3(1.0, 0.42, 0.07);

void vertex() {
	// Burning gas is already at full width the instant it clears the muzzle, so it
	// only puffs outwards slightly while it dies instead of growing from nothing.
	VERTEX.xy *= 0.86 + 0.34 * progress;
}

void fragment() {
	vec2 offset = UV * 2.0 - 1.0;
	float radius = length(offset);
	float angle = atan(offset.y, offset.x);
	// Ragged star rather than a soft blob: powder burn has hard tongues of flame.
	float spikes = 0.58 + 0.42 * abs(sin(angle * spike_count + seed));
	float shape = 1.0 - clamp(radius / max(spikes, 0.001), 0.0, 1.0);
	float intensity = pow(shape, 1.6) * pow(1.0 - progress, 0.8);
	vec3 color = mix(edge_color, core_color, pow(shape, 2.0));
	// Premultiplied: ALBEDO already carries the coverage, so it is not multiplied by
	// ALPHA again downstream. ALPHA only exists so the flash composites over the world.
	ALBEDO = color * intensity * brightness;
	ALPHA = clamp(intensity * 1.4, 0.0, 1.0);
}
