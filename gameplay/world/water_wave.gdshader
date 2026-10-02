// Вода (раздел 6 SPEC): плоскость с простым шейдером волн — лёгкое
// покачивание вершин и полупрозрачный цвет из палитры.
shader_type spatial;
render_mode blend_mix, depth_draw_always;

uniform vec4 water_color : source_color = vec4(0.5, 0.78, 0.91, 0.55);
uniform float wave_height = 0.05;
uniform float wave_length = 2.5;
uniform float wave_speed = 1.2;

void vertex() {
	vec3 pos = VERTEX;
	float w = sin(pos.x * TAU / wave_length + TIME * wave_speed)
		+ cos(pos.y * TAU / (wave_length * 1.3) + TIME * wave_speed * 1.4);
	pos.z += w * wave_height;
	VERTEX = pos;
}

void fragment() {
	ALBEDO = water_color.rgb;
	ALPHA = water_color.a;
	ROUGHNESS = 0.25;
}
