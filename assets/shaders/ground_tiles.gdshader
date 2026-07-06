shader_type spatial;
// Polished post-apocalyptic ground: a clean grassy field with organic
// patches of darker overgrowth reclaiming the tiles, plus faint grid
// seams for build-placement readability. World-space so it aligns to the
// gameplay grid regardless of mesh size. Procedural (no textures) and
// cheap enough for gl_compatibility / mobile.

uniform vec3 grass_a : source_color = vec3(0.42, 0.60, 0.30);   // healthy grass
uniform vec3 grass_b : source_color = vec3(0.36, 0.53, 0.26);   // shaded grass
uniform vec3 overgrowth : source_color = vec3(0.24, 0.40, 0.18); // dark reclaim
uniform vec3 dirt : source_color = vec3(0.40, 0.36, 0.24);       // worn earth
uniform vec3 seam_color : source_color = vec3(0.30, 0.44, 0.22);
uniform float cell_size = 4.0;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

// Cheap hash + value noise.
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
float fbm(vec2 p) {
	return noise(p) * 0.6 + noise(p * 2.3) * 0.3 + noise(p * 5.1) * 0.1;
}

void fragment() {
	vec2 uv = world_xz / cell_size;

	// Base grass: blend the two greens with low-frequency variation.
	float grain = fbm(world_xz * 0.6);
	vec3 col = mix(grass_a, grass_b, grain);

	// Overgrowth clumps reclaiming the ground.
	float clump = fbm(world_xz * 0.35 + 11.0);
	col = mix(col, overgrowth, smoothstep(0.55, 0.78, clump));

	// Occasional worn dirt patches for wasteland texture.
	float worn = fbm(world_xz * 0.9 + 47.0);
	col = mix(col, dirt, smoothstep(0.72, 0.9, worn) * 0.6);

	// Faint grid seams so players can read the build grid.
	vec2 edge = abs(fract(uv) - 0.5);
	float seam = smoothstep(0.47, 0.5, max(edge.x, edge.y));
	col = mix(col, seam_color, seam * 0.25);

	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
}
