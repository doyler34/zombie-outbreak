shader_type spatial;
// Bright, readable Clash-style ground: two-tone green checker per grid
// cell with soft tile seams. World-space UVs so tiles align with the
// gameplay grid regardless of mesh size.

uniform vec3 color_a : source_color = vec3(0.474, 0.647, 0.353);
uniform vec3 color_b : source_color = vec3(0.427, 0.600, 0.318);
uniform vec3 seam_color : source_color = vec3(0.365, 0.518, 0.278);
uniform float cell_size = 4.0;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 cell = world_xz / cell_size;
	float checker = mod(floor(cell.x) + floor(cell.y), 2.0);
	vec3 col = mix(color_a, color_b, checker);
	// Soft seams between tiles.
	vec2 edge_dist = abs(fract(cell) - 0.5);
	float seam = smoothstep(0.465, 0.5, max(edge_dist.x, edge_dist.y));
	col = mix(col, seam_color, seam * 0.55);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
