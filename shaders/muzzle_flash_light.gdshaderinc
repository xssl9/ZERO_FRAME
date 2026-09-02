// Additive muzzle-flash response for surfaces, shared by dev_grid.gdshader and
// rain_puddles.gdshader via #include.
//
// This is deliberately NOT the Godot OmniLight the weapon also spawns. That light gives a
// round, even diffuse pool, which is all a point light can express; what wet ground does
// with a sudden bright source is different and is what this file draws:
//   - a warm diffuse burst that dies with the flash,
//   - a specular lobe whose half-vector is compressed vertically, so the highlight smears
//     along the ground towards the viewer the way a light does on wet asphalt,
//   - a broad Fresnel-weighted sheen, the water film scattering the burst sideways.
//
// The two vec4s are packed so a shot costs two set_shader_parameter calls per material:
//   flash_position_energy = (world position, energy)   energy 0.0 means no flash
//   flash_color_radius    = (linear colour, radius in metres)
// scripts/weapons/weapon_base.gd writes them every frame the flash is alive, through
// PhotorealEnvironment.push_muzzle_flash().

uniform vec4 flash_position_energy = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 flash_color_radius : source_color = vec4(1.0, 0.68, 0.33, 9.0);
// How hard the highlight is squashed vertically on wet surfaces. 1.0 is a round dot.
uniform float flash_wet_smear : hint_range(1.0, 12.0, 0.1) = 5.5;
uniform float flash_specular_gain : hint_range(0.0, 8.0, 0.05) = 2.4;
uniform float flash_sheen_gain : hint_range(0.0, 4.0, 0.05) = 0.8;

// world_normal must be normalised, camera_position is CAMERA_POSITION_WORLD passed in by
// the caller (shader built-ins are not visible inside included functions), roughness is the
// surface roughness after any wetness has been applied, and wet is 0..1.
vec3 muzzle_flash_light(vec3 world_pos, vec3 world_normal, vec3 camera_position, float roughness, float wet) {
	float energy = flash_position_energy.w;
	if (energy <= 0.0001) {
		return vec3(0.0);
	}
	vec3 to_flash = flash_position_energy.xyz - world_pos;
	float distance_to_flash = length(to_flash);
	float radius = max(flash_color_radius.w, 0.01);
	if (distance_to_flash > radius) {
		return vec3(0.0);
	}
	vec3 light_dir = to_flash / max(distance_to_flash, 0.0001);
	// Inverse square, but windowed by the radius so the burst cannot creep across the map.
	float window = 1.0 - distance_to_flash / radius;
	float falloff = window * window / (1.0 + distance_to_flash * distance_to_flash);

	vec3 view_dir = normalize(camera_position - world_pos);
	float n_dot_l = max(dot(world_normal, light_dir), 0.0);

	// Diffuse burst. Wet surfaces are darker and more mirror-like, so they take less of it.
	vec3 diffuse = flash_color_radius.rgb * n_dot_l * mix(1.0, 0.45, wet);

	// Specular with a vertically compressed half-vector: squashing H.y lets far more of the
	// surface satisfy the mirror condition along the vertical, which is exactly the smear a
	// bright light leaves on standing water.
	vec3 half_vector = normalize(light_dir + view_dir);
	float smear = mix(1.0, flash_wet_smear, wet);
	vec3 stretched = normalize(vec3(half_vector.x, half_vector.y / smear, half_vector.z));
	float n_dot_h = max(dot(world_normal, stretched), 0.0);
	float sharpness = mix(18.0, 620.0, clamp(1.0 - roughness, 0.0, 1.0));
	vec3 specular = flash_color_radius.rgb * pow(n_dot_h, sharpness) * flash_specular_gain * mix(0.35, 1.0, wet);

	// Sheen: the thin water film scatters the burst at grazing angles, so the whole wet
	// patch lifts for those few milliseconds instead of only the highlight.
	float fresnel = pow(1.0 - max(dot(world_normal, view_dir), 0.0), 4.0);
	vec3 sheen = flash_color_radius.rgb * fresnel * flash_sheen_gain * wet;

	return (diffuse + specular + sheen) * energy * falloff;
}
