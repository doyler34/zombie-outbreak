shader_type canvas_item;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float brightness = dot(c.rgb, vec3(0.333));
	float hi = max(c.r, max(c.g, c.b));
	float lo = min(c.r, min(c.g, c.b));
	float saturation = hi - lo;
	// Remove both checkerboard shades (#cccccc brightness~0.80 and #999999 brightness~0.60)
	if (brightness > 0.55 && saturation < 0.06) {
		c.a = 0.0;
	}
	COLOR = c;
}
