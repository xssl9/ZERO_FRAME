shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, blend_mix, depth_draw_opaque;

// Micro-detail overlay: procedural dirt, dust, edge wear, moisture and surface aging.
// Applied as a second material pass on top of the base PBR material, or blended in
// through the dev_grid.gdshader variant system.
//
// This is NOT a replacement for authored textures. It is the layer that breaks up
// tiling repetition and adds the micro-scale variation that makes a surface read as
// a real physical object rather than a rendered material.
//
// World-space triplanar so the same material works on floors, walls and ceilings
// without UV work, and the dirt follows the building rather than the mesh UVs.

#include "res://shaders/muzzle_flash_light.gdshaderinc"

group_uniforms Surface;
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// ARM: ambient occlusion (R), roughness (G), metallic (B) — Poly Haven packing.
uniform sampler2D arm_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float texture_scale : hint_range(0.05, 8.0, 0.01) = 0.5;
uniform float normal_strength : hint_range(0.0, 3.0, 0.05) = 1.0;
uniform float base_roughness : hint_range(0.0, 1.0, 0.01) = 0.72;
uniform float base_metallic : hint_range(0.0, 1.0, 0.01) = 0.0;

group_uniforms MicroDetail;
// Dust: fine particles that settle on horizontal surfaces and in crevices.
// Increases roughness and slightly lightens albedo.
uniform float dust_amount : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float dust_scale : hint_range(0.5, 20.0, 0.1) = 6.0;
uniform vec3 dust_color : source_color = vec3(0.72, 0.70, 0.65);

// Dirt: heavier contamination, darker and rougher than dust.
uniform float dirt_amount : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform float dirt_scale : hint_range(0.5, 20.0, 0.1) = 3.5;
uniform vec3 dirt_color : source_color = vec3(0.28, 0.24, 0.19);

// Edge wear: surfaces are smoother and slightly more metallic at edges where
// paint and coating have been worn away by contact.
uniform float edge_wear_amount : hint_range(0.0, 1.0, 0.01) = 0.0;
// How far from a geometric edge the wear extends (in world units).
uniform float edge_wear_radius : hint_range(0.01, 0.5, 0.01) = 0.08;

// Moisture: subtle darkening and roughness reduction from ambient humidity.
// Not the same as the wetness system — this is the baseline damp of a concrete
// floor that has never fully dried out.
uniform float moisture_amount : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float moisture_scale : hint_range(0.5, 20.0, 0.1) = 4.0;

// Stains: water marks, oil spots, chemical spills.
uniform float stain_amount : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float stain_scale : hint_range(0.5, 40.0, 0.1) = 8.0;
uniform vec3 stain_color : source_color = vec3(0.18, 0.16, 0.14);

// Roughness variation: micro-scale surface irregularity that prevents the
// specular highlight from being perfectly uniform across a surface.
uniform float roughness_variation : hint_range(0.0, 0.3, 0.005) = 0.08;
uniform float roughness_variation_scale : hint_range(0.5, 40.0, 0.1) = 12.0;

// Wetness from the WetnessManager (set at runtime).
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float wet_roughness_floor : hint_range(0.1, 0.8) = 0.32;

varying vec3 world_position;
varying vec3 world_normal;

// --- Noise functions ---

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise_3d(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(cell), hash13(cell + vec3(1,0,0)), f.x),
			mix(hash13(cell + vec3(0,1,0)), hash13(cell + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash13(cell + vec3(0,0,1)), hash13(cell + vec3(1,0,1)), f.x),
			mix(hash13(cell + vec3(0,1,1)), hash13(cell + vec3(1,1,1)), f.x), f.y),
		f.z);
}

float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += value_noise_3d(p) * a;
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

// --- Triplanar helpers ---

vec3 triplanar_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / max(w.x + w.y + w.z, 0.0001);
}

vec3 triplanar_sample(sampler2D map, vec3 pos, vec3 w) {
	return texture(map, pos.zy).rgb * w.x
		+ texture(map, pos.xz).rgb * w.y
		+ texture(map, pos.xy).rgb * w.z;
}

vec3 triplanar_normal(sampler2D map, vec3 pos, vec3 w, vec3 n) {
	vec3 tx = texture(map, pos.zy).rgb * 2.0 - 1.0;
	vec3 ty = texture(map, pos.xz).rgb * 2.0 - 1.0;
	vec3 tz = texture(map, pos.xy).rgb * 2.0 - 1.0;
	vec3 wx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	vec3 wy = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	vec3 wz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	vec3 blended = normalize(wx.zyx * w.x + wy.xzy * w.y + wz.xyz * w.z);
	if (dot(blended, n) < 0.42) {
		blended = normalize(blended + n * 1.5);
	}
	return blended;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 w = triplanar_weights(n);
	vec3 tp = world_position * texture_scale;

	// --- Base PBR ---
	vec3 albedo = triplanar_sample(albedo_texture, tp, w);
	vec3 arm = triplanar_sample(arm_texture, tp, w);
	vec3 mapped_normal = triplanar_normal(normal_texture, tp, w, n);
	float roughness = mix(base_roughness, arm.g, 1.0);
	float metallic = mix(base_metallic, arm.b, 1.0);
	float ao = arm.r;

	// --- Micro roughness variation ---
	// Filter out sub-pixel variation to prevent specular shimmer.
	float footprint = length(fwidth(world_position * roughness_variation_scale));
	float micro_noise = (value_noise_3d(world_position * roughness_variation_scale) - 0.5)
		* (1.0 - smoothstep(0.3, 1.2, footprint));
	roughness = clamp(roughness + micro_noise * roughness_variation, 0.08, 0.98);

	// --- Dust ---
	// Dust settles on upward-facing surfaces and in crevices (low AO areas).
	if (dust_amount > 0.001) {
		float dust_noise = fbm3(world_position * dust_scale * 0.5);
		// Upward-facing bias: dust doesn't stick to vertical walls as much.
		float facing_up = smoothstep(0.2, 0.85, n.y);
		float dust_mask = dust_noise * facing_up * dust_amount;
		albedo = mix(albedo, dust_color, dust_mask * 0.55);
		roughness = mix(roughness, min(roughness + 0.12, 0.98), dust_mask * 0.7);
	}

	// --- Dirt ---
	// Heavier contamination, not facing-dependent (tracked in, splashed up).
	if (dirt_amount > 0.001) {
		float dirt_noise = fbm3(world_position * dirt_scale * 0.4 + vec3(17.3, 5.1, 9.7));
		float dirt_mask = smoothstep(0.42, 0.72, dirt_noise) * dirt_amount;
		albedo = mix(albedo, dirt_color, dirt_mask * 0.6);
		roughness = mix(roughness, min(roughness + 0.18, 0.98), dirt_mask * 0.8);
	}

	// --- Stains ---
	if (stain_amount > 0.001) {
		float stain_noise = fbm3(world_position * stain_scale * 0.25 + vec3(31.7, 12.4, 7.9));
		float stain_mask = smoothstep(0.55, 0.78, stain_noise) * stain_amount;
		// Stains are darker and slightly smoother (liquid residue).
		albedo = mix(albedo, stain_color, stain_mask * 0.7);
		roughness = mix(roughness, max(roughness - 0.08, 0.12), stain_mask * 0.5);
	}

	// --- Moisture ---
	if (moisture_amount > 0.001) {
		float moisture_noise = fbm3(world_position * moisture_scale * 0.3 + vec3(5.5, 22.1, 14.8));
		float moisture_mask = moisture_noise * moisture_amount;
		// Moisture darkens albedo and reduces roughness.
		albedo *= mix(1.0, 0.88, moisture_mask);
		roughness = mix(roughness, max(roughness - 0.15, wet_roughness_floor), moisture_mask * 0.6);
	}

	// --- Wetness (from WetnessManager) ---
	float wet = clamp(wetness, 0.0, 1.0) * mix(0.65, 1.0, max(n.y, 0.0));
	// Wet surfaces: darker albedo, lower roughness, stronger specular.
	albedo *= mix(1.0, 0.82, wet);
	// Normal maps flatten when wet (water film smooths micro-geometry).
	float bump = normal_strength * (1.0 - 0.45 * wet);
	vec3 shading_normal = normalize(mix(n, mapped_normal, clamp(bump, 0.0, 1.0)));
	roughness = mix(roughness, max(wet_roughness_floor, roughness * 0.68), wet);

	// Normal variance: broadens BRDF when details can't be resolved at distance.
	float variance = dot(dFdx(shading_normal), dFdx(shading_normal))
		+ dot(dFdy(shading_normal), dFdy(shading_normal));
	roughness = clamp(sqrt(roughness * roughness + min(variance * 0.18, 0.10)), 0.08, 1.0);

	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	AO = ao;
	AO_LIGHT_AFFECT = 0.65;
	SPECULAR = 0.5;
	NORMAL = normalize((VIEW_MATRIX * vec4(shading_normal, 0.0)).xyz);
	EMISSION = vec3(0.0);
}
