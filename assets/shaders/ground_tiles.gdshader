shader_type spatial;
// Painted survival-world ground. A low-res splat map (built at load by
// WorldDecorator from the region layout) blends five surface layers
// over the base grass: dirt paths (R), gravel (G), cracked asphalt (B)
// and the HQ's concrete slab (A). Every layer's detail is procedural —
// mud pockets in the dirt, speckle in the gravel, crack lines in the
// asphalt, expansion joints in the concrete — so no ground textures
// ship with the game and it stays cheap on mobile GPUs.

uniform vec3 grass_light : source_color = vec3(0.42, 0.55, 0.31);
uniform vec3 grass_dark : source_color = vec3(0.35, 0.47, 0.27);
uniform vec3 seam_color : source_color = vec3(0.32, 0.43, 0.25);
uniform vec3 dirt_color : source_color = vec3(0.47, 0.36, 0.24);
uniform vec3 mud_color : source_color = vec3(0.33, 0.26, 0.18);
uniform vec3 gravel_color : source_color = vec3(0.52, 0.50, 0.46);
uniform vec3 asphalt_color : source_color = vec3(0.23, 0.23, 0.25);
uniform vec3 concrete_color : source_color = vec3(0.56, 0.55, 0.51);
uniform float cell_size = 4.0;

// Splat painted by WorldDecorator; maps the whole world rect.
uniform sampler2D splat_map : filter_linear, repeat_disable;
uniform vec2 world_origin = vec2(-96.0, -96.0);
uniform vec2 world_extent = vec2(192.0, 192.0);

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
	// ── Base grass: soft mottling, faint build-grid seams ────────────
	float v = noise(world_xz * 0.18) * 0.7 + noise(world_xz * 0.5) * 0.3;
	vec3 grass = mix(grass_dark, grass_light, smoothstep(0.35, 0.75, v));
	vec2 uv = world_xz / cell_size;
	vec2 edge = abs(fract(uv) - 0.5);
	float seam = smoothstep(0.48, 0.5, max(edge.x, edge.y));
	grass = mix(grass, seam_color, seam * 0.18);

	// ── Painted layers from the splat map ────────────────────────────
	vec2 splat_uv = (world_xz - world_origin) / world_extent;
	vec4 splat = texture(splat_map, splat_uv);
	// Gentle organic edge wobble (large-scale, so it bends the painted
	// outline instead of pixelating it).
	float fray = (noise(world_xz * 0.30) - 0.5) * 0.35;

	float w_dirt = clamp(splat.r * (1.0 + fray), 0.0, 1.0);
	float w_gravel = clamp(splat.g * (1.0 + fray), 0.0, 1.0);
	float w_asphalt = clamp(splat.b, 0.0, 1.0);
	float w_concrete = clamp(splat.a, 0.0, 1.0);

	// Dirt with darker trodden mud pockets.
	float mud = smoothstep(0.55, 0.8, noise(world_xz * 0.35));
	vec3 dirt = mix(dirt_color, mud_color, mud * 0.7);
	// Gravel: soft pebbly variation, not static noise.
	float pebble = noise(world_xz * 1.6);
	vec3 gravel = gravel_color * (0.9 + 0.18 * pebble);
	// Asphalt: subtle wear + thin crack lines from ridged noise.
	float wear = noise(world_xz * 0.15);
	float ridge = abs(noise(world_xz * 0.45) * 2.0 - 1.0);
	float crack = 1.0 - smoothstep(0.02, 0.05, ridge);
	vec3 asphalt = asphalt_color * (0.92 + 0.14 * wear);
	asphalt = mix(asphalt, asphalt * 0.6, crack * 0.6);
	// Faded centre line down the highway.
	// (kept procedural: distance to the painted strip's own middle is
	// unknown here, so wear does the storytelling instead)
	// Concrete slab with expansion joints every two cells.
	vec2 slab = abs(fract(world_xz / (cell_size * 2.0)) - 0.5);
	float joint = smoothstep(0.47, 0.5, max(slab.x, slab.y));
	vec3 concrete = concrete_color * (0.92 + 0.12 * noise(world_xz * 0.6));
	concrete = mix(concrete, concrete * 0.72, joint);

	// Stack layers over grass; later layers (roads, slab) win.
	vec3 col = grass;
	col = mix(col, dirt, w_dirt);
	col = mix(col, gravel, w_gravel);
	col = mix(col, asphalt, w_asphalt);
	col = mix(col, concrete, w_concrete);

	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
