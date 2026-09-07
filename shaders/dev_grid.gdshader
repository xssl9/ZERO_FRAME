shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/muzzle_flash_light.gdshaderinc"
#include "res://shaders/rain_exposure.gdshaderinc"

// Classic greybox dev surface: checkerboard cells plus a thin grid line every
// cell and a thicker one every `major_cells`. World-space and triplanar, so one
// material reads correctly on the floor and on every wall without UV work.

uniform vec3 cell_color_a : source_color = vec3(0.58, 0.59, 0.60);
uniform vec3 cell_color_b : source_color = vec3(0.44, 0.45, 0.47);
uniform vec3 minor_line_color : source_color = vec3(0.24, 0.25, 0.27);
uniform vec3 major_line_color : source_color = vec3(0.10, 0.11, 0.13);
// One metre per cell keeps the grid usable as an in-world ruler.
uniform float cell_size : hint_range(0.25, 8.0, 0.25) = 1.0;
uniform float major_cells : hint_range(2.0, 16.0, 1.0) = 8.0;
uniform float minor_line_width : hint_range(0.002, 0.1, 0.002) = 0.016;
uniform float major_line_width : hint_range(0.004, 0.2, 0.002) = 0.04;
uniform float surface_roughness : hint_range(0.0, 1.0, 0.01) = 0.72;
// Rain. Wet concrete is both darker and far smoother than dry concrete, so one value
// drives both, and the screen-space reflections then have something to reflect in.
uniform float wetness : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float roughness_variation : hint_range(0.0, 0.2) = 0.08;
uniform float wet_roughness_floor : hint_range(0.15, 0.8) = 0.34;
uniform int debug_view = 0;
uniform vec3 material_id : source_color = vec3(0.5);

group_uniforms PhotoTextures;
// Real PBR maps on top of the greybox. World-space triplanar, so a 48 m box floor tiles
// properly without UVs and the same material works on walls; `texture_blend` at 0.0 leaves
// the procedural grid exactly as it was.
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
// Poly Haven ARM packing: ambient occlusion in R, roughness in G, metallic in B.
uniform sampler2D arm_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float texture_blend : hint_range(0.0, 1.0, 0.01) = 0.0;
// Texture repeats per metre. 0.5 puts one 2 m tile sheet every two metres.
uniform float texture_scale : hint_range(0.05, 4.0, 0.01) = 0.5;
uniform float normal_strength : hint_range(0.0, 3.0, 0.05) = 1.0;

group_uniforms PhotoTextures.Variation;
// A second material blended in over large patches. One tiling sheet across a 26 m storeroom
// reads as one surface no matter how good the sheet is, and a building does not: the pour was
// patched, the plaster came off over brick, someone tiled one room and not the next. The mask is
// two octaves of world-space value noise, so the patches follow the building and not the UVs,
// and it costs nothing on a material that leaves `variant_amount` at zero.
uniform sampler2D variant_albedo_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D variant_normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D variant_arm_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float variant_amount : hint_range(0.0, 1.0, 0.01) = 0.0;
// Metres across for a patch. Smaller than a room and larger than a tile sheet.
uniform float variant_patch_size : hint_range(0.5, 40.0, 0.5) = 9.0;
uniform float variant_edge : hint_range(0.01, 0.5, 0.01) = 0.14;
uniform float variant_scale : hint_range(0.05, 4.0, 0.01) = 0.5;

group_uniforms PhotoTextures.Unique;
// Grime that belongs to this exact corner of this exact building. A tiling sheet cannot have it:
// no matter how good the sheet is, it repeats, so the dark line where a wall meets a floor and the
// dirt gathered behind a pillar have to come from somewhere unique. This is ambient occlusion
// baked per mesh in Blender against the level's own geometry, sampled through the mesh's own UV
// rather than the triplanar projection, and multiplied on top of everything else.
uniform sampler2D unique_ao_texture : hint_default_white, filter_linear_mipmap;
uniform float unique_ao_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
// How much of it also darkens albedo rather than only the AO term. Dirt is not just shadow.
uniform float unique_ao_albedo : hint_range(0.0, 1.0, 0.01) = 0.45;

group_uniforms MicroDetail;
// Procedural dust layer: fine particles on upward-facing surfaces.
uniform float dust_amount : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform vec3 dust_color : source_color = vec3(0.70, 0.68, 0.63);
// Procedural stain layer: water marks, oil, chemical residue.
uniform float stain_amount : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform vec3 stain_color : source_color = vec3(0.22, 0.20, 0.17);

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

// Antialiased band around every integer boundary of `coordinate`.
float boundary_mask(vec2 coordinate, float width) {
	vec2 distance_to_edge = 0.5 - abs(fract(coordinate) - 0.5);
	vec2 filter_width = max(fwidth(coordinate), vec2(0.00001));
	vec2 mask = 1.0 - smoothstep(vec2(0.0), filter_width * 1.5, distance_to_edge - width);
	return max(mask.x, mask.y);
}

// Triplanar: blend the three axis projections by how much the surface faces each of them.
// The exponent decides how tight the seam is; 4.0 hides it on box geometry.
vec3 triplanar_weights(vec3 surface_normal) {
	vec3 weights = pow(abs(surface_normal), vec3(4.0));
	return weights / max(weights.x + weights.y + weights.z, 0.0001);
}

vec3 triplanar_sample(sampler2D map, vec3 position, vec3 weights) {
	return texture(map, position.zy).rgb * weights.x
		+ texture(map, position.xz).rgb * weights.y
		+ texture(map, position.xy).rgb * weights.z;
}

// Whiteout blend of three tangent-space normal samples straight into world space, which
// sidesteps the mesh tangents entirely: they do not match world-projected UVs.
//
// The geometric normal is summed into each sample before the blend, which is what keeps the
// result on the correct side of the surface. Without that term a vertical face ends up with
// normals pointing into the wall, N dot L goes negative for every light and the face renders
// black up close while distant mip levels flatten out and light correctly.
vec3 triplanar_normal(sampler2D map, vec3 position, vec3 weights, vec3 surface_normal) {
	vec3 tangent_x = texture(map, position.zy).rgb * 2.0 - 1.0;
	vec3 tangent_y = texture(map, position.xz).rgb * 2.0 - 1.0;
	vec3 tangent_z = texture(map, position.xy).rgb * 2.0 - 1.0;
	vec3 world_x = vec3(tangent_x.xy + surface_normal.zy, abs(tangent_x.z) * surface_normal.x);
	vec3 world_y = vec3(tangent_y.xy + surface_normal.xz, abs(tangent_y.z) * surface_normal.y);
	vec3 world_z = vec3(tangent_z.xy + surface_normal.xy, abs(tangent_z.z) * surface_normal.z);
	vec3 blended = normalize(world_x.zyx * weights.x + world_y.xzy * weights.y + world_z.xyz * weights.z);
	// Safety rail: never let a map tip the shading normal more than ~65 degrees off the
	// geometry, so no texture can ever black out a surface again.
	if (dot(blended, surface_normal) < 0.42) {
		blended = normalize(blended + surface_normal * 1.5);
	}
	return blended;
}

// Value noise in world space, used only for the large patch mask, so smooth beats cheap here:
// a hash straight off the world position would band the patches into visible cubes.
float hash13(vec3 point) {
	point = fract(point * 0.1031);
	point += dot(point, point.yzx + 33.33);
	return fract((point.x + point.y) * point.z);
}

float value_noise(vec3 point) {
	vec3 cell = floor(point);
	vec3 offset = fract(point);
	offset = offset * offset * (3.0 - 2.0 * offset);
	return mix(
		mix(mix(hash13(cell), hash13(cell + vec3(1.0, 0.0, 0.0)), offset.x),
			mix(hash13(cell + vec3(0.0, 1.0, 0.0)), hash13(cell + vec3(1.0, 1.0, 0.0)), offset.x), offset.y),
		mix(mix(hash13(cell + vec3(0.0, 0.0, 1.0)), hash13(cell + vec3(1.0, 0.0, 1.0)), offset.x),
			mix(hash13(cell + vec3(0.0, 1.0, 1.0)), hash13(cell + vec3(1.0, 1.0, 1.0)), offset.x), offset.y),
		offset.z);
}

void fragment() {
	// Project onto the plane the surface actually faces. Using only XZ would
	// smear the pattern into vertical stripes on every wall.
	vec3 axis_weight = abs(world_normal);
	vec2 plane_position;
	if (axis_weight.y >= axis_weight.x && axis_weight.y >= axis_weight.z) {
		plane_position = world_position.xz;
	} else if (axis_weight.x >= axis_weight.z) {
		plane_position = world_position.zy;
	} else {
		plane_position = world_position.xy;
	}

	vec2 cell_uv = plane_position / cell_size;
	vec2 cell_index = floor(cell_uv);
	float checker = mod(cell_index.x + cell_index.y, 2.0);
	vec3 surface = mix(cell_color_a, cell_color_b, checker);

	// Fade the whole pattern toward its average as the cells approach pixel
	// size. Without this the checker aliases into moire at grazing angles.
	float texel_span = max(fwidth(cell_uv).x, fwidth(cell_uv).y);
	float detail = 1.0 - smoothstep(0.25, 0.9, texel_span);
	surface = mix((cell_color_a + cell_color_b) * 0.5, surface, detail);

	float minor = boundary_mask(cell_uv, minor_line_width / cell_size);
	float major = boundary_mask(cell_uv / major_cells, major_line_width / (cell_size * major_cells));
	surface = mix(surface, minor_line_color, minor * detail);
	surface = mix(surface, major_line_color, major * detail);

	ALBEDO = surface;
	ROUGHNESS = surface_roughness;
	METALLIC = 0.0;
	AO = 1.0;
	SPECULAR = 0.5;
	float moisture = clamp(wetness, 0.0, 1.0) * mix(0.65, 1.0, max(world_normal.y, 0.0))
		* rain_exposure_at(world_position) * smoothstep(-0.3, 0.0, world_normal.y);
	vec3 shading_normal = normalize(world_normal);

	if (texture_blend > 0.0) {
		vec3 triplanar_position = world_position * texture_scale;
		vec3 weights = triplanar_weights(shading_normal);
		vec3 photo_albedo = triplanar_sample(albedo_texture, triplanar_position, weights);
		vec3 arm = triplanar_sample(arm_texture, triplanar_position, weights);
		vec3 mapped = triplanar_normal(normal_texture, triplanar_position, weights, shading_normal);
		if (variant_amount > 0.0) {
			float patch = mix(value_noise(world_position / variant_patch_size),
				value_noise(world_position / (variant_patch_size * 0.42)), 0.35);
			float variant = smoothstep(0.5 - variant_edge, 0.5 + variant_edge, patch) * variant_amount;
			if (variant > 0.001) {
				vec3 variant_position = world_position * variant_scale;
				photo_albedo = mix(photo_albedo,
					triplanar_sample(variant_albedo_texture, variant_position, weights), variant);
				arm = mix(arm, triplanar_sample(variant_arm_texture, variant_position, weights), variant);
				mapped = normalize(mix(mapped,
					triplanar_normal(variant_normal_texture, variant_position, weights, shading_normal),
					variant));
			}
		}
		ALBEDO = mix(ALBEDO, photo_albedo, texture_blend);
		ROUGHNESS = mix(ROUGHNESS, arm.g, texture_blend);
		METALLIC = mix(METALLIC, arm.b, texture_blend);
		AO = mix(1.0, arm.r, texture_blend);
		AO_LIGHT_AFFECT = 0.65;
		float bump = normal_strength * texture_blend * (1.0 - 0.4 * moisture);
		shading_normal = normalize(mix(shading_normal, mapped, clamp(bump, 0.0, 1.0)));
		// World space to view space: NORMAL is expected in view space in fragment().
		NORMAL = normalize((VIEW_MATRIX * vec4(shading_normal, 0.0)).xyz);
	}

	// Filter micro variation out before it becomes sub-pixel specular shimmer.
	float footprint = length(fwidth(world_position * 24.0));
	float micro = (value_noise(world_position * 24.0) - 0.5) * (1.0 - smoothstep(0.3, 1.2, footprint));
	float stains_noise = value_noise(world_position * 0.7);
	moisture *= mix(0.75, 1.0, stains_noise);
	ALBEDO *= mix(1.0, 0.83, moisture) * (1.0 - roughness_variation * 0.3 * stains_noise);
	float dry_roughness = clamp(ROUGHNESS + micro * roughness_variation, 0.12, 0.98);
	ROUGHNESS = mix(dry_roughness, max(wet_roughness_floor, dry_roughness * 0.68), moisture);
	// Normal variance broadens the BRDF when details can no longer be resolved.
	float variance = dot(dFdx(shading_normal), dFdx(shading_normal)) + dot(dFdy(shading_normal), dFdy(shading_normal));
	ROUGHNESS = clamp(sqrt(ROUGHNESS * ROUGHNESS + min(variance * 0.18, 0.10)), 0.12, 1.0);

	// --- Procedural micro-detail layers ---
	// Dust: fine particles on upward-facing surfaces. Increases roughness, lightens albedo.
	if (dust_amount > 0.001) {
		float dust_noise = value_noise(world_position * 5.5);
		float facing_up = smoothstep(0.2, 0.85, world_normal.y);
		float dust_mask = dust_noise * facing_up * dust_amount * (1.0 - moisture);
		ALBEDO = mix(ALBEDO, dust_color, dust_mask * 0.5);
		ROUGHNESS = mix(ROUGHNESS, min(ROUGHNESS + 0.14, 0.98), dust_mask * 0.65);
	}

	// Stains: water marks, oil, chemical residue. Darker and slightly smoother.
	if (stain_amount > 0.001) {
		float stain_noise = value_noise(world_position * 0.28 + vec3(31.7, 12.4, 7.9));
		float stain_mask = smoothstep(0.52, 0.76, stain_noise) * stain_amount;
		ALBEDO = mix(ALBEDO, stain_color, stain_mask * 0.65);
		ROUGHNESS = mix(ROUGHNESS, max(ROUGHNESS - 0.06, 0.12), stain_mask * 0.4);
	}

	// The existing real OmniLight now owns flash lighting. Adding the old unoccluded
	// emission here doubled the diffuse energy and illuminated through walls.
	EMISSION = vec3(0.0);

	// Baked occlusion last, so nothing above can brighten a corner back up.
	if (unique_ao_strength > 0.0) {
		float baked = texture(unique_ao_texture, UV).r;
		float occlusion = mix(1.0, baked, unique_ao_strength);
		AO = min(AO, occlusion);
		AO_LIGHT_AFFECT = 0.65;
		ALBEDO *= mix(1.0, occlusion, unique_ao_albedo);
	}
	if (debug_view > 0) {
		vec3 debug_color = vec3(ROUGHNESS);
		if (debug_view == 2) { debug_color = vec3(METALLIC); }
		if (debug_view == 3) { debug_color = shading_normal * 0.5 + 0.5; }
		if (debug_view == 4) { debug_color = vec3(AO); }
		if (debug_view == 5) { debug_color = vec3(moisture); }
		if (debug_view == 6) { debug_color = material_id; }
		// Debug mode 7: dust mask visualization
		if (debug_view == 7) {
			float dust_noise = value_noise(world_position * 5.5);
			float facing_up = smoothstep(0.2, 0.85, world_normal.y);
			debug_color = vec3(dust_noise * facing_up * dust_amount);
		}
		ALBEDO = vec3(0.0);
		EMISSION = debug_color;
	}
}
