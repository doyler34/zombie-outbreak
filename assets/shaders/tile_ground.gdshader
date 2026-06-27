shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D ground_texture : repeat_enable, filter_linear_mipmap;

void fragment() {
	// Tile the texture every 180 screen pixels using FRAGCOORD (no seams)
	vec2 uv = FRAGCOORD.xy / 180.0;
	COLOR = texture(ground_texture, uv);
}
