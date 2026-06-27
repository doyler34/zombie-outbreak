shader_type canvas_item;
render_mode blend_mix;

float hash(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 17.5);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i),                  hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void fragment() {
	vec2 uv = FRAGCOORD.xy * 0.006;
	float n =  noise(uv)                          * 0.50
	         + noise(uv * 2.3 + vec2(5.2,  1.3)) * 0.28
	         + noise(uv * 5.7 + vec2(2.7,  8.4)) * 0.14
	         + noise(uv * 11.0 + vec2(7.1, 3.6)) * 0.08;

	vec3 dark  = vec3(0.20, 0.13, 0.06);
	vec3 mid   = vec3(0.33, 0.22, 0.10);
	vec3 light = vec3(0.46, 0.33, 0.17);

	vec3 color = n < 0.5
		? mix(dark, mid, n * 2.0)
		: mix(mid, light, (n - 0.5) * 2.0);

	COLOR = vec4(color, 1.0);
}
