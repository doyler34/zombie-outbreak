shader_type canvas_item;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float brightness = dot(c.rgb, vec3(0.333));
	float hi = max(c.r, max(c.g, c.b));
	float lo = min(c.r, min(c.g, c.b));
	float saturation = hi - lo;
	// Treat bright, desaturated (grey/white checkerboard) pixels as transparent
	if (brightness > 0.38 && saturation < 0.10) {
		c.a = 0.0;
	}
	COLOR = c;
}
