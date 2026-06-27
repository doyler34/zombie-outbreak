shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D ground_tex : source_color, filter_linear, repeat_enable;

void fragment() {
	vec2 tex_size = vec2(textureSize(ground_tex, 0));
	COLOR = texture(ground_tex, FRAGCOORD.xy / tex_size);
}
