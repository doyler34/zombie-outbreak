shader_type spatial;
// Clean, polished Clash-style grass. Even green field with gentle
// large-scale tonal variation and very faint grid seams for build
// readability. The "overgrown areas to clear" are the scattered tree /
// bush obstacle props, not noise painted on the floor — keeps the
// ground crisp instead of muddy. Procedural, mobile-friendly.

uniform vec3 grass_light : source_color = vec3(0.46, 0.63, 0.33);
uniform vec3 grass_dark : source_color = vec3(0.40, 0.56, 0.29);
uniform vec3 seam_color : source_color = vec3(0.37, 0.52, 0.27);
uniform float cell_size = 4.0;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	// Soft, low-contrast mottling so the field isn't a flat slab but
	// reads clean — no camo blobs.
	float v = noise(world_xz * 0.18) * 0.7 + noise(world_xz * 0.5) * 0.3;
	vec3 col = mix(grass_dark, grass_light, smoothstep(0.35, 0.75, v));

	// Very faint grid seams aligned to the build grid.
	vec2 uv = world_xz / cell_size;
	vec2 edge = abs(fract(uv) - 0.5);
	float seam = smoothstep(0.48, 0.5, max(edge.x, edge.y));
	col = mix(col, seam_color, seam * 0.18);

	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
