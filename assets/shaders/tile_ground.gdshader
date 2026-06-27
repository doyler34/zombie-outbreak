shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D ground_tex : source_color, filter_nearest, repeat_enable;
uniform vec2 screen_size = vec2(720.0, 1280.0);

void fragment() {
	vec2 tile_count = screen_size / vec2(textureSize(ground_tex, 0));
	vec2 uv = fract(UV * tile_count);
	COLOR = texture(ground_tex, uv);
}
