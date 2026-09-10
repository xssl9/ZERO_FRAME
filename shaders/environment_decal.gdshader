shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

// Environmental decal: cracks, rust streaks, water stains, tire marks, moss, oil.
// Drawn on a thin quad or plane lying on/against a surface with a small standoff.
// The decal reads the underlying surface normal from the depth buffer and blends
// its own normal on top, so it conforms to the surface without UV work.
//
// Unlike Godot's built-in Decal node, this runs in the spatial pipeline and can
// carry a full PBR response including roughness variation and wetness.

uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
// ORM: occlusion (R), roughness (G), metallic (B).
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap_anisotropic;
// Alpha mask: controls where the decal is visible. Can be the same as albedo alpha.
uniform sampler2D mask_texture : hint_default_white, filter_linear_mipmap_anisotropic;

uniform float opacity : hint_range(0.0, 1.0, 0.01) = 0.85;
uniform float normal_strength : hint_range(0.0, 2.0, 0.05) = 0.8;
// Roughness offset applied on top of the texture value.
uniform float roughness_offset : hint_range(-0.5, 0.5, 0.01) = 0.0;
// Tint the decal albedo (e.g. rust = orange-brown, moss = green).
uniform vec3 color_tint : source_color = vec3(1.0);
// Edge fade: how far from the UV edge the decal fades out.
uniform float edge_fade : hint_range(0.0, 0.5, 0.01) = 0.08;
// Age: 0 = fresh, 1 = heavily weathered. Increases roughness and desaturates.
uniform float age : hint_range(0.0, 1.0, 0.01) = 0.5;
// Wetness from WetnessManager.
uniform float wetness : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = UV;

	// Edge fade: smooth falloff at UV boundaries so the decal doesn't have a hard edge.
	float edge_x = smoothstep(0.0, edge_fade, uv.x) * smoothstep(1.0, 1.0 - edge_fade, uv.x);
	float edge_y = smoothstep(0.0, edge_fade, uv.y) * smoothstep(1.0, 1.0 - edge_fade, uv.y);
	float edge_mask = edge_x * edge_y;

	vec4 albedo_sample = texture(albedo_texture, uv);
	float mask = texture(mask_texture, uv).r * albedo_sample.a * edge_mask * opacity;

	if (mask < 0.01) {
		discard;
	}

	vec3 orm = texture(orm_texture, uv).rgb;
	float roughness = clamp(orm.g + roughness_offset, 0.05, 1.0);
	float metallic = orm.b;
	float ao = orm.r;

	// Age: desaturate and roughen over time.
	vec3 albedo = albedo_sample.rgb * color_tint;
	float luma = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
	albedo = mix(albedo, vec3(luma), age * 0.35);
	roughness = mix(roughness, min(roughness + 0.22, 0.98), age * 0.5);

	// Wetness: darken and smooth the decal surface.
	albedo *= mix(1.0, 0.85, wetness * 0.6);
	roughness = mix(roughness, max(roughness * 0.65, 0.18), wetness * 0.5);

	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	AO = ao;
	AO_LIGHT_AFFECT = 0.5;
	SPECULAR = 0.5;
	ALPHA = mask;
	NORMAL_MAP = texture(normal_texture, uv).rgb;
	NORMAL_MAP_DEPTH = normal_strength * (1.0 - wetness * 0.4);
}
