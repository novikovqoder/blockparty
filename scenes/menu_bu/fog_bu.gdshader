// Ползущий туман для меню Born Unblessed. Рисуется поверх сцены аддитивно.
shader_type canvas_item;
render_mode blend_add;

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec4 tint : source_color = vec4(0.75, 0.12, 0.16, 1.0);
uniform float density : hint_range(0.0, 2.0) = 0.45;
uniform vec2 speed = vec2(0.012, 0.002);

void fragment() {
	vec2 uv = UV;
	float n1 = texture(noise_tex, uv * vec2(1.6, 1.0) + TIME * speed).r;
	float n2 = texture(noise_tex, uv * vec2(0.9, 0.7) - TIME * speed * 0.7 + vec2(0.37, 0.11)).r;
	float body = smoothstep(0.0, 0.45, uv.y) * smoothstep(1.0, 0.6, uv.y);
	float sides = smoothstep(0.0, 0.12, uv.x) * smoothstep(1.0, 0.88, uv.x);
	float a = clamp(n1 * n2 * 1.6 - 0.15, 0.0, 1.0) * body * sides * density;
	COLOR = vec4(tint.rgb, a);
}
