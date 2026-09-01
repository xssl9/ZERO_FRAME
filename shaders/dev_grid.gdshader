shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

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

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Antialiased band around every integer boundary of `coordinate`.
float boundary_mask(vec2 coordinate, float width) {
	vec2 distance_to_edge = 0.5 - abs(fract(coordinate) - 0.5);
	vec2 filter_width = max(fwidth(coordinate), vec2(0.00001));
	vec2 mask = 1.0 - smoothstep(vec2(0.0), filter_width * 1.5, distance_to_edge - width);
	return max(mask.x, mask.y);
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
	SPECULAR = 0.4;
}
